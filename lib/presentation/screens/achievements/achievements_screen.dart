import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/achievement.dart';
import '../../providers/cloud_providers.dart';
import '../../widgets/achievement_icons.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(achievementCatalogProvider);
    final unlocked = ref.watch(unlockedAchievementsProvider);
    final stats = ref.watch(achievementStatsProvider);
    final theme = Theme.of(context);
    final sorted = [...catalogue]..sort((a, b) {
        final ua = unlocked.containsKey(a.id), ub = unlocked.containsKey(b.id);
        if (ua != ub) return ua ? -1 : 1;
        return b.progress(stats[b.metric]).compareTo(a.progress(stats[a.metric]));
      });
    final count = catalogue.where((a) => unlocked.containsKey(a.id)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppPalette.amber, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$count of ${catalogue.length} badges', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: catalogue.isEmpty ? 0 : count / catalogue.length,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in sorted)
                  SizedBox(
                    width: w,
                    child: AchievementTile(achievement: a, unlocked: unlocked.containsKey(a.id), unlockedAt: unlocked[a.id], value: stats[a.metric]),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class AchievementTile extends StatelessWidget {
  const AchievementTile({super.key, required this.achievement, required this.unlocked, this.unlockedAt, this.value});
  final Achievement achievement;
  final bool unlocked;
  final DateTime? unlockedAt;
  final num? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = achievement;
    final color = unlocked ? AppPalette.amber : theme.disabledColor;
    final progress = a.progress(value);
    return Semantics(
      label: '${a.title}. ${a.description}. ${unlocked ? 'Unlocked' : 'Locked, ${(progress * 100).round()} percent'}',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.18),
                    child: Icon(achievementIcon(a.icon), color: unlocked ? AppPalette.flame : color),
                  ),
                  const Spacer(),
                  if (unlocked) const Icon(Icons.check_circle_rounded, color: AppPalette.mint, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(a.title, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(a.description, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              if (unlocked)
                Text(unlockedAt == null ? 'Unlocked' : 'Unlocked ${DateFormat.yMMMd().format(unlockedAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(color: AppPalette.mint))
              else
                LinearProgressIndicator(value: progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
            ],
          ),
        ),
      ),
    );
  }
}
