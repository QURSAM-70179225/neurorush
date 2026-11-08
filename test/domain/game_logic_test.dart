import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/games/color_clash_logic.dart';
import 'package:neurorush/domain/games/memory_grid_logic.dart';
import 'package:neurorush/domain/games/speed_math_logic.dart';

import '../helpers.dart';

void main() {
  group('SpeedMath', () {
    test('every generated answer is correct, non-negative, with 4 unique options', () {
      for (var level = 1; level <= 10; level++) {
        final r = Random(level * 31);
        for (var i = 0; i < 300; i++) {
          final q = SpeedMathLogic.generate(r, level);
          expect(evaluate(q.expression), q.answer, reason: q.expression);
          expect(q.answer, greaterThanOrEqualTo(0), reason: q.expression);
          expect(q.options.length, 4);
          expect(q.options.toSet().length, 4);
          expect(q.options, contains(q.answer));
          expect(q.options.every((o) => o >= 0), isTrue);
        }
      }
    });

    test('time limit shrinks as level rises, never below 2.6 s', () {
      for (var l = 2; l <= 10; l++) {
        expect(SpeedMathLogic.timeLimitFor(l) <= SpeedMathLogic.timeLimitFor(l - 1), isTrue);
      }
      expect(SpeedMathLogic.timeLimitFor(10), greaterThanOrEqualTo(2600));
    });

    test('same seed gives the same questions (needed for fair battles)', () {
      final a = Random(7), b = Random(7);
      for (var i = 0; i < 20; i++) {
        expect(SpeedMathLogic.generate(a, 5).expression, SpeedMathLogic.generate(b, 5).expression);
      }
    });

    test('spoken expression replaces symbols', () {
      const q = MathQuestion(expression: '7 × 8 − 3', answer: 53, options: [53], timeLimitMs: 1);
      expect(q.spokenExpression, '7 times 8 minus 3');
    });
  });

  group('ColorClash', () {
    test('options contain ink and word, are unique and sized by level', () {
      for (var level = 1; level <= 10; level++) {
        final r = Random(level);
        for (var i = 0; i < 300; i++) {
          final q = ColorClashLogic.generate(r, level);
          expect(q.options, contains(q.inkIndex));
          expect(q.options, contains(q.wordIndex));
          expect(q.options.toSet().length, q.options.length);
          expect(q.options.length, ColorClashLogic.optionCountFor(level));
          expect(q.isCorrect(q.inkIndex), isTrue);
          if (level >= 5) {
            for (var k = 0; k < q.options.length; k++) {
              expect(q.optionInkIndexes[k], isNot(q.options[k]),
                  reason: 'a label must never be drawn in its own color');
            }
          } else {
            expect(q.optionInkIndexes.every((c) => c == null), isTrue);
          }
        }
      }
    });

    test('high levels are almost never congruent', () {
      final r = Random(1);
      final congruent = List.generate(500, (_) => ColorClashLogic.generate(r, 10)).where((q) => q.isCongruent);
      expect(congruent, isEmpty);
    });

    test('both palettes have 6 distinct colors and names', () {
      for (final p in [ColorClashPalettes.standard, ColorClashPalettes.colorBlindSafe]) {
        expect(p.length, 6);
        expect(p.map((c) => c.name).toSet().length, 6);
        expect(p.map((c) => c.argb).toSet().length, 6);
      }
    });
  });

  group('MemoryGrid', () {
    test('difficulty never decreases with level and fits on the board', () {
      var prev = MemoryGridLogic.configFor(1);
      for (var l = 1; l <= 10; l++) {
        final c = MemoryGridLogic.configFor(l);
        expect(c.gridSize, greaterThanOrEqualTo(prev.gridSize));
        expect(c.tileCount, greaterThanOrEqualTo(prev.tileCount));
        expect(c.tileCount, lessThan(c.cellCount ~/ 2 + 1));
        expect(c.showMs, greaterThanOrEqualTo(700));
        prev = c;
      }
    });

    test('pattern has the right number of distinct in-range cells', () {
      final r = Random(3);
      for (var l = 1; l <= 10; l++) {
        final c = MemoryGridLogic.configFor(l);
        final p = MemoryGridLogic.generatePattern(r, c);
        expect(p.length, c.tileCount);
        expect(p.every((i) => i >= 0 && i < c.cellCount), isTrue);
      }
    });
  });
}
