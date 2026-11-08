import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/odd_one_out_logic.dart';
import '../game/game_session.dart';
import '../game/question_timer_bar.dart';
import '../providers/app_providers.dart';
import 'timed_question_mixin.dart';

/// Icons for every glyph key used by [OddGlyphs].
const oddGlyphIcons = <String, IconData>{
  'star': Icons.star_rounded,
  'star_outline': Icons.star_outline_rounded,
  'heart': Icons.favorite_rounded,
  'heart_outline': Icons.favorite_border_rounded,
  'bolt': Icons.bolt_rounded,
  'moon': Icons.dark_mode_rounded,
  'cloud': Icons.cloud_rounded,
  'cloud_off': Icons.cloud_off_rounded,
  'leaf': Icons.eco_rounded,
  'paw': Icons.pets_rounded,
  'music': Icons.music_note_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'diamond': Icons.diamond_rounded,
  'sun': Icons.wb_sunny_rounded,
  'flower': Icons.local_florist_rounded,
  'bell': Icons.notifications_rounded,
  'bell_off': Icons.notifications_off_rounded,
  'key': Icons.key_rounded,
  'flag': Icons.flag_rounded,
  'cake': Icons.cake_rounded,
  'smile': Icons.sentiment_satisfied_rounded,
  'frown': Icons.sentiment_dissatisfied_rounded,
  'lock': Icons.lock_rounded,
  'lock_open': Icons.lock_open_rounded,
  'mic': Icons.mic_rounded,
  'mic_off': Icons.mic_off_rounded,
  'eye': Icons.visibility_rounded,
  'eye_off': Icons.visibility_off_rounded,
  'wifi': Icons.wifi_rounded,
  'wifi_off': Icons.wifi_off_rounded,
  'thumb_up': Icons.thumb_up_rounded,
  'thumb_down': Icons.thumb_down_rounded,
  'volume_up': Icons.volume_up_rounded,
  'volume_off': Icons.volume_off_rounded,
  'battery_full': Icons.battery_full_rounded,
  'battery_low': Icons.battery_2_bar_rounded,
  'arrow': Icons.arrow_upward_rounded,
  'navigation': Icons.navigation_rounded,
};

class OddOneOutGame extends ConsumerStatefulWidget {
  const OddOneOutGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<OddOneOutGame> createState() => _OddOneOutGameState();
}

class _OddOneOutGameState extends ConsumerState<OddOneOutGame>
    with SingleTickerProviderStateMixin, TimedQuestionMixin {
  OddOneOutQuestion? _q;
  int _qId = 0;
  int? _tapped;
  bool _reveal = false;

  @override
  GameSession get session => widget.session;

  @override
  void nextQuestion() {
    final q = OddOneOutLogic.generate(session.random, session.level);
    setState(() {
      _q = q;
      _qId++;
      _tapped = null;
      _reveal = false;
    });
    startQuestion(q.timeLimitMs);
  }

  @override
  void onTimeout() => _answer(null);

  void _answer(int? index) {
    final q = _q;
    if (q == null) return;
    final ms = lockAnswer();
    if (ms == null) return;
    final correct = index == q.oddIndex;
    if (correct) {
      session.registerCorrect(
        basePoints: OddOneOutLogic.basePoints(session.level),
        reactionMs: ms,
        fast: ms < OddOneOutLogic.fastMs,
      );
    } else {
      session.registerWrong(reactionMs: index == null ? null : ms);
    }
    setState(() {
      _tapped = index;
      _reveal = true;
    });
    advanceAfter(correct ? 250 : 900);
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final q = _q;

    return Column(
      children: [
        QuestionTimerBar(controller: questionTimer, color: AppPalette.pink),
        const SizedBox(height: 12),
        Text('Tap the odd one out', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: q == null
                ? const SizedBox.shrink()
                : AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(builder: (context, c) {
                      final n = q.gridSize;
                      const gap = 6.0;
                      final cell = (c.maxWidth - gap * (n - 1)) / n;
                      return Wrap(
                        key: ValueKey(_qId),
                        spacing: gap,
                        runSpacing: gap,
                        children: List.generate(q.cellCount, (i) {
                          final odd = i == q.oddIndex;
                          final glyph = odd ? q.oddGlyph : q.baseGlyph;
                          Color bg = dark ? const Color(0xFF2A2250) : Colors.white;
                          if (_reveal && odd) bg = AppPalette.correct(colorBlind);
                          if (_reveal && i == _tapped && !odd) bg = AppPalette.wrong(colorBlind);
                          return Semantics(
                            button: true,
                            label: 'Icon ${i + 1}: ${glyph.replaceAll('_', ' ')}'
                                '${odd && q.oddTurns != 0 ? ', rotated' : ''}',
                            excludeSemantics: true,
                            child: GestureDetector(
                              onTapDown: (_) => _answer(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: cell,
                                height: cell,
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(cell * 0.2),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06), blurRadius: 5, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: RotationTransition(
                                  turns: AlwaysStoppedAnimation(odd ? q.oddTurns : 0),
                                  child: Icon(
                                    oddGlyphIcons[glyph],
                                    size: cell * 0.6,
                                    color: _reveal && (odd || i == _tapped) ? Colors.white : AppPalette.violet,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ).animate().fadeIn(duration: 150.ms).scale(begin: const Offset(0.95, 0.95));
                    }),
                  ),
          ),
        ),
        if (q != null) Text('Grid ${q.gridSize}×${q.gridSize}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
      ],
    );
  }
}
