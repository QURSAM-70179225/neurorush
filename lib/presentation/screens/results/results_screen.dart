import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/game_result.dart';
import '../../../domain/logic/xp_levels.dart';
import '../../../domain/entities/shop.dart';
import '../../game/results_args.dart';
import '../../providers/app_providers.dart';
import '../../providers/cloud_providers.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/cloud_widgets.dart';
import '../../widgets/confetti_burst.dart';
import '../../widgets/achievement_icons.dart';
import '../../widgets/common.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  ResultsScreen({super.key, required this.args}) : result = args.result;
  final ResultsArgs args;
  final GameResult result;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  late GameResult _result = widget.result;
  bool _boosting = false;

  /// Interstitials only ever appear here, between rounds.
  Future<void> _leave(VoidCallback go) async {
    await maybeShowInterstitial(ref);
    if (mounted) go();
  }

  Future<void> _doubleXp() async {
    setState(() => _boosting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final claim = await watchRewardedAd(ref, RewardType.doubleXp, sessionId: _result.id);
      if (claim == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Watch the whole ad to double your XP.')));
      } else if (claim.applied || claim.reason == 'pending') {
        final boosted = _result.copyWith(xp: _result.xp * 2, xpBoosted: true);
        await ref.read(gameHistoryProvider.notifier).replace(boosted);
        setState(() => _result = boosted);
        messenger.showSnackBar(SnackBar(content: Text('XP doubled: +${boosted.xp} XP!')));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(claim.reason == 'daily_limit' ? 'Daily reward limit reached.' : 'This round can’t be doubled.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(cloudErrorText(e))));
    } finally {
      if (mounted) setState(() => _boosting = false);
    }
  }

  final _confetti = GlobalKey<ConfettiBurstState>();

  @override
  void initState() {
    super.initState();
    final r = widget.result;
    final celebrate = widget.args.justPlayed &&
        (r.stars == 3 || r.isPersonalBest || widget.args.leveledUpTo != null || widget.args.newBadges.isNotEmpty);
    if (celebrate) {
      Future<void>.delayed(const Duration(milliseconds: 900), () => _confetti.currentState?.play());
    }
  }


  String get _headline {
    final r = widget.result;
    if (r.isPersonalBest && widget.args.justPlayed) return 'New personal best!';
    return switch (r.stars) {
      3 => 'Brilliant!',
      2 => 'Great job!',
      1 => 'Nice work!',
      _ => 'Keep practising!',
    };
  }

  @override
  Widget build(BuildContext context) {
    // Keep entitlements loaded so the interstitial check never sees stale data.
    ref.watch(entitlementsProvider);
    final r = _result;
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
                if (widget.args.leveledUpTo case final lvl?)
                  _Banner(
                    icon: Icons.military_tech_rounded,
                    color: const Color(0xFF7C3AED),
                    title: 'Level up! You reached level $lvl',
                    subtitle: XpLevels.titleFor(lvl),
                  ).animate(delay: 1300.ms).fadeIn().slideY(begin: 0.3),
                if (widget.args.streakExtendedTo case final days?)
                  _Banner(
                    icon: Icons.local_fire_department_rounded,
                    color: AppPalette.flame,
                    title: '$days-day streak!',
                    subtitle: days == 1 ? 'Come back tomorrow to keep it going.' : 'Keep the flame alive tomorrow.',
                  ).animate(delay: 1500.ms).fadeIn().slideY(begin: 0.3),
                for (final (i, b) in widget.args.newBadges.indexed)
                  _Banner(
                    icon: achievementIcon(b.icon),
                    color: AppPalette.amber,
                    title: 'Badge unlocked: ${b.title}',
                    subtitle: b.description,
                  ).animate(delay: (1700 + 200 * i).ms).fadeIn().slideY(begin: 0.3),
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
                if (widget.args.justPlayed && !r.xpBoosted && ref.watch(cloudRepositoryProvider).isAvailable) ...[
                  OutlinedButton.icon(
                    onPressed: _boosting ? null : _doubleXp,
                    icon: const Icon(Icons.ondemand_video_rounded),
                    label: Text('Watch an ad: double to +${r.xp * 2} XP'),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  onPressed: () => _leave(() => context.pushReplacement('/play/${r.gameType.id}')),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Play again'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _leave(() => context.pushReplacement('/play/${r.gameType.next.id}')),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text('Next game: ${r.gameType.next.title}'),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: () => _leave(() => context.go('/home')), child: const Text('Back to home')),
              ],
            ),
          ),
          Positioned.fill(child: ConfettiBurst(key: _confetti)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.title, required this.subtitle});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
