import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/entities/skill.dart';
import '../../domain/logic/brain_score.dart';
import '../../domain/logic/streak_logic.dart';
import '../../domain/logic/xp_levels.dart';

/// Radar chart of the five skills on a fixed 0–200 scale.
class SkillRadarChart extends StatelessWidget {
  const SkillRadarChart({super.key, required this.score, this.size = 260});
  final BrainScore score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grid = theme.colorScheme.onSurface.withValues(alpha: 0.15);
    final skills = Skill.values;
    return Semantics(
      label: 'Skill radar. ${skills.map((s) => '${s.label} ${score.of(s)} of ${BrainScore.maxPerSkill}').join(', ')}',
      excludeSemantics: true,
      child: Container(
        height: size,
        // Room for the skill labels drawn outside the polygon.
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: RadarChart(
          RadarChartData(
            radarShape: RadarShape.polygon,
            tickCount: 4,
            ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 1),
            tickBorderData: BorderSide(color: grid),
            gridBorderData: BorderSide(color: grid, width: 1.5),
            radarBorderData: BorderSide(color: grid),
            titlePositionPercentageOffset: 0.18,
            titleTextStyle: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
            getTitle: (i, _) => RadarChartTitle(text: '${skills[i].label}\n${score.of(skills[i])}'),
            dataSets: [
              // Invisible sets pin the scale to 0..200.
              RadarDataSet(
                dataEntries: [for (final _ in skills) const RadarEntry(value: BrainScore.maxPerSkill * 1.0)],
                fillColor: Colors.transparent,
                borderColor: Colors.transparent,
                entryRadius: 0,
              ),
              RadarDataSet(
                dataEntries: [for (final _ in skills) const RadarEntry(value: 0)],
                fillColor: Colors.transparent,
                borderColor: Colors.transparent,
                entryRadius: 0,
              ),
              RadarDataSet(
                dataEntries: [for (final s in skills) RadarEntry(value: score.of(s).toDouble())],
                fillColor: AppPalette.violet.withValues(alpha: 0.3),
                borderColor: AppPalette.violet,
                borderWidth: 3,
                entryRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Level badge with title and XP progress bar.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.info, this.onDark = false});
  final LevelInfo info;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = onDark ? Colors.white : theme.colorScheme.onSurface;
    return Semantics(
      label: 'Level ${info.level}, ${info.title}. '
          '${info.isMax ? 'Maximum level' : '${info.xpIntoLevel} of ${info.xpForNextLevel} XP to next level'}',
      excludeSemantics: true,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onDark ? Colors.white : AppPalette.violet,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${info.level}',
              style: TextStyle(
                color: onDark ? AppPalette.violet : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.title, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: info.progress,
                    minHeight: 8,
                    color: onDark ? Colors.white : AppPalette.violet,
                    backgroundColor: (onDark ? Colors.white : AppPalette.violet).withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.isMax ? 'Max level!' : '${info.xpIntoLevel} / ${info.xpForNextLevel} XP',
                  style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flame icon with the current streak; grey when today is not played yet.
class StreakFlame extends StatelessWidget {
  const StreakFlame({super.key, required this.status, required this.freezes, this.onTap});
  final StreakStatus status;
  final int freezes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lit = status.playedToday;
    final color = lit ? AppPalette.flame : Theme.of(context).disabledColor;
    return Semantics(
      button: onTap != null,
      label: '${status.current} day streak'
          '${status.atRisk ? ', play today to keep it' : ''}. $freezes streak freezes',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department_rounded, color: color),
              const SizedBox(width: 4),
              Text('${status.current}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color)),
              if (freezes > 0) ...[
                const SizedBox(width: 10),
                const Icon(Icons.ac_unit_rounded, size: 18, color: AppPalette.cyan),
                Text('$freezes', style: const TextStyle(fontWeight: FontWeight.w800, color: AppPalette.cyan)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Line chart of each skill score over the given daily snapshots.
class SkillTrendChart extends StatelessWidget {
  const SkillTrendChart({super.key, required this.trend});
  final List<(DateTime, BrainScore)> trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = trend.length;
    final labelEvery = n <= 7 ? 1 : 7;
    final first = trend.first.$2, last = trend.last.$2;
    return Semantics(
      label: 'Skill progress over $n days. '
          '${Skill.values.map((s) => '${s.label} from ${first.of(s)} to ${last.of(s)}').join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: 220,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: BrainScore.maxPerSkill.toDouble(),
            minX: 0,
            maxX: (n - 1).toDouble(),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: 50,
              getDrawingHorizontalLine: (_) => FlLine(color: theme.dividerColor.withValues(alpha: 0.3), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 50,
                  reservedSize: 32,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}', style: theme.textTheme.bodySmall),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 24,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= n || (n - 1 - i) % labelEvery != 0) return const SizedBox.shrink();
                    final d = trend[i].$1;
                    return Text('${d.day}/${d.month}', style: theme.textTheme.bodySmall);
                  },
                ),
              ),
            ),
            lineBarsData: [
              for (final s in Skill.values)
                LineChartBarData(
                  spots: [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), trend[i].$2.of(s).toDouble())],
                  color: AppPalette.skillColor(s),
                  barWidth: 3,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  dotData: FlDotData(show: n <= 7),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SkillLegend extends StatelessWidget {
  const SkillLegend({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final s in Skill.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: AppPalette.skillColor(s), shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(s.label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
          ],
        ),
      );
}
