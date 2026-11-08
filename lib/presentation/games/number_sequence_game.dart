import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/number_sequence_logic.dart';
import '../game/game_session.dart';
import '../game/question_timer_bar.dart';
import '../providers/app_providers.dart';
import 'timed_question_mixin.dart';

class NumberSequenceGame extends ConsumerStatefulWidget {
  const NumberSequenceGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<NumberSequenceGame> createState() => _NumberSequenceGameState();
}

class _NumberSequenceGameState extends ConsumerState<NumberSequenceGame>
    with SingleTickerProviderStateMixin, TimedQuestionMixin {
  SequenceQuestion? _q;
  int _qId = 0;
  int? _picked;

  @override
  GameSession get session => widget.session;

  @override
  void nextQuestion() {
    final q = NumberSequenceLogic.generate(session.random, session.level);
    setState(() {
      _q = q;
      _qId++;
      _picked = null;
    });
    startQuestion(q.timeLimitMs);
  }

  @override
  void onTimeout() => _answer(null);

  void _answer(int? value) {
    final q = _q;
    if (q == null) return;
    final ms = lockAnswer();
    if (ms == null) return;
    final correct = value == q.answer;
    if (correct) {
      session.registerCorrect(
        basePoints: NumberSequenceLogic.basePoints(session.level),
        reactionMs: ms,
        fast: ms < NumberSequenceLogic.fastMs,
      );
    } else {
      session.registerWrong(reactionMs: value == null ? null : ms);
    }
    setState(() => _picked = value ?? -1);
    // Leave time to read the rule after a mistake.
    advanceAfter(correct ? 250 : 1600);
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final theme = Theme.of(context);
    final q = _q;
    final revealed = _picked != null;

    return Column(
      children: [
        QuestionTimerBar(controller: questionTimer, color: AppPalette.amber),
        const SizedBox(height: 12),
        Text('What comes next?', style: theme.textTheme.titleMedium),
        Expanded(
          child: Center(
            child: q == null
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        liveRegion: true,
                        label: 'Sequence: ${q.shown.join(', ')}, then what?',
                        excludeSemantics: true,
                        child: Wrap(
                          key: ValueKey(_qId),
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, n) in q.shown.indexed)
                              _Term(text: '$n')
                                  .animate(delay: (60 * i).ms)
                                  .fadeIn(duration: 120.ms)
                                  .scale(begin: const Offset(0.7, 0.7)),
                            _Term(
                              text: revealed ? '${q.answer}' : '?',
                              highlight: revealed ? AppPalette.correct(colorBlind) : AppPalette.amber,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: revealed && _picked != q.answer ? 1 : 0,
                        child: Semantics(
                          liveRegion: true,
                          child: Text('Rule: ${q.rule}',
                              textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
                        ),
                      ),
                    ],
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
                Semantics(
                  button: true,
                  label: '$o',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTapDown: (_) => _answer(o),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: !revealed
                            ? theme.colorScheme.surface
                            : o == q.answer
                                ? AppPalette.correct(colorBlind)
                                : o == _picked
                                    ? AppPalette.wrong(colorBlind)
                                    : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Text('$o', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Term extends StatelessWidget {
  const _Term({required this.text, this.highlight});
  final String text;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: highlight != null ? Colors.white : null,
        ),
      ),
    );
  }
}
