import 'dart:math' as math;

/// Tracks score, combo multiplier, accuracy and reaction times for one round.
class ScoreTracker {
  ScoreTracker({this.maxMultiplier = 5, this.answersPerMultiplierStep = 3});

  final int maxMultiplier;

  /// How many consecutive correct answers raise the multiplier by one.
  final int answersPerMultiplierStep;

  int _score = 0;
  int _correct = 0;
  int _wrong = 0;
  int _streak = 0;
  int _maxStreak = 0;
  final List<int> _reactionTimes = [];

  int get score => _score;
  int get correct => _correct;
  int get wrong => _wrong;
  int get attempts => _correct + _wrong;

  /// Current run of consecutive correct answers.
  int get streak => _streak;
  int get maxStreak => _maxStreak;

  /// The multiplier the NEXT correct answer will receive.
  int get multiplier =>
      math.min(maxMultiplier, 1 + _streak ~/ answersPerMultiplierStep);

  double get accuracy => attempts == 0 ? 0 : _correct / attempts;

  List<int> get reactionTimes => List.unmodifiable(_reactionTimes);

  int? get averageReactionMs => _reactionTimes.isEmpty
      ? null
      : (_reactionTimes.reduce((a, b) => a + b) / _reactionTimes.length).round();

  int? get bestReactionMs =>
      _reactionTimes.isEmpty ? null : _reactionTimes.reduce(math.min);

  /// Records a correct answer and returns the points awarded.
  int recordCorrect({required int basePoints, int? reactionMs}) {
    assert(basePoints >= 0);
    final points = basePoints * multiplier;
    _score += points;
    _correct++;
    _streak++;
    _maxStreak = math.max(_maxStreak, _streak);
    _addReaction(reactionMs);
    return points;
  }

  /// Records a wrong answer (or a timeout) and breaks the combo.
  void recordWrong({int? reactionMs}) {
    _wrong++;
    _streak = 0;
    _addReaction(reactionMs);
  }

  void _addReaction(int? ms) {
    // Ignore physically impossible values (< 50 ms) and idle gaps (> 30 s).
    if (ms != null && ms >= 50 && ms <= 30000) _reactionTimes.add(ms);
  }
}
