import 'package:hive_ce/hive.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);
  final Box<dynamic> _box;
  static const _key = 'app_settings';

  @override
  AppSettings load() {
    final raw = _box.get(_key);
    return raw is Map ? AppSettings.fromMap(raw) : const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) => _box.put(_key, settings.toMap());
}
