import 'dart:math' as math;

/// Adaptive difficulty: climbs while the player answers correctly (faster for
/// quick answers) and drops after a mistake, so every player settles at the
/// edge of their ability.
class AdaptiveDifficulty {
  AdaptiveDifficulty({
    this.minLevel = 1,
    this.maxLevel = 10,
    int startLevel = 1,
    this.stepUp = 0.5,
    this.fastBonus = 0.25,
    this.stepDown = 1.0,
  })  : assert(minLevel <= maxLevel),
        _value = startLevel.clamp(minLevel, maxLevel).toDouble(),
        _maxReached = startLevel.clamp(minLevel, maxLevel);

  final int minLevel;
  final int maxLevel;

  /// Progress gained per correct answer (two correct answers = one level).
  final double stepUp;

  /// Extra progress for an answer faster than the game's "fast" threshold.
  final double fastBonus;

  /// Progress lost per mistake.
  final double stepDown;

  double _value;
  int _maxReached;

  /// The current integer level used by the game generators.
  int get level => _value.floor().clamp(minLevel, maxLevel);

  /// The highest level reached during this session.
  int get maxReached => _maxReached;

  /// Continuous progress value, useful for UI progress indicators.
  double get value => _value;

  void onCorrect({bool fast = false}) {
    _value = math.min(maxLevel.toDouble(), _value + stepUp + (fast ? fastBonus : 0));
    _maxReached = math.max(_maxReached, level);
  }

  void onMistake() {
    // Drop to the start of the level below so a mistake is always felt.
    _value = math.max(minLevel.toDouble(), (_value - stepDown).floorToDouble());
  }
}
