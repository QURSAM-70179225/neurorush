import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/repositories/push_repository.dart';

class FirebasePushRepository implements PushRepository {
  FirebasePushRepository(this._db);
  final FirebaseFirestore _db;

  /// Streak reminder and workout notification local hours.
  static const reminderLocalHour = 19;
  static const workoutLocalHour = 8;

  @override
  Future<void> saveTarget(String uid, {required String token, required int tzOffsetMinutes, required PushPrefs prefs}) async {
    final ref = _db.doc('pushTargets/$uid');
    // Keep up to 10 devices: this one plus the most recent others.
    Object? existing;
    try {
      existing = (await ref.get()).data()?['tokens'];
    } on FirebaseException {
      existing = null; // first registration or offline: start with this device
    }
    final tokens = <String>[token, ...((existing as List?)?.cast<String>() ?? const <String>[]).where((t) => t != token)].take(10).toList();
    await ref.set({
      'tokens': tokens,
      'tzOffsetMinutes': tzOffsetMinutes,
      'reminderHourUtc': utcHourFor(reminderLocalHour, tzOffsetMinutes),
      'workoutHourUtc': utcHourFor(workoutLocalHour, tzOffsetMinutes),
      'prefs': prefs.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
