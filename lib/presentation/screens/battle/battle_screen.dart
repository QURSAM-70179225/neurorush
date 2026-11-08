import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_type.dart';

/// Live 1v1 battles need the online services added in a later update. Until
/// then this tab offers a solo warm-up so the tab is still useful.
class BattleScreen extends StatelessWidget {
  const BattleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Brain Battle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppPalette.flame, AppPalette.pink]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 72),
                const SizedBox(height: 8),
                Text('Live 1v1 battles',
                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                const Text(
                  'Challenge random players or friends with the same questions in real time. '
                  'Battles unlock in an upcoming update.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Warm up for battle', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  const Text('Play a surprise round to sharpen your reflexes.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      final t = GameType.values[math.Random().nextInt(GameType.values.length)];
                      context.push('/play/${t.id}');
                    },
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Random round'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
