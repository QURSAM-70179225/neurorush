import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_result.dart';
import '../../widgets/common.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.result});
  final GameResult result;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ConfettiController _confetti =
      ConfettiController(duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    final r = widget.result;
    final celebrate = r.stars == 3 || r.isPersonalBest;
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (celebrate && !reduceMotion) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) _confetti.play();
      });
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  String get _headline {
    final r = widget.result;
    if (r.isPersonalBest) return 'New personal best!';
    return switch (r.stars) {
      3 => 'Brilliant!',
      2 => 'Great job!',
      1 => 'Nice work!',
      _ => 'Keep practising!',
    };
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final theme = Theme.of(context);
    final gradient = AppPalette.gameGradient(r.gameType);
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Home',
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(28)),
                  child: Column(
                    children: [
                      Text(r.gameType.title,
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Semantics(
                        liveRegion: true,
                        child: Text(_headline,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        label: '${r.stars} of 3 stars',
                        excludeSemantics: true,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (i) {
                            final on = i < r.stars;
                            return Padding(
                              padding: EdgeInsets.only(bottom: i == 1 ? 16 : 0),
                              child: Icon(
                                on ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: i == 1 ? 72 : 56,
                                color: on ? AppPalette.amber : Colors.white38,
                              )
                                  .animate(delay: (300 + i * 250).ms)
                                  .scale(begin: const Offset(0, 0), duration: 400.ms, curve: Curves.elasticOut),
                            );
                          }),
                        ),
                      ),
                      Semantics(
                        label: 'Score ${r.score}',
                        excludeSemantics: true,
                        child: TweenAnimationBuilder<int>(
                          tween: IntTween(begin: 0, end: r.score),
                          duration: const Duration(milliseconds: 1100),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => Text(
                            '$v',
                            style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                        child: Text('+${r.xp} XP',
                            style: const TextStyle(color: AppPalette.violet, fontWeight: FontWeight.w900, fontSize: 16)),
                      ).animate(delay: 1100.ms).fadeIn().scale(curve: Curves.easeOutBack),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StatGrid(
                  children: [
                    StatTile(icon: Icons.track_changes_rounded, label: 'Accuracy', value: '${r.accuracyPercent}%'),
                    StatTile(
                        icon: Icons.check_circle_rounded,
                        label: 'Correct / total',
                        value: '${r.correct}/${r.attempts}',
                        color: AppPalette.mint),
                    StatTile(
                        icon: Icons.speed_rounded, label: 'Avg reaction', value: formatMs(r.avgReactionMs), color: AppPalette.cyan),
                    StatTile(
                        icon: Icons.flash_on_rounded, label: 'Fastest', value: formatMs(r.bestReactionMs), color: AppPalette.amber),
                    StatTile(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Best streak',
                        value: '${r.maxCombo}',
                        color: AppPalette.flame),
                    StatTile(icon: Icons.trending_up_rounded, label: 'Top level', value: '${r.maxLevel}', color: AppPalette.pink),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.pushReplacement('/play/${r.gameType.id}'),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Play again'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => context.pushReplacement('/play/${r.gameType.next.id}'),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text('Next game: ${r.gameType.next.title}'),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: () => context.go('/home'), child: const Text('Back to home')),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 30,
              maxBlastForce: 30,
              minBlastForce: 10,
              gravity: 0.25,
              colors: const [AppPalette.violet, AppPalette.pink, AppPalette.cyan, AppPalette.amber, AppPalette.mint],
            ),
          ),
        ],
      ),
    );
  }
}
