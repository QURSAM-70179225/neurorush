import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/presentation/screens/brain/brain_screen.dart';
import 'package:neurorush/presentation/screens/brain_test/brain_test_screen.dart';

import '../helpers.dart';

void main() {
  testWidgets('Brain Test: 5 rounds, then a Brain Score and radar', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    final progress = MemoryProgressRepository();
    final settings = MemorySettingsRepository();
    final router = GoRouter(initialLocation: '/brain-test', routes: [
      GoRoute(path: '/brain-test', builder: (_, _) => const BrainTestScreen(roundDuration: Duration(seconds: 2))),
      GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('home page'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(history: history, progress: progress, settings: settings),
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(settings.value.brainTestOffered, isTrue);
    await tester.tap(find.text('Start Brain Test'));
    await tester.pumpAndSettle();

    for (var i = 0; i < BrainTestScreen.games.length; i++) {
      expect(find.text('Brain Test · ${i + 1} of 5'), findsOneWidget);
      expect(find.text(BrainTestScreen.games[i].title), findsWidgets);
      await tester.tap(find.text('Start'));
      for (var k = 0; k < 14; k++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
    }

    expect(find.text('Your Brain Score'), findsOneWidget);
    expect(history.items.map((r) => r.gameType), BrainTestScreen.games);
    expect(history.items.every((r) => r.durationSeconds == 2), isTrue);
    expect(progress.value.brainTestDone, isTrue);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('Brain Score screen shows score, skills and 7/30 day charts', (tester) async {
    usePhoneSize(tester);
    final now = DateTime(2026, 3, 10, 12);
    final history = MemoryHistoryRepository([
      for (var i = 0; i < 5; i++)
        sampleResult(type: GameType.values[i], at: now.subtract(Duration(days: i)), id: 'r$i'),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(history: history, clock: () => now),
      child: const MaterialApp(home: BrainScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('out of 1000'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Semantics && RegExp(r'^Skill radar\. Memory \d+ of 200').hasMatch(w.properties.label ?? '')),
      findsOneWidget,
    );
    await scrollTo(tester, find.text('30 days'));
    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Skill progress over 30 days')),
      findsOneWidget,
    );
  });
}
