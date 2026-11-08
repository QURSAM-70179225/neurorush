import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
