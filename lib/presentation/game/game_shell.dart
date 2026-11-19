import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/feedback/feedback_service.dart';
import '../../core/theme/app_palette.dart';
import '../../domain/entities/game_result.dart';
import '../../domain/entities/game_type.dart';
import '../../domain/logic/rewards.dart';
import '../providers/app_providers.dart';
import '../providers/cloud_providers.dart';
import '../providers/shop_providers.dart';
import '../providers/telemetry_providers.dart';
import 'results_args.dart';
import 'game_session.dart';

enum _Phase { intro, countdown, playing, paused, finished }

/// Hosts any mini-game: intro card, 3-2-1-GO countdown, 60 s round timer,
/// HUD, pause/resume (also on app background), and saving the result.
class GameShell extends ConsumerStatefulWidget {
  const GameShell({
    super.key,
    required this.type,
    required this.builder,
    this.seed,
    this.roundDuration = const Duration(seconds: GameType.roundSeconds),
    this.introExtra,
    this.introTitle,
    this.onFinished,
  });

  final GameType type;
  final Widget Function(BuildContext context, GameSession session) builder;
  final int? seed;
  final Duration roundDuration;

  /// Optional widget shown on the intro card (e.g. a language picker).
  final Widget? introExtra;

  /// Optional heading above the game title on the intro card.
  final String? introTitle;

  /// When set, called with the saved result instead of opening /results.
  final void Function(GameResult result)? onFinished;

  @override
  ConsumerState<GameShell> createState() => _GameShellState();
}

class _GameShellState extends ConsumerState<GameShell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final GameSession _session;
  late final AnimationController _clock;
  late final FeedbackService _fx;
  _Phase _phase = _Phase.intro;
  String? _countdownLabel;
  Timer? _countdownTimer;
  int _lastWholeSecond = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fx = ref.read(feedbackServiceProvider);
    _session = GameSession(type: widget.type, feedback: _fx, seed: widget.seed);
    // preserve: gameplay timers must not be shortened by the system
    // "remove animations" accessibility setting.
    _clock = AnimationController(
        vsync: this, duration: widget.roundDuration, animationBehavior: AnimationBehavior.preserve)
      ..addListener(_onClockTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _clock.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _Phase.playing) _pause();
  }

  int get _secondsLeft =>
      ((1 - _clock.value) * widget.roundDuration.inMilliseconds / 1000).ceil();

  void _onClockTick() {
    final s = _secondsLeft;
    if (s != _lastWholeSecond) {
      _lastWholeSecond = s;
      if (s <= 5 && s > 0) _fx.countdownTick();
      setState(() {});
    }
  }

  void _startCountdown() {
    setState(() => _phase = _Phase.countdown);
    const steps = ['3', '2', '1', 'GO!'];
    var i = 0;
    void step() {
      if (!mounted) return;
      if (i < steps.length) {
        final label = steps[i];
        setState(() => _countdownLabel = label);
        SemanticsService.sendAnnouncement(
            View.of(context), label, Directionality.of(context));
        label == 'GO!' ? _fx.go() : _fx.countdownTick();
        i++;
        _countdownTimer = Timer(Duration(milliseconds: label == 'GO!' ? 500 : 750), step);
      } else {
        setState(() {
          _countdownLabel = null;
          _phase = _Phase.playing;
        });
        _session.running.value = true;
        _clock.forward();
      }
    }

    step();
  }

  void _pause() {
    if (_phase != _Phase.playing) return;
    _clock.stop();
    _session.running.value = false;
    setState(() => _phase = _Phase.paused);
  }

  void _resume() {
    if (_phase != _Phase.paused) return;
    setState(() => _phase = _Phase.playing);
    _session.running.value = true;
    _clock.forward();
  }

  Future<void> _finish() async {
    if (_phase == _Phase.finished) return;
    _session.running.value = false;
    setState(() => _phase = _Phase.finished);
    _fx.finish();
    final t = _session.tracker;
    final stars = Rewards.starsFor(
      type: widget.type,
      score: t.score,
      accuracy: t.accuracy,
      correct: t.correct,
    );
    final result = GameResult(
      id: const Uuid().v4(),
      gameType: widget.type,
      score: t.score,
      correct: t.correct,
      wrong: t.wrong,
      maxCombo: t.maxStreak,
      maxLevel: _session.difficulty.maxReached,
      avgReactionMs: t.averageReactionMs,
      bestReactionMs: t.bestReactionMs,
      stars: stars,
      xp: Rewards.xpFor(score: t.score, stars: stars, accuracy: t.accuracy),
      playedAt: DateTime.now(),
      durationSeconds: widget.roundDuration.inSeconds,
    );
    final badgesBefore = ref.read(unlockedAchievementsProvider).keys.toSet();
    final workoutDoneBefore = ref.read(dailyWorkoutProvider).isComplete;
    final profileBefore = ref.read(cloudProfileProvider).value;
    final coinsBefore = ref.read(cloudRepositoryProvider).isAvailable && profileBefore != null ? profileBefore.entitlements.coins : null;
    final levelBefore = ref.read(levelProvider).level;
    final streakBefore = ref.read(streakProvider).current;
    final stored = await ref.read(gameHistoryProvider.notifier).add(result);
    ref.read(interstitialPolicyProvider).gameFinished();
    final analytics = ref.read(analyticsProvider);
    unawaited(analytics.gameEnd(
      gameId: stored.gameType.id,
      score: stored.score,
      stars: stored.stars,
      accuracyPercent: stored.accuracyPercent,
      seconds: stored.durationSeconds,
    ));
    if (!workoutDoneBefore && ref.read(dailyWorkoutProvider).isComplete) unawaited(analytics.workoutComplete());
    final levelAfter = ref.read(levelProvider).level;
    if (levelAfter > levelBefore) unawaited(analytics.levelUp(levelAfter));
    final streakAfter = ref.read(streakProvider).current;
    final newBadges = ref
        .read(achievementCatalogProvider)
        .where((a) => ref.read(unlockedAchievementsProvider).containsKey(a.id) && !badgesBefore.contains(a.id))
        .toList();
    // Let the "Time's up" banner register before leaving.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final onFinished = widget.onFinished;
    if (onFinished != null) {
      onFinished(stored);
    } else {
      context.pushReplacement(
        '/results',
        extra: ResultsArgs(
          result: stored,
          justPlayed: true,
          leveledUpTo: levelAfter > levelBefore ? levelAfter : null,
          streakExtendedTo: streakAfter > streakBefore ? streakAfter : null,
          newBadges: newBadges,
          coinsBefore: coinsBefore,
        ),
      );
    }
  }

  Future<void> _confirmQuit() async {
    final wasPlaying = _phase == _Phase.playing;
    if (wasPlaying) _pause();
    if (_phase == _Phase.intro || _phase == _Phase.finished) {
      if (mounted) context.pop();
      return;
    }
    final quit = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Quit this round?'),
        content: const Text('Your progress in this round will not be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep playing')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quit')),
        ],
      ),
    );
    if (!mounted) return;
    if (quit == true) {
      _countdownTimer?.cancel();
      _session.running.value = false;
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradient = AppPalette.gameGradient(widget.type);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmQuit();
      },
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _Hud(
                    session: _session,
                    gradient: gradient,
                    secondsLeft: _phase == _Phase.intro || _phase == _Phase.countdown
                        ? widget.roundDuration.inSeconds
                        : _secondsLeft,
                    progress: 1 - _clock.value,
                    onClose: _confirmQuit,
                    onPause: _phase == _Phase.playing ? _pause : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: IgnorePointer(
                        ignoring: _phase != _Phase.playing,
                        child: widget.builder(context, _session),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_phase == _Phase.intro)
              _IntroOverlay(
                type: widget.type,
                gradient: gradient,
                onStart: _startCountdown,
                extra: widget.introExtra,
                heading: widget.introTitle,
                seconds: widget.roundDuration.inSeconds,
              ),
            if (_phase == _Phase.countdown && _countdownLabel != null)
              _CountdownOverlay(label: _countdownLabel!),
            if (_phase == _Phase.paused)
              _PauseOverlay(onResume: _resume, onQuit: _confirmQuit),
            if (_phase == _Phase.finished) const _TimesUpOverlay(),
          ],
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.session,
    required this.gradient,
    required this.secondsLeft,
    required this.progress,
    required this.onClose,
    required this.onPause,
  });

  final GameSession session;
  final Gradient gradient;
  final int secondsLeft;
  final double progress;
  final VoidCallback onClose;
  final VoidCallback? onPause;

  @override
  Widget build(BuildContext context) {
    final low = secondsLeft <= 10;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(24)),
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final t = session.tracker;
          return Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Quit',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Pause',
                    onPressed: onPause,
                    icon: const Icon(Icons.pause_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  Semantics(
                    label: '$secondsLeft seconds left',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        Icon(Icons.timer_rounded, color: low ? Colors.yellowAccent : Colors.white, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          '$secondsLeft',
                          style: TextStyle(
                            color: low ? Colors.yellowAccent : Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Score ${t.score}',
                        excludeSemantics: true,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Text(
                              '${t.score}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                            if (session.lastFeedback case final f? when f.correct)
                              Positioned(
                                left: 0,
                                top: -18,
                                child: Text(
                                  '+${f.points}',
                                  key: ValueKey(f.id),
                                  style: const TextStyle(
                                    color: Colors.yellowAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                )
                                    .animate()
                                    .fadeIn(duration: 80.ms)
                                    .moveY(begin: 10, end: -6, duration: 500.ms)
                                    .then()
                                    .fadeOut(duration: 250.ms),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _Chip(icon: Icons.trending_up_rounded, label: 'Lv ${session.level}'),
                    const SizedBox(width: 8),
                    _Chip(
                      icon: Icons.local_fire_department_rounded,
                      label: 'x${t.multiplier}',
                      highlight: t.multiplier > 1,
                      semanticLabel: 'Combo multiplier ${t.multiplier}, streak ${t.streak}',
                    )
                        .animate(key: ValueKey('combo${t.multiplier}'))
                        .scale(begin: const Offset(1.25, 1.25), duration: 250.ms, curve: Curves.easeOutBack),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white24,
                  color: low ? Colors.yellowAccent : Colors.white,
                  semanticsLabel: 'Round time remaining',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.highlight = false, this.semanticLabel});
  final IconData icon;
  final String label;
  final bool highlight;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: highlight ? Colors.white : Colors.white24,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: highlight ? AppPalette.flame : Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: highlight ? AppPalette.flame : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroOverlay extends StatelessWidget {
  const _IntroOverlay({
    required this.type,
    required this.gradient,
    required this.onStart,
    required this.seconds,
    this.extra,
    this.heading,
  });
  final GameType type;
  final Gradient gradient;
  final VoidCallback onStart;
  final int seconds;
  final Widget? extra;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (heading != null) ...[
                    Text(heading!, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(gradient: gradient, shape: BoxShape.circle),
                    child: Icon(AppPalette.gameIcon(type), color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 16),
                  Text(type.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Trains ${type.skill.label}',
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 12),
                  Text(type.howToPlay, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text('$seconds seconds · gets harder as you improve',
                      textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  if (extra != null) ...[const SizedBox(height: 16), extra!],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start'),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.9, 0.9)),
        ),
      ),
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black45,
        child: Center(
          child: Text(
            label,
            key: ValueKey(label),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 120,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(blurRadius: 24, color: Colors.black38)],
            ),
          ).animate().scale(begin: const Offset(1.8, 1.8), duration: 350.ms, curve: Curves.easeOutBack).fadeIn(duration: 120.ms),
        ),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onQuit});
  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_filled_rounded, color: Colors.white, size: 80),
            const SizedBox(height: 12),
            const Text('Paused',
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Resume'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onQuit,
              child: const Text('Quit round', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimesUpOverlay extends StatelessWidget {
  const _TimesUpOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: const Text(
          "Time's up!",
          style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900),
        ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
      ),
    );
  }
}
