import { GAMES, Skill } from './catalog';
import { AchievementStats } from './achievements';
import { brainScore, levelFromXp, RATING_WINDOW, sessionRating, SkillRatings, starsFor, xpFor } from './rewards';
import { SessionInput } from './validation';

/** Server-managed part of users/{uid}. */
export interface ServerProfile {
  xp: number;
  level: number;
  rounds: number;
  bestScores: Record<string, number>;
  brainScore: number;
  skills: Record<Skill, number>;
  skillRatings: SkillRatings;
  stats: {
    threeStarRounds: number;
    perfectRounds: number;
    maxCombo: number;
    fastestReactionMs: number | null;
    gamesTried: Record<string, boolean>;
    maxDifficulty: number;
    friends: number;
  };
}

export function emptyProfile(): ServerProfile {
  return {
    xp: 0,
    level: 1,
    rounds: 0,
    bestScores: {},
    brainScore: 0,
    skills: { memory: 0, focus: 0, speed: 0, logic: 0, language: 0 },
    skillRatings: {},
    stats: {
      threeStarRounds: 0,
      perfectRounds: 0,
      maxCombo: 0,
      fastestReactionMs: null,
      gamesTried: {},
      maxDifficulty: 0,
      friends: 0,
    },
  };
}

/** Fills missing fields of a stored profile with defaults. */
export function normalizeProfile(raw: Record<string, unknown> | undefined): ServerProfile {
  const e = emptyProfile();
  if (!raw) return e;
  const p = raw as Partial<ServerProfile>;
  return {
    xp: p.xp ?? 0,
    level: p.level ?? 1,
    rounds: p.rounds ?? 0,
    bestScores: { ...(p.bestScores ?? {}) },
    brainScore: p.brainScore ?? 0,
    skills: { ...e.skills, ...(p.skills ?? {}) },
    skillRatings: { ...(p.skillRatings ?? {}) },
    stats: { ...e.stats, ...(p.stats ?? {}), gamesTried: { ...(p.stats?.gamesTried ?? {}) } },
  };
}

export interface SessionOutcome {
  stars: number;
  xp: number;
  accuracy: number;
  profile: ServerProfile;
}

/** A round counts as "perfect" with 100% accuracy over at least this many answers. */
export const PERFECT_MIN_ANSWERS = 10;

/** Applies one validated round to the profile. Pure; used inside a transaction. */
export function applySession(before: ServerProfile, s: SessionInput): SessionOutcome {
  const game = GAMES[s.gameId];
  const answers = s.correct + s.wrong;
  const accuracy = answers === 0 ? 0 : s.correct / answers;
  const stars = starsFor(game, s.score, accuracy, s.correct);
  const xp = xpFor(s.score, stars, accuracy);

  const p = normalizeProfile(before as unknown as Record<string, unknown>);
  p.xp += xp;
  p.level = levelFromXp(p.xp);
  p.rounds += 1;
  // Best scores only count full-length rounds so short Brain Test rounds don't lower the bar.
  if (s.durationSeconds === 60) p.bestScores[s.gameId] = Math.max(p.bestScores[s.gameId] ?? 0, s.score);
  if (stars === 3) p.stats.threeStarRounds += 1;
  if (accuracy === 1 && answers >= PERFECT_MIN_ANSWERS) p.stats.perfectRounds += 1;
  p.stats.maxCombo = Math.max(p.stats.maxCombo, s.maxCombo);
  if (s.bestReactionMs !== null) {
    p.stats.fastestReactionMs = p.stats.fastestReactionMs === null ? s.bestReactionMs : Math.min(p.stats.fastestReactionMs, s.bestReactionMs);
  }
  p.stats.gamesTried[s.gameId] = true;
  p.stats.maxDifficulty = Math.max(p.stats.maxDifficulty, s.maxLevel);

  const rating = sessionRating(s.gameId, s.score, accuracy, s.maxLevel, s.durationSeconds);
  p.skillRatings[game.skill] = [rating, ...(p.skillRatings[game.skill] ?? [])].slice(0, RATING_WINDOW);
  const bs = brainScore(p.skillRatings);
  p.brainScore = bs.total;
  p.skills = bs.skills;
  return { stars, xp, accuracy, profile: p };
}

/** Flattens the profile (+ client streak) into achievement metrics. */
export function achievementStats(p: ServerProfile, bestStreak: number): AchievementStats {
  const stats: AchievementStats = {
    rounds: p.rounds,
    xp: p.xp,
    level: p.level,
    bestStreak,
    threeStarRounds: p.stats.threeStarRounds,
    perfectRounds: p.stats.perfectRounds,
    maxCombo: p.stats.maxCombo,
    fastestReactionMs: p.stats.fastestReactionMs,
    gamesTried: Object.keys(p.stats.gamesTried).length,
    brainScore: p.brainScore,
    maxDifficulty: p.stats.maxDifficulty,
    friends: p.stats.friends,
  };
  for (const [g, v] of Object.entries(p.bestScores)) stats[`best_${g}`] = v;
  return stats;
}
