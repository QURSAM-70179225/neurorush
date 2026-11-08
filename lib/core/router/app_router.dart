import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/game_result.dart';
import '../../domain/entities/game_type.dart';
import '../../presentation/games/game_play_screen.dart';
import '../../presentation/providers/app_providers.dart';
import '../../presentation/screens/auth/auth_screen.dart';
import '../../presentation/screens/battle/battle_screen.dart';
import '../../presentation/screens/games/games_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/leaderboard/leaderboard_screen.dart';
import '../../presentation/screens/onboarding/onboarding_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/results/results_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/shell/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(currentUserProvider, (_, _) => refresh.value++);
  ref.listen(settingsProvider.select((s) => s.onboardingDone), (_, _) => refresh.value++);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onboarded = ref.read(settingsProvider).onboardingDone;
      final user = ref.read(currentUserProvider);
      if (!onboarded) return loc == '/onboarding' ? null : '/onboarding';
      if (user == null) return loc == '/auth' ? null : '/auth';
      if (loc == '/onboarding' || loc == '/auth') return '/home';
      if (loc == '/upgrade' && !user.isGuest) return '/profile';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/upgrade', builder: (_, _) => const AuthScreen(upgrade: true)),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
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
        redirect: (_, s) => s.extra is GameResult ? null : '/home',
        builder: (_, s) => ResultsScreen(result: s.extra! as GameResult),
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
