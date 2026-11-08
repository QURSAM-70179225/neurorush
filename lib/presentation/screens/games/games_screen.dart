import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_type.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common.dart';

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(playerStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text('Each round lasts ${GameType.roundSeconds} seconds and adapts to your level.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Semantics(
            button: true,
            label: 'Endless Mode. Infinite AI puzzles. Play',
            excludeSemantics: true,
            child: Material(
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: const BoxDecoration(gradient: AppPalette.brandGradient),
                child: InkWell(
                  onTap: () => context.push('/endless'),
                  child: const Padding(
                    padding: EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 40),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Endless Mode', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                              Text('Infinite AI riddles & sequences', style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                        Icon(Icons.auto_awesome_rounded, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final (i, t) in GameType.values.indexed) ...[
            GameCard(type: t, bestScore: stats.bestScoreFor(t), onTap: () => context.push('/play/${t.id}'))
                .animate(delay: (70 * i).ms)
                .fadeIn()
                .slideY(begin: 0.08),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
