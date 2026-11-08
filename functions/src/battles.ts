import { randomInt } from 'crypto';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineInt } from 'firebase-functions/params';
import { FieldValue, Timestamp, Transaction } from 'firebase-admin/firestore';
import { BATTLE_QUESTIONS, generateBattle, seededRandom } from './battleQuestions';
import {
  BattleMode, battleEndsAt, botPlan, COUNTDOWN_MS, LATE_GRACE_MS, pointsFor, questionWindow, trophyResult,
} from './battleRules';
import { db, REGION } from './db';
import { sendPush } from './push';

export const BOT_UID = 'neo-bot';
/** Time per question; lowered only for emulator tests. */
export const BATTLE_QUESTION_MS = defineInt('BATTLE_QUESTION_MS', { default: 8000 });
const MATCH_WAIT_MS = 60_000;
const INVITE_TTL_MS = 30 * 60_000;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return auth.uid;
}

interface PlayerInfo {
  username: string | null;
  displayName: string | null;
  trophies: number;
  level: number;
}

async function playerInfo(uid: string): Promise<PlayerInfo> {
  const u = (await db.doc(`users/${uid}`).get()).data() ?? {};
  return { username: u.username ?? null, displayName: u.displayName ?? null, trophies: u.trophies ?? 0, level: u.level ?? 1 };
}

const BOT_INFO: PlayerInfo = { username: 'neo_bot', displayName: 'Neo (practice bot)', trophies: 0, level: 10 };

/** Writes a new battle (public doc + hidden answers) inside a transaction. */
function writeBattle(
  tx: Transaction,
  mode: BattleMode,
  players: string[],
  info: Record<string, PlayerInfo>,
  startAt: number | null,
  extra: Record<string, unknown> = {},
): string {
  const ref = db.collection('battles').doc();
  const seed = randomInt(0, 2 ** 31);
  const qMs = BATTLE_QUESTION_MS.value();
  const qs = generateBattle(seededRandom(seed));
  const scores = Object.fromEntries(players.map((p) => [p, 0]));
  const doc = {
    mode,
    status: startAt === null ? 'waiting' : 'active',
    players,
    playerInfo: info,
    questions: qs.map((q) => q.question),
    count: BATTLE_QUESTIONS,
    questionMs: qMs,
    startAt: startAt === null ? null : Timestamp.fromMillis(startAt),
    endsAt: startAt === null ? null : Timestamp.fromMillis(battleEndsAt(startAt, BATTLE_QUESTIONS, qMs)),
    scores,
    answers: Object.fromEntries(players.map((p) => [p, {}])),
    winner: null,
    trophyDelta: null,
    createdAt: FieldValue.serverTimestamp(),
    ...extra,
  };
  const secret: Record<string, unknown> = { answers: qs.map((q) => q.answerIndex) };
  if (mode === 'bot') secret.bot = botPlan(seededRandom(seed ^ 0x5bd1e995), BATTLE_QUESTIONS, qMs);
  tx.set(ref, doc);
  tx.set(ref.collection('secret').doc('answers'), secret);
  return ref.id;
}

// --- matchmaking ---------------------------------------------------------------

/** Pairs with the longest-waiting player, or joins the queue. */
export const findMatch = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const me = await playerInfo(uid);
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const waiting = await tx.get(
      db.collection('matchQueue').where('createdAt', '>', Timestamp.fromMillis(now - MATCH_WAIT_MS)).orderBy('createdAt').limit(10),
    );
    const other = waiting.docs.find((d) => d.id !== uid && !d.get('battleId'));
    const myRef = db.doc(`matchQueue/${uid}`);
    if (other) {
      const startAt = now + COUNTDOWN_MS;
      const id = writeBattle(tx, 'random', [other.id, uid], { [other.id]: other.get('info'), [uid]: me }, startAt);
      tx.update(other.ref, { battleId: id });
      tx.delete(myRef);
      return { status: 'matched', battleId: id, serverNow: now };
    }
    tx.set(myRef, { uid, info: me, battleId: null, createdAt: Timestamp.fromMillis(now) });
    return { status: 'waiting', serverNow: now };
  });
});

export const cancelMatch = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const ref = db.doc(`matchQueue/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.get('battleId')) return { status: 'matched', battleId: snap.get('battleId') };
    if (snap.exists) tx.delete(ref);
    return { status: 'cancelled' };
  });
});

export const startBotBattle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const me = await playerInfo(uid);
  const now = Date.now();
  await db.doc(`matchQueue/${uid}`).delete();
  const id = await db.runTransaction(async (tx) => writeBattle(tx, 'bot', [uid, BOT_UID], { [uid]: me, [BOT_UID]: BOT_INFO }, now + COUNTDOWN_MS));
  return { battleId: id, serverNow: now };
});

// --- invites ---------------------------------------------------------------------

function newCode(): string {
  return Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(0, CODE_ALPHABET.length)]).join('');
}

async function createInviteFor(uid: string): Promise<{ battleId: string; code: string }> {
  const me = await playerInfo(uid);
  return db.runTransaction(async (tx) => {
    let code = newCode();
    for (let i = 0; i < 5 && (await tx.get(db.doc(`invites/${code}`))).exists; i++) code = newCode();
    const battleId = writeBattle(tx, 'invite', [uid], { [uid]: me }, null, { inviteCode: code, host: uid });
    tx.set(db.doc(`invites/${code}`), { battleId, host: uid, createdAt: FieldValue.serverTimestamp() });
    return { battleId, code };
  });
}

export const createInvite = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  return { ...(await createInviteFor(uid)), serverNow: Date.now() };
});

/** Invites a friend: creates a battle code and sends them a push notification. */
export const challengeFriend = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const friendUid = req.data?.friendUid;
  if (typeof friendUid !== 'string' || !friendUid) throw new HttpsError('invalid-argument', 'friendUid required');
  if (!(await db.doc(`friends/${uid}/list/${friendUid}`).get()).exists) throw new HttpsError('permission-denied', 'You can only challenge friends.');
  const invite = await createInviteFor(uid);
  const me = await playerInfo(uid);
  const name = me.displayName ?? (me.username ? `@${me.username}` : 'A friend');
  const delivered = await sendPush(friendUid, 'battle', {
    title: '⚡ Brain Battle challenge!',
    body: `${name} challenged you to a 1v1. Tap to accept — code ${invite.code}.`,
    data: { type: 'battle_invite', code: invite.code },
  });
  return { ...invite, notified: delivered > 0, serverNow: Date.now() };
});

export const joinInvite = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const code = typeof req.data?.code === 'string' ? req.data.code.trim().toUpperCase() : '';
  if (!/^[A-Z2-9]{6}$/.test(code)) throw new HttpsError('invalid-argument', 'Codes have 6 letters and numbers.');
  const me = await playerInfo(uid);
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const inv = await tx.get(db.doc(`invites/${code}`));
    if (!inv.exists) throw new HttpsError('not-found', 'That code is not valid or has expired.');
    const bRef = db.doc(`battles/${inv.get('battleId')}`);
    const b = await tx.get(bRef);
    if (!b.exists || b.get('status') !== 'waiting') throw new HttpsError('failed-precondition', 'That battle already started.');
    if (b.get('host') === uid) throw new HttpsError('failed-precondition', 'Share this code with a friend — you can’t join your own battle.');
    const startAt = now + COUNTDOWN_MS;
    tx.update(bRef, {
      status: 'active',
      players: [b.get('host'), uid],
      [`playerInfo.${uid}`]: me,
      [`scores.${uid}`]: 0,
      [`answers.${uid}`]: {},
      startAt: Timestamp.fromMillis(startAt),
      endsAt: Timestamp.fromMillis(battleEndsAt(startAt, BATTLE_QUESTIONS, b.get('questionMs'))),
    });
    tx.delete(inv.ref);
    return { battleId: bRef.id, serverNow: now };
  });
});

// --- playing ---------------------------------------------------------------------------

type Answers = Record<string, Record<string, { correct: boolean; points: number; ms: number }>>;

/** Applies the bot's answers for questions whose bot time has passed. */
function applyBot(data: FirebaseFirestore.DocumentData, secret: FirebaseFirestore.DocumentData, now: number, updates: Record<string, unknown>): void {
  if (data.mode !== 'bot') return;
  const startAt = (data.startAt as Timestamp).toMillis();
  const qMs = data.questionMs as number;
  const answers = (data.answers as Answers)[BOT_UID] ?? {};
  let score = (data.scores as Record<string, number>)[BOT_UID] ?? 0;
  (secret.bot as { correct: boolean; ms: number }[]).forEach((plan, i) => {
    if (answers[i] || updates[`answers.${BOT_UID}.${i}`]) return;
    if (now < questionWindow(startAt, i, qMs).opens + plan.ms) return;
    const points = pointsFor(plan.correct, plan.ms, qMs);
    updates[`answers.${BOT_UID}.${i}`] = { correct: plan.correct, points, ms: plan.ms };
    score += points;
  });
  updates[`scores.${BOT_UID}`] = score;
}

export const submitBattleAnswer = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const { battleId, index, choice } = req.data ?? {};
  if (typeof battleId !== 'string' || !Number.isInteger(index) || !Number.isInteger(choice) || choice < 0 || choice > 3) {
    throw new HttpsError('invalid-argument', 'battleId, index and choice required');
  }
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`battles/${battleId}`);
    const [b, s] = await Promise.all([tx.get(ref), tx.get(ref.collection('secret').doc('answers'))]);
    const now = Date.now();
    if (!b.exists || !(b.get('players') as string[]).includes(uid)) throw new HttpsError('not-found', 'Battle not found.');
    if (b.get('status') !== 'active') throw new HttpsError('failed-precondition', 'Battle is not running.');
    const data = b.data()!;
    const startAt = (data.startAt as Timestamp).toMillis();
    const qMs = data.questionMs as number;
    const win = questionWindow(startAt, index, qMs);
    if (index < 0 || index >= data.count || now < win.opens || now > win.closes + LATE_GRACE_MS) {
      throw new HttpsError('failed-precondition', 'That question is closed.');
    }
    if ((data.answers as Answers)[uid]?.[index]) throw new HttpsError('already-exists', 'Already answered.');
    const answerIndex = (s.get('answers') as number[])[index];
    const correct = choice === answerIndex;
    const ms = Math.min(now - win.opens, win.closes - win.opens);
    const points = pointsFor(correct, ms, qMs);
    const updates: Record<string, unknown> = {
      [`answers.${uid}.${index}`]: { correct, points, ms },
      [`scores.${uid}`]: ((data.scores as Record<string, number>)[uid] ?? 0) + points,
    };
    applyBot(data, s.data()!, now, updates);
    tx.update(ref, updates);
    return { correct, answerIndex, points, serverNow: now };
  });
});

/** Lets bot battles advance between answers; also a clock-sync ping. */
export const tickBattle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const battleId = req.data?.battleId;
  if (typeof battleId !== 'string') throw new HttpsError('invalid-argument', 'battleId required');
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`battles/${battleId}`);
    const [b, s] = await Promise.all([tx.get(ref), tx.get(ref.collection('secret').doc('answers'))]);
    if (!b.exists || !(b.get('players') as string[]).includes(uid)) throw new HttpsError('not-found', 'Battle not found.');
    if (b.get('status') !== 'active' || b.get('mode') !== 'bot') return;
    const updates: Record<string, unknown> = {};
    applyBot(b.data()!, s.data()!, now, updates);
    tx.update(ref, updates);
  });
  return { serverNow: now };
});

/** Finishes a battle whose time is up: winner, trophies, stats. Idempotent. */
export async function finish(battleId: string, now: number): Promise<Record<string, unknown>> {
  const ref = db.doc(`battles/${battleId}`);
  return db.runTransaction(async (tx) => {
    const [b, s] = await Promise.all([tx.get(ref), tx.get(ref.collection('secret').doc('answers'))]);
    if (!b.exists) throw new HttpsError('not-found', 'Battle not found.');
    const data = b.data()!;
    if (data.status === 'finished') return { winner: data.winner, trophyDelta: data.trophyDelta, scores: data.scores };
    if (data.status !== 'active') throw new HttpsError('failed-precondition', 'Battle has not started.');
    const ends = (data.endsAt as Timestamp).toMillis();
    if (now < ends - 300) throw new HttpsError('failed-precondition', `Battle ends in ${Math.ceil((ends - now) / 1000)} s.`);

    const updates: Record<string, unknown> = {};
    applyBot(data, s.data()!, Number.MAX_SAFE_INTEGER, updates);
    const scores = { ...(data.scores as Record<string, number>) };
    if (updates[`scores.${BOT_UID}`] !== undefined) scores[BOT_UID] = updates[`scores.${BOT_UID}`] as number;
    delete updates[`scores.${BOT_UID}`]; // written below as part of the whole map

    const humans = (data.players as string[]).filter((p) => p !== BOT_UID);
    const userSnaps = await Promise.all(humans.map((p) => tx.get(db.doc(`users/${p}`))));
    const current = Object.fromEntries(userSnaps.map((u) => [u.id, (u.get('trophies') as number | undefined) ?? 0]));
    const result = trophyResult(data.mode as BattleMode, scores, current);
    for (const u of userSnaps) {
      const d = result.delta[u.id] ?? 0;
      const outcome = result.winner === null ? 'draws' : result.winner === u.id ? 'wins' : 'losses';
      tx.set(
        u.ref,
        { trophies: Math.max(0, (current[u.id] ?? 0) + d), battleStats: { played: FieldValue.increment(1), [outcome]: FieldValue.increment(1) } },
        { merge: true },
      );
    }
    tx.update(ref, { ...updates, scores, status: 'finished', winner: result.winner, trophyDelta: result.delta, finishedAt: FieldValue.serverTimestamp() });
    return { winner: result.winner, trophyDelta: result.delta, scores };
  });
}

export const finishBattle = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const battleId = req.data?.battleId;
  if (typeof battleId !== 'string') throw new HttpsError('invalid-argument', 'battleId required');
  const b = await db.doc(`battles/${battleId}`).get();
  if (!b.exists || !(b.get('players') as string[]).includes(uid)) throw new HttpsError('not-found', 'Battle not found.');
  return { ...(await finish(battleId, Date.now())), serverNow: Date.now() };
});

/** Every 10 minutes: finish abandoned battles, expire invites and stale queue entries. */
export const cleanupBattles = onSchedule({ schedule: 'every 10 minutes', region: REGION }, async () => {
  await runBattleCleanup(Date.now());
});

export async function runBattleCleanup(now: number): Promise<void> {
  const stale = await db.collection('battles').where('status', '==', 'active').where('endsAt', '<', Timestamp.fromMillis(now - 60_000)).limit(200).get();
  for (const d of stale.docs) await finish(d.id, now).catch(() => undefined);
  const invites = await db.collection('invites').where('createdAt', '<', Timestamp.fromMillis(now - INVITE_TTL_MS)).limit(200).get();
  for (const inv of invites.docs) {
    await db.doc(`battles/${inv.get('battleId')}`).update({ status: 'expired' }).catch(() => undefined);
    await inv.ref.delete();
  }
  const queue = await db.collection('matchQueue').where('createdAt', '<', Timestamp.fromMillis(now - 2 * MATCH_WAIT_MS)).limit(500).get();
  await Promise.all(queue.docs.map((d) => d.ref.delete()));
}

