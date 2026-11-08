import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import { db, REGION } from './db';
import { sendPush } from './push';
import { overtakenGames, reminderFor } from './notificationRules';

const GAME_TITLES: Record<string, string> = {
  memory_grid: 'Memory Grid',
  color_clash: 'Color Clash',
  speed_math: 'Speed Math',
  shape_match: 'Shape Match',
  number_sequence: 'Number Sequence',
  word_scramble: 'Word Scramble',
  odd_one_out: 'Odd One Out',
  path_recall: 'Path Recall',
};

/**
 * Hourly: sends streak reminders (players' local 19:00) and "workout ready"
 * (local 08:00). Targets store the matching UTC hours, so each run only reads
 * the players due now.
 */
export const hourlyReminders = onSchedule({ schedule: '0 * * * *', timeZone: 'Etc/UTC', region: REGION }, async () => {
  await runHourlyReminders(Date.now());
});

export async function runHourlyReminders(nowMs: number): Promise<number> {
  const hour = new Date(nowMs).getUTCHours();
  let sent = 0;
  for (const kind of ['streak', 'workout'] as const) {
    const field = kind === 'streak' ? 'reminderHourUtc' : 'workoutHourUtc';
    const due = await db.collection('pushTargets').where(field, '==', hour).limit(1000).get();
    for (const t of due.docs) {
      const user = (await db.doc(`users/${t.id}`).get()).data() ?? {};
      const msg = reminderFor(kind, user, Number(t.get('tzOffsetMinutes') ?? 0), nowMs);
      if (msg) sent += (await sendPush(t.id, kind, { ...msg, data: { type: kind === 'streak' ? 'streak_reminder' : 'workout_ready' } })) > 0 ? 1 : 0;
    }
  }
  logger.info('Reminders sent', { hour, sent });
  return sent;
}

/** "Your friend beat your score!" when a weekly best overtakes a friend's. */
export const notifyFriendsOnNewBest = onDocumentWritten({ document: 'leaderboards/{weekId}/entries/{uid}', region: REGION }, async (event) => {
  const before = (event.data?.before.data()?.bestScores ?? {}) as Record<string, number>;
  const afterDoc = event.data?.after.data();
  if (!afterDoc) return;
  const after = (afterDoc.bestScores ?? {}) as Record<string, number>;
  const improved = Object.keys(after).filter((g) => after[g] > (before[g] ?? 0));
  if (improved.length === 0) return;
  const { weekId, uid } = event.params;
  const name = afterDoc.displayName ?? (afterDoc.username ? `@${afterDoc.username}` : 'A friend');
  const friends = await db.collection(`friends/${uid}/list`).limit(100).get();
  for (const f of friends.docs) {
    const theirs = ((await db.doc(`leaderboards/${weekId}/entries/${f.id}`).get()).get('bestScores') ?? {}) as Record<string, number>;
    const games = overtakenGames(before, after, theirs);
    if (games.length === 0) continue;
    const g = games[0];
    await sendPush(f.id, 'friends', {
      title: `${name} beat your score!`,
      body: `${after[g].toLocaleString('en-US')} in ${GAME_TITLES[g] ?? g} this week. Take it back?`,
      data: { type: 'friend_beat', gameId: g },
    });
  }
});
