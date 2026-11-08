/**
 * Battle questions are generated on the server so answers never reach the
 * client before the round ends. Mirrors the style of the single-player games.
 */
export type BattleQuestion =
  | { type: 'math'; prompt: string; choices: string[] }
  | { type: 'sequence'; prompt: string; choices: string[] }
  | { type: 'stroop'; word: number; ink: number; choices: string[] };

export interface GeneratedQuestion {
  question: BattleQuestion;
  answerIndex: number;
}

/** Same 6 colour slots as the app's Color Clash palettes. */
export const STROOP_COLORS = 6;
export const BATTLE_QUESTIONS = 8;

type Rnd = () => number;
const ri = (r: Rnd, a: number, b: number) => a + Math.floor(r() * (b - a + 1));

function shuffle<T>(r: Rnd, a: T[]): T[] {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(r() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function numericChoices(r: Rnd, answer: number, tempting: number[] = []): { choices: string[]; answerIndex: number } {
  const set = new Set<number>([answer]);
  for (const t of tempting) if (set.size < 4 && t >= 0) set.add(t);
  const offsets = [1, 2, 3, 10];
  while (set.size < 4) {
    const v = answer + offsets[ri(r, 0, offsets.length - 1)] * (r() < 0.5 ? -1 : 1);
    if (v >= 0) set.add(v);
  }
  const choices = shuffle(r, [...set]).map(String);
  return { choices, answerIndex: choices.indexOf(String(answer)) };
}

function math(r: Rnd, level: number): GeneratedQuestion {
  let prompt: string, answer: number;
  const kind = ri(r, 0, level >= 3 ? 3 : 1);
  if (kind === 0) {
    const a = ri(r, 5, 20 * level), b = ri(r, 5, 20 * level);
    [prompt, answer] = [`${a} + ${b}`, a + b];
  } else if (kind === 1) {
    let a = ri(r, 10, 25 * level), b = ri(r, 2, 20 * level);
    if (b > a) [a, b] = [b, a];
    [prompt, answer] = [`${a} − ${b}`, a - b];
  } else if (kind === 2) {
    const a = ri(r, 3, 6 + level), b = ri(r, 3, 9);
    [prompt, answer] = [`${a} × ${b}`, a * b];
  } else {
    const d = ri(r, 2, 9), q = ri(r, 2, 6 + level);
    [prompt, answer] = [`${d * q} ÷ ${d}`, q];
  }
  const c = numericChoices(r, answer);
  return { question: { type: 'math', prompt, choices: c.choices }, answerIndex: c.answerIndex };
}

function sequence(r: Rnd, level: number): GeneratedQuestion {
  let terms: number[];
  const kind = ri(r, 0, Math.min(3, level));
  if (kind === 0) {
    const d = ri(r, 2, 9), a = ri(r, 1, 20);
    terms = [0, 1, 2, 3, 4].map((i) => a + d * i);
  } else if (kind === 1) {
    const m = ri(r, 2, 3), a = ri(r, 1, 4);
    terms = [0, 1, 2, 3, 4].map((i) => a * m ** i);
  } else if (kind === 2) {
    const a = ri(r, 1, 9), d = ri(r, 1, 3);
    terms = [a];
    for (let i = 0; i < 4; i++) terms.push(terms[terms.length - 1] + d + i);
  } else {
    const a = ri(r, 1, 4), b = ri(r, a, a + 3);
    terms = [a, b];
    while (terms.length < 5) terms.push(terms[terms.length - 1] + terms[terms.length - 2]);
  }
  const answer = terms[4];
  const shown = terms.slice(0, 4);
  const c = numericChoices(r, answer, [shown[3] + (shown[3] - shown[2]) + 1]);
  return { question: { type: 'sequence', prompt: `${shown.join(', ')}, ?`, choices: c.choices }, answerIndex: c.answerIndex };
}

function stroop(r: Rnd): GeneratedQuestion {
  const ink = ri(r, 0, STROOP_COLORS - 1);
  let word = ink;
  while (word === ink) word = ri(r, 0, STROOP_COLORS - 1);
  const set = new Set<number>([ink, word]);
  while (set.size < 4) set.add(ri(r, 0, STROOP_COLORS - 1));
  const opts = shuffle(r, [...set]);
  return { question: { type: 'stroop', word, ink, choices: opts.map(String) }, answerIndex: opts.indexOf(ink) };
}

/** 8 questions getting harder, mixing the three types. */
export function generateBattle(r: Rnd): GeneratedQuestion[] {
  const out: GeneratedQuestion[] = [];
  for (let i = 0; i < BATTLE_QUESTIONS; i++) {
    const level = 1 + Math.floor(i / 2);
    const t = i % 3;
    out.push(t === 0 ? math(r, level) : t === 1 ? stroop(r) : sequence(r, level));
  }
  return out;
}

/** Deterministic PRNG (mulberry32) so tests can reproduce battles. */
export function seededRandom(seed: number): Rnd {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
