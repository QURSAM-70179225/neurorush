import { createHash } from 'crypto';
import { ChatMessage, cleanText, LlmClient } from './llm';

export type PuzzleKind = 'sequence' | 'riddle' | 'logic';

export interface Puzzle {
  kind: PuzzleKind;
  question: string;
  choices: string[];
  answerIndex: number;
  explanation: string;
  difficulty: number;
  source: 'ai' | 'generated';
}

export const CHOICES = 4;

/** 1 = easy … 5 = expert, from how many puzzles were solved in this run. */
export function difficultyForRun(run: number): number {
  return Math.min(5, 1 + Math.floor(run / 3));
}

const DIFFICULTY_WORDS = ['', 'easy', 'fairly easy', 'medium', 'hard', 'very hard'];

const THEMES = [
  'animals', 'space', 'cricket', 'cooking', 'trains', 'music', 'gardens', 'clocks', 'birthdays', 'mountains',
  'oceans', 'colours', 'school', 'markets', 'weather', 'travel', 'robots', 'books', 'kites', 'football',
];

export function generationMessages(kind: PuzzleKind, difficulty: number, theme: string): ChatMessage[] {
  const what = {
    sequence: 'a number-sequence puzzle: show 5 or 6 numbers and ask which number comes next. Use a clear rule (arithmetic, geometric, squares, alternating steps, Fibonacci-like, etc.).',
    riddle: `a short lateral-thinking or word riddle themed around ${theme}, with one clearly best answer.`,
    logic: `a short logic puzzle themed around ${theme} (ordering, who-is-who, simple deduction or arithmetic word problem) with exactly one correct answer.`,
  }[kind];
  return [
    {
      role: 'system',
      content:
        'You write puzzles for NeuroRush, a family-friendly brain game. Reply ONLY with JSON: ' +
        '{"question": string, "choices": [4 strings], "answerIndex": 0-3, "explanation": string}. ' +
        'Rules: question max 280 characters; each choice max 40 characters; all choices different and plausible; ' +
        'exactly one correct choice; explanation max 200 characters explains why. ' +
        'No trick wording, no culturally sensitive or violent content, no emojis, no markdown.',
    },
    { role: 'user', content: `Create ${what} Difficulty: ${DIFFICULTY_WORDS[difficulty]} (${difficulty}/5).` },
  ];
}

export function solverMessages(p: Pick<Puzzle, 'question' | 'choices'>): ChatMessage[] {
  return [
    {
      role: 'system',
      content:
        'You are a careful puzzle solver. Think it through, then reply ONLY with JSON: ' +
        '{"answerIndex": 0-3, "confident": true|false}. Set confident to false if more than one choice could be correct or none is.',
    },
    {
      role: 'user',
      content: `${p.question}\nChoices:\n${p.choices.map((c, i) => `${i}. ${c}`).join('\n')}`,
    },
  ];
}

/** Validates and normalises a model-produced puzzle; null if unusable. */
export function parsePuzzle(raw: Record<string, unknown>, kind: PuzzleKind, difficulty: number): Puzzle | null {
  const question = cleanText(raw.question, 300);
  const explanation = cleanText(raw.explanation, 220);
  if (!question || !explanation || !Array.isArray(raw.choices) || raw.choices.length !== CHOICES) return null;
  const choices = raw.choices.map((c) => cleanText(typeof c === 'number' ? String(c) : c, 48, 1));
  if (choices.some((c) => c === null)) return null;
  const norm = choices.map((c) => c!.toLowerCase());
  if (new Set(norm).size !== CHOICES) return null;
  const idx = raw.answerIndex;
  if (typeof idx !== 'number' || !Number.isInteger(idx) || idx < 0 || idx >= CHOICES) return null;
  // Never leak the answer in the question.
  if (question.toLowerCase().includes(`answer is ${norm[idx]}`)) return null;
  return { kind, question, choices: choices as string[], answerIndex: idx, explanation, difficulty, source: 'ai' };
}

/** For sequences, checks the numbers follow a recognisable rule leading to the answer. */
export function sequenceIsConsistent(p: Puzzle): boolean {
  const nums = (p.question.match(/-?\d+(?:\.\d+)?/g) ?? []).map(Number);
  const answer = Number(p.choices[p.answerIndex].replace(/[^\d.-]/g, ''));
  if (nums.length < 4 || !Number.isFinite(answer)) return false;
  const terms = nums.slice(-6);
  const t = [...terms, answer];
  const diffs = t.slice(1).map((v, i) => v - t[i]);
  const allEq = (a: number[]) => a.every((x) => Math.abs(x - a[0]) < 1e-9);
  const second = diffs.slice(1).map((v, i) => v - diffs[i]);
  const ratios = t.every((v) => v !== 0) ? t.slice(1).map((v, i) => v / t[i]) : [];
  const fib = t.slice(2).every((v, i) => v === t[i] + t[i + 1]);
  const alternating = diffs.length >= 4 && diffs[0] !== diffs[1] && diffs.every((d, i) => d === diffs[i % 2]);
  // Constant first or second differences cover arithmetic, square and triangular numbers.
  return allEq(diffs) || allEq(second) || (ratios.length > 0 && allEq(ratios)) || fib || alternating;
}

export function puzzleHash(question: string): string {
  return createHash('sha1').update(question.toLowerCase().replace(/[^a-z0-9]/g, '')).digest('hex').slice(0, 16);
}

/**
 * AI puzzle with an independent check: a second model call must solve it to
 * the same answer with confidence, otherwise the puzzle is discarded.
 */
export async function generateVerifiedPuzzle(llm: LlmClient, run: number, rnd: () => number, seen: Set<string>): Promise<Puzzle | null> {
  const difficulty = difficultyForRun(run);
  const kinds: PuzzleKind[] = ['sequence', 'riddle', 'logic'];
  for (let attempt = 0; attempt < 3; attempt++) {
    const kind = kinds[Math.floor(rnd() * kinds.length)];
    const theme = THEMES[Math.floor(rnd() * THEMES.length)];
    const raw = await llm.json(generationMessages(kind, difficulty, theme), { temperature: 0.95, maxTokens: 450 });
    const p = parsePuzzle(raw, kind, difficulty);
    if (!p || seen.has(puzzleHash(p.question))) continue;
    if (kind === 'sequence' && !sequenceIsConsistent(p)) continue;
    const check = await llm.json(solverMessages(p), { temperature: 0, maxTokens: 300 });
    if (check.answerIndex === p.answerIndex && check.confident === true) return p;
  }
  return null;
}

/** Algorithmic sequence puzzle (no AI), used when the AI is unavailable. */
export function generatedSequencePuzzle(run: number, rnd: () => number): Puzzle {
  const difficulty = difficultyForRun(run);
  const r = (a: number, b: number) => a + Math.floor(rnd() * (b - a + 1));
  let terms: number[];
  let rule: string;
  const family = r(0, Math.min(4, difficulty));
  if (family === 0) {
    const d = r(2, 9), a = r(1, 30);
    terms = Array.from({ length: 6 }, (_, i) => a + d * i);
    rule = `Each number goes up by ${d}.`;
  } else if (family === 1) {
    const m = r(2, 3), a = r(1, 5);
    terms = Array.from({ length: 6 }, (_, i) => a * m ** i);
    rule = `Each number is multiplied by ${m}.`;
  } else if (family === 2) {
    const a = r(1, 10), d0 = r(1, 4);
    terms = [a];
    for (let i = 0; i < 5; i++) terms.push(terms[terms.length - 1] + d0 + i);
    rule = 'The gap grows by 1 each time.';
  } else if (family === 3) {
    const a = r(1, 5), b = r(a, a + 4);
    terms = [a, b];
    while (terms.length < 6) terms.push(terms[terms.length - 1] + terms[terms.length - 2]);
    rule = 'Each number is the sum of the two before it.';
  } else {
    const k = r(2, 7), c = r(0, 5);
    terms = Array.from({ length: 6 }, (_, i) => (k + i) ** 2 + c);
    rule = c === 0 ? 'These are square numbers.' : `These are square numbers plus ${c}.`;
  }
  const answer = terms[5];
  const shown = terms.slice(0, 5);
  const options = new Set<number>([answer]);
  const offsets = [1, 2, 3, 5, 10];
  while (options.size < CHOICES) {
    const v = answer + offsets[r(0, offsets.length - 1)] * (rnd() < 0.5 ? -1 : 1);
    if (v >= 0) options.add(v);
  }
  const choices = [...options].map(String);
  for (let i = choices.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [choices[i], choices[j]] = [choices[j], choices[i]];
  }
  return {
    kind: 'sequence',
    question: `What number comes next? ${shown.join(', ')}, ?`,
    choices,
    answerIndex: choices.indexOf(String(answer)),
    explanation: `${rule} So the next number is ${answer}.`,
    difficulty,
    source: 'generated',
  };
}

/** Normalises a free-text answer for comparison. */
export function normaliseAnswer(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, ' ');
}
