/// ISO-8601 week id in UTC, e.g. "2026-W45". Mirrors functions/src/weeks.ts.
String isoWeekId(DateTime t) {
  final u = t.toUtc();
  var d = DateTime.utc(u.year, u.month, u.day);
  d = d.add(Duration(days: 4 - d.weekday)); // Thursday decides the year
  final yearStart = DateTime.utc(d.year);
  final week = (d.difference(yearStart).inDays ~/ 7) + 1;
  return '${d.year}-W${week.toString().padLeft(2, '0')}';
}

/// The next Monday 00:00 UTC (when the weekly boards reset).
DateTime nextWeeklyReset(DateTime t) {
  final u = t.toUtc();
  final today = DateTime.utc(u.year, u.month, u.day);
  return today.add(Duration(days: 8 - today.weekday));
}
