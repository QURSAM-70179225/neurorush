import 'dart:convert';

/// A badge from shared/achievements.json (also used by Cloud Functions).
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.metric,
    required this.op,
    required this.target,
    required this.icon,
  });

  final String id;
  final String title;
  final String description;

  /// Name of the statistic measured (see [AchievementStats]).
  final String metric;

  /// ">=" (reach at least) or "<" (go below, e.g. reaction time).
  final String op;
  final num target;

  /// Material icon name.
  final String icon;

  bool isMet(num? value) {
    if (value == null) return false;
    return op == '>=' ? value >= target : value < target;
  }

  /// Progress 0..1 towards the badge (for "lower is better" metrics it is
  /// 1 once met and 0 otherwise).
  double progress(num? value) {
    if (value == null) return 0;
    if (op == '<') return isMet(value) ? 1 : 0;
    return (value / target).clamp(0, 1).toDouble();
  }

  static List<Achievement> parseCatalogue(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    return [
      for (final a in data['achievements'] as List)
        Achievement(
          id: a['id'] as String,
          title: a['title'] as String,
          description: a['description'] as String,
          metric: a['metric'] as String,
          op: a['op'] as String,
          target: a['target'] as num,
          icon: a['icon'] as String,
        ),
    ];
  }
}
