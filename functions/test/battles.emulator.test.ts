/**
 * Battles + push end-to-end on the emulators (BATTLE_QUESTION_MS=1500, PUSH_DRY_RUN=true).
 * Run with: npm run test:emulators
 */
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const PROJECT = 'demo-neurorush';
const FN = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
if (getApps().length === 0) initializeApp({ projectId: PROJECT });
const db = getFirestore();
jest.setTimeout(60000);

type User = { uid: string; token: string };
async function newUser(): Promise<User> {
  const r = await fetch(`${AUTH}/accounts:signUp?key=fake`, { method: 'POST', body: JSON.stringify({ returnSecureToken: true }), headers: { 'content-type': 'application/json' } });
  const j = (await r.json()) as { localId: string; idToken: string };
  return { uid: j.localId, token: j.idToken };
}
async function call<T = Record<string, unknown>>(name: string, u: User, data: unknown = {}) {
  const r = await fetch(`${FN}/${name}`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${u.token}` }, body: JSON.stringify({ data }) });
  return (await r.json()) as { result?: T; error?: { status: string; message: string } };
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, Math.max(0, ms)));

async function battle(id: string) {
  return (await db.doc(`battles/${id}`).get()).data()!;
}
async function answers(id: string): Promise<number[]> {
  return (await db.doc(`battles/${id}/secret/answers`).get()).get('answers');
}
/** Plays every question; [pick] chooses the answer given the right one. */
async function play(id: string, u: User, pick: (right: number) => number, delayMs = 150) {
  const b = await battle(id);
  const right = await answers(id);
  const start = (b.startAt as Timestamp).toMillis();
  for (let i = 0; i < b.count; i++) {
    await sleep(start + i * b.questionMs + delayMs - Date.now());
    const r = await call<{ correct: boolean; points: number }>('submitBattleAnswer', u, { battleId: id, index: i, choice: pick(right[i]) });
    expect(r.error).toBeUndefined();
  }
  await sleep((b.endsAt as Timestamp).toMillis() - Date.now() + 50);
}

test('practice bot battle: answers checked and timed on the server, trophies awarded', async () => {
  const me = await newUser();
  const started = await call<{ battleId: string; serverNow: number }>('startBotBattle', me);
  const id = started.result!.battleId;
  const b = await battle(id);
  expect(b).toMatchObject({ mode: 'bot', status: 'active', count: 8, questionMs: 1500 });
  expect(b.players).toEqual([me.uid, 'neo-bot']);
  expect(JSON.stringify(b)).not.toContain('answerIndex');

  // Too early: the first question is not open yet.
  expect((await call('submitBattleAnswer', me, { battleId: id, index: 0, choice: 0 })).error?.status).toBe('FAILED_PRECONDITION');
  expect((await call('finishBattle', me, { battleId: id })).error?.status).toBe('FAILED_PRECONDITION');

  await play(id, me, (right) => right);
  const fin = await call<{ winner: string; trophyDelta: Record<string, number>; scores: Record<string, number> }>('finishBattle', me, { battleId: id });
  const done = await battle(id);
  expect(done.status).toBe('finished');
  expect(Object.keys(done.answers['neo-bot'])).toHaveLength(8);
  expect(fin.result!.scores[me.uid]).toBeGreaterThan(8 * 100);
  expect(fin.result!.winner).toBe(me.uid);
  expect((await db.doc(`users/${me.uid}`).get()).data()).toMatchObject({ trophies: 10, battleStats: { played: 1, wins: 1 } });
  // Idempotent.
  expect((await call('finishBattle', me, { battleId: id })).result).toMatchObject({ winner: me.uid });
  expect((await db.doc(`users/${me.uid}`).get()).get('trophies')).toBe(10);
});

test('random matchmaking pairs two players who get the same questions; rules enforced', async () => {
  const a = await newUser();
  const b = await newUser();
  const outsider = await newUser();
  await db.doc(`users/${b.uid}`).set({ trophies: 5 }, { merge: true });

  expect((await call<{ status: string }>('findMatch', a)).result?.status).toBe('waiting');
  const m = await call<{ status: string; battleId: string }>('findMatch', b);
  expect(m.result?.status).toBe('matched');
  const id = m.result!.battleId;
  expect((await db.doc(`matchQueue/${a.uid}`).get()).get('battleId')).toBe(id);
  expect((await battle(id)).players).toEqual([a.uid, b.uid]);

  const bt = await battle(id);
  await sleep((bt.startAt as Timestamp).toMillis() + 100 - Date.now());
  expect((await call('submitBattleAnswer', outsider, { battleId: id, index: 0, choice: 0 })).error?.status).toBe('NOT_FOUND');

  await Promise.all([play(id, a, (r) => r, 100), play(id, b, (r) => (r + 1) % 4, 300).catch(() => undefined)]);
  const again = await call('submitBattleAnswer', a, { battleId: id, index: 7, choice: 0 });
  expect(['ALREADY_EXISTS', 'FAILED_PRECONDITION']).toContain(again.error?.status);

  const fin = await call<{ winner: string; trophyDelta: Record<string, number> }>('finishBattle', b, { battleId: id });
  expect(fin.result).toMatchObject({ winner: a.uid, trophyDelta: { [a.uid]: 30, [b.uid]: -5 } });
  expect((await db.doc(`users/${b.uid}`).get()).get('trophies')).toBe(0);
});

test('invites: join by code; friend challenge sends a push', async () => {
  const host = await newUser();
  const guest = await newUser();
  const inv = await call<{ battleId: string; code: string }>('createInvite', host);
  expect(inv.result!.code).toMatch(/^[A-Z2-9]{6}$/);
  expect((await call('joinInvite', host, { code: inv.result!.code })).error?.status).toBe('FAILED_PRECONDITION');
  expect((await call('joinInvite', guest, { code: 'ZZZZZZ' })).error?.status).toBe('NOT_FOUND');
  const joined = await call<{ battleId: string }>('joinInvite', guest, { code: inv.result!.code.toLowerCase() });
  expect(joined.result?.battleId).toBe(inv.result!.battleId);
  expect(await battle(inv.result!.battleId)).toMatchObject({ status: 'active', mode: 'invite', players: [host.uid, guest.uid] });

  expect((await call('challengeFriend', host, { friendUid: guest.uid })).error?.status).toBe('PERMISSION_DENIED');
  await db.doc(`friends/${host.uid}/list/${guest.uid}`).set({ uid: guest.uid });
  await db.doc(`pushTargets/${guest.uid}`).set({ tokens: ['device-token-1'], prefs: { battle: true } });
  const ch = await call<{ code: string; notified: boolean }>('challengeFriend', host, { friendUid: guest.uid });
  expect(ch.result?.notified).toBe(true);
  const log = await db.collection('pushLog').where('uid', '==', guest.uid).get();
  expect(log.docs.map((d) => d.data())).toEqual([expect.objectContaining({ kind: 'battle', data: { type: 'battle_invite', code: ch.result!.code } })]);

  // Players who turned battle notifications off are not disturbed.
  await db.doc(`pushTargets/${guest.uid}`).set({ prefs: { battle: false } }, { merge: true });
  expect((await call<{ notified: boolean }>('challengeFriend', host, { friendUid: guest.uid })).result?.notified).toBe(false);
});

test('"your friend beat your score" push from the leaderboard trigger', async () => {
  const a = await newUser();
  const b = await newUser();
  await db.doc(`friends/${a.uid}/list/${b.uid}`).set({ uid: b.uid });
  await db.doc(`pushTargets/${b.uid}`).set({ tokens: ['device-b'], prefs: {} });
  const weekDocs = await db.collection('leaderboards').get();
  // B's best this week (written like the server would).
  const { isoWeekId } = await import('../src/weeks');
  const week = isoWeekId(new Date());
  await db.doc(`leaderboards/${week}/entries/${b.uid}`).set({ uid: b.uid, bestScores: { speed_math: 1000 }, xp: 10 });
  void weekDocs;
  const s = { id: `beat-${Date.now()}`, gameId: 'speed_math', score: 1200, correct: 20, wrong: 0, maxCombo: 20, maxLevel: 5, avgReactionMs: 900, bestReactionMs: 400, playedAt: Date.now() - 1000, durationSeconds: 60 };
  expect((await call<{ status: string }>('submitGameSession', a, { session: s })).result?.status).toBe('accepted');
  let log: FirebaseFirestore.DocumentData[] = [];
  for (let i = 0; i < 20 && log.length === 0; i++) {
    await sleep(300);
    log = (await db.collection('pushLog').where('uid', '==', b.uid).get()).docs.map((d) => d.data());
  }
  expect(log).toEqual([expect.objectContaining({ kind: 'friends', data: { type: 'friend_beat', gameId: 'speed_math' } })]);
  expect(log[0].body).toContain('1,200 in Speed Math');
});
