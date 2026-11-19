import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { newlyUnlocked } from './achievements';
import { db, paths, REGION } from './db';
import { achievementStats, applySession, normalizeProfile } from './progress';
import { levelFromXp } from './rewards';
import { reserveDefaultUsername } from './usernames';
import { InvalidInput, parseSession, validateSession } from './validation';
import { isoWeekId } from './weeks';
import { advanceStreak, capDailyCoins, CoinEarnState, coinsForRound, localDayOf } from './economyRules';
import { economy } from './config';

export interface SubmitResult {
  status: 'accepted' | 'duplicate' | 'rejected';
  reason?: string;
  stars?: number;
  xp?: number;
  totalXp?: number;
  level?: number;
  brainScore?: number;
  newAchievements?: string[];
  streak?: number;
  freezesUsed?: number;
  freezeEarned?: boolean;
  coinsEarned?: number;
}

/**
 * The only way scores reach Firestore: validates a finished round, recomputes
 * stars/XP server-side, updates the profile, weekly leaderboard and
 * achievements atomically. Idempotent per session id (safe to retry).
 */
export const submitGameSession = onCall({ region: REGION }, async (req): Promise<SubmitResult> => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');

  let s;
  try {
    s = parseSession(req.data?.session);
  } catch (e) {
    if (e instanceof InvalidInput) throw new HttpsError('invalid-argument', e.message);
    throw e;
  }

  const tzRaw = req.data?.tzOffsetMinutes;
  const tz = typeof tzRaw === 'number' && Number.isInteger(tzRaw) && Math.abs(tzRaw) <= 14 * 60 ? tzRaw : 0;

  const now = Date.now();
  const verdict = validateSession(s, now);
  if (!verdict.ok) {
    logger.warn('Rejected session', { uid, id: s.id, game: s.gameId, reason: verdict.reason });
    return { status: 'rejected', reason: verdict.reason };
  }

  // Two rounds of the same player cannot overlap in time.
  const windowMs = (s.durationSeconds - 5) * 1000;
  const overlapping = await db
    .collection('gameSessions')
    .where('uid', '==', uid)
    .where('playedAt', '>', Timestamp.fromMillis(s.playedAt - windowMs))
    .where('playedAt', '<', Timestamp.fromMillis(s.playedAt + windowMs))
    .limit(2)
    .get();
  if (overlapping.docs.some((d) => d.id !== s.id)) {
    logger.warn('Rejected overlapping session', { uid, id: s.id });
    return { status: 'rejected', reason: 'overlap' };
  }

  const weekId = isoWeekId(new Date(now));
  const econ = await economy();
  return db.runTransaction(async (tx): Promise<SubmitResult> => {
    const sessionRef = db.doc(paths.session(s.id));
    const userRef = db.doc(paths.user(uid));
    const entryRef = db.doc(paths.entry(weekId, uid));
    const achRef = db.doc(paths.achievements(uid));
    const [sessionSnap, userSnap, entrySnap, achSnap] = await Promise.all([
      tx.get(sessionRef),
      tx.get(userRef),
      tx.get(entryRef),
      tx.get(achRef),
    ]);
    const userData = userSnap.data() ?? {};

    if (sessionSnap.exists) {
      if (sessionSnap.get('uid') !== uid) throw new HttpsError('already-exists', 'Session id in use.');
      return { status: 'duplicate', totalXp: userData.xp ?? 0, level: userData.level ?? 1, brainScore: userData.brainScore ?? 0 };
    }

    let username = userData.username as string | undefined;
    if (!username) username = await reserveDefaultUsername(tx, uid);

    const applied = applySession(normalizeProfile(userData), s);
    const { stars, accuracy, profile } = applied;
    // A rewarded "double XP" ad watched before this round was uploaded.
    const boosted = (userData.pendingBoosts as Record<string, boolean> | undefined)?.[s.id] === true;
    const xp = boosted ? applied.xp * 2 : applied.xp;
    if (boosted) {
      profile.xp += applied.xp;
      profile.level = levelFromXp(profile.xp);
    }
    // Streaks and freezes are kept on the server (in the player's local days).
    const streakResult = advanceStreak(
      {
        current: Number(userData.currentStreak ?? 0),
        best: Number(userData.bestStreak ?? 0),
        lastDay: (userData.streakDay as string | undefined) ?? null,
      },
      localDayOf(s.playedAt, tz),
      Number(userData.freezes ?? 1),
    );
    const bestStreak = streakResult.streak.best;
    const unlockedBefore = Object.keys((achSnap.get('unlocked') as Record<string, unknown>) ?? {});
    const fresh = newlyUnlocked(achievementStats(profile, bestStreak), unlockedBefore);

    // Coins for playing: repeatable parts are capped per day, one-offs are not.
    const newDay = streakResult.streak.lastDay !== ((userData.streakDay as string | undefined) ?? null);
    const earned = coinsForRound(
      {
        stars,
        newDay,
        streak: streakResult.streak.current,
        levelsGained: profile.level - Number(userData.level ?? 1),
        newAchievements: fresh.length,
      },
      econ,
    );
    const capped = capDailyCoins(userData.coinEarn as CoinEarnState | undefined, new Date(now).toISOString().slice(0, 10), earned.repeatable, econ.coins_daily_cap);
    const coinsEarned = capped.granted + earned.oneOff;

    // --- writes ---
    if (!userData.username) {
      tx.set(db.doc(paths.username(username)), { uid, createdAt: FieldValue.serverTimestamp() });
    }
    tx.set(sessionRef, {
      ...s,
      uid,
      playedAt: Timestamp.fromMillis(s.playedAt),
      accuracy,
      stars,
      xp,
      boosted,
      coinsEarned,
      weekId,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      userRef,
      {
        ...profile,
        username,
        currentStreak: streakResult.streak.current,
        bestStreak: streakResult.streak.best,
        streakDay: streakResult.streak.lastDay,
        freezes: streakResult.freezes,
        coins: Number(userData.coins ?? 0) + coinsEarned,
        coinEarn: capped.state,
        ...(boosted ? { pendingBoosts: { [s.id]: FieldValue.delete() } } : {}),
        lastSessionAt: Timestamp.fromMillis(s.playedAt),
        createdAt: userData.createdAt ?? FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    const entry = entrySnap.data() ?? {};
    const bestScores = { ...(entry.bestScores ?? {}) } as Record<string, number>;
    if (s.durationSeconds === 60) bestScores[s.gameId] = Math.max(bestScores[s.gameId] ?? 0, s.score);
    tx.set(entryRef, {
      uid,
      username,
      displayName: userData.displayName ?? null,
      country: userData.country ?? null,
      weekId,
      xp: (entry.xp ?? 0) + xp,
      rounds: (entry.rounds ?? 0) + 1,
      bestScores,
      level: profile.level,
      updatedAt: FieldValue.serverTimestamp(),
    });
    // Parent doc lets the weekly job find and clean up old boards.
    tx.set(db.doc(paths.week(weekId)), { weekId }, { merge: true });
    if (fresh.length > 0) {
      const unlocked: Record<string, FieldValue> = {};
      for (const id of fresh) unlocked[id] = FieldValue.serverTimestamp();
      tx.set(achRef, { unlocked }, { merge: true });
    }
    return {
      status: 'accepted',
      stars,
      xp,
      totalXp: profile.xp,
      level: profile.level,
      brainScore: profile.brainScore,
      newAchievements: fresh,
      streak: streakResult.streak.current,
      freezesUsed: streakResult.freezesUsed,
      freezeEarned: streakResult.freezeEarned,
      coinsEarned,
    };
  });
});
