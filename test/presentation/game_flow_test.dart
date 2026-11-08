import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurorush/domain/entities/game_result.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:neurorush/presentation/game/game_shell.dart';
import 'package:neurorush/presentation/games/color_clash_game.dart';
import 'package:neurorush/presentation/games/memory_grid_game.dart';
import 'package:neurorush/presentation/games/speed_math_game.dart';
import 'package:neurorush/presentation/screens/results/results_screen.dart';

import '../helpers.dart';

Widget _host(MemoryHistoryRepository history, GameType type, Duration round) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      GoRoute(
        path: '/play',
        builder: (_, _) => GameShell(
          type: type,
          seed: 42,
          roundDuration: round,
          builder: (context, s) => switch (type) {
            GameType.speedMath => SpeedMathGame(session: s),
            GameType.colorClash => ColorClashGame(session: s),
            GameType.memoryGrid => MemoryGridGame(session: s),
          },
        ),
      ),
      GoRoute(path: '/results', builder: (_, s) => ResultsScreen(result: s.extra! as GameResult)),
      GoRoute(path: '/play/:id', builder: (_, s) => Text('replay ${s.pathParameters['id']}')),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
    ],
  );
  return ProviderScope(
    overrides: testOverrides(history: history),
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _openAndStart(WidgetTester tester) async {
  final ctx = tester.element(find.text('home'));
  GoRouter.of(ctx).push('/play');
  await tester.pumpAndSettle();
  expect(find.text('Start'), findsOneWidget);
  await tester.tap(find.text('Start'));
  // 3, 2, 1 (750 ms each) + GO (500 ms)
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 760));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('Speed Math: countdown, correct answers score, results saved', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(_host(history, GameType.speedMath, const Duration(seconds: 8)));
    await tester.pumpAndSettle();
    await _openAndStart(tester);

    // Answer three questions correctly.
    for (var i = 0; i < 3; i++) {
      final q = tester.widget<Text>(find.textContaining('= ?')).data!;
      final answer = evaluate(q.replaceAll(' = ?', ''));
      await tester.tap(find.text('$answer').last);
      await tester.pump(const Duration(milliseconds: 350));
        }

    // Regression: with reduced motion on, the round clock must not be
    // shortened (AnimationController would otherwise run 20x faster).
    expect(find.text("Time's up!"), findsNothing);

    // Pause and resume.
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Paused'), findsNothing);

    // Run out the clock and wait for the results screen.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(find.byType(ResultsScreen), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);

    expect(history.items, hasLength(1));
    final r = history.items.single;
    expect(r.gameType, GameType.speedMath);
    expect(r.correct, greaterThanOrEqualTo(3));
    expect(r.score, greaterThan(0));
    expect(r.isPersonalBest, isTrue);
    expect(r.stars, greaterThanOrEqualTo(1));

    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();
    expect(find.text('replay speed_math'), findsOneWidget);
  });

  testWidgets('Color Clash: tapping the ink color is scored as correct', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(_host(history, GameType.colorClash, const Duration(seconds: 5)));
    await tester.pumpAndSettle();
    await _openAndStart(tester);

    final word = find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 72);
    final shown = tester.widget<Text>(word);
    final label = tester
        .widget<Semantics>(find.ancestor(of: word, matching: find.byType(Semantics)).first)
        .properties
        .label!;
    final ink = RegExp(r'written in (\w+) ink').firstMatch(label)![1]!;
    expect(shown.data, isNotNull);
    await tester.tap(find.text(ink).last);
    await tester.pump(const Duration(milliseconds: 250));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(history.items.single.correct, greaterThanOrEqualTo(1));
  });

  testWidgets('Memory Grid: wrong tile counts as a mistake', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(_host(history, GameType.memoryGrid, const Duration(seconds: 6)));
    await tester.pumpAndSettle();
    await _openAndStart(tester);

    expect(find.textContaining('Memorise'), findsOneWidget);
    final lit = find.bySemanticsLabel(RegExp(r'Tile row \d column \d, lit'));
    final unlit = find.bySemanticsLabel(RegExp(r'^Tile row \d column \d$'));
    expect(lit, findsNWidgets(3));
    final wrongTile = tester.getCenter(unlit.first);
    // Wait for the pattern to hide, then tap a tile that was not lit.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.textContaining('Tap the tiles'), findsOneWidget);
    await tester.tapAt(wrongTile);
    await tester.pump();
    expect(find.text('Missed — here they were'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(history.items.single.wrong, greaterThanOrEqualTo(1));
  });
}
