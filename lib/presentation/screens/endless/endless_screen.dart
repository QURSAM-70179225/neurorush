import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/entities/ai_models.dart';
import '../../../domain/repositories/cloud_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/cloud_providers.dart';
import '../../widgets/cloud_widgets.dart';

enum _Phase { intro, loading, question, checking, answered, over, error }

/// Endless Mode: AI-generated puzzles, one after another, until 3 lives are
/// lost. Answers are checked on the server; the client never sees them first.
class EndlessScreen extends ConsumerStatefulWidget {
  const EndlessScreen({super.key, this.timeLimit = const Duration(seconds: 45)});
  final Duration timeLimit;

  @override
  ConsumerState<EndlessScreen> createState() => _EndlessScreenState();
}

class _EndlessScreenState extends ConsumerState<EndlessScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: widget.timeLimit,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed && _phase == _Phase.question) _answer(-1);
    });

  _Phase _phase = _Phase.intro;
  EndlessPuzzle? _puzzle;
  EndlessVerdict? _verdict;
  int? _picked;
  String? _error;
  bool _quotaReached = false;

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  CloudRepository get _cloud => ref.read(cloudRepositoryProvider);

  Future<void> _load({bool newRun = false}) async {
    setState(() {
      _phase = _Phase.loading;
      _verdict = null;
      _picked = null;
      _error = null;
    });
    try {
      final p = await _cloud.getEndlessPuzzle(newRun: newRun);
      if (!mounted) return;
      setState(() {
        _puzzle = p;
        _phase = _Phase.question;
      });
      _timer.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = cloudErrorText(e);
        _quotaReached = e is CloudFailure && e.code == 'resource-exhausted';
      });
    }
  }

  Future<void> _answer(int index) async {
    final p = _puzzle;
    if (p == null || _phase != _Phase.question) return;
    _timer.stop();
    setState(() {
      _phase = _Phase.checking;
      _picked = index;
    });
    final fx = ref.read(feedbackServiceProvider);
    try {
      final v = await _cloud.submitEndlessAnswer(p.id, index);
      if (!mounted) return;
      v.correct ? fx.correct() : fx.wrong();
      setState(() {
        _verdict = v;
        _phase = _Phase.answered;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = cloudErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = ref.watch(cloudRepositoryProvider);
    final p = _puzzle;
    final v = _verdict;
    final lives = v?.lives ?? p?.lives ?? 3;
    final run = v?.run ?? p?.run ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Endless Mode'),
        actions: [
          if (_phase != _Phase.intro && _phase != _Phase.over) ...[
            Semantics(
              label: '$lives lives left',
              excludeSemantics: true,
              child: Row(children: [
                for (var i = 0; i < 3; i++)
                  Icon(i < lives ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: AppPalette.pink),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Chip(label: Text('Run $run'), avatar: const Icon(Icons.bolt_rounded, size: 18)),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: !cloud.isAvailable
            ? const Center(
                child: InfoState(icon: Icons.cloud_off_rounded, message: 'Endless Mode creates fresh AI puzzles online. Connect and sign in to play.'),
              )
            : Padding(padding: const EdgeInsets.all(16), child: _body(theme, p, v)),
      ),
    );
  }

  Widget _body(ThemeData theme, EndlessPuzzle? p, EndlessVerdict? v) {
    switch (_phase) {
      case _Phase.intro:
        return _Intro(onStart: () => _load(newRun: true));
      case _Phase.loading:
        return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Neo is crafting a fresh puzzle…'),
          ]),
        );
      case _Phase.error:
        return Center(
          child: InfoState(
            icon: _quotaReached ? Icons.workspace_premium_rounded : Icons.wifi_off_rounded,
            message: _error ?? 'Something went wrong.',
            action: _quotaReached ? 'Back' : 'Try again',
            onAction: _quotaReached ? () => Navigator.of(context).maybePop() : () => _load(),
          ),
        );
      case _Phase.over:
        return _GameOver(verdict: v!, onRestart: () => _load(newRun: true));
      case _Phase.question:
      case _Phase.checking:
      case _Phase.answered:
        return _PuzzleView(
          puzzle: p!,
          timer: _timer,
          picked: _picked,
          verdict: v,
          busy: _phase == _Phase.checking,
          onPick: _answer,
          onNext: () {
            if (v!.gameOver) {
              setState(() => _phase = _Phase.over);
            } else {
              _load();
            }
          },
        );
    }
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 130,
          height: 130,
          decoration: const BoxDecoration(gradient: AppPalette.brandGradient, shape: BoxShape.circle),
          child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 72),
        ).animate().scale(curve: Curves.easeOutBack, duration: 500.ms),
        const SizedBox(height: 24),
        Text('Infinite AI puzzles', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(
          'Riddles, logic problems and number sequences made fresh by AI and double-checked before you see them. '
          'You have 3 lives and 45 seconds per puzzle. Puzzles get harder the longer your run lasts.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text('Free: 10 puzzles a day · Pro: unlimited', style: theme.textTheme.bodySmall),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Start run')),
        ),
      ],
    );
  }
}

class _PuzzleView extends StatelessWidget {
  const _PuzzleView({
    required this.puzzle,
    required this.timer,
    required this.picked,
    required this.verdict,
    required this.busy,
    required this.onPick,
    required this.onNext,
  });

  final EndlessPuzzle puzzle;
  final AnimationController timer;
  final int? picked;
  final EndlessVerdict? verdict;
  final bool busy;
  final ValueChanged<int> onPick;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = verdict;
    final kindLabel = {'sequence': 'Number sequence', 'riddle': 'Riddle', 'logic': 'Logic puzzle'}[puzzle.kind] ?? 'Puzzle';
    return ListView(
      children: [
        ExcludeSemantics(
          child: AnimatedBuilder(
            animation: timer,
            builder: (_, _) => LinearProgressIndicator(
              value: 1 - timer.value,
              minHeight: 8,
              borderRadius: BorderRadius.circular(6),
              color: timer.value > 0.75 ? Colors.redAccent : AppPalette.violet,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Chip(label: Text(kindLabel)),
            const SizedBox(width: 8),
            Semantics(
              label: 'Difficulty ${puzzle.difficulty} of 5',
              excludeSemantics: true,
              child: Row(children: [
                for (var i = 0; i < 5; i++)
                  Icon(Icons.circle, size: 10, color: i < puzzle.difficulty ? AppPalette.flame : theme.disabledColor),
              ]),
            ),
            const Spacer(),
            if (puzzle.remainingToday != null) Text('${puzzle.remainingToday} left today', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Semantics(liveRegion: true, child: Text(puzzle.question, style: theme.textTheme.titleLarge)),
          ),
        ).animate(key: ValueKey(puzzle.id)).fadeIn().slideY(begin: 0.05),
        const SizedBox(height: 12),
        for (var i = 0; i < puzzle.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Choice(
              text: puzzle.choices[i],
              state: v == null
                  ? (picked == i ? _ChoiceState.picked : _ChoiceState.idle)
                  : i == v.answerIndex
                      ? _ChoiceState.correct
                      : i == picked
                          ? _ChoiceState.wrong
                          : _ChoiceState.idle,
              onTap: v == null && !busy ? () => onPick(i) : null,
            ),
          ),
        if (busy) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
        if (v != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              v.correct ? 'Correct!' : (v.timedOut || picked == -1 ? 'Time’s up!' : 'Not quite.'),
              style: theme.textTheme.headlineSmall?.copyWith(color: v.correct ? AppPalette.mint : AppPalette.flame),
            ),
          ),
          const SizedBox(height: 4),
          Text(v.explanation, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          FilledButton(onPressed: onNext, child: Text(v.gameOver ? 'See results' : 'Next puzzle')),
        ],
      ],
    );
  }
}

enum _ChoiceState { idle, picked, correct, wrong }

class _Choice extends StatelessWidget {
  const _Choice({required this.text, required this.state, required this.onTap});
  final String text;
  final _ChoiceState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = switch (state) {
      _ChoiceState.correct => (AppPalette.mint, Colors.white),
      _ChoiceState.wrong => (AppPalette.flame, Colors.white),
      _ChoiceState.picked => (AppPalette.violet.withValues(alpha: 0.2), null),
      _ChoiceState.idle => (theme.colorScheme.surface, null),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(color: fg)),
        ),
      ),
    );
  }
}

class _GameOver extends StatelessWidget {
  const _GameOver({required this.verdict, required this.onRestart});
  final EndlessVerdict verdict;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = verdict.bestRun;
    return Column(
      children: [
        const Spacer(),
        const Icon(Icons.flag_rounded, size: 72, color: AppPalette.flame),
        Text('Run over', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text('You solved ${verdict.run} puzzle${verdict.run == 1 ? '' : 's'} in a row', style: theme.textTheme.titleMedium),
        ),
        Text(verdict.run >= best && best > 0 ? 'New best run!' : 'Best run: $best', style: theme.textTheme.bodyLarge),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(onPressed: onRestart, icon: const Icon(Icons.replay_rounded), label: const Text('New run')),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Back to games')),
      ],
    );
  }
}
