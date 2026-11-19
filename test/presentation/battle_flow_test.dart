import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:neurorush/core/push/push_service.dart';
import 'package:neurorush/domain/entities/battle.dart';
import 'package:neurorush/domain/entities/cloud_models.dart';
import 'package:neurorush/domain/logic/server_clock.dart';
import 'package:neurorush/core/router/app_router.dart';
import 'package:neurorush/presentation/providers/app_providers.dart';
import 'package:neurorush/presentation/providers/battle_providers.dart';
import 'package:neurorush/presentation/screens/battle/battle_screen.dart';
import 'package:neurorush/presentation/screens/battle/live_battle_screen.dart';
import 'package:neurorush/presentation/screens/battle/matchmaking_screen.dart';
import 'package:neurorush/presentation/widgets/push_listener.dart';

import '../helpers.dart';

const opp = 'opp-uid';
final t0 = DateTime.utc(2026, 11, 8, 12);

Battle battle({
  String id = 'b1',
  BattleStatus status = BattleStatus.active,
  Map<String, int> scores = const {testUid: 0, opp: 0},
  Map<String, Map<int, BattleAnswer>> answers = const {},
  String? winner,
  Map<String, int> delta = const {},
  Map<String, int> coins = const {},
  BattleMode mode = BattleMode.random,
  String? code,
}) =>
    Battle(
      id: id,
      mode: mode,
      status: status,
      players: const [BattlePlayer(uid: testUid, username: 'me'), BattlePlayer(uid: opp, username: 'omar', trophies: 120, level: 6)],
      questions: const [
        BattleQuestion(type: 'math', prompt: '6 × 7', choices: ['42', '48', '36', '41']),
        BattleQuestion(type: 'stroop', word: 0, ink: 1, choices: ['0', '1', '2', '3']),
      ],
      questionMs: 3000,
      startAt: t0.add(const Duration(seconds: 2)),
      endsAt: t0.add(const Duration(seconds: 8)),
      scores: scores,
      answers: answers,
      winner: winner,
      trophyDelta: delta,
      coinDelta: coins,
      inviteCode: code,
    );

void main() {
  late DateTime now;
  late FakeBattleRepository repo;

  Widget app(String initial, {CloudProfile? profile}) {
    final cloud = FakeCloudRepository();
    if (profile != null) cloud.profiles[testUid] = profile;
    final router = GoRouter(initialLocation: initial, routes: [
      GoRoute(path: '/', builder: (_, _) => const BattleScreen()),
      GoRoute(path: '/battle/search', builder: (_, _) => const MatchmakingScreen(botOfferAfter: Duration(seconds: 3))),
      GoRoute(path: '/battle/join/:code', builder: (_, s) => JoinBattleScreen(code: s.pathParameters['code']!)),
      GoRoute(path: '/battle/:id', builder: (_, s) => LiveBattleScreen(battleId: s.pathParameters['id']!)),
    ]);
    return ProviderScope(
      overrides: [
        ...testOverrides(cloud: cloud),
        battleRepositoryProvider.overrideWithValue(repo),
        serverClockProvider.overrideWithValue(ServerClock(now: () => now)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> advance(WidgetTester tester, Duration d) async {
    final steps = d.inMilliseconds ~/ 100;
    for (var i = 0; i < steps; i++) {
      now = now.add(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() {
    now = t0;
    repo = FakeBattleRepository();
  });

  testWidgets('live battle: countdown, synced questions, server-checked answers, result', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    repo.emit(battle());
    repo.onAnswer = (id, i, c) => battle(
          scores: {testUid: 180 * (i + 1), opp: 100},
          answers: {
            testUid: {for (var k = 0; k <= i; k++) k: const BattleAnswer(correct: true, points: 180, ms: 600)},
            opp: {0: const BattleAnswer(correct: true, points: 100, ms: 2900)},
          },
        );
    repo.onFinish = (id) => repo.emit(battle(
          status: BattleStatus.finished,
          scores: const {testUid: 360, opp: 100},
          winner: testUid,
          delta: const {testUid: 30, opp: -20},
          coins: const {testUid: 30, opp: 0},
        ));
    await tester.pumpWidget(app('/battle/b1'));
    await tester.pump();

    expect(find.text('You vs @omar'), findsOneWidget);
    expect(find.text('Level 6 · 120 trophies'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // countdown

    await advance(tester, const Duration(milliseconds: 2100));
    expect(find.text('Question 1 of 2'), findsOneWidget);
    expect(find.text('6 × 7 = ?'), findsOneWidget);
    await tester.tap(find.text('42'));
    await tester.pump();
    await tester.pump();
    expect(repo.calls, contains('answer:0:0'));
    expect(find.text('+180 points!'), findsOneWidget);
    expect(find.text('180'), findsOneWidget); // my live score
    // Can't answer twice.
    await tester.tap(find.text('48'));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('answer:0')), hasLength(1));

    await advance(tester, const Duration(milliseconds: 3000));
    expect(find.text('Question 2 of 2'), findsOneWidget);
    expect(find.text('Tap the INK colour'), findsOneWidget);
    expect(find.text('RED'), findsWidgets); // word shown (and as a choice)
    await tester.tap(find.text('BLUE')); // the ink
    await tester.pump();
    await tester.pump();
    expect(repo.calls, contains('answer:1:1'));

    await advance(tester, const Duration(milliseconds: 3200));
    await tester.pump();
    expect(repo.calls, contains('finish'));
    expect(find.text('You won!'), findsOneWidget);
    expect(find.text('+30 trophies'), findsOneWidget);
    expect(find.text('+30 coins'), findsOneWidget);
    expect(find.text('360 – 100 vs @omar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // let confetti finish
  });

  testWidgets('practice battles tick the server at each new question', (tester) async {
    usePhoneSize(tester);
    useReducedMotion(tester);
    repo.emit(battle(mode: BattleMode.bot));
    await tester.pumpWidget(app('/battle/b1'));
    await tester.pump();
    await advance(tester, const Duration(milliseconds: 2200));
    await advance(tester, const Duration(milliseconds: 3000));
    expect(repo.calls.where((c) => c == 'tick').length, greaterThanOrEqualTo(2));
    expect(find.text('Practice battle'), findsOneWidget);
  });

  testWidgets('invite: waiting screen shows the code', (tester) async {
    usePhoneSize(tester);
    repo.emit(battle(id: 'inv1', status: BattleStatus.waiting, code: 'ABC234'));
    await tester.pumpWidget(app('/battle/inv1'));
    await tester.pump();
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.textContaining('Waiting for your friend'), findsOneWidget);
  });

  testWidgets('Battle tab: trophies, invite, join by code (valid and invalid)', (tester) async {
    usePhoneSize(tester);
    repo.emit(battle(id: 'inv1', status: BattleStatus.waiting, code: 'ABC234'));
    repo.emit(battle(id: 'joined1'));
    await tester.pumpWidget(app('/', profile: const CloudProfile(uid: testUid, trophies: 140, battleWins: 5, battleLosses: 2)));
    await tester.pumpAndSettle();
    expect(find.text('140 trophies'), findsOneWidget);
    expect(find.text('5 W · 2 L · 0 D'), findsOneWidget);

    await tester.tap(find.text('Invite'));
    await tester.pump();
    await tester.pump();
    expect(find.text('ABC234'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Join code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'badbad');
    await tester.tap(find.text('Join'));
    await tester.pump();
    await tester.pump();
    expect(repo.calls, contains('join:BADBAD'));
    expect(find.text('That code is not valid or has expired.'), findsOneWidget);
  });

  testWidgets('matchmaking: waits, offers the bot, and opens the battle when paired', (tester) async {
    usePhoneSize(tester);
    repo.emit(battle(id: 'm1'));
    await tester.pumpWidget(app('/battle/search'));
    await tester.pump();
    expect(find.text('Looking for an opponent…'), findsOneWidget);
    expect(find.text('Practice vs Neo instead'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Practice vs Neo instead'), findsOneWidget);

    repo.emitMatch('m1');
    await tester.pump();
    await tester.pump();
    expect(find.text('You vs @omar'), findsOneWidget);
    expect(repo.calls, isNot(contains('cancelMatch')));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('notifications: tap opens the target screen; foreground shows a banner', (tester) async {
    usePhoneSize(tester);
    final push = FakePushService();
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/battle/join/:code', builder: (_, s) => Scaffold(body: Text('join ${s.pathParameters['code']}'))),
      GoRoute(path: '/friends', builder: (_, _) => const Scaffold(body: Text('friends page'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...testOverrides(),
        pushServiceProvider.overrideWithValue(push),
        routerProvider.overrideWithValue(router),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        scaffoldMessengerKey: scaffoldMessengerKey,
        builder: (_, child) => PushListener(child: child!),
      ),
    ));
    await tester.pumpAndSettle();

    push.events$.add(const PushEvent(data: {'type': 'battle_invite', 'code': 'QWE234'}, opened: true));
    await tester.pumpAndSettle();
    expect(find.text('join QWE234'), findsOneWidget);

    push.events$.add(const PushEvent(data: {'type': 'friend_request'}, title: 'New friend request', body: 'Sara wants to be friends.', opened: false));
    await tester.pumpAndSettle();
    expect(find.text('New friend request — Sara wants to be friends.'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('friends page'), findsOneWidget);
  });

  test('push registration saves token, local reminder hours and preferences', () async {
    final pushRepo = FakePushRepository();
    final settings = MemorySettingsRepository();
    final c = ProviderContainer(overrides: [
      ...testOverrides(cloud: FakeCloudRepository(), settings: settings),
      pushServiceProvider.overrideWithValue(FakePushService()),
      pushRepositoryProvider.overrideWithValue(pushRepo),
    ]);
    addTearDown(c.dispose);
    c.listen(pushRegistrarProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(pushRepo.saves.single, containsPair('token', 'fid-123'));
    expect(pushRepo.saves.single, containsPair('streak', true));

    await c.read(settingsProvider.notifier).update((s) => s.copyWith(notifyStreak: false));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(pushRepo.saves.last, containsPair('streak', false));
  });
}
