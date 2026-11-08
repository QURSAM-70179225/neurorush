import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/feedback/feedback_service.dart';
import '../../domain/entities/game_type.dart';
import '../../domain/logic/adaptive_difficulty.dart';
import '../../domain/logic/score_tracker.dart';

/// Feedback for the most recent answer, used for score pop-ups.
class AnswerFeedback {
  const AnswerFeedback({required this.id, required this.correct, required this.points});
  final int id;
  final bool correct;
  final int points;
}

/// Live state of one round, shared between the [GameShell] (timer, HUD) and
/// the mini-game widget (questions, input).
class GameSession extends ChangeNotifier {
  GameSession({
    required this.type,
    required this.feedback,
    int? seed,
    int startLevel = 1,
  })  : random = math.Random(seed),
        tracker = ScoreTracker(),
        difficulty = AdaptiveDifficulty(startLevel: startLevel);

  final GameType type;
  final FeedbackService feedback;

  /// Seeded so a round can be replayed identically (used by battles later).
  final math.Random random;
  final ScoreTracker tracker;
  final AdaptiveDifficulty difficulty;

  /// True only while the clock is running. Games must ignore input and pause
  /// their own timers while this is false (countdown, pause, finished).
  final ValueNotifier<bool> running = ValueNotifier(false);

  AnswerFeedback? _last;
  AnswerFeedback? get lastFeedback => _last;
  int _feedbackCounter = 0;

  bool get isRunning => running.value;
  int get level => difficulty.level;

  /// Records a correct answer; returns the points awarded.
  int registerCorrect({required int basePoints, int? reactionMs, bool fast = false}) {
    if (!isRunning) return 0;
    final multiplierBefore = tracker.multiplier;
    final points = tracker.recordCorrect(basePoints: basePoints, reactionMs: reactionMs);
    difficulty.onCorrect(fast: fast);
    feedback.correct(combo: tracker.multiplier > multiplierBefore);
    _last = AnswerFeedback(id: ++_feedbackCounter, correct: true, points: points);
    notifyListeners();
    return points;
  }

  /// Records a mistake or a timeout.
  void registerWrong({int? reactionMs}) {
    if (!isRunning) return;
    tracker.recordWrong(reactionMs: reactionMs);
    difficulty.onMistake();
    feedback.wrong();
    _last = AnswerFeedback(id: ++_feedbackCounter, correct: false, points: 0);
    notifyListeners();
  }

  @override
  void dispose() {
    running.dispose();
    super.dispose();
  }
}
