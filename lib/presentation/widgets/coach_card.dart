import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../providers/ai_providers.dart';

/// Home card with the AI Brain Coach's tip and fun fact after the workout.
class CoachCard extends ConsumerWidget {
  const CoachCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(coachProvider);
    final theme = Theme.of(context);
    final s = state.value;
    if (s is CoachLocked) {
      return _Shell(
        child: Row(
          children: [
            const Icon(Icons.lock_clock_rounded),
            const SizedBox(width: 12),
            Expanded(child: Text('Finish today’s workout to unlock a personal tip from Neo, your Brain Coach.', style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    }
    return _Shell(
      child: switch (s) {
        CoachReady(:final tip) => Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip.tip, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppPalette.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_rounded, color: AppPalette.amber),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Brain fact: ${tip.funFact}', style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
                if (!tip.isAi) ...[
                  const SizedBox(height: 6),
                  Text('AI coach is busy — here’s a tip from our training guide.', style: theme.textTheme.bodySmall),
                ],
              ],
            ).animate().fadeIn(duration: 300.ms),
          ),
        CoachSyncing() => const _Loading(text: 'Uploading your workout…'),
        CoachUnavailable(:final message) => Row(
            children: [
              Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
              TextButton(onPressed: () => ref.invalidate(coachProvider), child: const Text('Retry')),
            ],
          ),
        _ => const _Loading(text: 'Neo is reviewing your workout…'),
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(gradient: AppPalette.brandGradient, shape: BoxShape.circle),
                    child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text('Brain Coach', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _Loading extends StatelessWidget {
  const _Loading({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      );
}
