import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions/v2';
import { FieldValue } from 'firebase-admin/firestore';
import { db, paths, REGION } from './db';
import { isoWeekId, weekStart } from './weeks';

/** Trophies for the weekly global top 3. */
export const WEEKLY_TROPHIES = [30, 20, 10];
export const KEEP_WEEKS = 12;

/**
 * Weekly reset (Mondays 00:05 UTC). Boards are keyed by ISO week, so new
 * scores already go to a fresh board; this job finalises last week (winners,
 * trophies), opens the new week and deletes boards older than KEEP_WEEKS.
 */
export const weeklyLeaderboardReset = onSchedule(
  { schedule: '5 0 * * 1', timeZone: 'Etc/UTC', region: REGION },
  async () => {
    const now = new Date();
    await finalizeWeek(isoWeekId(new Date(now.getTime() - 24 * 3600 * 1000)));
    const start = weekStart(now);
    await db.doc(paths.week(isoWeekId(now))).set(
      { weekId: isoWeekId(now), startsAt: start, endsAt: new Date(start.getTime() + 7 * 86400000), finalized: false },
      { merge: true },
    );
    await deleteOldWeeks(now);
  },
);

export async function finalizeWeek(weekId: string): Promise<void> {
  const weekRef = db.doc(paths.week(weekId));
  const meta = await weekRef.get();
  if (meta.get('finalized') === true) return;
  const top = await weekRef.collection('entries').orderBy('xp', 'desc').limit(WEEKLY_TROPHIES.length).get();
  const winners = top.docs.map((d, i) => ({
    uid: d.id,
    username: d.get('username') ?? null,
    xp: d.get('xp') ?? 0,
    trophies: WEEKLY_TROPHIES[i],
  }));
  const batch = db.batch();
  for (const w of winners) {
    batch.set(db.doc(paths.user(w.uid)), { trophies: FieldValue.increment(w.trophies) }, { merge: true });
  }
  batch.set(weekRef, { weekId, finalized: true, winners, finalizedAt: FieldValue.serverTimestamp() }, { merge: true });
  await batch.commit();
  logger.info('Finalized week', { weekId, winners: winners.length });
}

async function deleteOldWeeks(now: Date): Promise<void> {
  const cutoff = isoWeekId(new Date(now.getTime() - KEEP_WEEKS * 7 * 86400000));
  const old = await db.collection('leaderboards').where('weekId', '<', cutoff).get();
  for (const doc of old.docs) await db.recursiveDelete(doc.ref);
}
