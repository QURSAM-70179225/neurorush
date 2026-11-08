import { GameDef, GAMES, SKILLS, Skill } from './catalog';

/** Mirrors lib/domain/logic/rewards.dart. */
export function starsFor(game: GameDef, score: number, accuracy: number, correct: number): number {
  if (correct === 0) return 0;
  const [, two, three] = game.starThresholds;
  if (score >= three && accuracy >= 0.8) return 3;
  if (score >= two) return 2;
  return 1;
}

export function xpFor(score: number, stars: number, accuracy: number): number {
  return Math.max(5, Math.floor(score / 20) + stars * 15 + (accuracy >= 0.9 ? 20 : 0));
}

/** Mirrors lib/domain/logic/xp_levels.dart. */
export const MAX_PLAYER_LEVEL = 50;
export function totalXpForLevel(level: number): number {
  const l = Math.min(Math.max(level, 1), MAX_PLAYER_LEVEL) - 1;
  return 100 * l + 40 * Math.floor((l * (l - 1)) / 2);
}
export function levelFromXp(xp: number): number {
  let level = 1;
  while (level < MAX_PLAYER_LEVEL && xp >= totalXpForLevel(level + 1)) level++;
  return level;
}

/** Mirrors BrainScore.sessionRating in lib/domain/logic/brain_score.dart. */
export function sessionRating(gameId: string, score: number, accuracy: number, maxLevel: number, durationSeconds: number): number {
  const game = GAMES[gameId];
  const perMinute = durationSeconds <= 0 ? 0 : (score * 60) / durationSeconds;
  const scorePart = Math.min(1, perMinute / game.starThresholds[2]);
  const levelPart = Math.min(Math.max(maxLevel - 1, 0), 9) / 9;
  return Math.min(1, Math.max(0, 0.55 * scorePart + 0.3 * accuracy + 0.15 * levelPart));
}

export const RATING_WINDOW = 12;
export const RATING_DECAY = 0.8;
export const MAX_PER_SKILL = 200;

/** [ratings] newest first. */
export function skillScore(ratings: number[]): number {
  if (ratings.length === 0) return 0;
  let weight = 1, sum = 0, weights = 0;
  for (const r of ratings.slice(0, RATING_WINDOW)) {
    sum += r * weight;
    weights += weight;
    weight *= RATING_DECAY;
  }
  return Math.round((sum / weights) * MAX_PER_SKILL);
}

export type SkillRatings = Partial<Record<Skill, number[]>>;

export function brainScore(ratings: SkillRatings): { total: number; skills: Record<Skill, number> } {
  const skills = {} as Record<Skill, number>;
  let total = 0;
  for (const s of SKILLS) {
    skills[s] = skillScore(ratings[s] ?? []);
    total += skills[s];
  }
  return { total, skills };
}
