import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_type.dart';
import '../../../domain/entities/skill.dart';
import '../../../domain/logic/brain_score.dart';
import '../../providers/app_providers.dart';
import '../../widgets/brain_widgets.dart';
import '../../widgets/common.dart';

/// Brain Score, skill radar, per-skill breakdown and progress charts.
class BrainScreen extends ConsumerStatefulWidget {
  const BrainScreen({super.key});

  @override
  ConsumerState<BrainScreen> createState() => _BrainScreenState();
}

class _BrainScreenState extends ConsumerState<BrainScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final score = ref.watch(brainScoreProvider);
    final history = ref.watch(gameHistoryProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final trend = BrainScore.dailyTrend(history, days: _days, now: now);
    final weekAgo = trend.length >= 7 ? trend[trend.length - 7].$2.total : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Brain Score')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Center(
            child: Semantics(
              label: 'Brain Score ${score.total} of ${BrainScore.maxTotal}',
              excludeSemantics: true,
              child: Column(
                children: [
                  Text('${score.total}', style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w900, color: AppPalette.violet)),
                  Text('out of ${BrainScore.maxTotal}', style: theme.textTheme.bodyMedium),
                  if (score.hasData && score.total != weekAgo)
                    Text(
                      '${score.total > weekAgo ? '▲' : '▼'} ${(score.total - weekAgo).abs()} this week',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: score.total > weekAgo ? AppPalette.mint : AppPalette.flame,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SkillRadarChart(score: score, size: 280),
          const SectionHeader('Skills'),
          for (final s in Skill.values) _SkillRow(skill: s, value: score.of(s), weakest: score.weakest == s),
          SectionHeader(
            'Progress',
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 7, label: Text('7 days')), ButtonSegment(value: 30, label: Text('30 days'))],
              selected: {_days},
              onSelectionChanged: (v) => setState(() => _days = v.first),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
              child: Column(
                children: [
                  if (!score.hasData)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Play a few rounds to see your progress here.'),
                    )
                  else ...[
                    SkillTrendChart(trend: trend),
                    const SizedBox(height: 8),
                    const SkillLegend(),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Each skill (0–200) blends your recent score speed, accuracy and the level you reach, '
            'with newer rounds counting more.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill, required this.value, required this.weakest});
  final Skill skill;
  final int value;
  final bool weakest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppPalette.skillColor(skill);
    final games = GameType.values.where((g) => g.skill == skill).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(skill.label, style: theme.textTheme.titleMedium),
                  if (weakest) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppPalette.amber.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
                      child: const Text('Train this', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ],
                  const Spacer(),
                  Text('$value', style: theme.textTheme.titleLarge?.copyWith(color: color)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value / BrainScore.maxPerSkill,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                  semanticsLabel: '${skill.label} $value of ${BrainScore.maxPerSkill}',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final g in games)
                    ActionChip(
                      avatar: Icon(AppPalette.gameIcon(g), size: 18),
                      label: Text(g.title),
                      onPressed: () => context.push('/play/${g.id}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
