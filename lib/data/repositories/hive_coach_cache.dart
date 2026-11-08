import 'package:hive_ce/hive.dart';

import '../../domain/entities/ai_models.dart';
import '../../domain/repositories/coach_cache.dart';

class HiveCoachCache implements CoachTipCache {
  HiveCoachCache(this._box);
  final Box<dynamic> _box;

  static String _key(String uid, String day) => 'coach_${uid}_$day';

  @override
  CoachTip? read(String uid, String day) {
    final raw = _box.get(_key(uid, day));
    return raw is Map ? CoachTip.tryFromMap(raw) : null;
  }

  @override
  Future<void> write(String uid, String day, CoachTip tip) => _box.put(_key(uid, day), tip.toMap());
}
