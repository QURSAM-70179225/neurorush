import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_result.dart';
import '../../../domain/entities/game_type.dart';
import '../../providers/app_providers.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('${_greeting(DateTime.now())},', style: theme.textTheme.titleMedium),
            Text(user?.name ?? 'Player', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppPalette.brandGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: AppPalette.violet.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Today', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    stats.gamesToday == 0
                        ? 'Ready for a quick brain boost?'
                        : '${stats.gamesToday} round${stats.gamesToday == 1 ? '' : 's'} played today',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _HeroStat(icon: Icons.bolt_rounded, value: '${stats.totalXp}', label: 'Total XP'),
                      _HeroStat(icon: Icons.star_rounded, value: '${stats.totalStars}', label: 'Stars'),
                      _HeroStat(
                          icon: Icons.track_changes_rounded,
                          value: stats.gamesPlayed == 0 ? '—' : '${(stats.averageAccuracy * 100).round()}%',
                          label: 'Accuracy'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppPalette.violet),
                    onPressed: () => context.push('/play/${_suggested(history).id}'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('Play ${_suggested(history).title}'),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
            const SectionHeader('Quick play'),
            for (final (i, t) in GameType.values.indexed) ...[
              GameCard(
                type: t,
                bestScore: stats.bestScoreFor(t),
                onTap: () => context.push('/play/${t.id}'),
              ).animate(delay: (80 * i).ms).fadeIn().slideX(begin: 0.05),
              const SizedBox(height: 12),
            ],
            SectionHeader('Recent rounds',
                trailing: history.isEmpty
                    ? null
                    : TextButton(onPressed: () => context.go('/leaderboard'), child: const Text('Records'))),
            if (history.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Your results will appear here after your first round.',
                      style: theme.textTheme.bodyMedium),
                ),
              )
            else
              for (final r in history.take(5)) _RecentTile(result: r),
          ],
        ),
      ),
    );
  }

  /// Suggests the least played game so practice stays balanced.
  static GameType _suggested(List<GameResult> history) {
    final counts = {for (final t in GameType.values) t: 0};
    for (final r in history) {
      counts[r.gameType] = counts[r.gameType]! + 1;
    }
    return counts.entries.reduce((a, b) => b.value < a.value ? b : a).key;
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: '$label $value',
          excludeSemantics: true,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
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
            decoration: BoxDecoration(
                gradient: AppPalette.gameGradient(result.gameType), borderRadius: BorderRadius.circular(14)),
            child: Icon(AppPalette.gameIcon(result.gameType), color: Colors.white),
          ),
          title: Text(result.gameType.title, style: theme.textTheme.titleSmall),
          subtitle: Text(
              '${DateFormat.MMMd().add_jm().format(result.playedAt)} · ${result.accuracyPercent}% accuracy'),
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
