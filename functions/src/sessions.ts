import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { newlyUnlocked } from './achievements';
import { db, paths, REGION } from './db';
import { achievementStats, applySession, normalizeProfile } from './progress';
import { reserveDefaultUsername } from './usernames';
import { InvalidInput, parseSession, validateSession } from './validation';
import { isoWeekId } from './weeks';

export interface SubmitResult {
  status: 'accepted' | 'duplicate' | 'rejected';
  reason?: string;
  stars?: number;
  xp?: number;
  totalXp?: number;
  level?: number;
  brainScore?: number;
  newAchievements?: string[];
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

    const { stars, xp, accuracy, profile } = applySession(normalizeProfile(userData), s);
    const bestStreak = typeof userData.bestStreak === 'number' ? userData.bestStreak : 0;
    const unlockedBefore = Object.keys((achSnap.get('unlocked') as Record<string, unknown>) ?? {});
    const fresh = newlyUnlocked(achievementStats(profile, bestStreak), unlockedBefore);

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
      weekId,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      userRef,
      {
        ...profile,
        username,
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
    };
  });
});
