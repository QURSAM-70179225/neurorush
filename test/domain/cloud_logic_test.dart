import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/entities/cloud_models.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/domain/logic/achievement_stats.dart';
import 'package:neurorush/domain/logic/weeks.dart';

import '../helpers.dart';

void main() {
  group('weeks (same cases as functions/test/logic.test.ts)', () {
    test('ISO week ids', () {
      expect(isoWeekId(DateTime.utc(2026, 11, 8)), '2026-W45');
      expect(isoWeekId(DateTime.utc(2026, 11, 9)), '2026-W46');
      expect(isoWeekId(DateTime.utc(2021, 1, 3)), '2020-W53');
      expect(isoWeekId(DateTime.utc(2024, 12, 30)), '2025-W01');
    });
    test('next reset is the coming Monday 00:00 UTC', () {
      expect(nextWeeklyReset(DateTime.utc(2026, 11, 8, 23)), DateTime.utc(2026, 11, 9));
      expect(nextWeeklyReset(DateTime.utc(2026, 11, 9, 0, 1)), DateTime.utc(2026, 11, 16));
    });
  });

  group('server/client parity', () {
    test('game catalogue matches functions/src/catalog.ts', () {
      final ts = File('functions/src/catalog.ts').readAsStringSync();
      for (final g in GameType.values) {
        final m = RegExp('${g.id}: \\{[^}]*skill: \'(\\w+)\', starThresholds: \\[(\\d+), (\\d+), (\\d+)\\]').firstMatch(ts);
        expect(m, isNotNull, reason: '${g.id} missing in catalog.ts');
        expect(m![1], g.skill.name);
        expect([int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!)], g.starThresholds);
      }
    });

    test('every achievement metric is produced by the Dart stats builder', () {
      final stats = achievementStats(
        history: [for (final g in GameType.values) sampleResult(type: g, id: g.id)],
        bestStreak: 1,
      );
      for (final a in testCatalogue) {
        expect(stats.containsKey(a.metric), isTrue, reason: 'metric ${a.metric} (${a.id})');
      }
      expect(testCatalogue, hasLength(30));
    });
  });

  group('achievement stats', () {
    test('first round, perfect round, reflexes and records', () {
      final stats = achievementStats(history: [
        sampleResult(score: 3100, correct: 12, wrong: 0, maxCombo: 12, stars: 3, bestReactionMs: 290, id: 'a'),
        sampleResult(score: 9999, durationSeconds: 24, bestReactionMs: 60, id: 'b'), // short round, glitchy reaction
      ], bestStreak: 3, friends: 1);
      final unlocked = unlockedIds(testCatalogue, stats);
      expect(unlocked, containsAll(['first_round', 'perfect_1', 'stars3_1', 'combo_10', 'reflex_300', 'reflex_500', 'streak_3', 'friend_1', 'calculator']));
      expect(stats['best_speed_math'], 3100, reason: 'short rounds do not count as records');
      expect(stats['fastestReactionMs'], 290, reason: 'reactions under 100 ms are ignored');
      expect(unlocked, isNot(contains('explorer')));
    });

    test('progress towards a badge', () {
      final a = testCatalogue.firstWhere((a) => a.id == 'rounds_10');
      expect(a.progress(5), 0.5);
      expect(a.progress(50), 1);
      final r = testCatalogue.firstWhere((a) => a.id == 'reflex_300');
      expect(r.progress(310), 0);
      expect(r.progress(250), 1);
      expect(r.progress(null), 0);
    });
  });

  test('a friend’s streak is only shown while it is alive', () {
    const p = CloudProfile(uid: 'f', currentStreak: 9, streakDay: '2026-03-09');
    expect(p.visibleStreak(DateTime(2026, 3, 9, 22)), 9);
    expect(p.visibleStreak(DateTime(2026, 3, 10, 8)), 9);
    expect(p.visibleStreak(DateTime(2026, 3, 11, 8)), 0);
  });
}
