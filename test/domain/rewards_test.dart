import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/domain/logic/rewards.dart';

void main() {
  group('Rewards.starsFor', () {
    const type = GameType.speedMath; // thresholds 800 / 1800 / 3000

    int stars(int score, double acc, {int correct = 10}) =>
        Rewards.starsFor(type: type, score: score, accuracy: acc, correct: correct);

    test('0 stars with no correct answers', () => expect(stars(0, 0, correct: 0), 0));
    test('1 star for finishing below the 2-star threshold', () => expect(stars(100, 0.5), 1));
    test('2 stars at the second threshold', () => expect(stars(1800, 0.5), 2));
    test('3 stars needs the score AND 80% accuracy', () {
      expect(stars(3000, 0.79), 2);
      expect(stars(3000, 0.8), 3);
    });

    test('every game has ascending thresholds', () {
      for (final t in GameType.values) {
        expect(t.starThresholds.length, 3);
        expect(t.starThresholds[0] < t.starThresholds[1], isTrue);
        expect(t.starThresholds[1] < t.starThresholds[2], isTrue);
      }
    });
  });

  group('Rewards.xpFor', () {
    test('minimum 5 XP', () => expect(Rewards.xpFor(score: 0, stars: 0, accuracy: 0), 5));
    test('score, star and accuracy bonuses add up', () {
      // 2000/20 = 100, 3 stars = 45, accuracy bonus = 20
      expect(Rewards.xpFor(score: 2000, stars: 3, accuracy: 0.95), 165);
      expect(Rewards.xpFor(score: 2000, stars: 3, accuracy: 0.85), 145);
    });
  });
}
