import 'dart:math' as math;

class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.title,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
  });

  final int level;
  final String title;

  /// XP earned since reaching [level].
  final int xpIntoLevel;

  /// XP needed to go from [level] to the next one (0 at max level).
  final int xpForNextLevel;

  bool get isMax => level >= XpLevels.maxLevel;
  double get progress => isMax ? 1 : xpIntoLevel / xpForNextLevel;
}

/// 50 player levels. Each level needs 40 XP more than the previous one.
class XpLevels {
  const XpLevels._();

  static const maxLevel = 50;

  static const tierTitles = [
    'Rookie Brain',
    'Curious Mind',
    'Quick Thinker',
    'Sharp Spark',
    'Focus Ninja',
    'Memory Ace',
    'Logic Wizard',
    'Mind Master',
    'Brain Titan',
    'Neuron Master',
  ];

  static const _roman = ['I', 'II', 'III', 'IV', 'V'];

  /// XP needed to advance from [level] to [level] + 1.
  static int xpToNext(int level) => 100 + (level - 1) * 40;

  /// Total XP required to reach [level] (level 1 = 0 XP).
  static int totalXpFor(int level) {
    final l = level.clamp(1, maxLevel) - 1;
    return 100 * l + 40 * (l * (l - 1) ~/ 2);
  }

  static String titleFor(int level) {
    final l = level.clamp(1, maxLevel);
    if (l == maxLevel) return tierTitles.last;
    return '${tierTitles[(l - 1) ~/ 5]} ${_roman[(l - 1) % 5]}';
  }

  static LevelInfo fromXp(int totalXp) {
    final xp = math.max(0, totalXp);
    var level = 1;
    while (level < maxLevel && xp >= totalXpFor(level + 1)) {
      level++;
    }
    final isMax = level == maxLevel;
    return LevelInfo(
      level: level,
      title: titleFor(level),
      xpIntoLevel: xp - totalXpFor(level),
      xpForNextLevel: isMax ? 0 : xpToNext(level),
    );
  }
}
