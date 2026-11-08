import 'dart:math' as math;

enum OddKind { differentIcon, similarIcon, rotated }

/// Glyph keys. The presentation layer maps each key to an icon; the domain
/// only needs to know which ones are similar or asymmetric.
class OddGlyphs {
  const OddGlyphs._();

  static const distinct = [
    'star', 'heart', 'bolt', 'moon', 'cloud', 'leaf', 'paw', 'music', //
    'rocket', 'diamond', 'sun', 'flower', 'bell', 'key', 'flag', 'cake',
  ];

  /// Pairs that look alike at a glance.
  static const similarPairs = [
    ('heart', 'heart_outline'),
    ('star', 'star_outline'),
    ('smile', 'frown'),
    ('bell', 'bell_off'),
    ('lock', 'lock_open'),
    ('mic', 'mic_off'),
    ('eye', 'eye_off'),
    ('wifi', 'wifi_off'),
    ('thumb_up', 'thumb_down'),
    ('cloud', 'cloud_off'),
    ('volume_up', 'volume_off'),
    ('battery_full', 'battery_low'),
  ];

  /// Glyphs whose rotation is visible.
  static const asymmetric = ['arrow', 'navigation', 'thumb_up', 'key', 'music', 'flag', 'rocket', 'paw'];

  static Set<String> get all => {
        ...distinct,
        for (final p in similarPairs) ...[p.$1, p.$2],
        ...asymmetric,
      };
}

class OddOneOutQuestion {
  const OddOneOutQuestion({
    required this.gridSize,
    required this.oddIndex,
    required this.baseGlyph,
    required this.oddGlyph,
    required this.oddTurns,
    required this.kind,
    required this.timeLimitMs,
  });

  final int gridSize;
  final int oddIndex;
  final String baseGlyph;
  final String oddGlyph;

  /// Rotation of the odd glyph in full turns (0.5 = 180°).
  final double oddTurns;
  final OddKind kind;
  final int timeLimitMs;

  int get cellCount => gridSize * gridSize;
}

class OddOneOutLogic {
  const OddOneOutLogic._();

  static const _gridSizes = [2, 3, 3, 4, 4, 5, 5, 6, 6, 7];
  static int gridSizeFor(int level) => _gridSizes[level.clamp(1, 10) - 1];

  static int timeLimitFor(int level) => math.max(3000, 6500 - level.clamp(1, 10) * 300);
  static int basePoints(int level) => 10 + level * 6;
  static const int fastMs = 1500;

  static OddOneOutQuestion generate(math.Random r, int level) {
    final l = level.clamp(1, 10);
    final size = gridSizeFor(l);
    final OddKind kind;
    if (l <= 3) {
      kind = OddKind.differentIcon;
    } else if (l <= 6) {
      kind = OddKind.similarIcon;
    } else {
      kind = r.nextBool() ? OddKind.similarIcon : OddKind.rotated;
    }

    String base, odd;
    var turns = 0.0;
    switch (kind) {
      case OddKind.differentIcon:
        base = OddGlyphs.distinct[r.nextInt(OddGlyphs.distinct.length)];
        do {
          odd = OddGlyphs.distinct[r.nextInt(OddGlyphs.distinct.length)];
        } while (odd == base);
      case OddKind.similarIcon:
        final p = OddGlyphs.similarPairs[r.nextInt(OddGlyphs.similarPairs.length)];
        (base, odd) = r.nextBool() ? (p.$1, p.$2) : (p.$2, p.$1);
      case OddKind.rotated:
        base = OddGlyphs.asymmetric[r.nextInt(OddGlyphs.asymmetric.length)];
        odd = base;
        // Smaller rotations are harder to notice.
        turns = switch (l) { 7 => 0.5, 8 => 0.25, _ => 0.125 } * (r.nextBool() ? 1 : -1);
    }

    return OddOneOutQuestion(
      gridSize: size,
      oddIndex: r.nextInt(size * size),
      baseGlyph: base,
      oddGlyph: odd,
      oddTurns: turns,
      kind: kind,
      timeLimitMs: timeLimitFor(l),
    );
  }
}
