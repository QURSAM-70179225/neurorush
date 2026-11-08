import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurorush/domain/entities/ai_models.dart';
import 'package:neurorush/domain/entities/game_result.dart';
import 'package:neurorush/domain/entities/skill.dart';
import 'package:neurorush/domain/logic/daily_workout.dart';
import 'package:neurorush/domain/repositories/cloud_repository.dart';
import 'package:neurorush/domain/repositories/coach_cache.dart';
import 'package:neurorush/presentation/providers/ai_providers.dart';
import 'package:neurorush/presentation/providers/cloud_providers.dart';
import 'package:neurorush/presentation/screens/endless/endless_screen.dart';
import 'package:neurorush/presentation/widgets/coach_card.dart';

import '../helpers.dart';

class MemoryCoachCache implements CoachTipCache {
  final Map<String, CoachTip> items = {};
  @override
  CoachTip? read(String uid, String day) => items['$uid/$day'];
  @override
  Future<void> write(String uid, String day, CoachTip tip) async => items['$uid/$day'] = tip;
}

EndlessPuzzle puzzle(String id, {int? remaining = 9}) => EndlessPuzzle(
      id: id,
      kind: 'riddle',
      question: 'Question $id: what has keys but cannot open locks?',
      choices: const ['A piano', 'A map', 'A door', 'A tree'],
      difficulty: 2,
      isAi: true,
      run: 0,
      lives: 3,
      bestRun: 0,
      remainingToday: remaining,
    );

void main() {
  final now = DateTime(2026, 3, 10, 18);

  Widget host(Widget child, {required FakeCloudRepository cloud, MemoryHistoryRepository? history, MemoryCoachCache? cache}) =>
      ProviderScope(
        overrides: [
          ...testOverrides(cloud: cloud, history: history, clock: () => now),
          coachCacheProvider.overrideWithValue(cache ?? MemoryCoachCache()),
        ],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
      );

  /// History that completes today's workout (all rounds synced).
  MemoryHistoryRepository completedWorkout() {
    final games = DailyWorkout.build(history: const [], now: now).games;
    return MemoryHistoryRepository([
      for (final (i, g) in games.indexed) sampleResult(type: g, id: 'w$i', at: now, syncState: SyncState.synced),
    ]);
  }

  group('Brain Coach card', () {
    testWidgets('locked until the workout is done', (tester) async {
      await tester.pumpWidget(host(const CoachCard(), cloud: FakeCloudRepository()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Finish today’s workout'), findsOneWidget);
    });

    testWidgets('shows the AI tip and fun fact, cached for offline use', (tester) async {
      final cloud = FakeCloudRepository()
        ..coachTip = const CoachTip(tip: 'Great work! Try Path Recall next.', funFact: 'Sleep consolidates memories.', focusSkill: Skill.memory, isAi: true);
      final cache = MemoryCoachCache();
      final history = completedWorkout();
      await tester.pumpWidget(host(const CoachCard(), cloud: cloud, history: history, cache: cache));
      await tester.pumpAndSettle();
      expect(find.text('Great work! Try Path Recall next.'), findsOneWidget);
      expect(find.text('Brain fact: Sleep consolidates memories.'), findsOneWidget);
      expect(cache.items, hasLength(1));

      // Offline later: still shown from the cache, no new request.
      cloud.online = false;
      await tester.pumpWidget(host(const CoachCard(key: ValueKey(2)), cloud: cloud, history: history, cache: cache));
      await tester.pumpAndSettle();
      expect(find.text('Great work! Try Path Recall next.'), findsOneWidget);
      expect(cloud.coachCalls, 1);
    });

    testWidgets('waits for the workout to upload; fallback tips are labelled and not cached', (tester) async {
      final cloud = FakeCloudRepository(online: false)
        ..coachTip = const CoachTip(tip: 'Logic is your growth area.', funFact: 'The brain uses 20% of your energy.', focusSkill: Skill.logic, isAi: false);
      final games = DailyWorkout.build(history: const [], now: now).games;
      final history = MemoryHistoryRepository([for (final (i, g) in games.indexed) sampleResult(type: g, id: 'p$i', at: now)]);
      final cache = MemoryCoachCache();
      await tester.pumpWidget(host(const CoachCard(), cloud: cloud, history: history, cache: cache));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Uploading your workout…'), findsOneWidget);

      await tester.pumpWidget(host(const CoachCard(key: ValueKey(2)), cloud: cloud..online = true, history: completedWorkout(), cache: cache));
      await tester.pumpAndSettle();
      expect(find.text('Logic is your growth area.'), findsOneWidget);
      expect(find.textContaining('AI coach is busy'), findsOneWidget);
      expect(cache.items, isEmpty);
    });
  });

  testWidgets('offline with rounds still to upload asks to connect', (tester) async {
    final cloud = FakeCloudRepository(online: false)..coachTip = const CoachTip(tip: 't', funFact: 'f', focusSkill: null, isAi: true);
    final games = DailyWorkout.build(history: const [], now: now).games;
    final history = MemoryHistoryRepository([for (final (i, g) in games.indexed) sampleResult(type: g, id: 'q$i', at: now)]);
    await tester.pumpWidget(host(const CoachCard(), cloud: cloud, history: history));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(CoachCard)));
    await container.read(syncProvider.notifier).sync();
    await tester.pumpAndSettle();
    expect(find.text('Connect to the internet to get today’s coach tip.'), findsOneWidget);
  });

  group('Endless Mode', () {
    Future<void> start(WidgetTester tester, FakeCloudRepository cloud) async {
      usePhoneSize(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: testOverrides(cloud: cloud, clock: () => now),
        child: const MaterialApp(home: EndlessScreen(timeLimit: Duration(seconds: 5))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('server-checked answers, explanation, lives and game over', (tester) async {
      final cloud = FakeCloudRepository();
      for (final id in ['a', 'b', 'c', 'd']) {
        cloud.endlessQueue.add((puzzle(id), 0, 'A piano has keys.'));
      }
      await start(tester, cloud);
      expect(find.textContaining('Question a'), findsOneWidget);
      expect(find.text('9 left today'), findsOneWidget);

      await tester.tap(find.text('A piano'));
      await tester.pumpAndSettle();
      expect(find.text('Correct!'), findsOneWidget);
      expect(find.text('A piano has keys.'), findsOneWidget);
      expect(find.text('Run 1'), findsOneWidget);

      for (final id in ['b', 'c', 'd']) {
        await tester.tap(find.text('Next puzzle').hitTestable().evaluate().isEmpty ? find.text('See results') : find.text('Next puzzle'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.textContaining('Question $id'), findsOneWidget);
        await tester.tap(find.text('A map'));
        await tester.pumpAndSettle();
        expect(find.text('Not quite.'), findsOneWidget);
      }
      expect(cloud.endlessAnswers, ['a:0', 'b:1', 'c:1', 'd:1']);
      await tester.tap(find.text('See results'));
      await tester.pumpAndSettle();
      expect(find.text('Run over'), findsOneWidget);
      expect(find.text('New best run!'), findsOneWidget);
    });

    testWidgets('running out of time submits a timeout', (tester) async {
      final cloud = FakeCloudRepository()..endlessQueue.add((puzzle('t'), 2, 'Explained.'));
      await start(tester, cloud);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(cloud.endlessAnswers, ['t:-1']);
      expect(find.text('Time’s up!'), findsOneWidget);
    });

    testWidgets('daily limit message for free players', (tester) async {
      final cloud = FakeCloudRepository()
        ..endlessError = const CloudFailure('You’ve used today’s 10 free puzzles.', code: 'resource-exhausted');
      await start(tester, cloud);
      await tester.pumpAndSettle();
      expect(find.text('You’ve used today’s 10 free puzzles.'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });
  });
}
