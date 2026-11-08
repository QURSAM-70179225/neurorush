import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/color_clash_logic.dart';
import '../game/game_session.dart';
import '../game/question_timer_bar.dart';
import '../providers/app_providers.dart';

class ColorClashGame extends ConsumerStatefulWidget {
  const ColorClashGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<ColorClashGame> createState() => _ColorClashGameState();
}

class _ColorClashGameState extends ConsumerState<ColorClashGame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _qTimer;
  ColorClashQuestion? _q;
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
    final q = ColorClashLogic.generate(_s.random, _s.level);
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

  /// [choice] is null when the question timed out.
  Future<void> _answer(int? choice) async {
    final q = _q;
    if (q == null || _locked || !_s.isRunning) return;
    _locked = true;
    _qTimer.stop();
    final ms = _watch.elapsedMilliseconds;
    if (choice != null && q.isCorrect(choice)) {
      _s.registerCorrect(
        basePoints: ColorClashLogic.basePoints(_s.level),
        reactionMs: ms,
        fast: ms < ColorClashLogic.fastMs,
      );
    } else {
      _s.registerWrong(reactionMs: choice == null ? null : ms);
    }
    setState(() => _picked = choice ?? -1);
    await Future<void>.delayed(Duration(milliseconds: choice != null && q.isCorrect(choice) ? 180 : 550));
    if (mounted && _s.isRunning) _next();
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final palette = colorBlind ? ColorClashPalettes.colorBlindSafe : ColorClashPalettes.standard;
    final theme = Theme.of(context);
    final q = _q;
    final neutral = theme.colorScheme.onSurface;

    return Column(
      children: [
        QuestionTimerBar(controller: _qTimer, color: AppPalette.pink),
        const SizedBox(height: 12),
        Text('Tap the INK color', style: theme.textTheme.titleMedium),
        Expanded(
          child: Center(
            child: q == null
                ? const SizedBox.shrink()
                : Semantics(
                    liveRegion: true,
                    label: 'The word ${palette[q.wordIndex].name} written in '
                        '${palette[q.inkIndex].name} ink',
                    excludeSemantics: true,
                    child: FittedBox(
                      child: Text(
                        palette[q.wordIndex].name,
                        key: ValueKey(_qId),
                        style: TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: Color(palette[q.inkIndex].argb),
                          shadows: const [Shadow(blurRadius: 2, color: Colors.black26)],
                        ),
                      ).animate().scale(begin: const Offset(0.6, 0.6), duration: 180.ms, curve: Curves.easeOutBack),
                    ),
                  ),
          ),
        ),
        if (q != null)
          LayoutBuilder(builder: (context, c) {
            final cols = q.options.length <= 2 ? 2 : (q.options.length <= 4 ? 2 : 3);
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < q.options.length; i++)
                  _OptionButton(
                    width: w,
                    label: palette[q.options[i]].name,
                    labelColor: q.optionInkIndexes[i] == null
                        ? neutral
                        : Color(palette[q.optionInkIndexes[i]!].argb),
                    state: _picked == null
                        ? _OptionState.idle
                        : q.options[i] == q.inkIndex
                            ? _OptionState.correct
                            : _picked == q.options[i]
                                ? _OptionState.wrong
                                : _OptionState.idle,
                    colorBlind: colorBlind,
                    onTap: () => _answer(q.options[i]),
                  ),
              ],
            );
          }),
        const SizedBox(height: 8),
      ],
    );
  }
}

enum _OptionState { idle, correct, wrong }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.width,
    required this.label,
    required this.labelColor,
    required this.state,
    required this.colorBlind,
    required this.onTap,
  });

  final double width;
  final String label;
  final Color labelColor;
  final _OptionState state;
  final bool colorBlind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = switch (state) {
      _OptionState.idle => Colors.transparent,
      _OptionState.correct => AppPalette.correct(colorBlind),
      _OptionState.wrong => AppPalette.wrong(colorBlind),
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => onTap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: labelColor),
          ),
        ),
      ),
    );
  }
}
