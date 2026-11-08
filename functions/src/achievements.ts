import catalog from './generated/achievements.json';

export interface Achievement {
  id: string;
  title: string;
  description: string;
  metric: string;
  op: '>=' | '<';
  target: number;
  icon: string;
}

export const ACHIEVEMENTS: Achievement[] = catalog.achievements as Achievement[];

/** Player statistics the achievements are measured on. */
export type AchievementStats = Record<string, number | null | undefined>;

export function isUnlocked(a: Achievement, stats: AchievementStats): boolean {
  const v = stats[a.metric];
  if (v === null || v === undefined) return false;
  return a.op === '>=' ? v >= a.target : v < a.target;
}

/** Ids of achievements satisfied by [stats] that are not in [already]. */
export function newlyUnlocked(stats: AchievementStats, already: Iterable<string>): string[] {
  const have = new Set(already);
  return ACHIEVEMENTS.filter((a) => !have.has(a.id) && isUnlocked(a, stats)).map((a) => a.id);
}
