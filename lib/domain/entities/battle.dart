/// A battle question as the client sees it (the answer is server-only).
class BattleQuestion {
  const BattleQuestion({required this.type, required this.choices, this.prompt, this.word, this.ink});

  /// math, sequence or stroop.
  final String type;
  final String? prompt;

  /// Stroop: colour slot of the word and of the ink (0–5).
  final int? word;
  final int? ink;

  /// For stroop: colour slot numbers as strings.
  final List<String> choices;

  factory BattleQuestion.fromMap(Map<dynamic, dynamic> m) => BattleQuestion(
        type: m['type'] as String,
        prompt: m['prompt'] as String?,
        word: (m['word'] as num?)?.toInt(),
        ink: (m['ink'] as num?)?.toInt(),
        choices: [for (final c in m['choices'] as List) '$c'],
      );
}

class BattleAnswer {
  const BattleAnswer({required this.correct, required this.points, required this.ms});
  final bool correct;
  final int points;
  final int ms;
}

class BattlePlayer {
  const BattlePlayer({required this.uid, this.username, this.displayName, this.trophies = 0, this.level = 1});
  final String uid;
  final String? username;
  final String? displayName;
  final int trophies;
  final int level;

  String get name {
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    return username != null ? '@$username' : 'Player';
  }
}

enum BattleStatus { waiting, active, finished, expired }

enum BattleMode { random, invite, bot }

class Battle {
  const Battle({
    required this.id,
    required this.mode,
    required this.status,
    required this.players,
    required this.questions,
    required this.questionMs,
    required this.scores,
    required this.answers,
    this.startAt,
    this.endsAt,
    this.inviteCode,
    this.winner,
    this.trophyDelta = const {},
  });

  final String id;
  final BattleMode mode;
  final BattleStatus status;
  final List<BattlePlayer> players;
  final List<BattleQuestion> questions;
  final int questionMs;
  final DateTime? startAt;
  final DateTime? endsAt;
  final Map<String, int> scores;
  final Map<String, Map<int, BattleAnswer>> answers;
  final String? inviteCode;
  final String? winner;
  final Map<String, int> trophyDelta;

  int get count => questions.length;

  BattlePlayer? player(String uid) => players.where((p) => p.uid == uid).firstOrNull;
  BattlePlayer? opponentOf(String uid) => players.where((p) => p.uid != uid).firstOrNull;

  /// Index of the open question at server time [now]: -1 before the start,
  /// [count] once all questions are over.
  int questionAt(DateTime now) {
    final s = startAt;
    if (s == null || now.isBefore(s)) return -1;
    final i = now.difference(s).inMilliseconds ~/ questionMs;
    return i > count ? count : i;
  }

  /// Time left on question [index] at [now].
  Duration timeLeft(int index, DateTime now) {
    final closes = startAt!.add(Duration(milliseconds: (index + 1) * questionMs));
    final d = closes.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

class MatchResult {
  const MatchResult({required this.battleId});

  /// null while waiting in the queue.
  final String? battleId;
}

class AnswerResult {
  const AnswerResult({required this.correct, required this.answerIndex, required this.points});
  final bool correct;
  final int answerIndex;
  final int points;
}

class BattleSummary {
  const BattleSummary({required this.battle, required this.myUid});
  final Battle battle;
  final String myUid;

  String get opponentName => battle.opponentOf(myUid)?.name ?? 'Opponent';
  int get myScore => battle.scores[myUid] ?? 0;
  int get opponentScore => battle.scores[battle.opponentOf(myUid)?.uid] ?? 0;
  bool get won => battle.winner == myUid;
  bool get draw => battle.status == BattleStatus.finished && battle.winner == null;
}
