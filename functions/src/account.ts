import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue } from 'firebase-admin/firestore';
import { db, REGION } from './db';

async function deleteQuery(q: FirebaseFirestore.Query): Promise<number> {
  let total = 0;
  for (;;) {
    const snap = await q.limit(300).get();
    if (snap.empty) return total;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    total += snap.size;
  }
}

/**
 * Deletes everything stored about the player, then the auth account
 * (Google Play account-deletion requirement). Purchase records are kept for
 * tax/refund law but unlinked from the account.
 */
export async function deleteUserData(uid: string): Promise<void> {
  const user = await db.doc(`users/${uid}`).get();
  const username = user.get('username') as string | undefined;

  // Friendships on both sides.
  const friends = await db.collection(`friends/${uid}/list`).get();
  for (const f of friends.docs) {
    await db.doc(`friends/${f.id}/list/${uid}`).delete();
    await db.doc(`users/${f.id}`).set({ stats: { friends: FieldValue.increment(-1) } }, { merge: true });
  }
  await db.recursiveDelete(db.doc(`friends/${uid}`));
  await deleteQuery(db.collectionGroup('requests').where('fromUid', '==', uid));

  await deleteQuery(db.collection('gameSessions').where('uid', '==', uid));
  await deleteQuery(db.collection('endlessPuzzles').where('uid', '==', uid));
  await deleteQuery(db.collection('coachTips').where('uid', '==', uid));
  await deleteQuery(db.collection('rewardGrants').where('uid', '==', uid));
  const weeks = await db.collection('leaderboards').get();
  for (const w of weeks.docs) await w.ref.collection('entries').doc(uid).delete();
  await db.recursiveDelete(db.doc(`dailyWorkouts/${uid}`));
  for (const path of [`achievements/${uid}`, `pushTargets/${uid}`, `matchQueue/${uid}`]) await db.doc(path).delete();
  if (username) await db.doc(`usernames/${username}`).delete();

  const purchases = await db.collection('purchases').where('uid', '==', uid).get();
  for (const p of purchases.docs) await p.ref.update({ uid: null, deletedAccount: true });

  // Battles keep the opponent's history; this player's name is removed.
  const battles = await db.collection('battles').where('players', 'array-contains', uid).get();
  for (const b of battles.docs) {
    await b.ref.update({ [`playerInfo.${uid}`]: { username: null, displayName: 'Deleted player', trophies: 0, level: 1 } });
  }
  await db.recursiveDelete(db.doc(`users/${uid}`));
}

export const deleteAccount = onCall({ region: REGION, timeoutSeconds: 300 }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (req.data?.confirm !== 'DELETE') throw new HttpsError('invalid-argument', 'Confirmation missing.');
  await deleteUserData(uid);
  await getAuth().deleteUser(uid).catch((e) => logger.warn('Auth user already gone', { uid, error: (e as Error).message }));
  logger.info('Account deleted', { uid });
  return { deleted: true };
});
