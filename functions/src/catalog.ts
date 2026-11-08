/**
 * Game catalogue shared with the app (lib/domain/entities/game_type.dart and
 * the *_logic.dart generators). Keep the numbers in sync with the Dart code.
 */
export type Skill = 'memory' | 'focus' | 'speed' | 'logic' | 'language';
export const SKILLS: Skill[] = ['memory', 'focus', 'speed', 'logic', 'language'];

export interface GameDef {
  id: string;
  skill: Skill;
  /** Scores for 1, 2, 3 stars (per 60 s round). */
  starThresholds: [number, number, number];
  /** Smallest base points a correct answer can earn (level 1, smallest task). */
  minBasePoints: number;
  /** Largest base points a correct answer can earn (level 10, largest task). */
  maxBasePoints: number;
  /** Fastest humanly plausible time per answer, used to cap answer counts. */
  minSecondsPerAnswer: number;
}

export const MAX_MULTIPLIER = 5;
export const MAX_LEVEL = 10;
export const ALLOWED_DURATIONS = [24, 60];

export const GAMES: Record<string, GameDef> = {
  memory_grid: { id: 'memory_grid', skill: 'memory', starThresholds: [600, 1500, 2600], minBasePoints: 35, maxBasePoints: 170, minSecondsPerAnswer: 0.8 },
  color_clash: { id: 'color_clash', skill: 'focus', starThresholds: [1000, 2500, 4500], minBasePoints: 14, maxBasePoints: 50, minSecondsPerAnswer: 0.2 },
  speed_math: { id: 'speed_math', skill: 'speed', starThresholds: [800, 1800, 3000], minBasePoints: 15, maxBasePoints: 60, minSecondsPerAnswer: 0.25 },
  shape_match: { id: 'shape_match', skill: 'speed', starThresholds: [700, 1700, 2900], minBasePoints: 15, maxBasePoints: 60, minSecondsPerAnswer: 0.2 },
  number_sequence: { id: 'number_sequence', skill: 'logic', starThresholds: [400, 1000, 1800], minBasePoints: 21, maxBasePoints: 75, minSecondsPerAnswer: 0.4 },
  word_scramble: { id: 'word_scramble', skill: 'language', starThresholds: [400, 1000, 1800], minBasePoints: 40, maxBasePoints: 136, minSecondsPerAnswer: 0.5 },
  odd_one_out: { id: 'odd_one_out', skill: 'focus', starThresholds: [600, 1500, 2700], minBasePoints: 16, maxBasePoints: 70, minSecondsPerAnswer: 0.2 },
  path_recall: { id: 'path_recall', skill: 'memory', starThresholds: [500, 1300, 2300], minBasePoints: 53, maxBasePoints: 206, minSecondsPerAnswer: 1.0 },
};
