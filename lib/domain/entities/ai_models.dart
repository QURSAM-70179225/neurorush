import 'skill.dart';

/// Tip from the AI Brain Coach (or a curated fallback when AI is unavailable).
class CoachTip {
  const CoachTip({required this.tip, required this.funFact, required this.focusSkill, required this.isAi});
  final String tip;
  final String funFact;
  final Skill? focusSkill;
  final bool isAi;

  Map<String, Object?> toMap() => {'tip': tip, 'funFact': funFact, 'focusSkill': focusSkill?.name, 'isAi': isAi};

  static CoachTip? tryFromMap(Map<dynamic, dynamic>? m) {
    if (m == null || m['tip'] is! String || m['funFact'] is! String) return null;
    return CoachTip(
      tip: m['tip'] as String,
      funFact: m['funFact'] as String,
      focusSkill: Skill.values.where((s) => s.name == m['focusSkill']).firstOrNull,
      isAi: m['isAi'] == true || m['source'] == 'ai',
    );
  }
}

/// An Endless Mode puzzle as served to the client (no answer included).
class EndlessPuzzle {
  const EndlessPuzzle({
    required this.id,
    required this.kind,
    required this.question,
    required this.choices,
    required this.difficulty,
    required this.isAi,
    required this.run,
    required this.lives,
    required this.bestRun,
    this.remainingToday,
  });

  final String id;

  /// sequence, riddle or logic.
  final String kind;
  final String question;
  final List<String> choices;

  /// 1 (easy) … 5 (expert).
  final int difficulty;
  final bool isAi;
  final int run;
  final int lives;
  final int bestRun;

  /// Free puzzles left today; null for Pro (unlimited).
  final int? remainingToday;
}

/// Server verdict for an Endless answer.
class EndlessVerdict {
  const EndlessVerdict({
    required this.correct,
    required this.answerIndex,
    required this.explanation,
    required this.run,
    required this.lives,
    required this.bestRun,
    required this.gameOver,
    this.timedOut = false,
    this.coinsEarned = 0,
  });

  final bool correct;
  final int answerIndex;
  final String explanation;
  final int run;
  final int lives;
  final int bestRun;
  final bool gameOver;
  final bool timedOut;
  final int coinsEarned;
}
