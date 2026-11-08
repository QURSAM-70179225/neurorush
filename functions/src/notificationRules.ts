/** Pure notification rules (no Firebase imports), unit tested. */
/** Local date (yyyy-MM-dd) for a UTC instant and an offset in minutes east of UTC. */
export function localDay(nowMs: number, tzOffsetMinutes: number, deltaDays = 0): string {
  return new Date(nowMs + tzOffsetMinutes * 60_000 + deltaDays * 86400_000).toISOString().slice(0, 10);
}

/** What to send to one player this hour, or null. Pure; unit tested. */
export function reminderFor(
  kind: 'streak' | 'workout',
  user: { currentStreak?: number; streakDay?: string },
  tzOffsetMinutes: number,
  nowMs: number,
): { title: string; body: string } | null {
  const today = localDay(nowMs, tzOffsetMinutes);
  const yesterday = localDay(nowMs, tzOffsetMinutes, -1);
  const playedToday = user.streakDay === today;
  if (kind === 'streak') {
    const streak = user.currentStreak ?? 0;
    if (playedToday || streak < 1 || user.streakDay !== yesterday) return null;
    return { title: `🔥 Your ${streak}-day streak ends at midnight`, body: 'One quick 60-second round keeps it alive.' };
  }
  if (playedToday) return null;
  return { title: '🧠 Your Daily Brain Workout is ready', body: '3 games picked for your weakest skills. About 3 minutes.' };
}

/** Games where a friend with best [theirs] was just overtaken: before < theirs ≤ after. */
export function overtakenGames(before: Record<string, number>, after: Record<string, number>, theirs: Record<string, number>): string[] {
  return Object.keys(after).filter((g) => {
    const t = theirs[g];
    return t !== undefined && t > 0 && (before[g] ?? 0) < t && after[g] >= t;
  });
}

