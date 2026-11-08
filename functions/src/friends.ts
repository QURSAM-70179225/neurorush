import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { FieldValue, Transaction } from 'firebase-admin/firestore';
import { newlyUnlocked } from './achievements';
import { db, paths, REGION } from './db';
import { achievementStats, normalizeProfile } from './progress';
import { normalizeUsername } from './usernames';

export const MAX_FRIENDS = 200;

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return auth.uid;
}

/** Creates the friendship both ways and updates friend counts + badges. */
async function befriend(tx: Transaction, a: string, b: string): Promise<void> {
  const [ua, ub, aa, ab, existing] = await Promise.all([
    tx.get(db.doc(paths.user(a))),
    tx.get(db.doc(paths.user(b))),
    tx.get(db.doc(paths.achievements(a))),
    tx.get(db.doc(paths.achievements(b))),
    tx.get(db.doc(paths.friend(a, b))),
  ]);
  tx.delete(db.doc(paths.request(a, b)));
  tx.delete(db.doc(paths.request(b, a)));
  if (existing.exists) return;
  for (const [uid, other, userSnap, achSnap] of [
    [a, b, ua, aa],
    [b, a, ub, ab],
  ] as const) {
    const profile = normalizeProfile(userSnap.data());
    if (profile.stats.friends >= MAX_FRIENDS) throw new HttpsError('resource-exhausted', 'Friend list is full.');
    profile.stats.friends += 1;
    tx.set(db.doc(paths.friend(uid, other)), { uid: other, since: FieldValue.serverTimestamp() });
    tx.set(db.doc(paths.user(uid)), { stats: { friends: profile.stats.friends } }, { merge: true });
    const unlockedBefore = Object.keys((achSnap.get('unlocked') as Record<string, unknown>) ?? {});
    const fresh = newlyUnlocked(achievementStats(profile, userSnap.get('bestStreak') ?? 0), unlockedBefore);
    if (fresh.length) {
      tx.set(
        db.doc(paths.achievements(uid)),
        { unlocked: Object.fromEntries(fresh.map((id) => [id, FieldValue.serverTimestamp()])) },
        { merge: true },
      );
    }
  }
}

/** Sends a request by username; if they already asked you, you become friends. */
export const sendFriendRequest = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const name = normalizeUsername(req.data?.username);
  const nameSnap = await db.doc(paths.username(name)).get();
  const target = nameSnap.get('uid') as string | undefined;
  if (!target) throw new HttpsError('not-found', `No player called "${name}".`);
  if (target === uid) throw new HttpsError('invalid-argument', "That's you!");

  return db.runTransaction(async (tx) => {
    const [already, reverse, me] = await Promise.all([
      tx.get(db.doc(paths.friend(uid, target))),
      tx.get(db.doc(paths.request(uid, target))),
      tx.get(db.doc(paths.user(uid))),
    ]);
    if (already.exists) return { status: 'already_friends' };
    if (reverse.exists) {
      await befriend(tx, uid, target);
      return { status: 'friends' };
    }
    const myName = me.get('username') as string | undefined;
    if (!myName) throw new HttpsError('failed-precondition', 'Choose a username first.');
    tx.set(db.doc(paths.request(target, uid)), {
      fromUid: uid,
      fromUsername: myName,
      fromDisplayName: me.get('displayName') ?? null,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { status: 'requested' };
  });
});

export const respondFriendRequest = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const from = req.data?.fromUid;
  const accept = req.data?.accept === true;
  if (typeof from !== 'string' || from.length === 0) throw new HttpsError('invalid-argument', 'fromUid required');
  return db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(db.doc(paths.request(uid, from)));
    if (!reqSnap.exists) throw new HttpsError('not-found', 'That request no longer exists.');
    if (!accept) {
      tx.delete(reqSnap.ref);
      return { status: 'declined' };
    }
    await befriend(tx, uid, from);
    return { status: 'friends' };
  });
});

export const removeFriend = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const other = req.data?.friendUid;
  if (typeof other !== 'string' || other.length === 0) throw new HttpsError('invalid-argument', 'friendUid required');
  return db.runTransaction(async (tx) => {
    const [link, ua, ub] = await Promise.all([
      tx.get(db.doc(paths.friend(uid, other))),
      tx.get(db.doc(paths.user(uid))),
      tx.get(db.doc(paths.user(other))),
    ]);
    if (!link.exists) return { status: 'not_friends' };
    tx.delete(db.doc(paths.friend(uid, other)));
    tx.delete(db.doc(paths.friend(other, uid)));
    for (const [id, snap] of [
      [uid, ua],
      [other, ub],
    ] as const) {
      const n = Math.max(0, ((snap.get('stats.friends') as number | undefined) ?? 1) - 1);
      tx.set(db.doc(paths.user(id)), { stats: { friends: n } }, { merge: true });
    }
    return { status: 'removed' };
  });
});
