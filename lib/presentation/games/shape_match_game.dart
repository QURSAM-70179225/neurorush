import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../domain/games/color_clash_logic.dart';
import '../../domain/games/shape_match_logic.dart';
import '../game/game_session.dart';
import '../game/question_timer_bar.dart';
import '../providers/app_providers.dart';
import 'timed_question_mixin.dart';

class ShapeMatchGame extends ConsumerStatefulWidget {
  const ShapeMatchGame({super.key, required this.session});
  final GameSession session;

  @override
  ConsumerState<ShapeMatchGame> createState() => _ShapeMatchGameState();
}

class _ShapeMatchGameState extends ConsumerState<ShapeMatchGame>
    with SingleTickerProviderStateMixin, TimedQuestionMixin {
  late final ShapeMatchSequence _seq = ShapeMatchSequence(session.random);
  ShapeMatchRound? _round;
  int _cardId = 0;
  int _lastNBack = 1;
  bool _nBackChanged = false;
  bool? _lastAnswerCorrect;

  @override
  GameSession get session => widget.session;

  @override
  void nextQuestion() {
    final round = _seq.next(session.level);
    setState(() {
      _nBackChanged = round.nBack != _lastNBack;
      _lastNBack = round.nBack;
      _round = round;
      _cardId++;
      _lastAnswerCorrect = null;
    });
    if (round.isQuestion) {
      startQuestion(round.timeLimitMs);
    } else {
      // A card to memorise: no answer needed.
      startQuestion(null);
      answerLocked = true;
      advanceAfter(_nBackChanged ? 1600 : 900);
    }
  }

  @override
  void onTimeout() => _answer(null);

  void _answer(bool? saidYes) {
    final round = _round;
    if (round == null || !round.isQuestion) return;
    final ms = lockAnswer();
    if (ms == null) return;
    final correct = saidYes != null && saidYes == round.isMatch;
    if (correct) {
      session.registerCorrect(
        basePoints: ShapeMatchLogic.basePoints(session.level),
        reactionMs: ms,
        fast: ms < ShapeMatchLogic.fastMs,
      );
    } else {
      session.registerWrong(reactionMs: saidYes == null ? null : ms);
    }
    setState(() => _lastAnswerCorrect = correct);
    advanceAfter(correct ? 160 : 450);
  }

  @override
  Widget build(BuildContext context) {
    final colorBlind = ref.watch(settingsProvider.select((s) => s.colorBlindMode));
    final palette = colorBlind ? ColorClashPalettes.colorBlindSafe : ColorClashPalettes.standard;
    final theme = Theme.of(context);
    final round = _round;
    final prompt = round == null
        ? ''
        : !round.isQuestion
            ? 'Remember this shape'
            : round.nBack == 1
                ? 'Same shape as the previous card?'
                : 'Same shape as 2 cards back?';

    return Column(
      children: [
        QuestionTimerBar(controller: questionTimer, color: const Color(0xFF14B8A6)),
        const SizedBox(height: 12),
        Semantics(liveRegion: true, child: Text(prompt, style: theme.textTheme.titleMedium)),
        if (_nBackChanged && round != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppPalette.amber, borderRadius: BorderRadius.circular(20)),
              child: Text(
                round.nBack == 2 ? 'Level up! Now compare with 2 cards back' : 'Back to comparing with the previous card',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ).animate().shake(),
          ),
        Expanded(
          child: Center(
            child: round == null
                ? const SizedBox.shrink()
                : Semantics(
                    label: 'Card: ${round.card.kind.name}',
                    excludeSemantics: true,
                    child: Container(
                      key: ValueKey(_cardId),
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                          width: 5,
                          color: switch (_lastAnswerCorrect) {
                            true => AppPalette.correct(colorBlind),
                            false => AppPalette.wrong(colorBlind),
                            null => Colors.transparent,
                          },
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)],
                      ),
                      padding: const EdgeInsets.all(36),
                      child: CustomPaint(
                        painter: ShapePainter(round.card.kind, Color(palette[round.card.colorIndex].argb)),
                      ),
                    ).animate().slideX(begin: 0.6, duration: 180.ms, curve: Curves.easeOut).fadeIn(duration: 120.ms),
                  ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _BigButton(
                label: 'NO',
                icon: Icons.close_rounded,
                color: AppPalette.wrong(colorBlind),
                enabled: round?.isQuestion ?? false,
                onTap: () => _answer(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigButton(
                label: 'YES',
                icon: Icons.check_rounded,
                color: AppPalette.correct(colorBlind),
                enabled: round?.isQuestion ?? false,
                onTap: () => _answer(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          onTapDown: enabled ? (_) => onTap() : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: enabled ? 1 : 0.4,
            child: Container(
              height: 84,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 32),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Draws one of the [ShapeKind]s filling its box.
class ShapePainter extends CustomPainter {
  ShapePainter(this.kind, this.color);
  final ShapeKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width, h = size.height, c = Offset(w / 2, h / 2), r = math.min(w, h) / 2;
    Path polygon(int sides, {double rotation = -math.pi / 2, double inner = 0}) {
      final path = Path();
      final points = inner > 0 ? sides * 2 : sides;
      for (var i = 0; i < points; i++) {
        final rad = inner > 0 && i.isOdd ? r * inner : r;
        final a = rotation + i * 2 * math.pi / points;
        final pt = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      return path..close();
    }

    switch (kind) {
      case ShapeKind.circle:
        canvas.drawCircle(c, r, p);
      case ShapeKind.square:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: r * 0.9), Radius.circular(r * 0.15)), p);
      case ShapeKind.triangle:
        canvas.drawPath(polygon(3, rotation: -math.pi / 2), p);
      case ShapeKind.star:
        canvas.drawPath(polygon(5, inner: 0.45), p);
      case ShapeKind.diamond:
        canvas.drawPath(polygon(4), p);
      case ShapeKind.hexagon:
        canvas.drawPath(polygon(6, rotation: 0), p);
      case ShapeKind.cross:
        final t = r * 0.35;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 2 * r, height: 2 * t), Radius.circular(t * 0.4)), p);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 2 * t, height: 2 * r), Radius.circular(t * 0.4)), p);
      case ShapeKind.heart:
        final path = Path()
          ..moveTo(c.dx, h * 0.92)
          ..cubicTo(w * -0.15, h * 0.45, w * 0.2, h * -0.1, c.dx, h * 0.28)
          ..cubicTo(w * 0.8, h * -0.1, w * 1.15, h * 0.45, c.dx, h * 0.92)
          ..close();
        canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(ShapePainter old) => old.kind != kind || old.color != color;
}
