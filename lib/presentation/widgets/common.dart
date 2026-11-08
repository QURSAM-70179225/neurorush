import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/entities/game_type.dart';

/// Row of 0–3 stars.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 18});
  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars of 3 stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (i) => Icon(
            i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i < stars ? AppPalette.amber : Theme.of(context).disabledColor,
          ),
        ),
      ),
    );
  }
}

/// Small labelled value used in stats grids.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.label, required this.value, this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: c, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colourful card that launches a game.
class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.type, required this.bestScore, required this.onTap, this.compact = false});
  final GameType type;
  final int bestScore;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Play ${type.title}. ${type.tagline}. Trains ${type.skill.label}. '
          'Best score $bestScore',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: AppPalette.gameGradient(type)),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 18),
              child: Row(
                children: [
                  Container(
                    width: compact ? 46 : 56,
                    height: compact ? 46 : 56,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
                    child: Icon(AppPalette.gameIcon(type), color: Colors.white, size: compact ? 26 : 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type.title,
                            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                        Text(type.tagline,
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _Pill(text: type.skill.label),
                            const SizedBox(width: 6),
                            if (bestScore > 0) _Pill(text: 'Best $bestScore'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

String formatMs(int? ms) => ms == null ? '—' : '$ms ms';

/// Two-column grid whose rows grow with their content (safe for large text).
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.spacing = 10});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [for (final child in children) SizedBox(width: w, child: child)],
          );
        },
      );
}
