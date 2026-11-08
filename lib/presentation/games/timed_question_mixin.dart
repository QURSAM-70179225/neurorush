import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/game_session.dart';

/// Shared plumbing for question-based games: a per-question timer that
/// pauses with the round, a reaction stopwatch and an answer lock.
mixin TimedQuestionMixin<W extends ConsumerStatefulWidget> on ConsumerState<W>, SingleTickerProviderStateMixin<W> {
  late final AnimationController questionTimer;
  final Stopwatch reactionWatch = Stopwatch();
  bool answerLocked = false;
  bool hasQuestion = false;
  bool _timed = false;

  /// Set when an [advanceAfter] delay ended while the round was paused.
  bool _advancePending = false;

  GameSession get session;

  /// Show the first / next question (call [startQuestion] from it).
  void nextQuestion();

  /// The question timed out.
  void onTimeout();

  @override
  void initState() {
    super.initState();
    questionTimer = AnimationController(vsync: this, animationBehavior: AnimationBehavior.preserve)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && !answerLocked && session.isRunning) onTimeout();
      });
    session.running.addListener(_onRunningChanged);
  }

  @override
  void dispose() {
    session.running.removeListener(_onRunningChanged);
    questionTimer.dispose();
    super.dispose();
  }

  void _onRunningChanged() {
    if (session.isRunning) {
      if (!hasQuestion || _advancePending) {
        _advancePending = false;
        nextQuestion();
      } else if (!answerLocked) {
        reactionWatch.start();
        if (_timed) questionTimer.forward();
      }
    } else {
      reactionWatch.stop();
      questionTimer.stop();
    }
  }

  /// Starts timing a newly shown question. [timeLimitMs] of null = untimed.
  void startQuestion(int? timeLimitMs) {
    hasQuestion = true;
    answerLocked = false;
    _timed = timeLimitMs != null;
    if (timeLimitMs != null) {
      questionTimer
        ..duration = Duration(milliseconds: timeLimitMs)
        ..forward(from: 0);
    } else {
      questionTimer.value = 0;
    }
    reactionWatch
      ..reset()
      ..start();
  }

  /// Locks input and returns the reaction time in ms, or null if already locked.
  int? lockAnswer() {
    if (answerLocked || !session.isRunning) return null;
    answerLocked = true;
    questionTimer.stop();
    reactionWatch.stop();
    return reactionWatch.elapsedMilliseconds;
  }

  /// Waits [ms] then shows the next question if the round is still running.
  Future<void> advanceAfter(int ms) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
    if (!mounted) return;
    if (session.isRunning) {
      nextQuestion();
    } else {
      // Paused (or finished) during the delay: continue on resume.
      _advancePending = true;
    }
  }
}
