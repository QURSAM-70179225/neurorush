/**
 * AI functions end-to-end on the emulators, with a mock Groq server.
 * Run with: npm run test:emulators
 */
import { createServer, Server } from 'http';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const PROJECT = 'demo-neurorush';
const FN = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
if (getApps().length === 0) initializeApp({ projectId: PROJECT });
const db = getFirestore();

// --- mock Groq -----------------------------------------------------------------
let mode: 'ok' | 'down' = 'ok';
let groqCalls: { auth?: string; model: string; system: string }[] = [];
/** Every puzzle the mock has written (each one unique, like a real model). */
const PUZZLES: { question: string; choices: string[]; answerIndex: number; explanation: string }[] = [];
function nextPuzzle() {
  const k = PUZZLES.length + 2;
  const terms = [1, 2, 3, 4, 5].map((i) => i * k);
  const answer = 6 * k;
  const choices = [answer - 1, answer, answer + 1, answer + k].map(String);
  const p = { question: `What number comes next? ${terms.join(', ')}, ?`, choices, answerIndex: 1, explanation: `Add ${k} each time.` };
  PUZZLES.push(p);
  return p;
}
let server: Server;

beforeAll(async () => {
  server = createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      const body = JSON.parse(raw);
      const system: string = body.messages[0].content;
      groqCalls.push({ auth: req.headers.authorization, model: body.model, system });
      if (mode === 'down') {
        res.writeHead(503).end('{}');
        return;
      }
      let content: unknown;
      if (system.includes('brain coach')) {
        content = { tip: 'Great speed today! Try Number Sequence next to build your logic.', funFact: 'Your brain has about 86 billion neurons.' };
      } else if (system.includes('puzzle solver')) {
        const user: string = body.messages[1].content;
        const p = PUZZLES.find((x) => user.startsWith(x.question))!; // solver "solves" it
        content = { answerIndex: p.answerIndex, confident: true };
      } else {
        content = nextPuzzle();
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ message: { content: JSON.stringify(content) } }] }));
    });
  });
  await new Promise<void>((r) => server.listen(4599, '127.0.0.1', () => r()));
});
afterAll(() => new Promise((r) => server.close(r)));
beforeEach(() => {
  mode = 'ok';
  groqCalls = [];
});

async function newUser(): Promise<{ uid: string; token: string }> {
  const r = await fetch(`${AUTH}/accounts:signUp?key=fake`, { method: 'POST', body: JSON.stringify({ returnSecureToken: true }), headers: { 'content-type': 'application/json' } });
  const j = (await r.json()) as { localId: string; idToken: string };
  return { uid: j.localId, token: j.idToken };
}
async function call<T = Record<string, unknown>>(name: string, token: string, data: unknown) {
  const r = await fetch(`${FN}/${name}`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` }, body: JSON.stringify({ data }) });
  return (await r.json()) as { result?: T; error?: { status: string; message: string } };
}
jest.setTimeout(30000);

const today = () => new Date().toISOString().slice(0, 10);

test('coach: needs a workout, then returns an AI tip once and serves it from cache', async () => {
  const u = await newUser();
  const early = await call('getBrainCoachTip', u.token, { day: today(), tzOffsetMinutes: 0 });
  expect(early.error?.status).toBe('FAILED_PRECONDITION');

  await db.doc(`gameSessions/coach-${u.uid}`).set({
    uid: u.uid, gameId: 'speed_math', score: 1500, accuracy: 0.9, maxLevel: 6, avgReactionMs: 1200, stars: 2,
    playedAt: Timestamp.now(),
  });
  const first = await call<{ tip: string; funFact: string; source: string; cached: boolean; focusSkill: string }>('getBrainCoachTip', u.token, { day: today(), tzOffsetMinutes: 0 });
  expect(first.result).toMatchObject({ source: 'ai', cached: false });
  expect(first.result?.tip).toContain('Number Sequence');
  expect(groqCalls).toHaveLength(1);
  expect(groqCalls[0]).toMatchObject({ auth: 'Bearer emulator-test-key', model: 'mock-llama' });

  const again = await call<{ cached: boolean; tip: string }>('getBrainCoachTip', u.token, { day: today(), tzOffsetMinutes: 0 });
  expect(again.result?.cached).toBe(true);
  expect(again.result?.tip).toBe(first.result?.tip);
  expect(groqCalls).toHaveLength(1);
});

test('coach: falls back to a curated tip when Groq is down', async () => {
  const u = await newUser();
  await db.doc(`gameSessions/coach2-${u.uid}`).set({ uid: u.uid, gameId: 'word_scramble', score: 300, accuracy: 0.5, maxLevel: 2, avgReactionMs: null, stars: 1, playedAt: Timestamp.now() });
  mode = 'down';
  const r = await call<{ source: string; tip: string; funFact: string }>('getBrainCoachTip', u.token, { day: today(), tzOffsetMinutes: 0 });
  expect(r.result?.source).toBe('fallback');
  expect(r.result?.tip.length).toBeGreaterThan(20);
  expect(r.result?.funFact.length).toBeGreaterThan(20);
});

test('endless: verified AI puzzle, answer hidden, validated on the server, lives and runs', async () => {
  const u = await newUser();
  const p1 = await call<{ puzzleId: string; question: string; choices: string[]; run: number; lives: number; remainingToday: number }>('getEndlessPuzzle', u.token, { newRun: true });
  expect(p1.result).toMatchObject({ run: 0, lives: 3, remainingToday: 9 });
  expect(p1.result).not.toHaveProperty('answerIndex');
  expect(p1.result).not.toHaveProperty('explanation');
  expect(groqCalls.map((c) => (c.system.includes('solver') ? 'solve' : 'write'))).toEqual(['write', 'solve']);

  // Asking again before answering returns the same puzzle (no skipping).
  const same = await call<{ puzzleId: string; remainingToday: number }>('getEndlessPuzzle', u.token, {});
  expect(same.result?.puzzleId).toBe(p1.result?.puzzleId);
  expect(same.result?.remainingToday).toBe(9);

  const puzzle = PUZZLES.find((x) => x.question === p1.result!.question)!;
  const ok = await call<{ correct: boolean; run: number; lives: number; explanation: string }>('submitEndlessAnswer', u.token, { puzzleId: p1.result!.puzzleId, answerIndex: puzzle.answerIndex });
  expect(ok.result).toMatchObject({ correct: true, run: 1, lives: 3, answerIndex: puzzle.answerIndex });
  expect(ok.result?.explanation).toBe(puzzle.explanation);

  const twice = await call('submitEndlessAnswer', u.token, { puzzleId: p1.result!.puzzleId, answerIndex: puzzle.answerIndex });
  expect(twice.error?.status).toBe('FAILED_PRECONDITION');

  let lives = 3;
  for (let i = 0; i < 3; i++) {
    const p = await call<{ puzzleId: string; question: string }>('getEndlessPuzzle', u.token, {});
    const right = PUZZLES.find((x) => x.question === p.result!.question)!.answerIndex;
    const wrong = await call<{ correct: boolean; lives: number; gameOver: boolean; bestRun: number }>('submitEndlessAnswer', u.token, { puzzleId: p.result!.puzzleId, answerIndex: (right + 1) % 4 });
    lives--;
    expect(wrong.result).toMatchObject({ correct: false, lives, gameOver: lives === 0, bestRun: 1 });
  }
  const fresh = await call<{ run: number; lives: number }>('getEndlessPuzzle', u.token, {});
  expect(fresh.result).toMatchObject({ run: 0, lives: 3 });

  const other = await newUser();
  const steal = await call('submitEndlessAnswer', other.token, { puzzleId: p1.result!.puzzleId, answerIndex: 0 });
  expect(steal.error?.status).toBe('NOT_FOUND');
});

test('endless: free daily limit, Pro unlimited, generated puzzle when Groq is down', async () => {
  const u = await newUser();
  await db.doc(`users/${u.uid}`).set({ endless: { day: today(), used: 10, run: 0, lives: 3 } }, { merge: true });
  const blocked = await call('getEndlessPuzzle', u.token, {});
  expect(blocked.error?.status).toBe('RESOURCE_EXHAUSTED');

  await db.doc(`users/${u.uid}`).set({ entitlements: { pro: true } }, { merge: true });
  mode = 'down';
  const pro = await call<{ source: string; remainingToday: number | null; choices: string[] }>('getEndlessPuzzle', u.token, {});
  expect(pro.result).toMatchObject({ source: 'generated', remainingToday: null });
  expect(pro.result?.choices).toHaveLength(4);
});
