import 'package:hive_ce/hive.dart';

import '../../domain/entities/game_result.dart';
import '../../domain/repositories/game_history_repository.dart';

class HiveGameHistoryRepository implements GameHistoryRepository {
  HiveGameHistoryRepository(this._box);
  final Box<dynamic> _box;

  @override
  List<GameResult> all() {
    final list = <GameResult>[];
    for (final v in _box.values) {
      if (v is Map) {
        final r = GameResult.tryFromMap(v);
        if (r != null) list.add(r);
      }
    }
    list.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return list;
  }

  @override
  Future<void> save(GameResult result) => _box.put(result.id, result.toMap());

  @override
  Future<void> clear() => _box.clear();
}
