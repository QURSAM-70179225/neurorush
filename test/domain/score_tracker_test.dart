import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/logic/score_tracker.dart';

void main() {
  group('ScoreTracker', () {
    test('multiplier grows every 3 correct answers and caps at 5', () {
      final t = ScoreTracker();
      final points = [for (var i = 0; i < 16; i++) t.recordCorrect(basePoints: 10)];
      expect(points.sublist(0, 3), [10, 10, 10]);
      expect(points.sublist(3, 6), [20, 20, 20]);
      expect(points.sublist(6, 9), [30, 30, 30]);
      expect(points[12], 50);
      expect(points[15], 50); // capped
      expect(t.score, points.reduce((a, b) => a + b));
    });

    test('a wrong answer resets the combo but keeps the score', () {
      final t = ScoreTracker();
      for (var i = 0; i < 4; i++) {
        t.recordCorrect(basePoints: 10);
      }
      expect(t.multiplier, 2);
      final before = t.score;
      t.recordWrong();
      expect(t.streak, 0);
      expect(t.multiplier, 1);
      expect(t.score, before);
      expect(t.maxStreak, 4);
    });

    test('accuracy is correct / attempts', () {
      final t = ScoreTracker();
      expect(t.accuracy, 0);
      t
        ..recordCorrect(basePoints: 1)
        ..recordCorrect(basePoints: 1)
        ..recordCorrect(basePoints: 1)
        ..recordWrong();
      expect(t.accuracy, 0.75);
      expect(t.attempts, 4);
    });

    test('reaction times: average and best, implausible values ignored', () {
      final t = ScoreTracker();
      t.recordCorrect(basePoints: 1, reactionMs: 400);
      t.recordCorrect(basePoints: 1, reactionMs: 600);
      t.recordWrong(reactionMs: 20); // too fast to be human
      t.recordWrong(reactionMs: 60000); // idle
      t.recordWrong(); // timeout, no reaction
      expect(t.reactionTimes, [400, 600]);
      expect(t.averageReactionMs, 500);
      expect(t.bestReactionMs, 400);
    });

    test('no reactions gives null averages', () {
      final t = ScoreTracker();
      expect(t.averageReactionMs, isNull);
      expect(t.bestReactionMs, isNull);
    });
  });
}
