import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/games/number_sequence_logic.dart';
import 'package:neurorush/domain/games/odd_one_out_logic.dart';
import 'package:neurorush/domain/games/path_recall_logic.dart';
import 'package:neurorush/domain/games/shape_match_logic.dart';
import 'package:neurorush/domain/games/word_lists.dart';
import 'package:neurorush/domain/games/word_scramble_logic.dart';

bool isPrime(int n) {
  if (n < 2) return false;
  for (var i = 2; i * i <= n; i++) {
    if (n % i == 0) return false;
  }
  return true;
}

/// Independently checks that [t] (including the answer) follows [f].
void expectFollows(SequenceFamily f, List<int> t) {
  final d = [for (var i = 1; i < t.length; i++) t[i] - t[i - 1]];
  switch (f) {
    case SequenceFamily.arithmetic:
    case SequenceFamily.decreasing:
      expect(d.toSet().length, 1, reason: '$t');
      expect(f == SequenceFamily.decreasing ? d.first < 0 : d.first > 0, isTrue);
    case SequenceFamily.geometric:
      final m = t[1] ~/ t[0];
      for (var i = 1; i < t.length; i++) {
        expect(t[i], t[i - 1] * m, reason: '$t');
      }
    case SequenceFamily.alternatingSteps:
      for (var i = 2; i < d.length; i++) {
        expect(d[i], d[i - 2], reason: '$t');
      }
      expect(d[0] != d[1], isTrue);
    case SequenceFamily.growingSteps:
      for (var i = 1; i < d.length; i++) {
        expect(d[i] - d[i - 1], 1, reason: '$t');
      }
    case SequenceFamily.squares:
      for (var i = 2; i < d.length; i++) {
        expect(d[i] - d[i - 1], 2, reason: '$t'); // second difference of squares
      }
    case SequenceFamily.fibonacci:
      for (var i = 2; i < t.length; i++) {
        expect(t[i], t[i - 1] + t[i - 2], reason: '$t');
      }
    case SequenceFamily.interleaved:
      for (var i = 2; i < t.length; i++) {
        expect(t[i] - t[i - 2], t[i.isEven ? 2 : 3] - t[i.isEven ? 0 : 1], reason: '$t');
      }
    case SequenceFamily.doubleThenAdd:
      final k = t[1] - 2 * t[0];
      for (var i = 1; i < t.length; i++) {
        expect(t[i], 2 * t[i - 1] + k, reason: '$t');
      }
    case SequenceFamily.cubes:
      for (final v in t) {
        final r = pow(v, 1 / 3).round();
        expect(r * r * r, v, reason: '$t');
      }
    case SequenceFamily.primes:
      expect(t.every(isPrime), isTrue, reason: '$t');
      for (var v = t.first; v <= t.last; v++) {
        if (isPrime(v)) expect(t, contains(v), reason: 'no prime skipped in $t');
      }
    case SequenceFamily.triangular:
      for (var i = 1; i < d.length; i++) {
        expect(d[i] - d[i - 1], 1, reason: '$t');
      }
  }
}

void main() {
  group('NumberSequence', () {
    test('every family produces valid sequences, options and answers', () {
      final seen = <SequenceFamily>{};
      for (var level = 1; level <= 10; level++) {
        final r = Random(level * 7);
        for (var i = 0; i < 300; i++) {
          final q = NumberSequenceLogic.generate(r, level);
          seen.add(q.family);
          expect(NumberSequenceLogic.familiesFor(level), contains(q.family));
          expect(q.shown.length, greaterThanOrEqualTo(4));
          expect(q.options, hasLength(4));
          expect(q.options.toSet(), hasLength(4));
          expect(q.options, contains(q.answer));
          expect(q.options.every((o) => o >= 0), isTrue);
          expect(q.fullSequence.every((v) => v >= 0), isTrue, reason: '${q.fullSequence}');
          expect(q.rule, isNotEmpty);
          expectFollows(q.family, q.fullSequence);
        }
      }
      expect(seen, SequenceFamily.values.toSet());
    });

    test('more families unlock as the level rises', () {
      for (var l = 2; l <= 10; l++) {
        expect(NumberSequenceLogic.familiesFor(l).length, greaterThan(NumberSequenceLogic.familiesFor(l - 1).length));
      }
    });
  });

  group('ShapeMatch', () {
    test('first n cards are memorise-only, then answers are consistent with n-back', () {
      for (final level in [1, 4, 7, 10]) {
        final seq = ShapeMatchSequence(Random(level));
        final n = ShapeMatchLogic.configFor(level).nBack;
        var matches = 0;
        for (var i = 0; i < 400; i++) {
          final round = seq.next(level);
          final h = seq.history;
          if (i < n) {
            expect(round.isQuestion, isFalse);
            continue;
          }
          expect(round.isQuestion, isTrue);
          expect(round.isMatch, h[h.length - 1].kind == h[h.length - 1 - n].kind);
          if (round.isMatch) matches++;
        }
        expect(matches / (400 - n), closeTo(0.5, 0.1));
      }
    });

    test('n-back switches to 2 at level 7 and colors vary from level 3', () {
      expect(ShapeMatchLogic.configFor(6).nBack, 1);
      expect(ShapeMatchLogic.configFor(7).nBack, 2);
      expect(ShapeMatchLogic.configFor(2).varyColors, isFalse);
      expect(ShapeMatchLogic.configFor(3).varyColors, isTrue);
    });

    test('shapes come only from the allowed set', () {
      final seq = ShapeMatchSequence(Random(1));
      for (var i = 0; i < 100; i++) {
        final r = seq.next(1);
        expect(r.card.kind.index, lessThan(ShapeMatchLogic.configFor(1).shapeCount));
      }
    });
  });

  group('WordScramble', () {
    test('lists are clean: unique, lowercase English, Urdu without diacritics', () {
      expect(WordLists.english.toSet(), hasLength(WordLists.english.length));
      expect(WordLists.urdu.toSet(), hasLength(WordLists.urdu.length));
      expect(WordLists.english.every((w) => RegExp(r'^[a-z]{4,8}$').hasMatch(w)), isTrue);
      // Arabic-script letters only (U+0600–U+06FF, U+0750–U+077F), no harakat.
      final urduLetter = RegExp(r'^[ء-غف-يٹ-ۓ]+$');
      for (final w in WordLists.urdu) {
        expect(urduLetter.hasMatch(w), isTrue, reason: 'unexpected character in "$w"');
        expect(w.characters.length, inInclusiveRange(3, 6));
      }
    });

    test('every level has enough words of the target length in both languages', () {
      for (final lang in WordLanguage.values) {
        for (var l = 1; l <= 10; l++) {
          final len = WordScrambleLogic.targetLength(l, lang);
          final count = WordScrambleLogic.wordsFor(lang).where((w) => w.characters.length == len).length;
          expect(count, greaterThanOrEqualTo(3), reason: '$lang level $l length $len');
        }
      }
    });

    test('tiles are a real shuffle of the word', () {
      final r = Random(5);
      for (final lang in WordLanguage.values) {
        for (var i = 0; i < 300; i++) {
          final q = WordScrambleLogic.generate(r, 1 + i % 10, lang);
          expect([...q.tiles]..sort(), [...q.word.characters]..sort());
          expect(q.tiles.join(), isNot(q.word));
          expect(WordScrambleLogic.isCorrect(q.word, q), isTrue);
        }
      }
    });

    test('accepts valid anagrams from the list, rejects other words', () {
      final q = ScrambleQuestion(word: 'heart', tiles: 'earth'.characters.toList(), language: WordLanguage.english);
      expect(WordScrambleLogic.isCorrect('earth', q), isTrue);
      expect(WordScrambleLogic.isCorrect('hater', q), isFalse); // not in the list
      expect(WordScrambleLogic.isCorrect('heart', q), isTrue);
    });

    test('avoids recently used words', () {
      final r = Random(2);
      final used = <String>{};
      for (var i = 0; i < 30; i++) {
        final q = WordScrambleLogic.generate(r, 1, WordLanguage.english, avoid: used);
        expect(used, isNot(contains(q.word)));
        used.add(q.word);
      }
    });
  });

  group('OddOneOut', () {
    test('the odd cell always really differs and is on the board', () {
      for (var level = 1; level <= 10; level++) {
        final r = Random(level);
        for (var i = 0; i < 200; i++) {
          final q = OddOneOutLogic.generate(r, level);
          expect(q.oddIndex, inInclusiveRange(0, q.cellCount - 1));
          expect(q.baseGlyph != q.oddGlyph || q.oddTurns != 0, isTrue);
          expect(OddGlyphs.all, contains(q.baseGlyph));
          expect(OddGlyphs.all, contains(q.oddGlyph));
          if (q.kind == OddKind.rotated) expect(OddGlyphs.asymmetric, contains(q.baseGlyph));
        }
      }
    });

    test('grid grows with level', () {
      for (var l = 2; l <= 10; l++) {
        expect(OddOneOutLogic.gridSizeFor(l), greaterThanOrEqualTo(OddOneOutLogic.gridSizeFor(l - 1)));
      }
      expect(OddOneOutLogic.gridSizeFor(10), 7);
    });
  });

  group('PathRecall', () {
    test('paths are connected, self-avoiding and the right length', () {
      for (var level = 1; level <= 10; level++) {
        final cfg = PathRecallLogic.configFor(level);
        final r = Random(level);
        for (var i = 0; i < 100; i++) {
          final p = PathRecallLogic.generatePath(r, cfg);
          expect(p, hasLength(cfg.length));
          expect(p.toSet(), hasLength(cfg.length));
          expect(p.every((c) => c >= 0 && c < cfg.cellCount), isTrue);
          for (var k = 1; k < p.length; k++) {
            expect(PathRecallLogic.isAdjacent(p[k - 1], p[k], cfg.gridSize), isTrue, reason: '$p');
          }
        }
      }
    });

    test('adjacency does not wrap around rows', () {
      expect(PathRecallLogic.isAdjacent(3, 4, 4), isFalse); // end of row 0 → start of row 1
      expect(PathRecallLogic.isAdjacent(0, 4, 4), isTrue);
      expect(PathRecallLogic.neighbours(0, 4).toSet(), {1, 4});
    });
  });
}
