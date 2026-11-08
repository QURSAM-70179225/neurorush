/** Pure battle rules (timing, scoring, trophies); unit tested. */
export const COUNTDOWN_MS = 5000;
export const QUESTION_MS = 8000;
export const MAX_SPEED_BONUS = 100;
export const BASE_POINTS = 100;
/** Grace for network latency when an answer arrives right at the end. */
export const LATE_GRACE_MS = 600;

export type BattleMode = 'random' | 'invite' | 'bot';

export function questionWindow(startAt: number, index: number, qMs = QUESTION_MS): { opens: number; closes: number } {
  const opens = startAt + index * qMs;
  return { opens, closes: opens + qMs };
}

export function battleEndsAt(startAt: number, count: number, qMs = QUESTION_MS): number {
  return startAt + count * qMs;
}

/** Index of the question open at [now], or -1 before start / [count] after the end. */
export function currentQuestion(startAt: number, count: number, now: number, qMs = QUESTION_MS): number {
  if (now < startAt) return -1;
  return Math.min(count, Math.floor((now - startAt) / qMs));
}

/** 100 for a correct answer plus up to 100 for speed. */
export function pointsFor(correct: boolean, responseMs: number, qMs = QUESTION_MS): number {
  if (!correct) return 0;
  const clamped = Math.min(Math.max(responseMs, 0), qMs);
  return BASE_POINTS + Math.round(MAX_SPEED_BONUS * (1 - clamped / qMs));
}

export interface TrophyResult {
  winner: string | null; // null = draw
  delta: Record<string, number>;
}

const TROPHIES: Record<BattleMode, { win: number; lose: number; draw: number }> = {
  random: { win: 30, lose: -20, draw: 10 },
  invite: { win: 15, lose: -10, draw: 5 },
  bot: { win: 10, lose: 0, draw: 0 },
};

/** Winner and trophy changes; trophies never drop below zero. */
export function trophyResult(mode: BattleMode, scores: Record<string, number>, current: Record<string, number>): TrophyResult {
  const [a, b] = Object.keys(scores);
  const t = TROPHIES[mode];
  const delta: Record<string, number> = {};
  let winner: string | null = null;
  if (scores[a] === scores[b]) {
    delta[a] = t.draw;
    delta[b] = t.draw;
  } else {
    winner = scores[a] > scores[b] ? a : b;
    const loser = winner === a ? b : a;
    delta[winner] = t.win;
    delta[loser] = Math.max(t.lose, -(current[loser] ?? 0));
  }
  return { winner, delta };
}

/** A practice-bot plan: per question, correct or not and answer time. */
export function botPlan(rnd: () => number, count: number, qMs = QUESTION_MS): { correct: boolean; ms: number }[] {
  return Array.from({ length: count }, (_, i) => ({
    correct: rnd() < 0.72 - i * 0.03,
    ms: Math.round(qMs * (0.18 + rnd() * 0.56)),
  }));
}
