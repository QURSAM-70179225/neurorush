import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/word_scramble_logic.dart';
import '../game/game_session.dart';
import '../providers/app_providers.dart';
import 'timed_question_mixin.dart';

enum _Feedback { none, correct, wrong, revealed }

class WordScrambleGame extends ConsumerStatefulWidget {
  const WordScrambleGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<WordScrambleGame> createState() => WordScrambleGameState();
}

class WordScrambleGameState extends ConsumerState<WordScrambleGame>
    with SingleTickerProviderStateMixin, TimedQuestionMixin {
  ScrambleQuestion? _q;
  final List<int> _placed = [];
  final Set<String> _recent = {};
  _Feedback _feedback = _Feedback.none;
  int _attemptId = 0;

  @override
  GameSession get session => widget.session;

  /// The word currently being unscrambled (for tests).
  @visibleForTesting
  String? get debugCurrentWord => _q?.word;

  @override
  void nextQuestion() {
    final lang = ref.read(settingsProvider).wordLanguage;
    final q = WordScrambleLogic.generate(session.random, session.level, lang, avoid: _recent);
    _recent.add(q.word);
    setState(() {
      _q = q;
      _placed.clear();
      _feedback = _Feedback.none;
    });
    startQuestion(null);
  }

  @override
  void onTimeout() {}

  void _tapTile(int index) {
    final q = _q;
    if (q == null || answerLocked || !session.isRunning || _placed.contains(index)) return;
    session.feedback.tapHaptic();
    setState(() => _placed.add(index));
    if (_placed.length == q.length) _check();
  }

  void _removeAt(int slot) {
    if (answerLocked || !session.isRunning || slot >= _placed.length) return;
    setState(() => _placed.removeAt(slot));
  }

  void _check() {
    final q = _q!;
    final attempt = _placed.map((i) => q.tiles[i]).join();
    if (WordScrambleLogic.isCorrect(attempt, q)) {
      final ms = lockAnswer();
      if (ms == null) return;
      session.registerCorrect(
        basePoints: WordScrambleLogic.basePoints(q, session.level),
        reactionMs: ms,
        fast: ms < WordScrambleLogic.fastMs,
      );
      setState(() => _feedback = _Feedback.correct);
      advanceAfter(450);
    } else {
      // Wrong word: counts as a mistake, the player tries the same word again.
      session.registerWrong();
      setState(() {
        _feedback = _Feedback.wrong;
        _attemptId++;
      });
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (mounted && _q == q && _feedback == _Feedback.wrong) {
          setState(() {
            _placed.clear();
            _feedback = _Feedback.none;
          });
        }
      });
    }
  }

  void _skip() {
    final q = _q;
    if (q == null) return;
    if (lockAnswer() == null) return;
    session.registerWrong();
    setState(() {
      _feedback = _Feedback.revealed;
      _placed
        ..clear()
        ..addAll(_solutionOrder(q));
    });
    advanceAfter(1300);
  }

  /// Tile indexes that spell the target word.
  List<int> _solutionOrder(ScrambleQuestion q) {
    final used = <int>{};
    return [
      for (final letter in WordScrambleLogic.lettersOf(q.word))
        () {
          final i = List.generate(q.tiles.length, (i) => i).firstWhere((i) => !used.contains(i) && q.tiles[i] == letter);
          used.add(i);
          return i;
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final theme = Theme.of(context);
    final q = _q;
    if (q == null) return const SizedBox.shrink();
    final rtl = q.language.isRtl;
    final slotColor = switch (_feedback) {
      _Feedback.correct => AppPalette.correct(colorBlind),
      _Feedback.wrong => AppPalette.wrong(colorBlind),
      _Feedback.revealed => AppPalette.amber,
      _Feedback.none => AppPalette.violet,
    };
    final attempt = _placed.map((i) => q.tiles[i]).join();

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(rtl ? 'لفظ بنائیں' : 'Build the word', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${q.length} letters', textDirection: TextDirection.ltr, style: theme.textTheme.bodySmall),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The word as typed so far, rendered with proper joining.
                  Semantics(
                    liveRegion: true,
                    label: attempt.isEmpty ? 'Empty' : 'Your word: $attempt',
                    excludeSemantics: true,
                    child: SizedBox(
                      height: 56,
                      child: Text(
                        attempt,
                        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: slotColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    key: ValueKey('slots$_attemptId'),
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var s = 0; s < q.length; s++)
                        Semantics(
                          button: s < _placed.length,
                          label: s < _placed.length ? 'Remove ${q.tiles[_placed[s]]}' : 'Empty slot',
                          excludeSemantics: true,
                          child: GestureDetector(
                            onTap: () => _removeAt(s),
                            child: Container(
                              width: 42,
                              height: 50,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: slotColor, width: 4)),
                              ),
                              child: Text(
                                s < _placed.length ? _display(q.tiles[_placed[s]], q.language) : '',
                                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ).animate(target: _feedback == _Feedback.wrong ? 1 : 0).shake(hz: 5, offset: const Offset(8, 0)),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < q.tiles.length; i++)
                Semantics(
                  button: true,
                  enabled: !_placed.contains(i),
                  label: 'Letter ${q.tiles[i]}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTapDown: (_) => _tapTile(i),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _placed.contains(i) ? 0.2 : 1,
                      child: Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 3))],
                        ),
                        child: Text(
                          _display(q.tiles[i], q.language),
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _skip,
            icon: const Icon(Icons.skip_next_rounded),
            label: Text(rtl ? 'چھوڑیں' : 'Skip'),
          ),
        ],
      ),
    );
  }

  static String _display(String letter, WordLanguage lang) =>
      lang == WordLanguage.english ? letter.toUpperCase() : letter;
}

/// Language picker shown on the Word Scramble intro card.
class WordLanguagePicker extends ConsumerWidget {
  const WordLanguagePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(settingsProvider.select((s) => s.wordLanguage));
    return SegmentedButton<WordLanguage>(
      segments: [for (final l in WordLanguage.values) ButtonSegment(value: l, label: Text(l.label))],
      selected: {lang},
      onSelectionChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(wordLanguage: v.first)),
    );
  }
}
