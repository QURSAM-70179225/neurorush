import 'package:hive_ce/hive.dart';

import '../../domain/entities/progress_state.dart';
import '../../domain/repositories/progress_repository.dart';

class HiveProgressRepository implements ProgressRepository {
  HiveProgressRepository(this._box);
  final Box<dynamic> _box;
  /// Phase 2 stored a single device-wide record under this key.
  static const _legacyKey = 'progress';
  static String _key(String uid) => 'progress_$uid';

  @override
  ProgressState load(String uid) {
    var raw = _box.get(_key(uid));
    // The first player to load inherits the pre-accounts record.
    if (raw == null && _box.containsKey(_legacyKey)) {
      raw = _box.get(_legacyKey);
      _box.put(_key(uid), raw);
      _box.delete(_legacyKey);
    }
    return raw is Map ? ProgressState.fromMap(raw) : const ProgressState();
  }

  @override
  Future<void> save(String uid, ProgressState state) => _box.put(_key(uid), state.toMap());
}
