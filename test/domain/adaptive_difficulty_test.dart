import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/logic/adaptive_difficulty.dart';

void main() {
  group('AdaptiveDifficulty', () {
    test('starts at the start level', () {
      expect(AdaptiveDifficulty(startLevel: 3).level, 3);
    });

    test('two correct answers raise the level by one', () {
      final d = AdaptiveDifficulty();
      d.onCorrect();
      expect(d.level, 1);
      d.onCorrect();
      expect(d.level, 2);
    });

    test('fast answers climb faster', () {
      final slow = AdaptiveDifficulty(), fast = AdaptiveDifficulty();
      for (var i = 0; i < 4; i++) {
        slow.onCorrect();
        fast.onCorrect(fast: true);
      }
      expect(slow.level, 3);
      expect(fast.level, 4);
    });

    test('a mistake drops at least one full level', () {
      final d = AdaptiveDifficulty(startLevel: 5);
      d.onCorrect(); // 5.5
      d.onMistake(); // floor(4.5) = 4
      expect(d.level, 4);
      expect(d.value, 4.0);
    });

    test('never goes below min or above max', () {
      final d = AdaptiveDifficulty(maxLevel: 4);
      d.onMistake();
      expect(d.level, 1);
      for (var i = 0; i < 50; i++) {
        d.onCorrect(fast: true);
      }
      expect(d.level, 4);
    });

    test('tracks the highest level reached', () {
      final d = AdaptiveDifficulty();
      for (var i = 0; i < 6; i++) {
        d.onCorrect();
      }
      d.onMistake();
      d.onMistake();
      expect(d.level, 2);
      expect(d.maxReached, 4);
    });
  });
}
