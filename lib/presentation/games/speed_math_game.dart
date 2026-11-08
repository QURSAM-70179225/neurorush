import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/speed_math_logic.dart';
import '../game/game_session.dart';
import '../game/question_timer_bar.dart';
import '../providers/app_providers.dart';

class SpeedMathGame extends ConsumerStatefulWidget {
  const SpeedMathGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<SpeedMathGame> createState() => _SpeedMathGameState();
}

class _SpeedMathGameState extends ConsumerState<SpeedMathGame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _qTimer;
  MathQuestion? _q;
  int _qId = 0;
  int? _picked;
  bool _locked = false;
  final Stopwatch _watch = Stopwatch();

  GameSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _qTimer = AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve)
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed && !_locked) _answer(null);
      });
    _s.running.addListener(_onRunningChanged);
  }

  @override
  void dispose() {
    _s.running.removeListener(_onRunningChanged);
    _qTimer.dispose();
    super.dispose();
  }

  void _onRunningChanged() {
    if (_s.isRunning) {
      if (_q == null) {
        _next();
      } else if (!_locked) {
        _watch.start();
        _qTimer.forward();
      }
    } else {
      _watch.stop();
      _qTimer.stop();
    }
  }

  void _next() {
    final q = SpeedMathLogic.generate(_s.random, _s.level);
    setState(() {
      _q = q;
      _qId++;
      _picked = null;
      _locked = false;
    });
    _qTimer
      ..duration = Duration(milliseconds: q.timeLimitMs)
      ..forward(from: 0);
    _watch
      ..reset()
      ..start();
  }

  Future<void> _answer(int? value) async {
    final q = _q;
    if (q == null || _locked || !_s.isRunning) return;
    _locked = true;
    _qTimer.stop();
    final ms = _watch.elapsedMilliseconds;
    final correct = value == q.answer;
    if (correct) {
      _s.registerCorrect(
        basePoints: SpeedMathLogic.basePoints(_s.level),
        reactionMs: ms,
        fast: ms < SpeedMathLogic.fastMs,
      );
    } else {
      _s.registerWrong(reactionMs: value == null ? null : ms);
    }
    setState(() => _picked = value ?? -1);
    await Future<void>.delayed(Duration(milliseconds: correct ? 200 : 700));
    if (mounted && _s.isRunning) _next();
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final theme = Theme.of(context);
    final q = _q;

    return Column(
      children: [
        QuestionTimerBar(controller: _qTimer, color: AppPalette.cyan),
        Expanded(
          child: Center(
            child: q == null
                ? const SizedBox.shrink()
                : Semantics(
                    liveRegion: true,
                    label: '${q.spokenExpression} equals what?',
                    excludeSemantics: true,
                    child: FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${q.expression} = ?',
                          key: ValueKey(_qId),
                          style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w900),
                        )
                            .animate()
                            .fadeIn(duration: 120.ms)
                            .slideY(begin: 0.3, duration: 200.ms, curve: Curves.easeOut),
                      ),
                    ),
                  ),
          ),
        ),
        if (q != null)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
            children: [
              for (final o in q.options)
                _AnswerButton(
                  value: o,
                  highlight: _picked == null
                      ? null
                      : o == q.answer
                          ? AppPalette.correct(colorBlind)
                          : o == _picked
                              ? AppPalette.wrong(colorBlind)
                              : null,
                  onTap: () => _answer(o),
                ),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.value, required this.highlight, required this.onTap});
  final int value;
  final Color? highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$value',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => onTap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: highlight ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            '$value',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: highlight != null ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }
}
