import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { FieldValue, Transaction } from 'firebase-admin/firestore';
import { db, paths, REGION } from './db';

export const USERNAME_RE = /^[a-z0-9_]{3,20}$/;
const RESERVED = new Set(['admin', 'neurorush', 'support', 'moderator', 'system']);

export function normalizeUsername(raw: unknown): string {
  if (typeof raw !== 'string') throw new HttpsError('invalid-argument', 'username must be a string');
  const name = raw.trim().toLowerCase();
  if (!USERNAME_RE.test(name)) {
    throw new HttpsError('invalid-argument', 'Use 3–20 letters, numbers or underscores.');
  }
  if (RESERVED.has(name)) throw new HttpsError('already-exists', 'That username is taken.');
  return name;
}

/**
 * Inside a transaction: picks a free "brain12345"-style username. All reads
 * happen before the caller's writes.
 */
export async function reserveDefaultUsername(tx: Transaction, uid: string): Promise<string> {
  for (let i = 0; i < 6; i++) {
    const candidate = `brain${Math.floor(10000 + Math.random() * 90000)}`;
    const snap = await tx.get(db.doc(paths.username(candidate)));
    if (!snap.exists) return candidate;
  }
  return `brain_${uid.slice(0, 12).toLowerCase().replace(/[^a-z0-9]/g, '')}`;
}

/** Claims (or changes to) a unique username. */
export const claimUsername = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const name = normalizeUsername(req.data?.username);
  await db.runTransaction(async (tx) => {
    const nameRef = db.doc(paths.username(name));
    const userRef = db.doc(paths.user(uid));
    const [nameSnap, userSnap] = await Promise.all([tx.get(nameRef), tx.get(userRef)]);
    if (nameSnap.exists && nameSnap.get('uid') !== uid) {
      throw new HttpsError('already-exists', 'That username is taken.');
    }
    const old = userSnap.get('username') as string | undefined;
    if (old && old !== name) tx.delete(db.doc(paths.username(old)));
    tx.set(nameRef, { uid, createdAt: FieldValue.serverTimestamp() });
    tx.set(userRef, { username: name }, { merge: true });
  });
  return { username: name };
});
