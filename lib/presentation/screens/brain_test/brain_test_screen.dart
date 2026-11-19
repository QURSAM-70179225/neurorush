import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_type.dart';
import '../../../domain/logic/brain_score.dart';
import '../../game/game_shell.dart';
import '../../games/game_play_screen.dart';
import '../../providers/app_providers.dart';
import '../../providers/telemetry_providers.dart';
import '../../widgets/brain_widgets.dart';

/// 2-minute Brain Test: one short round per skill. The rounds are saved like
/// normal games, so they seed the Brain Score and radar chart.
class BrainTestScreen extends ConsumerStatefulWidget {
  const BrainTestScreen({super.key, this.roundDuration = const Duration(seconds: 24)});

  final Duration roundDuration;

  /// One game per skill, in this order.
  static const games = [
    GameType.memoryGrid,
    GameType.colorClash,
    GameType.speedMath,
    GameType.numberSequence,
    GameType.wordScramble,
  ];

  @override
  ConsumerState<BrainTestScreen> createState() => _BrainTestScreenState();
}

class _BrainTestScreenState extends ConsumerState<BrainTestScreen> {
  /// -1 = intro, 0..4 = playing, 5 = finished.
  int _step = -1;

  @override
  void initState() {
    super.initState();
    // Offered once automatically; afterwards it is reachable from Home.
    Future.microtask(() => ref.read(settingsProvider.notifier).update((s) => s.copyWith(brainTestOffered: true)));
  }

  Future<void> _roundFinished() async {
    if (_step == BrainTestScreen.games.length - 1) {
      await ref.read(progressProvider.notifier).markBrainTestDone();
      unawaited(ref.read(analyticsProvider).brainTestComplete(ref.read(brainScoreProvider).total));
    }
    if (mounted) setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final games = BrainTestScreen.games;
    if (_step >= 0 && _step < games.length) {
      final type = games[_step];
      return GameShell(
        key: ValueKey('brain-test-$_step'),
        type: type,
        roundDuration: widget.roundDuration,
        introTitle: 'Brain Test · ${_step + 1} of ${games.length}',
        introExtra: introExtraFor(type),
        builder: gameBuilderFor(type),
        onFinished: (_) => _roundFinished(),
      );
    }
    return _step < 0 ? _intro(context) : _summary(context);
  }

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = (widget.roundDuration.inSeconds * BrainTestScreen.games.length / 60).round();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(gradient: AppPalette.brandGradient, shape: BoxShape.circle),
                child: const Icon(Icons.psychology_alt_rounded, color: Colors.white, size: 80),
              ).animate().scale(curve: Curves.easeOutBack, duration: 500.ms),
              const SizedBox(height: 28),
              Text('$minutes-minute Brain Test', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Five quick rounds measure your Memory, Focus, Speed, Logic and Language '
                'to set your starting Brain Score.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in BrainTestScreen.games)
                    Chip(avatar: Icon(AppPalette.gameIcon(g), size: 18), label: Text(g.skill.label)),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => setState(() => _step = 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start Brain Test'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => context.go('/home'), child: const Text('Maybe later')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final score = ref.watch(brainScoreProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Your Brain Score', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            Semantics(
              liveRegion: true,
              label: 'Brain Score ${score.total} of ${BrainScore.maxTotal}',
              excludeSemantics: true,
              child: TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: score.total),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(
                  '$v',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w900, color: AppPalette.violet),
                ),
              ),
            ),
            Text('out of ${BrainScore.maxTotal}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SkillRadarChart(score: score),
            const SizedBox(height: 16),
            if (score.weakest case final w?)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Biggest room to grow: ${w.label}. Your Daily Workout will focus on it.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => context.go('/home'), child: const Text('Continue')),
          ],
        ),
      ),
    );
  }
}
