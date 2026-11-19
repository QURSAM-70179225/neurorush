import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/game_result.dart';
import '../../domain/entities/game_type.dart';
import '../../presentation/game/results_args.dart';
import '../../presentation/games/game_play_screen.dart';
import '../../presentation/providers/app_providers.dart';
import '../../presentation/providers/telemetry_providers.dart';
import '../../presentation/screens/achievements/achievements_screen.dart';
import '../../presentation/screens/auth/auth_screen.dart';
import '../../presentation/screens/battle/battle_screen.dart';
import '../../presentation/screens/battle/live_battle_screen.dart';
import '../../presentation/screens/battle/matchmaking_screen.dart';
import '../../presentation/screens/brain/brain_screen.dart';
import '../../presentation/screens/brain_test/brain_test_screen.dart';
import '../../presentation/screens/endless/endless_screen.dart';
import '../../presentation/screens/friends/friends_screen.dart';
import '../../presentation/screens/games/games_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/leaderboard/leaderboard_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/results/results_screen.dart';
import '../../presentation/screens/privacy/privacy_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/shop/shop_screen.dart';
import '../../presentation/screens/shell/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(currentUserProvider, (prev, next) {
    refresh.value++;
    if (prev?.uid != next?.uid) ref.read(analyticsProvider).setUser(next?.uid);
  });
  ref.listen(settingsProvider.select((s) => s.onboardingDone), (_, _) => refresh.value++);

  final observer = ref.read(analyticsProvider).observer;
  final router = GoRouter(
    navigatorKey: _rootKey,
    observers: [?observer],
    initialLocation: '/home',
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onboarded = ref.read(settingsProvider).onboardingDone;
      final user = ref.read(currentUserProvider);
      if (loc == '/privacy') return null; // readable before signing in
      if (!onboarded) return loc == '/onboarding' ? null : '/onboarding';
      if (user == null) return loc == '/auth' ? null : '/auth';
      // Offer the Brain Test once, right after the first sign-in.
      final offerTest = !ref.read(settingsProvider).brainTestOffered && !ref.read(progressProvider).brainTestDone;
      if (loc == '/onboarding' || loc == '/auth') return offerTest ? '/brain-test' : '/home';
      if (loc == '/upgrade' && !user.isGuest) return '/profile';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/upgrade', builder: (_, _) => const AuthScreen(upgrade: true)),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/shop', builder: (_, _) => const ShopScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/brain', builder: (_, _) => const BrainScreen()),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
      GoRoute(path: '/endless', builder: (_, _) => const EndlessScreen()),
      GoRoute(path: '/battle/search', builder: (_, _) => const MatchmakingScreen()),
      GoRoute(path: '/battle/join/:code', builder: (_, s) => JoinBattleScreen(code: s.pathParameters['code']!)),
      GoRoute(path: '/battle/:id', builder: (_, s) => LiveBattleScreen(battleId: s.pathParameters['id']!)),
      GoRoute(path: '/achievements', builder: (_, _) => const AchievementsScreen()),
      GoRoute(path: '/brain-test', builder: (_, _) => const BrainTestScreen()),
      GoRoute(
        path: '/play/:gameId',
        redirect: (_, s) => GameType.fromId(s.pathParameters['gameId']!) == null ? '/games' : null,
        pageBuilder: (_, s) => MaterialPage(
          key: s.pageKey,
          fullscreenDialog: true,
          child: GamePlayScreen(type: GameType.fromId(s.pathParameters['gameId']!)!),
        ),
      ),
      GoRoute(
        path: '/results',
        redirect: (_, s) => s.extra is GameResult || s.extra is ResultsArgs ? null : '/home',
        builder: (_, s) => ResultsScreen(
          args: switch (s.extra) {
            final ResultsArgs a => a,
            final GameResult r => ResultsArgs(result: r),
            _ => throw StateError('unreachable: guarded by redirect'),
          },
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/games', builder: (_, _) => const GamesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/battle', builder: (_, _) => const BattleScreen())]),
          StatefulShellBranch(
              routes: [GoRoute(path: '/leaderboard', builder: (_, _) => const LeaderboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())]),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
