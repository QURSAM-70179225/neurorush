import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurorush/domain/entities/game_type.dart';
import 'package:flame/game.dart';
import 'package:neurorush/domain/entities/app_settings.dart';
import 'package:neurorush/domain/games/odd_one_out_logic.dart';
import 'package:neurorush/domain/games/word_scramble_logic.dart';
import 'package:neurorush/presentation/game/game_shell.dart';
import 'package:neurorush/presentation/games/odd_one_out_game.dart';
import 'package:neurorush/presentation/games/path_recall_board.dart';
import 'package:neurorush/presentation/games/path_recall_game.dart';
import 'package:neurorush/presentation/games/word_scramble_game.dart';
import 'package:neurorush/presentation/game/results_args.dart';
import 'package:neurorush/presentation/games/game_play_screen.dart';
import 'package:neurorush/presentation/screens/results/results_screen.dart';

import '../helpers.dart';

Widget host(MemoryHistoryRepository history, GameType type, Duration round, {MemoryProgressRepository? progress}) {
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
          builder: gameBuilderFor(type),
        ),
      ),
      GoRoute(path: '/results', builder: (_, s) => ResultsScreen(args: s.extra! as ResultsArgs)),
      GoRoute(path: '/play/:id', builder: (_, s) => Text('replay ${s.pathParameters['id']}')),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
    ],
  );
  return ProviderScope(
    overrides: testOverrides(history: history, progress: progress),
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> openAndStart(WidgetTester tester) async {
  final ctx = tester.element(find.text('home'));
  GoRouter.of(ctx).push('/play');
  // Not pumpAndSettle: the Flame board animates every frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
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
    // 98 XP: any finished round (min 5 XP) levels the player up to level 2.
    final history = MemoryHistoryRepository([sampleResult(type: GameType.memoryGrid, xp: 98, at: DateTime(2020))]);
    await tester.pumpWidget(host(history, GameType.speedMath, const Duration(seconds: 8)));
    await tester.pumpAndSettle();
    await openAndStart(tester);

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
    await scrollTo(tester, find.text('Play again'));

    expect(find.text('Level up! You reached level 2'), findsOneWidget);
    expect(find.textContaining('-day streak!'), findsOneWidget);

    expect(history.items, hasLength(2));
    final r = history.items.last;
    expect(r.gameType, GameType.speedMath);
    expect(r.correct, greaterThanOrEqualTo(3));
    expect(r.score, greaterThan(0));
    expect(r.isPersonalBest, isTrue);
    expect(r.stars, greaterThanOrEqualTo(1));

    await tester.tap(find.text('Play again'));
    await tester.pumpAndSettle();
    expect(find.text('replay speed_math'), findsOneWidget);
  });

  testWidgets('Shape Match: memorise first card, then YES/NO answers are scored', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(host(history, GameType.shapeMatch, const Duration(seconds: 6)));
    await tester.pumpAndSettle();
    await openAndStart(tester);
    expect(find.text('Remember this shape'), findsOneWidget);
    String card() => tester
        .widget<Semantics>(find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Card: ')))
        .properties
        .label!;
    var previous = card();
    await tester.pump(const Duration(milliseconds: 1000));
    for (var i = 0; i < 4; i++) {
      expect(find.text('Same shape as the previous card?'), findsOneWidget);
      final now = card();
      await tester.tap(semanticsWidget(now == previous ? 'YES' : 'NO'));
      await tester.pump(const Duration(milliseconds: 250));
      previous = now;
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    final r = history.items.single;
    expect(r.correct, greaterThanOrEqualTo(4));
    expect(r.wrong, lessThanOrEqualTo(r.attempts - 4));
  });

  testWidgets('Number Sequence: a wrong answer reveals the rule', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(host(history, GameType.numberSequence, const Duration(seconds: 6)));
    await tester.pumpAndSettle();
    await openAndStart(tester);
    final label = tester
        .widget<Semantics>(find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Sequence: ')))
        .properties
        .label!;
    final shown = RegExp(r'\d+').allMatches(label).map((m) => int.parse(m[0]!)).toList();
    // Level 1 is always "add d": the answer is last + d.
    final answer = shown.last + (shown[1] - shown[0]);
    final options = tester
        .widgetList<Semantics>(find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true))
        .map((w) => int.tryParse(w.properties.label ?? ''))
        .whereType<int>()
        .toList();
    final wrong = options.firstWhere((o) => o != answer);
    await tester.tap(semanticsWidget('$wrong'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Rule: Add'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(history.items.single.wrong, greaterThanOrEqualTo(1));
  });

  testWidgets('Word Scramble: building the word scores; English and Urdu', (tester) async {
    for (final urdu in [false, true]) {
      usePhoneSize(tester);
      useReducedMotion(tester);
      final history = MemoryHistoryRepository();
      final settings = MemorySettingsRepository(AppSettings(wordLanguage: urdu ? WordLanguage.urdu : WordLanguage.english));
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(
          path: '/play',
          builder: (_, _) => GameShell(
            type: GameType.wordScramble,
            seed: 3,
            roundDuration: const Duration(seconds: 6),
            builder: gameBuilderFor(GameType.wordScramble),
          ),
        ),
        GoRoute(path: '/results', builder: (_, s) => ResultsScreen(args: s.extra! as ResultsArgs)),
      ]);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: testOverrides(history: history, settings: settings),
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      await openAndStart(tester);
      final state = tester.state<WordScrambleGameState>(find.byType(WordScrambleGame));
      final word = state.debugCurrentWord!;
      final letters = word.characters.toList();
      // Tap tiles in order, picking each letter among the remaining tiles.
      final used = <int>{};
      final tiles = find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Letter '));
      final tileLabels = tester.widgetList<Semantics>(tiles).map((w) => w.properties.label!.substring(7)).toList();
      for (final l in letters) {
        final i = List.generate(tileLabels.length, (i) => i).firstWhere((i) => !used.contains(i) && tileLabels[i] == l);
        used.add(i);
        await tester.tap(tiles.at(i));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 600));
      expect(state.debugCurrentWord, isNot(word), reason: 'moves on to a new word');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pumpAndSettle();
      expect(history.items.single.correct, 1, reason: urdu ? 'urdu' : 'english');
    }
  });

  testWidgets('Odd One Out: tapping the odd icon is correct', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(host(history, GameType.oddOneOut, const Duration(seconds: 5)));
    await tester.pumpAndSettle();
    await openAndStart(tester);
    for (var round = 0; round < 3; round++) {
      final cells = tester
          .widgetList<Semantics>(find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Icon ')))
          .map((w) => w.properties.label!)
          .toList();
      String glyph(String l) => l.substring(l.indexOf(':') + 2);
      final counts = <String, int>{};
      for (final c in cells) {
        counts[glyph(c)] = (counts[glyph(c)] ?? 0) + 1;
      }
      final odd = cells.firstWhere((c) => counts[glyph(c)] == 1);
      await tester.tap(semanticsWidget(odd));
      await tester.pump(const Duration(milliseconds: 300));
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(history.items.single.correct, 3);
    expect(history.items.single.wrong, 0);
  });

  testWidgets('Path Recall (Flame): tracing the path by tapping cells scores', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(host(history, GameType.pathRecall, const Duration(seconds: 8)));
    await tester.pumpAndSettle();
    await openAndStart(tester);
    expect(find.textContaining('Watch the path'), findsOneWidget);
    final state = tester.state<PathRecallGameState>(find.byType(PathRecallGame));
    final path = state.debugPath;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Trace it'), findsOneWidget);
    final origin = tester.getTopLeft(find.byType(GameWidget<PathRecallBoard>));
    for (final cell in path) {
      await tester.tapAt(origin + state.board.cellCenter(cell));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Perfect path!'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(history.items.single.correct, greaterThanOrEqualTo(1));
  });

  test('every Odd One Out glyph has an icon', () {
    expect(oddGlyphIcons.keys.toSet(), containsAll(OddGlyphs.all));
  });

  testWidgets('Color Clash: tapping the ink color is scored as correct', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    final history = MemoryHistoryRepository();
    await tester.pumpWidget(host(history, GameType.colorClash, const Duration(seconds: 5)));
    await tester.pumpAndSettle();
    await openAndStart(tester);

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
    await tester.pumpWidget(host(history, GameType.memoryGrid, const Duration(seconds: 6)));
    await tester.pumpAndSettle();
    await openAndStart(tester);

    expect(find.textContaining('Memorise'), findsOneWidget);
    final lit = find.byWidgetPredicate(
        (w) => w is Semantics && RegExp(r'^Tile row \d column \d, lit$').hasMatch(w.properties.label ?? ''));
    final unlit = find.byWidgetPredicate(
        (w) => w is Semantics && RegExp(r'^Tile row \d column \d$').hasMatch(w.properties.label ?? ''));
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
