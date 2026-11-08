import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_type.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common.dart';

/// Personal records from this device. Global / country / friends boards are
/// added once cloud sync is enabled.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(playerStatsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('Your personal bests on this device.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(icon: Icons.sports_esports_rounded, label: 'Rounds played', value: '${stats.gamesPlayed}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.flash_on_rounded,
                  label: 'Fastest reaction',
                  value: formatMs(stats.bestReactionMs),
                  color: AppPalette.amber,
                ),
              ),
            ],
          ),
          const SectionHeader('Best scores'),
          for (final (i, t) in GameType.values.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  leading: CircleAvatar(
                    backgroundColor: AppPalette.violet.withValues(alpha: 0.15),
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  title: Text(t.title, style: theme.textTheme.titleSmall),
                  subtitle: Text(switch (stats.bestResults[t]) {
                    final r? => 'Set ${DateFormat.yMMMd().format(r.playedAt)} · ${r.accuracyPercent}% accuracy',
                    null => 'Not played yet',
                  }),
                  trailing: stats.bestResults[t] == null
                      ? FilledButton.tonal(onPressed: () => context.push('/play/${t.id}'), child: const Text('Play'))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${stats.bestScoreFor(t)}', style: theme.textTheme.titleMedium),
                            StarRow(stars: stats.bestResults[t]!.stars, size: 14),
                          ],
                        ),
                  onTap: stats.bestResults[t] == null
                      ? null
                      : () => context.push('/results', extra: stats.bestResults[t]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
