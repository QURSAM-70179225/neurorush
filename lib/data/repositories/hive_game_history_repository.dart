import 'package:hive_ce/hive.dart';

import '../../domain/entities/game_result.dart';
import '../../domain/repositories/game_history_repository.dart';

class HiveGameHistoryRepository implements GameHistoryRepository {
  HiveGameHistoryRepository(this._box);
  final Box<dynamic> _box;

  Iterable<GameResult> _decoded() sync* {
    for (final v in _box.values) {
      if (v is Map) {
        final r = GameResult.tryFromMap(v);
        if (r != null) yield r;
      }
    }
  }

  @override
  List<GameResult> all(String uid) {
    final list = _decoded().where((r) => r.ownerUid == uid).toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return list;
  }

  @override
  Future<void> save(GameResult result) => _box.put(result.id, result.toMap());

  @override
  Future<void> clear(String uid) async {
    final ids = _decoded().where((r) => r.ownerUid == uid).map((r) => r.id).toList();
    await _box.deleteAll(ids);
  }

  @override
  Future<int> claimUnowned(String uid) async {
    final unowned = _decoded().where((r) => r.ownerUid == null).toList();
    for (final r in unowned) {
      await _box.put(r.id, r.copyWith(ownerUid: uid).toMap());
    }
    return unowned.length;
  }
}
