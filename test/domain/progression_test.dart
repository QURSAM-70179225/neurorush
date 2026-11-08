import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/domain/entities/progress_state.dart';
import 'package:neurorush/domain/entities/skill.dart';
import 'package:neurorush/domain/logic/brain_score.dart';
import 'package:neurorush/domain/logic/daily_workout.dart';
import 'package:neurorush/domain/logic/streak_logic.dart';
import 'package:neurorush/domain/logic/xp_levels.dart';
import 'package:neurorush/presentation/providers/app_providers.dart';

import '../helpers.dart';

DateTime d(int day) => DateTime(2026, 3, day);

void main() {
  group('XpLevels', () {
    test('level thresholds', () {
      expect(XpLevels.totalXpFor(1), 0);
      expect(XpLevels.totalXpFor(2), 100);
      expect(XpLevels.totalXpFor(3), 240); // 100 + 140
      expect(XpLevels.totalXpFor(50), 51940);
      expect(XpLevels.fromXp(99).level, 1);
      expect(XpLevels.fromXp(100).level, 2);
      expect(XpLevels.fromXp(239).level, 2);
      expect(XpLevels.fromXp(240).level, 3);
    });

    test('progress within a level', () {
      final info = XpLevels.fromXp(170);
      expect(info.level, 2);
      expect(info.xpIntoLevel, 70);
      expect(info.xpForNextLevel, 140);
      expect(info.progress, closeTo(0.5, 1e-9));
    });

    test('caps at 50 with the top title', () {
      final info = XpLevels.fromXp(10000000);
      expect(info.level, 50);
      expect(info.isMax, isTrue);
      expect(info.progress, 1);
      expect(info.title, 'Neuron Master');
    });

    test('titles go from Rookie Brain to Neuron Master', () {
      expect(XpLevels.titleFor(1), 'Rookie Brain I');
      expect(XpLevels.titleFor(5), 'Rookie Brain V');
      expect(XpLevels.titleFor(6), 'Curious Mind I');
      expect(XpLevels.titleFor(46), 'Neuron Master I');
      final all = {for (var l = 1; l <= 50; l++) XpLevels.titleFor(l)};
      expect(all, hasLength(50));
    });
  });

  group('StreakLogic', () {
    test('counts consecutive played days ending today', () {
      final s = StreakLogic.compute(playedDays: {d(8), d(9), d(10)}, frozenDays: {}, today: d(10));
      expect(s.current, 3);
      expect(s.playedToday, isTrue);
      expect(s.atRisk, isFalse);
    });

    test('streak is still alive (but at risk) before today is played', () {
      final s = StreakLogic.compute(playedDays: {d(8), d(9)}, frozenDays: {}, today: d(10));
      expect(s.current, 2);
      expect(s.atRisk, isTrue);
    });

    test('a missed day breaks the streak', () {
      final s = StreakLogic.compute(playedDays: {d(5), d(6), d(7), d(9)}, frozenDays: {}, today: d(10));
      expect(s.current, 1);
      expect(s.best, 3);
    });

    test('frozen days bridge the gap without counting', () {
      final s = StreakLogic.compute(playedDays: {d(6), d(7), d(9), d(10)}, frozenDays: {d(8)}, today: d(10));
      expect(s.current, 4);
    });

    test('several plays on one day count once; times of day are ignored', () {
      final s = StreakLogic.compute(
        playedDays: {DateTime(2026, 3, 9, 8), DateTime(2026, 3, 9, 22), DateTime(2026, 3, 10, 0, 5)},
        frozenDays: {},
        today: DateTime(2026, 3, 10, 23, 59),
      );
      expect(s.current, 2);
    });

    test('daysToFreeze covers the gap only when enough freezes', () {
      expect(
        StreakLogic.daysToFreeze(playedDays: {d(7)}, frozenDays: {}, freezesAvailable: 2, today: d(10)),
        [d(8), d(9)],
      );
      expect(StreakLogic.daysToFreeze(playedDays: {d(7)}, frozenDays: {}, freezesAvailable: 1, today: d(10)), isEmpty);
      expect(StreakLogic.daysToFreeze(playedDays: {d(9)}, frozenDays: {}, freezesAvailable: 2, today: d(10)), isEmpty);
      expect(StreakLogic.daysToFreeze(playedDays: {}, frozenDays: {}, freezesAvailable: 2, today: d(10)), isEmpty);
    });

    test('free freeze every 7 days', () {
      expect(StreakLogic.earnsFreeze(7), isTrue);
      expect(StreakLogic.earnsFreeze(14), isTrue);
      expect(StreakLogic.earnsFreeze(8), isFalse);
      expect(StreakLogic.earnsFreeze(0), isFalse);
    });
  });

  group('ProgressNotifier', () {
    ProviderContainer container({required DateTime now, required List<DateTime> played, ProgressState? progress}) {
      final c = ProviderContainer(overrides: [
        ...testOverrides(
          history: MemoryHistoryRepository([for (final p in played) sampleResult(at: p, id: '$p')]),
          progress: MemoryProgressRepository(progress ?? const ProgressState()),
          clock: () => now,
        ),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('uses a freeze automatically for one missed day', () async {
      final c = container(now: d(10).add(const Duration(hours: 9)), played: [d(8), d(7)]);
      expect(c.read(streakProvider).current, 0); // yesterday missed
      final u = await c.read(progressProvider.notifier).refresh();
      expect(u.frozenDays, 1);
      expect(c.read(progressProvider).freezes, 0);
      expect(c.read(streakProvider).current, 2);
      expect(c.read(streakProvider).atRisk, isTrue);
      // Running again does nothing more.
      expect((await c.read(progressProvider.notifier).refresh()).isEmpty, isTrue);
    });

    test('awards a freeze on the 7th day, once', () async {
      final c = container(
        now: d(13).add(const Duration(hours: 20)),
        played: [for (var i = 7; i <= 13; i++) d(i).add(const Duration(hours: 10))],
        progress: const ProgressState(freezes: 0),
      );
      final u = await c.read(progressProvider.notifier).refresh();
      expect(u.freezeEarned, isTrue);
      expect(c.read(progressProvider).freezes, 1);
      expect((await c.read(progressProvider.notifier).refresh()).freezeEarned, isFalse);
    });

    test('ProgressState survives a storage round trip', () {
      final p = ProgressState(freezes: 2, frozenDays: {d(3)}, freezeAwardDays: {d(5)}, brainTestDone: true);
      final back = ProgressState.fromMap(p.toMap());
      expect(back.freezes, 2);
      expect(back.frozenDays, {d(3)});
      expect(back.freezeAwardDays, {d(5)});
      expect(back.brainTestDone, isTrue);
    });
  });

  group('BrainScore', () {
    test('no history = 0 everywhere', () {
      final b = BrainScore.fromHistory(const []);
      expect(b.total, 0);
      expect(b.hasData, isFalse);
      expect(b.weakest, isNull);
    });

    test('a perfect round scores the full 200 for its skill', () {
      final r = sampleResult(type: GameType.speedMath, score: 5000, correct: 20, wrong: 0, maxLevel: 10);
      expect(BrainScore.sessionRating(r), 1.0);
      final b = BrainScore.fromHistory([r]);
      expect(b.of(Skill.speed), 200);
      expect(b.total, 200);
    });

    test('ratings are independent of round length', () {
      final long = sampleResult(score: 1500, durationSeconds: 60);
      final short = sampleResult(score: 600, durationSeconds: 24);
      expect(BrainScore.sessionRating(short), closeTo(BrainScore.sessionRating(long), 1e-9));
    });

    test('newer rounds weigh more', () {
      final good = sampleResult(score: 3000, correct: 10, wrong: 0, maxLevel: 10);
      final bad = sampleResult(score: 100, correct: 2, wrong: 8, maxLevel: 1);
      final improving = BrainScore.fromHistory([good, bad]).of(Skill.speed);
      final declining = BrainScore.fromHistory([bad, good]).of(Skill.speed);
      expect(improving, greaterThan(declining));
    });

    test('weakest skill and total', () {
      final b = BrainScore.fromHistory([
        sampleResult(type: GameType.speedMath, score: 3000, correct: 10, wrong: 0, maxLevel: 10),
        sampleResult(type: GameType.memoryGrid, score: 2600, correct: 10, wrong: 0, maxLevel: 10),
      ]);
      expect(b.total, b.of(Skill.speed) + b.of(Skill.memory));
      expect(b.weakest, isIn([Skill.focus, Skill.logic, Skill.language]));
    });

    test('daily trend only uses rounds up to each day', () {
      final trend = BrainScore.dailyTrend(
        [sampleResult(at: d(10)), sampleResult(type: GameType.memoryGrid, at: d(8))],
        days: 4,
        now: d(10),
      );
      expect(trend.map((e) => e.$1), [d(7), d(8), d(9), d(10)]);
      expect(trend[0].$2.total, 0);
      expect(trend[1].$2.of(Skill.memory), greaterThan(0));
      expect(trend[1].$2.of(Skill.speed), 0);
      expect(trend[3].$2.of(Skill.speed), greaterThan(0));
    });
  });

  group('DailyWorkout', () {
    test('picks 3 different weakest skills and tracks completion', () {
      final history = [
        sampleResult(type: GameType.speedMath, score: 3000, maxLevel: 10, at: d(9)),
        sampleResult(type: GameType.memoryGrid, score: 2600, maxLevel: 10, at: d(9)),
        sampleResult(type: GameType.numberSequence, score: 100, at: d(10)),
      ];
      final w = DailyWorkout.build(history: history, now: d(10));
      expect(w.games, hasLength(3));
      expect(w.games.map((g) => g.skill).toSet(), hasLength(3));
      expect(w.games.map((g) => g.skill), isNot(contains(Skill.speed)));
      expect(w.games.map((g) => g.skill), isNot(contains(Skill.memory)));
      expect(w.completed, {GameType.numberSequence});
      expect(w.isComplete, isFalse);
      expect(w.nextGame, isNot(GameType.numberSequence));
    });

    test('same day gives the same workout', () {
      final a = DailyWorkout.build(history: const [], now: DateTime(2026, 3, 10, 8));
      final b = DailyWorkout.build(history: const [], now: DateTime(2026, 3, 10, 22));
      expect(a.games, b.games);
    });
  });
}
