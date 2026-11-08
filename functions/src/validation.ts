import { ALLOWED_DURATIONS, GAMES, MAX_LEVEL, MAX_MULTIPLIER } from './catalog';

export interface SessionInput {
  id: string;
  gameId: string;
  score: number;
  correct: number;
  wrong: number;
  maxCombo: number;
  maxLevel: number;
  avgReactionMs: number | null;
  bestReactionMs: number | null;
  /** Finish time, epoch milliseconds. */
  playedAt: number;
  durationSeconds: number;
}

export class InvalidInput extends Error {}

/** Fastest plausible human reaction (ms) for a single answer. */
export const MIN_HUMAN_REACTION_MS = 100;
/** Fastest plausible average over a round. */
export const MIN_HUMAN_AVERAGE_MS = 150;
/** Offline rounds may be uploaded up to this long after they were played. */
export const MAX_UPLOAD_DELAY_MS = 14 * 24 * 3600 * 1000;
export const MAX_CLOCK_SKEW_MS = 2 * 60 * 1000;

function int(v: unknown, name: string, min = 0, max = 10_000_000): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) {
    throw new InvalidInput(`${name} must be an integer in [${min}, ${max}]`);
  }
  return v;
}

function optInt(v: unknown, name: string): number | null {
  return v === null || v === undefined ? null : int(v, name, 0, 600_000);
}

/** Checks the shape of the payload; throws [InvalidInput] for malformed data. */
export function parseSession(raw: unknown): SessionInput {
  if (typeof raw !== 'object' || raw === null) throw new InvalidInput('session must be an object');
  const r = raw as Record<string, unknown>;
  if (typeof r.id !== 'string' || !/^[A-Za-z0-9-]{8,64}$/.test(r.id)) throw new InvalidInput('bad id');
  if (typeof r.gameId !== 'string' || !(r.gameId in GAMES)) throw new InvalidInput('unknown game');
  return {
    id: r.id,
    gameId: r.gameId,
    score: int(r.score, 'score'),
    correct: int(r.correct, 'correct', 0, 10_000),
    wrong: int(r.wrong, 'wrong', 0, 10_000),
    maxCombo: int(r.maxCombo, 'maxCombo', 0, 10_000),
    maxLevel: int(r.maxLevel, 'maxLevel', 1, MAX_LEVEL),
    avgReactionMs: optInt(r.avgReactionMs, 'avgReactionMs'),
    bestReactionMs: optInt(r.bestReactionMs, 'bestReactionMs'),
    playedAt: int(r.playedAt, 'playedAt', 0, Number.MAX_SAFE_INTEGER),
    durationSeconds: int(r.durationSeconds, 'durationSeconds', 1, 600),
  };
}

export type Verdict = { ok: true } | { ok: false; reason: string };

/**
 * Anti-cheat: rejects rounds that the game rules make impossible (too many
 * answers, too many points, inhuman reaction times, inconsistent numbers).
 */
export function validateSession(s: SessionInput, nowMs: number): Verdict {
  const game = GAMES[s.gameId];
  const answers = s.correct + s.wrong;
  const fail = (reason: string): Verdict => ({ ok: false, reason });

  if (!ALLOWED_DURATIONS.includes(s.durationSeconds)) return fail('duration');
  if (s.playedAt > nowMs + MAX_CLOCK_SKEW_MS) return fail('future');
  if (s.playedAt < nowMs - MAX_UPLOAD_DELAY_MS) return fail('too_old');
  if (answers > Math.floor(s.durationSeconds / game.minSecondsPerAnswer)) return fail('too_many_answers');
  if (s.maxCombo > s.correct) return fail('combo');
  if (s.correct === 0 && s.score !== 0) return fail('score_without_answers');
  if (s.score > s.correct * game.maxBasePoints * MAX_MULTIPLIER) return fail('score_too_high');
  if (s.score < s.correct * game.minBasePoints) return fail('score_too_low');
  if (s.bestReactionMs !== null && s.bestReactionMs < MIN_HUMAN_REACTION_MS) return fail('reaction_inhuman');
  if (s.avgReactionMs !== null && s.avgReactionMs < MIN_HUMAN_AVERAGE_MS) return fail('average_inhuman');
  if (s.avgReactionMs !== null && s.bestReactionMs !== null && s.bestReactionMs > s.avgReactionMs) {
    return fail('reaction_inconsistent');
  }
  if ((s.avgReactionMs === null) !== (s.bestReactionMs === null)) return fail('reaction_inconsistent');
  return { ok: true };
}
