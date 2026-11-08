import 'dart:math' as math;

import 'shared_options.dart';

enum SequenceFamily {
  arithmetic,
  decreasing,
  geometric,
  alternatingSteps,
  growingSteps,
  squares,
  fibonacci,
  interleaved,
  doubleThenAdd,
  cubes,
  primes,
  triangular,
}

class SequenceQuestion {
  const SequenceQuestion({
    required this.shown,
    required this.answer,
    required this.options,
    required this.rule,
    required this.family,
    required this.timeLimitMs,
  });

  final List<int> shown;
  final int answer;
  final List<int> options;

  /// Short explanation shown after a mistake so the player learns the rule.
  final String rule;
  final SequenceFamily family;
  final int timeLimitMs;

  /// All terms including the answer.
  List<int> get fullSequence => [...shown, answer];
}

class NumberSequenceLogic {
  const NumberSequenceLogic._();

  static int timeLimitFor(int level) => math.max(5000, 10000 - level.clamp(1, 10) * 450);
  static int basePoints(int level) => 15 + level * 6;
  static const int fastMs = 3000;

  /// Families unlocked at [level]. Newer families are listed last and are
  /// picked more often so the game keeps getting harder.
  static List<SequenceFamily> familiesFor(int level) {
    final l = level.clamp(1, 10);
    const order = [
      [SequenceFamily.arithmetic],
      [SequenceFamily.decreasing],
      [SequenceFamily.geometric],
      [SequenceFamily.alternatingSteps],
      [SequenceFamily.growingSteps],
      [SequenceFamily.squares],
      [SequenceFamily.fibonacci],
      [SequenceFamily.interleaved],
      [SequenceFamily.doubleThenAdd],
      [SequenceFamily.cubes, SequenceFamily.primes, SequenceFamily.triangular],
    ];
    return [for (var i = 0; i < l; i++) ...order[i]];
  }

  static SequenceQuestion generate(math.Random r, int level) {
    final families = familiesFor(level);
    // 60% newest family of this level, otherwise any unlocked family.
    final newest = families.length - (level >= 10 ? 3 : 1);
    final family = r.nextDouble() < 0.6
        ? families[newest + r.nextInt(families.length - newest)]
        : families[r.nextInt(families.length)];
    final (terms, rule, tempting) = _build(r, family);
    final shown = terms.sublist(0, terms.length - 1);
    final answer = terms.last;
    return SequenceQuestion(
      shown: shown,
      answer: answer,
      options: buildNumericOptions(r, answer, tempting: tempting.where((t) => t != answer)),
      rule: rule,
      family: family,
      timeLimitMs: timeLimitFor(level),
    );
  }

  static int _r(math.Random r, int min, int max) => min + r.nextInt(max - min + 1);

  /// Returns (terms including answer, rule text, tempting wrong answers).
  static (List<int>, String, List<int>) _build(math.Random r, SequenceFamily f) {
    switch (f) {
      case SequenceFamily.arithmetic:
        final d = _r(r, 1, 6), a = _r(r, 1, 20);
        final t = List.generate(5, (i) => a + d * i);
        return (t, 'Add $d each time', [t.last + 1, t.last - 1]);
      case SequenceFamily.decreasing:
        final d = _r(r, 2, 9), a = d * 5 + _r(r, 1, 30);
        final t = List.generate(5, (i) => a - d * i);
        return (t, 'Subtract $d each time', [t[3] + d, t.last - 1]);
      case SequenceFamily.geometric:
        final m = _r(r, 2, 3), a = _r(r, 1, 5);
        final t = List.generate(5, (i) => a * math.pow(m, i).toInt());
        return (t, 'Multiply by $m each time', [t[3] + (t[3] - t[2]), t.last + m]);
      case SequenceFamily.alternatingSteps:
        final x = _r(r, 1, 5);
        var y = _r(r, 2, 9);
        if (y == x) y++;
        final a = _r(r, 1, 15);
        final t = <int>[a];
        for (var i = 1; i < 7; i++) {
          t.add(t.last + (i.isOdd ? x : y));
        }
        // Next step after an even count of steps is +x.
        return (t, 'Add $x, then $y, alternately', [t[5] + y]);
      case SequenceFamily.growingSteps:
        final a = _r(r, 1, 10), d0 = _r(r, 1, 4);
        final t = <int>[a];
        for (var i = 0; i < 5; i++) {
          t.add(t.last + d0 + i);
        }
        return (t, 'The step grows by 1 each time', [t[4] + (t[4] - t[3])]);
      case SequenceFamily.squares:
        final k = _r(r, 1, 6), c = r.nextBool() ? 0 : _r(r, 1, 5);
        final t = List.generate(5, (i) => (k + i) * (k + i) + c);
        return (
          t,
          c == 0 ? 'Square numbers' : 'Square numbers plus $c',
          [t[3] + (t[3] - t[2])],
        );
      case SequenceFamily.fibonacci:
        final a = _r(r, 1, 5), b = _r(r, a, a + 4);
        final t = [a, b];
        while (t.length < 7) {
          t.add(t[t.length - 1] + t[t.length - 2]);
        }
        return (t, 'Each number is the sum of the two before it', [t[5] * 2, t[5] + (t[5] - t[4])]);
      case SequenceFamily.interleaved:
        final a = _r(r, 1, 10), b = _r(r, 20, 40), da = _r(r, 2, 5), db = _r(r, 1, 4);
        // a, b, a+da, b-db, a+2da, b-2db, a+3da
        final t = <int>[];
        for (var i = 0; i < 7; i++) {
          final k = i ~/ 2;
          t.add(i.isEven ? a + da * k : b - db * k);
        }
        return (t, 'Two sequences take turns: +$da and −$db', [t[5] - db, t[5] + da]);
      case SequenceFamily.doubleThenAdd:
        final a = _r(r, 1, 4), k = _r(r, 1, 3);
        final t = [a];
        while (t.length < 5) {
          t.add(t.last * 2 + k);
        }
        return (t, 'Double, then add $k', [t[3] * 2, t[3] + (t[3] - t[2])]);
      case SequenceFamily.cubes:
        final k = _r(r, 1, 4);
        final t = List.generate(5, (i) => math.pow(k + i, 3).toInt());
        return (t, 'Cube numbers', [t[3] + (t[3] - t[2])]);
      case SequenceFamily.primes:
        const primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61];
        final s = _r(r, 0, primes.length - 6);
        final t = primes.sublist(s, s + 6);
        return (t, 'Prime numbers', [t[4] + 2, t[4] + (t[4] - t[3])]);
      case SequenceFamily.triangular:
        final k = _r(r, 1, 6);
        final t = List.generate(5, (i) => (k + i) * (k + i + 1) ~/ 2);
        return (t, 'Triangular numbers (add 1 more each step)', [t[3] + (t[3] - t[2])]);
    }
  }
}
