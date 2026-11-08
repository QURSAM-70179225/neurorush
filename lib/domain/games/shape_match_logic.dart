import 'dart:math' as math;

enum ShapeKind { circle, square, triangle, star, diamond, hexagon, cross, heart }

class ShapeCard {
  const ShapeCard(this.kind, this.colorIndex);
  final ShapeKind kind;

  /// Index into the presentation palette. Irrelevant for matching.
  final int colorIndex;
}

class ShapeMatchConfig {
  const ShapeMatchConfig({
    required this.nBack,
    required this.shapeCount,
    required this.varyColors,
    required this.timeLimitMs,
  });

  /// Compare with the card this many positions back (1 or 2).
  final int nBack;

  /// How many different shapes can appear (fewer = more confusable repeats).
  final int shapeCount;

  /// Random colors act as a distractor: only the shape counts.
  final bool varyColors;
  final int timeLimitMs;
}

/// One card shown to the player. When [isQuestion] is false the player only
/// has to remember it (the first cards, before there is anything to compare).
class ShapeMatchRound {
  const ShapeMatchRound({
    required this.card,
    required this.isQuestion,
    required this.isMatch,
    required this.nBack,
    required this.timeLimitMs,
  });
  final ShapeCard card;
  final bool isQuestion;
  final bool isMatch;
  final int nBack;
  final int timeLimitMs;
}

class ShapeMatchLogic {
  const ShapeMatchLogic._();

  static const colorCount = 6;
  static const matchChance = 0.5;
  static const int fastMs = 700;

  static ShapeMatchConfig configFor(int level) {
    final l = level.clamp(1, 10);
    final nBack = l >= 7 ? 2 : 1;
    final shapes = switch (l) {
      1 || 2 => 3,
      3 || 4 => 4,
      5 || 6 => 6,
      7 => 4,
      8 => 5,
      9 => 6,
      _ => 8,
    };
    return ShapeMatchConfig(
      nBack: nBack,
      shapeCount: shapes,
      varyColors: l >= 3,
      timeLimitMs: math.max(1400, 3000 - l * 160),
    );
  }

  static int basePoints(int level) => 10 + level * 5;
}

/// Stateful generator: remembers the cards already shown.
class ShapeMatchSequence {
  ShapeMatchSequence(this._random);
  final math.Random _random;
  final List<ShapeCard> _history = [];

  List<ShapeCard> get history => List.unmodifiable(_history);

  ShapeMatchRound next(int level) {
    final cfg = ShapeMatchLogic.configFor(level);
    final kinds = ShapeKind.values.take(cfg.shapeCount).toList();
    final color = cfg.varyColors ? _random.nextInt(ShapeMatchLogic.colorCount) : 0;

    if (_history.length < cfg.nBack) {
      final card = ShapeCard(kinds[_random.nextInt(kinds.length)], color);
      _history.add(card);
      return ShapeMatchRound(
        card: card,
        isQuestion: false,
        isMatch: false,
        nBack: cfg.nBack,
        timeLimitMs: cfg.timeLimitMs,
      );
    }

    final target = _history[_history.length - cfg.nBack].kind;
    final match = _random.nextDouble() < ShapeMatchLogic.matchChance;
    ShapeKind kind;
    if (match) {
      kind = target;
    } else {
      final others = kinds.where((k) => k != target).toList();
      kind = others[_random.nextInt(others.length)];
    }
    final card = ShapeCard(kind, color);
    _history.add(card);
    return ShapeMatchRound(
      card: card,
      isQuestion: true,
      isMatch: match,
      nBack: cfg.nBack,
      timeLimitMs: cfg.timeLimitMs,
    );
  }
}
