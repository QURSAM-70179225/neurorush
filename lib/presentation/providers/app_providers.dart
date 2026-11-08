import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feedback/feedback_service.dart';
import '../../data/local/hive_store.dart';
import '../../data/repositories/hive_game_history_repository.dart';
import '../../data/repositories/hive_settings_repository.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/game_result.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/logic/player_stats.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/game_history_repository.dart';
import '../../domain/repositories/settings_repository.dart';

/// Overridden in main() once Hive is open.
final hiveStoreProvider = Provider<HiveStore>(
  (ref) => throw UnimplementedError('hiveStoreProvider must be overridden'),
);

/// Overridden in main() with the Firebase or local implementation.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('authRepositoryProvider must be overridden'),
);

/// Overridden in main() after sounds are preloaded.
final feedbackServiceProvider = Provider<FeedbackService>((ref) => FeedbackService());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => HiveSettingsRepository(ref.watch(hiveStoreProvider).settings),
);

final gameHistoryRepositoryProvider = Provider<GameHistoryRepository>(
  (ref) => HiveGameHistoryRepository(ref.watch(hiveStoreProvider).sessions),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final s = ref.watch(settingsRepositoryProvider).load();
    _applyToFeedback(s);
    return s;
  }

  void _applyToFeedback(AppSettings s) {
    ref.read(feedbackServiceProvider)
      ..soundOn = s.soundOn
      ..hapticsOn = s.hapticsOn;
  }

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    state = next;
    _applyToFeedback(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final authStateProvider = StreamProvider<UserProfile?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// The current user, falling back to the repository's synchronous value while
/// the stream has not emitted yet.
final currentUserProvider = Provider<UserProfile?>((ref) {
  final async = ref.watch(authStateProvider);
  return async.hasValue ? async.value : ref.watch(authRepositoryProvider).currentUser;
});

class GameHistoryNotifier extends Notifier<List<GameResult>> {
  @override
  List<GameResult> build() => ref.watch(gameHistoryRepositoryProvider).all();

  /// Saves [result], marking it as a personal best when it beats every
  /// previous score in the same game. Returns the stored result.
  Future<GameResult> add(GameResult result) async {
    final previousBest = state
        .where((r) => r.gameType == result.gameType)
        .fold<int>(0, (best, r) => r.score > best ? r.score : best);
    final stored = result.copyWith(isPersonalBest: result.score > 0 && result.score > previousBest);
    await ref.read(gameHistoryRepositoryProvider).save(stored);
    state = [stored, ...state];
    return stored;
  }

  Future<void> clear() async {
    await ref.read(gameHistoryRepositoryProvider).clear();
    state = const [];
  }
}

final gameHistoryProvider =
    NotifierProvider<GameHistoryNotifier, List<GameResult>>(GameHistoryNotifier.new);

final playerStatsProvider = Provider<PlayerStats>(
  (ref) => PlayerStats.fromHistory(ref.watch(gameHistoryProvider)),
);
