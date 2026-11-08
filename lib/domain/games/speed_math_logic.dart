import 'dart:math' as math;

class MathQuestion {
  const MathQuestion({
    required this.expression,
    required this.answer,
    required this.options,
    required this.timeLimitMs,
  });

  /// Human readable expression, e.g. "7 × 8".
  final String expression;
  final int answer;

  /// Four distinct choices, one of which is [answer].
  final List<int> options;
  final int timeLimitMs;

  /// Text read by screen readers ("7 times 8").
  String get spokenExpression => expression
      .replaceAll('×', 'times')
      .replaceAll('÷', 'divided by')
      .replaceAll('−', 'minus')
      .replaceAll('+', 'plus')
      .replaceAll('% of', 'percent of')
      .replaceAll('²', ' squared');
}

class SpeedMathLogic {
  const SpeedMathLogic._();

  static const int optionCount = 4;

  static int timeLimitFor(int level) => math.max(2600, 7000 - level.clamp(1, 10) * 440);

  static int basePoints(int level) => 10 + level * 5;

  static const int fastMs = 1800;

  static MathQuestion generate(math.Random random, int level) {
    final l = level.clamp(1, 10);
    final (expr, ans) = _expression(random, l);
    return MathQuestion(
      expression: expr,
      answer: ans,
      options: _options(random, ans),
      timeLimitMs: timeLimitFor(l),
    );
  }

  static int _r(math.Random r, int min, int max) => min + r.nextInt(max - min + 1);

  static (String, int) _add(math.Random r, int min, int max) {
    final a = _r(r, min, max), b = _r(r, min, max);
    return ('$a + $b', a + b);
  }

  static (String, int) _sub(math.Random r, int min, int max) {
    var a = _r(r, min, max), b = _r(r, min, max);
    if (b > a) (a, b) = (b, a);
    return ('$a − $b', a - b);
  }

  static (String, int) _mul(math.Random r, int aMin, int aMax, int bMin, int bMax) {
    final a = _r(r, aMin, aMax), b = _r(r, bMin, bMax);
    return ('$a × $b', a * b);
  }

  static (String, int) _div(math.Random r, int maxDivisor, int maxQuotient) {
    final d = _r(r, 2, maxDivisor), q = _r(r, 2, maxQuotient);
    return ('${d * q} ÷ $d', q);
  }

  static (String, int) _expression(math.Random r, int level) {
    switch (level) {
      case 1:
        return _add(r, 1, 9);
      case 2:
        return r.nextBool() ? _add(r, 2, 20) : _sub(r, 2, 20);
      case 3:
        return r.nextBool() ? _add(r, 10, 50) : _sub(r, 10, 50);
      case 4:
        return switch (r.nextInt(3)) {
          0 => _mul(r, 2, 9, 2, 9),
          1 => _add(r, 20, 99),
          _ => _sub(r, 20, 99),
        };
      case 5:
        return r.nextBool() ? _mul(r, 3, 12, 3, 9) : _div(r, 9, 12);
      case 6:
        // a + b × c  (operator precedence)
        final b = _r(r, 2, 9), c = _r(r, 2, 9);
        if (r.nextBool()) {
          final a = _r(r, 2, 20);
          return ('$a + $b × $c', a + b * c);
        }
        final a = _r(r, 1, b * c - 1); // keeps the answer positive
        return ('$b × $c − $a', b * c - a);
      case 7:
        if (r.nextBool()) return _mul(r, 11, 25, 3, 9);
        final a = _r(r, 2, 12), b = _r(r, 2, 12), c = _r(r, 2, 6);
        return ('($a + $b) × $c', (a + b) * c);
      case 8:
        return switch (r.nextInt(3)) {
          0 => _div(r, 12, 15),
          1 => _mul(r, 12, 49, 4, 9),
          _ => () {
              final a = _r(r, 20, 90), b = _r(r, 10, 60), c = _r(r, 5, 40); // a + b >= 30 > c
              return ('$a + $b − $c', a + b - c);
            }(),
        };
      case 9:
        if (r.nextBool()) {
          final n = _r(r, 4, 20);
          return ('$n²', n * n);
        }
        final pct = [10, 20, 25, 50, 75][r.nextInt(5)];
        final base = _r(r, 1, 12) * 20;
        return ('$pct% of $base', base * pct ~/ 100);
      default:
        return switch (r.nextInt(3)) {
          0 => _mul(r, 13, 39, 11, 19),
          1 => () {
              final a = _r(r, 3, 12), b = _r(r, 3, 12), c = _r(r, 10, 60);
              return ('$a × $b + $c', a * b + c);
            }(),
          _ => () {
              final n = _r(r, 11, 25);
              final d = _r(r, 2, 9);
              return ('$n² − $d', n * n - d);
            }(),
        };
    }
  }

  /// Three plausible distractors close to the answer, plus the answer.
  static List<int> _options(math.Random r, int answer) {
    final offsets = <int>[1, 2, 3, 10, if (answer >= 20) 20];
    final opts = <int>{answer};
    var guard = 0;
    while (opts.length < optionCount && guard++ < 100) {
      final off = offsets[r.nextInt(offsets.length)] * (r.nextBool() ? 1 : -1);
      final v = answer + off;
      if (v >= 0) opts.add(v);
    }
    var fill = answer + 4;
    while (opts.length < optionCount) {
      opts.add(fill++);
    }
    return opts.toList()..shuffle(r);
  }
}
