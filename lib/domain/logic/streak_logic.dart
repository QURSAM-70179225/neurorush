/// Calendar-day helpers. All dates are normalised to local midnight.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

class StreakStatus {
  const StreakStatus({
    required this.current,
    required this.best,
    required this.playedToday,
  });

  /// Consecutive active days ending today (or yesterday if today is not
  /// played yet — the streak is still alive until midnight).
  final int current;
  final int best;
  final bool playedToday;

  /// True when the streak will be lost if the player does not play today.
  bool get atRisk => current > 0 && !playedToday;
}

/// Daily streaks with streak-freeze items. A frozen day keeps the streak
/// alive without adding to it.
class StreakLogic {
  const StreakLogic._();

  static const maxFreezes = 2;

  /// A free freeze is awarded at every multiple of this streak length.
  static const freezeMilestone = 7;

  static StreakStatus compute({
    required Set<DateTime> playedDays,
    required Set<DateTime> frozenDays,
    required DateTime today,
  }) {
    final t = dayOf(today);
    final played = playedDays.map(dayOf).toSet();
    final frozen = frozenDays.map(dayOf).toSet();
    final playedToday = played.contains(t);

    var current = 0;
    var day = playedToday ? t : _prev(t);
    while (played.contains(day) || frozen.contains(day)) {
      if (played.contains(day)) current++;
      day = _prev(day);
    }

    // Best streak over the whole history.
    var best = 0, run = 0;
    final all = {...played, ...frozen}.toList()..sort();
    DateTime? last;
    for (final d in all) {
      if (last == null || _prev(d) != last) run = 0;
      if (played.contains(d)) run++;
      if (run > best) best = run;
      last = d;
    }
    return StreakStatus(current: current, best: best < current ? current : best, playedToday: playedToday);
  }

  /// Days that should be covered by freezes right now: the missed days
  /// between the last active day and today. Returns an empty list when there
  /// is no streak to save or not enough freezes to cover the whole gap.
  static List<DateTime> daysToFreeze({
    required Set<DateTime> playedDays,
    required Set<DateTime> frozenDays,
    required int freezesAvailable,
    required DateTime today,
  }) {
    final t = dayOf(today);
    final active = {...playedDays.map(dayOf), ...frozenDays.map(dayOf)};
    if (active.isEmpty || freezesAvailable <= 0) return const [];
    final gap = <DateTime>[];
    var day = _prev(t);
    while (!active.contains(day)) {
      gap.add(day);
      if (gap.length > freezesAvailable) return const [];
      day = _prev(day);
      if (t.difference(day).inDays > 400) return const [];
    }
    // Only worth freezing if the day before the gap had a played streak.
    return gap.reversed.toList();
  }

  /// True when reaching [streak] today earns a free freeze.
  static bool earnsFreeze(int streak) => streak > 0 && streak % freezeMilestone == 0;

  static DateTime _prev(DateTime d) => DateTime(d.year, d.month, d.day - 1);
}
