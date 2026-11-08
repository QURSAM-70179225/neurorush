import 'package:hive_ce/hive.dart';

import '../../domain/entities/progress_state.dart';
import '../../domain/repositories/progress_repository.dart';

class HiveProgressRepository implements ProgressRepository {
  HiveProgressRepository(this._box);
  final Box<dynamic> _box;
  static const _key = 'progress';

  @override
  ProgressState load() {
    final raw = _box.get(_key);
    return raw is Map ? ProgressState.fromMap(raw) : const ProgressState();
  }

  @override
  Future<void> save(ProgressState state) => _box.put(_key, state.toMap());
}
