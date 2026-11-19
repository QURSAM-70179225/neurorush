import { randomBytes, randomInt } from 'crypto';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { SKILLS, Skill } from './catalog';
import { CoachInput, DaySession, fallbackCoachTip, generateCoachTip } from './ai/coach';
import { GroqClient, LlmClient } from './ai/llm';
import { CHOICES, generatedSequencePuzzle, generateVerifiedPuzzle, Puzzle, puzzleHash } from './ai/puzzles';
import { db, REGION } from './db';
import { capDailyCoins, CoinEarnState, proActive } from './economyRules';
import { economy } from './config';

/** Set with: firebase functions:secrets:set GROQ_API_KEY */
export const GROQ_API_KEY = defineSecret('GROQ_API_KEY');
/**
 * Groq retired its Llama chat models for new keys; gpt-oss-120b is the
 * default (verified live). Override per project in functions/.env.<project>.
 */
export const GROQ_MODEL = defineString('GROQ_MODEL', { default: 'openai/gpt-oss-120b' });
export const GROQ_BASE_URL = defineString('GROQ_BASE_URL', { default: 'https://api.groq.com/openai/v1' });

export const ENDLESS_LIVES = 3;
/** Answers later than this after the puzzle was served count as wrong. */
export const ENDLESS_ANSWER_WINDOW_MS = 60_000;
const COACH_MAX_AI_ATTEMPTS = 3;

/** Overridable in tests. */
export let llmFactory: () => LlmClient = () => new GroqClient(GROQ_API_KEY.value(), GROQ_MODEL.value(), GROQ_BASE_URL.value());
export function setLlmFactory(f: () => LlmClient): void {
  llmFactory = f;
}

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return auth.uid;
}

// --- AI Brain Coach ---------------------------------------------------------------

/** UTC start of the player's local [day] given their offset (minutes east of UTC). */
export function localDayStartUtc(day: string, tzOffsetMinutes: number): number {
  const [y, m, d] = day.split('-').map(Number);
  return Date.UTC(y, m - 1, d) - tzOffsetMinutes * 60_000;
}

/**
 * Personalised tip + brain fun fact after the daily workout. Built from the
 * rounds the server accepted for that local day; cached in coachTips/{uid}_{day}.
 */
export const getBrainCoachTip = onCall({ region: REGION, secrets: [GROQ_API_KEY], timeoutSeconds: 60 }, async (req) => {
  const uid = requireUid(req.auth);
  const day = req.data?.day;
  const tz = req.data?.tzOffsetMinutes;
  if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new HttpsError('invalid-argument', 'day must be yyyy-MM-dd');
  if (typeof tz !== 'number' || !Number.isInteger(tz) || Math.abs(tz) > 14 * 60) throw new HttpsError('invalid-argument', 'bad tzOffsetMinutes');
  const start = localDayStartUtc(day, tz);
  const now = Date.now();
  if (start > now + 3600_000 || start < now - 3 * 86400_000) throw new HttpsError('invalid-argument', 'day out of range');

  const cacheRef = db.doc(`coachTips/${uid}_${day}`);
  const cached = await cacheRef.get();
  if (cached.exists && cached.get('source') === 'ai') {
    return { tip: cached.get('tip'), funFact: cached.get('funFact'), focusSkill: cached.get('focusSkill'), source: 'ai', cached: true };
  }

  const snap = await db
    .collection('gameSessions')
    .where('uid', '==', uid)
    .where('playedAt', '>=', Timestamp.fromMillis(start))
    .where('playedAt', '<', Timestamp.fromMillis(start + 86400_000))
    .orderBy('playedAt', 'desc')
    .limit(20)
    .get();
  if (snap.empty) throw new HttpsError('failed-precondition', 'Play today’s workout first.');

  const user = (await db.doc(`users/${uid}`).get()).data() ?? {};
  const skills = Object.fromEntries(SKILLS.map((s) => [s, Number(user.skills?.[s] ?? 0)])) as Record<Skill, number>;
  const input: CoachInput = {
    sessions: snap.docs.map((d) => ({
      gameId: d.get('gameId'),
      score: d.get('score'),
      accuracy: d.get('accuracy') ?? 0,
      maxLevel: d.get('maxLevel'),
      avgReactionMs: d.get('avgReactionMs') ?? null,
      stars: d.get('stars') ?? 0,
    })) as DaySession[],
    skills,
    streak: Number(user.currentStreak ?? 0),
  };

  const attempts = Number(cached.get('attempts') ?? 0);
  if (attempts < COACH_MAX_AI_ATTEMPTS) {
    try {
      const tip = await generateCoachTip(llmFactory(), input);
      await cacheRef.set({ uid, day, ...tip, createdAt: FieldValue.serverTimestamp() });
      return { ...tip, cached: false };
    } catch (e) {
      logger.warn('Coach AI failed, using fallback', { uid, error: (e as Error).message });
      await cacheRef.set({ uid, day, source: 'fallback', attempts: attempts + 1 }, { merge: true });
    }
  }
  const seed = [...day].reduce((a, c) => a + c.charCodeAt(0), 0) + snap.size;
  return { ...fallbackCoachTip(input, seed), cached: false };
});

// --- Endless Mode -------------------------------------------------------------------

interface EndlessState {
  day: string;
  used: number;
  run: number;
  lives: number;
  bestRun: number;
  solved: number;
  activePuzzleId: string | null;
  recent: string[];
  /** A rewarded ad already gave this run an extra life. */
  revived: boolean;
}

function endlessState(raw: unknown, today: string): EndlessState {
  const e = (raw ?? {}) as Partial<EndlessState>;
  return {
    day: today,
    used: e.day === today ? e.used ?? 0 : 0,
    run: e.run ?? 0,
    lives: e.lives ?? ENDLESS_LIVES,
    bestRun: e.bestRun ?? 0,
    solved: e.solved ?? 0,
    activePuzzleId: e.activePuzzleId ?? null,
    recent: Array.isArray(e.recent) ? e.recent.slice(-50) : [],
    revived: e.revived === true,
  };
}

function publicPuzzle(id: string, p: Pick<Puzzle, 'kind' | 'question' | 'choices' | 'difficulty' | 'source'>) {
  return { puzzleId: id, kind: p.kind, question: p.question, choices: p.choices, difficulty: p.difficulty, source: p.source };
}

function cryptoRandom(): number {
  return randomInt(0, 2 ** 31) / 2 ** 31;
}

/**
 * Serves the next Endless puzzle. The answer stays on the server
 * (endlessPuzzles is not readable by clients). Re-requesting before answering
 * returns the same puzzle, so players cannot skip hard ones.
 */
export const getEndlessPuzzle = onCall({ region: REGION, secrets: [GROQ_API_KEY], timeoutSeconds: 60 }, async (req) => {
  const uid = requireUid(req.auth);
  const newRun = req.data?.newRun === true;
  const today = new Date().toISOString().slice(0, 10);
  const userRef = db.doc(`users/${uid}`);
  const userSnap = await userRef.get();
  const pro = proActive(userSnap.get('entitlements'), Date.now());
  const state = endlessState(userSnap.get('endless'), today);
  const freePerDay = (await economy()).free_endless_per_day;

  if (newRun || state.lives <= 0) {
    state.run = 0;
    state.lives = ENDLESS_LIVES;
    state.revived = false;
  }

  if (state.activePuzzleId && !newRun) {
    const active = await db.doc(`endlessPuzzles/${state.activePuzzleId}`).get();
    if (active.exists && active.get('answered') === false) {
      await userRef.set({ endless: state }, { merge: true });
      return { ...publicPuzzle(active.id, active.data() as Puzzle), run: state.run, lives: state.lives, bestRun: state.bestRun, remainingToday: pro ? null : freePerDay - state.used };
    }
  }

  if (!pro && state.used >= freePerDay) {
    throw new HttpsError('resource-exhausted', `You’ve used today’s ${freePerDay} free puzzles. NeuroRush Pro unlocks unlimited Endless Mode.`);
  }

  let puzzle: Puzzle | null = null;
  try {
    puzzle = await generateVerifiedPuzzle(llmFactory(), state.run, cryptoRandom, new Set(state.recent));
  } catch (e) {
    logger.warn('Endless AI failed, using generated puzzle', { uid, error: (e as Error).message });
  }
  if (!puzzle) puzzle = generatedSequencePuzzle(state.run, cryptoRandom);

  const id = randomBytes(12).toString('hex');
  await db.doc(`endlessPuzzles/${id}`).set({ uid, ...puzzle, answered: false, createdAt: FieldValue.serverTimestamp() });
  state.used += 1;
  state.activePuzzleId = id;
  state.recent = [...state.recent, puzzleHash(puzzle.question)].slice(-50);
  await userRef.set({ endless: state }, { merge: true });
  return { ...publicPuzzle(id, puzzle), run: state.run, lives: state.lives, bestRun: state.bestRun, remainingToday: pro ? null : freePerDay - state.used };
});

/** Checks an Endless answer on the server and updates the run. answerIndex -1 = timed out. */
export const submitEndlessAnswer = onCall({ region: REGION }, async (req) => {
  const uid = requireUid(req.auth);
  const puzzleId = req.data?.puzzleId;
  const answerIndex = req.data?.answerIndex;
  if (typeof puzzleId !== 'string' || !/^[a-f0-9]{24}$/.test(puzzleId)) throw new HttpsError('invalid-argument', 'bad puzzleId');
  if (typeof answerIndex !== 'number' || !Number.isInteger(answerIndex) || answerIndex < -1 || answerIndex >= CHOICES) {
    throw new HttpsError('invalid-argument', 'bad answerIndex');
  }
  const today = new Date().toISOString().slice(0, 10);
  const econ = await economy();
  return db.runTransaction(async (tx) => {
    const pRef = db.doc(`endlessPuzzles/${puzzleId}`);
    const uRef = db.doc(`users/${uid}`);
    const [p, u] = await Promise.all([tx.get(pRef), tx.get(uRef)]);
    if (!p.exists || p.get('uid') !== uid) throw new HttpsError('not-found', 'Puzzle not found.');
    if (p.get('answered') === true) throw new HttpsError('failed-precondition', 'Already answered.');
    const state = endlessState(u.get('endless'), today);
    const created = (p.get('createdAt') as Timestamp | undefined)?.toMillis() ?? Date.now();
    const inTime = Date.now() - created <= ENDLESS_ANSWER_WINDOW_MS;
    const correct = inTime && answerIndex === p.get('answerIndex');
    if (correct) {
      state.run += 1;
      state.solved += 1;
      state.bestRun = Math.max(state.bestRun, state.run);
    } else {
      state.lives = Math.max(0, state.lives - 1);
    }
    if (state.activePuzzleId === puzzleId) state.activePuzzleId = null;
    const capped = capDailyCoins(u.get('coinEarn') as CoinEarnState | undefined, today, correct ? econ.coins_endless_solve : 0, econ.coins_daily_cap);
    tx.update(pRef, { answered: true, correct, givenIndex: answerIndex, answeredAt: FieldValue.serverTimestamp() });
    tx.set(
      uRef,
      { endless: state, ...(capped.granted > 0 ? { coins: FieldValue.increment(capped.granted), coinEarn: capped.state } : {}) },
      { merge: true },
    );
    return {
      correct,
      timedOut: !inTime,
      answerIndex: p.get('answerIndex') as number,
      explanation: p.get('explanation') as string,
      run: state.run,
      lives: state.lives,
      bestRun: state.bestRun,
      gameOver: state.lives === 0,
      coinsEarned: capped.granted,
    };
  });
});
