import 'skill.dart';

/// Public profile from users/{uid}.
class CloudProfile {
  const CloudProfile({
    required this.uid,
    this.username,
    this.displayName,
    this.country,
    this.photoUrl,
    this.xp = 0,
    this.level = 1,
    this.rounds = 0,
    this.brainScore = 0,
    this.skills = const {},
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.streakDay,
    this.friends = 0,
    this.trophies = 0,
    this.lastActiveAt,
  });

  final String uid;
  final String? username;
  final String? displayName;
  final String? country;
  final String? photoUrl;
  final int xp;
  final int level;
  final int rounds;
  final int brainScore;
  final Map<Skill, int> skills;
  final int currentStreak;
  final int bestStreak;

  /// Local date (yyyy-MM-dd) of the last day that counted for the streak.
  final String? streakDay;
  final int friends;
  final int trophies;
  final DateTime? lastActiveAt;

  String get name {
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    return username ?? 'Player';
  }

  /// Streak as visible today: a streak whose last day is before yesterday is over.
  int visibleStreak(DateTime now) {
    final day = streakDay;
    if (day == null) return 0;
    final last = DateTime.tryParse(day);
    if (last == null) return 0;
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(last).inDays <= 1 ? currentStreak : 0;
  }
}

enum LeaderboardScope { global, country, friends }

class LeaderboardQuery {
  const LeaderboardQuery({required this.scope, required this.weekId, this.gameId, this.country, this.friendUids = const []});

  final LeaderboardScope scope;
  final String weekId;

  /// null = weekly XP, otherwise best score in that game this week.
  final String? gameId;
  final String? country;
  final List<String> friendUids;

  String get field => gameId == null ? 'xp' : 'bestScores.$gameId';

  @override
  bool operator ==(Object other) =>
      other is LeaderboardQuery &&
      other.scope == scope &&
      other.weekId == weekId &&
      other.gameId == gameId &&
      other.country == country &&
      other.friendUids.join(',') == friendUids.join(',');

  @override
  int get hashCode => Object.hash(scope, weekId, gameId, country, friendUids.join(','));
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.value,
    required this.rank,
    this.username,
    this.displayName,
    this.country,
    this.level = 1,
  });

  final String uid;
  final int value;
  final int rank;
  final String? username;
  final String? displayName;
  final String? country;
  final int level;

  String get name {
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    return username ?? 'Player';
  }
}

class LeaderboardPage {
  const LeaderboardPage({required this.entries, this.me});
  final List<LeaderboardEntry> entries;

  /// The current player's entry and rank, even when outside [entries].
  final LeaderboardEntry? me;
}

class FriendRequest {
  const FriendRequest({required this.fromUid, required this.fromUsername, this.fromDisplayName});
  final String fromUid;
  final String fromUsername;
  final String? fromDisplayName;
}

enum SubmitStatus { accepted, duplicate, rejected }

class SubmitOutcome {
  const SubmitOutcome({required this.status, this.reason, this.newAchievements = const []});
  final SubmitStatus status;
  final String? reason;
  final List<String> newAchievements;
}

enum FriendRequestResult { requested, friends, alreadyFriends }
