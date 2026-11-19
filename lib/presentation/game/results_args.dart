import '../../domain/entities/achievement.dart';
import '../../domain/entities/game_result.dart';

/// Arguments for the results screen.
class ResultsArgs {
  const ResultsArgs({
    required this.result,
    this.justPlayed = false,
    this.leveledUpTo,
    this.streakExtendedTo,
    this.newBadges = const [],
    this.coinsBefore,
  });

  final GameResult result;

  /// False when re-opening an old result from history.
  final bool justPlayed;

  /// New player level if this round caused a level-up.
  final int? leveledUpTo;

  /// New streak length if this round extended the daily streak.
  final int? streakExtendedTo;

  /// Achievements unlocked by this round.
  final List<Achievement> newBadges;

  /// Server coin balance before this round (null offline). Coins earned are
  /// shown once the round has synced and the balance has gone up.
  final int? coinsBefore;
}
