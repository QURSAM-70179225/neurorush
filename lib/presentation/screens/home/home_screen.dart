import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_result.dart';
import '../../../domain/entities/game_type.dart';
import '../../../domain/logic/brain_score.dart';
import '../../providers/app_providers.dart';
import '../../widgets/brain_widgets.dart';
import '../../widgets/coach_card.dart';
import '../../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final stats = ref.watch(playerStatsProvider);
    final history = ref.watch(gameHistoryProvider);
    final streak = ref.watch(streakProvider);
    final progress = ref.watch(progressProvider);
    final level = ref.watch(levelProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_greeting(DateTime.now())},', style: theme.textTheme.titleMedium),
                      Text(user?.name ?? 'Player', style: theme.textTheme.headlineMedium, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                StreakFlame(status: streak, freezes: progress.freezes, onTap: () => _showStreakInfo(context, ref)),
              ],
            ),
            if (streak.atRisk)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Play a round today to keep your ${streak.current}-day streak!',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppPalette.flame, fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: LevelBar(info: level))),
            const SizedBox(height: 12),
            _BrainScoreCard(testDone: progress.brainTestDone),
            const SizedBox(height: 12),
            const _DailyWorkoutCard(),
            const SizedBox(height: 12),
            const CoachCard(),
            SectionHeader('Quick play',
                trailing: TextButton(onPressed: () => context.go('/games'), child: const Text('All games'))),
            for (final (i, t) in _suggested(history).indexed) ...[
              GameCard(
                type: t,
                compact: true,
                bestScore: stats.bestScoreFor(t),
                onTap: () => context.push('/play/${t.id}'),
              ).animate(delay: (80 * i).ms).fadeIn().slideX(begin: 0.05),
              const SizedBox(height: 10),
            ],
            SectionHeader('Recent rounds',
                trailing: history.isEmpty
                    ? null
                    : TextButton(onPressed: () => context.go('/leaderboard'), child: const Text('Records'))),
            if (history.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Your results will appear here after your first round.', style: theme.textTheme.bodyMedium),
                ),
              )
            else
              for (final r in history.take(5)) _RecentTile(result: r),
          ],
        ),
      ),
    );
  }

  void _showStreakInfo(BuildContext context, WidgetRef ref) {
    final streak = ref.read(streakProvider);
    final freezes = ref.read(progressProvider).freezes;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department_rounded, color: AppPalette.flame, size: 56),
            Text('${streak.current}-day streak', style: Theme.of(c).textTheme.headlineSmall),
            Text('Best: ${streak.best} days'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.ac_unit_rounded, color: AppPalette.cyan),
              title: Text('$freezes streak freeze${freezes == 1 ? '' : 's'}'),
              subtitle: const Text(
                  'A freeze is used automatically if you miss a day. Earn one every 7-day streak (max 2).'),
            ),
          ],
        ),
      ),
    );
  }

  /// The three least-played games, so practice stays balanced.
  static List<GameType> _suggested(List<GameResult> history) {
    final counts = {for (final t in GameType.values) t: 0};
    for (final r in history) {
      counts[r.gameType] = counts[r.gameType]! + 1;
    }
    final sorted = GameType.values.toList()..sort((a, b) => counts[a]!.compareTo(counts[b]!));
    return sorted.take(3).toList();
  }
}

class _BrainScoreCard extends ConsumerWidget {
  const _BrainScoreCard({required this.testDone});
  final bool testDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(brainScoreProvider);
    final theme = Theme.of(context);
    final showTest = !testDone && !score.hasData;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppPalette.brandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: AppPalette.violet.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: showTest
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Brain Score', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Find your starting score in 2 minutes',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppPalette.violet),
                  onPressed: () => context.push('/brain-test'),
                  icon: const Icon(Icons.psychology_alt_rounded),
                  label: const Text('Take the Brain Test'),
                ),
              ],
            )
          : Semantics(
              button: true,
              label: 'Brain Score ${score.total} of ${BrainScore.maxTotal}. Open details',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => context.push('/brain'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Brain Score', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                          Text('${score.total}',
                              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, height: 1.1)),
                          Text('of ${BrainScore.maxTotal}', style: const TextStyle(color: Colors.white70)),
                          if (score.weakest case final w?) ...[
                            const SizedBox(height: 8),
                            Text('Focus area: ${w.label}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        for (final s in score.skills.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 64,
                                  child: Text(s.key.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: s.value / BrainScore.maxPerSkill,
                                      minHeight: 6,
                                      color: Colors.white,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white),
                  ],
                ),
              ),
            ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }
}

class _DailyWorkoutCard extends ConsumerWidget {
  const _DailyWorkoutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(dailyWorkoutProvider);
    final theme = Theme.of(context);
    final next = w.nextGame;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center_rounded, color: AppPalette.pink),
                const SizedBox(width: 8),
                Expanded(child: Text('Daily Brain Workout', style: theme.textTheme.titleMedium)),
                Text('${w.completed.length}/${w.games.length}', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              w.isComplete ? 'Workout complete — great job! New one tomorrow.' : 'Three games picked for your weakest skills.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final g in w.games)
              Semantics(
                label: '${g.title}, trains ${g.skill.label}, ${w.completed.contains(g) ? 'done' : 'not done'}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        w.completed.contains(g) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: w.completed.contains(g) ? AppPalette.mint : theme.disabledColor,
                      ),
                      const SizedBox(width: 10),
                      Icon(AppPalette.gameIcon(g), size: 20),
                      const SizedBox(width: 6),
                      Expanded(child: Text(g.title)),
                      Text(g.skill.label, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            if (next != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push('/play/${next.id}'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(w.completed.isEmpty ? 'Start workout: ${next.title}' : 'Next: ${next.title}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.result});
  final GameResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          onTap: () => context.push('/results', extra: result),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient: AppPalette.gameGradient(result.gameType), borderRadius: BorderRadius.circular(14)),
            child: Icon(AppPalette.gameIcon(result.gameType), color: Colors.white),
          ),
          title: Text(result.gameType.title, style: theme.textTheme.titleSmall),
          subtitle: Text('${DateFormat.MMMd().add_jm().format(result.playedAt)} · ${result.accuracyPercent}% accuracy'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${result.score}', style: theme.textTheme.titleMedium),
              StarRow(stars: result.stars, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
