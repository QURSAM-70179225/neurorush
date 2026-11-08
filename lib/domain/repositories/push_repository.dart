/// Push-notification settings stored for the server (pushTargets/{uid}).
class PushPrefs {
  const PushPrefs({this.streak = true, this.workout = true, this.friends = true, this.battle = true});
  final bool streak;
  final bool workout;
  final bool friends;
  final bool battle;

  Map<String, bool> toMap() => {'streak': streak, 'workout': workout, 'friends': friends, 'battle': battle};
}

/// UTC hour at which local [hour]:00 happens for a timezone offset (minutes east of UTC).
int utcHourFor(int localHour, int tzOffsetMinutes) => ((localHour * 60 - tzOffsetMinutes) % 1440 + 1440) % 1440 ~/ 60;

abstract interface class PushRepository {
  /// Registers this device's [token] (keeping the player's other devices).
  Future<void> saveTarget(String uid, {required String token, required int tzOffsetMinutes, required PushPrefs prefs});
}
