/** Pure rules for streaks, freezes, coins and rewards (unit tested). */

export const MAX_FREEZES = 3;
export const FREEZE_MILESTONE = 7;

export interface StreakState {
  current: number;
  best: number;
  /** Local yyyy-MM-dd of the last day that counted. */
  lastDay: string | null;
}

function dayNumber(day: string): number {
  const [y, m, d] = day.split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / 86400000);
}

export function addDays(day: string, n: number): string {
  return new Date((dayNumber(day) + n) * 86400000).toISOString().slice(0, 10);
}

/**
 * Updates the server-side streak for a round played on local [day].
 * Missed days are covered by freezes when there are enough; otherwise the
 * streak restarts. Rounds older than the last counted day do not change it.
 */
export function advanceStreak(
  s: StreakState,
  day: string,
  freezes: number,
): { streak: StreakState; freezes: number; freezesUsed: number; freezeEarned: boolean } {
  if (s.lastDay !== null && dayNumber(day) <= dayNumber(s.lastDay)) {
    return { streak: s, freezes, freezesUsed: 0, freezeEarned: false };
  }
  let current: number;
  let used = 0;
  if (s.lastDay === null) {
    current = 1;
  } else {
    const missed = dayNumber(day) - dayNumber(s.lastDay) - 1;
    if (missed === 0) {
      current = s.current + 1;
    } else if (missed <= freezes) {
      used = missed;
      current = s.current + 1;
    } else {
      current = 1;
    }
  }
  let left = freezes - used;
  const earned = current % FREEZE_MILESTONE === 0 && left < MAX_FREEZES;
  if (earned) left += 1;
  return {
    streak: { current, best: Math.max(s.best, current), lastDay: day },
    freezes: left,
    freezesUsed: used,
    freezeEarned: earned,
  };
}

/** Local calendar day for an instant and an offset in minutes east of UTC. */
export function localDayOf(ms: number, tzOffsetMinutes: number): string {
  return new Date(ms + tzOffsetMinutes * 60000).toISOString().slice(0, 10);
}

export type RewardType = 'streak_freeze' | 'double_xp' | 'extra_life';
export const REWARD_TYPES: RewardType[] = ['streak_freeze', 'double_xp', 'extra_life'];

/** custom_data sent with a rewarded ad: "<reward>:<nonce>[:<sessionId>]". */
export function parseRewardCustomData(raw: string): { reward: RewardType; nonce: string; sessionId: string | null } | null {
  const parts = raw.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  const [reward, nonce, sessionId] = parts;
  if (!REWARD_TYPES.includes(reward as RewardType)) return null;
  if (!/^[A-Za-z0-9-]{8,64}$/.test(nonce)) return null;
  if (sessionId !== undefined && !/^[A-Za-z0-9-]{8,64}$/.test(sessionId)) return null;
  return { reward: reward as RewardType, nonce, sessionId: sessionId ?? null };
}

export const PREMIUM_THEMES = ['neon_pulse', 'neon_ocean', 'neon_sunset'];

/** Is Pro active at [now] given stored entitlements? */
export function proActive(e: { pro?: boolean; proExpiresAt?: { toMillis(): number } | number | null } | undefined, now: number): boolean {
  if (!e?.pro) return false;
  const exp = e.proExpiresAt;
  if (exp === null || exp === undefined) return false;
  const ms = typeof exp === 'number' ? exp : exp.toMillis();
  return ms > now;
}

/**
 * Economy values the team can change without an app update. Read from the
 * Remote Config *server* template; these defaults apply when a key is missing
 * (and on the emulators).
 */
export const ECONOMY_DEFAULTS = {
  freeze_price_coins: 100,
  theme_price_coins: 300,
  coins_small_amount: 500,
  coins_medium_amount: 1200,
  coins_large_amount: 3000,
  rewarded_daily_limit: 10,
  free_endless_per_day: 10,
};
export type Economy = typeof ECONOMY_DEFAULTS;

