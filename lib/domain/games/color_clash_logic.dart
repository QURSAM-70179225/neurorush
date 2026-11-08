import 'dart:math' as math;

/// A named ink color. The [argb] value is resolved against the active palette
/// (standard or color-blind safe) by the presentation layer.
class InkColor {
  const InkColor(this.name, this.argb);
  final String name;
  final int argb;
}

class ColorClashPalettes {
  const ColorClashPalettes._();

  static const standard = <InkColor>[
    InkColor('RED', 0xFFE53935),
    InkColor('BLUE', 0xFF1E88E5),
    InkColor('GREEN', 0xFF43A047),
    InkColor('YELLOW', 0xFFFDD835),
    InkColor('PURPLE', 0xFF8E24AA),
    InkColor('ORANGE', 0xFFFB8C00),
  ];

  /// Okabe–Ito palette: distinguishable with the common color-vision
  /// deficiencies. Names describe what the colors look like.
  static const colorBlindSafe = <InkColor>[
    InkColor('ORANGE', 0xFFE69F00),
    InkColor('SKY', 0xFF56B4E9),
    InkColor('GREEN', 0xFF009E73),
    InkColor('YELLOW', 0xFFF0E442),
    InkColor('BLUE', 0xFF0072B2),
    InkColor('PINK', 0xFFCC79A7),
  ];
}

class ColorClashQuestion {
  const ColorClashQuestion({
    required this.wordIndex,
    required this.inkIndex,
    required this.options,
    required this.optionInkIndexes,
    required this.timeLimitMs,
  });

  /// Palette index of the color NAME displayed.
  final int wordIndex;

  /// Palette index of the INK the word is drawn in — the correct answer.
  final int inkIndex;

  /// Palette indexes offered as answer buttons (contains [inkIndex]).
  final List<int> options;

  /// Ink used to draw each option's label; null = neutral text color.
  /// At higher levels the labels themselves are drawn in misleading inks.
  final List<int?> optionInkIndexes;

  final int timeLimitMs;

  bool get isCongruent => wordIndex == inkIndex;
  bool isCorrect(int paletteIndex) => paletteIndex == inkIndex;
}

class ColorClashLogic {
  const ColorClashLogic._();

  static int optionCountFor(int level) {
    final l = level.clamp(1, 10);
    if (l <= 2) return 2;
    if (l <= 4) return 3;
    if (l <= 7) return 4;
    return 6;
  }

  static int timeLimitFor(int level) => math.max(1300, 3200 - level.clamp(1, 10) * 190);

  /// Chance that word and ink match (easy "warm up" questions).
  static double congruentChanceFor(int level) =>
      math.max(0.0, 0.35 - level.clamp(1, 10) * 0.05);

  static ColorClashQuestion generate(math.Random random, int level, {int paletteSize = 6}) {
    final optionCount = math.min(optionCountFor(level), paletteSize);
    final ink = random.nextInt(paletteSize);
    int word;
    if (random.nextDouble() < congruentChanceFor(level)) {
      word = ink;
    } else {
      do {
        word = random.nextInt(paletteSize);
      } while (word == ink);
    }

    // Always include the ink (correct) and the word (the tempting wrong answer).
    final options = <int>{ink, word};
    while (options.length < optionCount) {
      options.add(random.nextInt(paletteSize));
    }
    final shuffled = options.toList()..shuffle(random);

    final tricky = level >= 5;
    final optionInks = shuffled.map<int?>((o) {
      if (!tricky) return null;
      int c;
      do {
        c = random.nextInt(paletteSize);
      } while (c == o);
      return c;
    }).toList();

    return ColorClashQuestion(
      wordIndex: word,
      inkIndex: ink,
      options: shuffled,
      optionInkIndexes: optionInks,
      timeLimitMs: timeLimitFor(level),
    );
  }

  static int basePoints(int level) => 10 + level * 4;

  /// Answers faster than this count as "fast" for adaptive difficulty.
  static const int fastMs = 900;
}
