/**
 * End-to-end: calls the deployed-to-emulator callables with real auth tokens.
 * Run with: npm run test:emulators
 */
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const PROJECT = 'demo-neurorush';
const FN = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';

if (getApps().length === 0) initializeApp({ projectId: PROJECT });
const db = getFirestore();

async function newUser(): Promise<{ uid: string; token: string }> {
  const r = await fetch(`${AUTH}/accounts:signUp?key=fake`, { method: 'POST', body: JSON.stringify({ returnSecureToken: true }), headers: { 'content-type': 'application/json' } });
  const j = (await r.json()) as { localId: string; idToken: string };
  return { uid: j.localId, token: j.idToken };
}

async function call<T>(name: string, token: string, data: unknown): Promise<{ result?: T; error?: { status: string; message: string } }> {
  const r = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
  });
  return (await r.json()) as { result?: T; error?: { status: string; message: string } };
}

let n = 0;
function session(over: Record<string, unknown> = {}) {
  n++;
  return {
    id: `e2e-session-${Date.now()}-${n}`,
    gameId: 'speed_math',
    score: 1200,
    correct: 20,
    wrong: 3,
    maxCombo: 9,
    maxLevel: 6,
    avgReactionMs: 1400,
    bestReactionMs: 650,
    playedAt: Date.now() - n * 120_000,
    durationSeconds: 60,
    ...over,
  };
}

jest.setTimeout(30000);

test('submit: accepted, idempotent, updates profile, leaderboard and achievements', async () => {
  const u = await newUser();
  const s = session();
  const first = await call<{ status: string; xp: number; totalXp: number; newAchievements: string[] }>('submitGameSession', u.token, { session: s });
  expect(first.result?.status).toBe('accepted');
  expect(first.result?.newAchievements).toContain('first_round');
  const xp = first.result!.xp;

  const again = await call<{ status: string; totalXp: number }>('submitGameSession', u.token, { session: s });
  expect(again.result?.status).toBe('duplicate');
  expect(again.result?.totalXp).toBe(xp);

  const user = (await db.doc(`users/${u.uid}`).get()).data()!;
  expect(user.xp).toBe(xp);
  expect(user.rounds).toBe(1);
  expect(user.username).toMatch(/^brain/);
  expect(user.bestScores.speed_math).toBe(1200);

  const week = (await db.collection('leaderboards').get()).docs.map((d) => d.id);
  expect(week.length).toBeGreaterThan(0);
  const entry = (await db.doc(`leaderboards/${week[0]}/entries/${u.uid}`).get()).data()!;
  expect(entry.xp).toBe(xp);
  const ach = (await db.doc(`achievements/${u.uid}`).get()).data()!;
  expect(Object.keys(ach.unlocked)).toContain('first_round');
});

test('submit: impossible rounds are rejected and change nothing', async () => {
  const u = await newUser();
  const res = await call<{ status: string; reason: string }>('submitGameSession', u.token, { session: session({ score: 999999 }) });
  expect(res.result).toEqual({ status: 'rejected', reason: 'score_too_high' });
  expect((await db.doc(`users/${u.uid}`).get()).exists).toBe(false);

  const ok = await call<{ status: string }>('submitGameSession', u.token, { session: session({ playedAt: Date.now() - 10_000 }) });
  expect(ok.result?.status).toBe('accepted');
  const overlap = await call<{ status: string; reason: string }>('submitGameSession', u.token, { session: session({ playedAt: Date.now() - 20_000 }) });
  expect(overlap.result).toEqual({ status: 'rejected', reason: 'overlap' });
});

test('submit: requires sign-in and well-formed data', async () => {
  const noAuth = await call('submitGameSession', 'not-a-token', { session: session() });
  expect(noAuth.error?.status).toBe('UNAUTHENTICATED');
  const u = await newUser();
  const bad = await call('submitGameSession', u.token, { session: { id: 'x' } });
  expect(bad.error?.status).toBe('INVALID_ARGUMENT');
});

test('usernames and friends: request, accept, unlock badge, remove', async () => {
  const a = await newUser();
  const b = await newUser();
  const nameA = `amina${Date.now() % 100000}`;
  const nameB = `bilal${Date.now() % 100000}`;
  expect((await call('claimUsername', a.token, { username: nameA })).result).toEqual({ username: nameA });
  expect((await call('claimUsername', b.token, { username: nameB.toUpperCase() })).result).toEqual({ username: nameB });
  expect((await call('claimUsername', b.token, { username: nameA })).error?.status).toBe('ALREADY_EXISTS');
  expect((await call('claimUsername', b.token, { username: 'no spaces' })).error?.status).toBe('INVALID_ARGUMENT');

  expect((await call('sendFriendRequest', a.token, { username: nameB })).result).toEqual({ status: 'requested' });
  expect((await db.doc(`friends/${b.uid}/requests/${a.uid}`).get()).get('fromUsername')).toBe(nameA);
  expect((await call('sendFriendRequest', a.token, { username: 'nobody_here_x' })).error?.status).toBe('NOT_FOUND');

  expect((await call('respondFriendRequest', b.token, { fromUid: a.uid, accept: true })).result).toEqual({ status: 'friends' });
  expect((await db.doc(`friends/${a.uid}/list/${b.uid}`).get()).exists).toBe(true);
  expect((await db.doc(`friends/${b.uid}/list/${a.uid}`).get()).exists).toBe(true);
  expect((await db.doc(`users/${a.uid}`).get()).get('stats.friends')).toBe(1);
  expect(Object.keys((await db.doc(`achievements/${b.uid}`).get()).get('unlocked'))).toContain('friend_1');

  expect((await call('removeFriend', a.token, { friendUid: b.uid })).result).toEqual({ status: 'removed' });
  expect((await db.doc(`friends/${b.uid}/list/${a.uid}`).get()).exists).toBe(false);
  expect((await db.doc(`users/${b.uid}`).get()).get('stats.friends')).toBe(0);
});
