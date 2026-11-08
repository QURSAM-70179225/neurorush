import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Opens and exposes the Hive boxes used for offline storage. Values are
/// stored as plain maps so no generated adapters are required.
class HiveStore {
  HiveStore._(this.settings, this.sessions, this.auth);

  static const _settingsBox = 'settings';
  static const _sessionsBox = 'game_sessions';
  static const _authBox = 'local_auth';

  final Box<dynamic> settings;
  final Box<dynamic> sessions;
  final Box<dynamic> auth;

  static Future<HiveStore> open() async {
    await Hive.initFlutter('neurorush');
    return HiveStore._(
      await Hive.openBox<dynamic>(_settingsBox),
      await Hive.openBox<dynamic>(_sessionsBox),
      await Hive.openBox<dynamic>(_authBox),
    );
  }

  /// Opens boxes in [path] without Flutter bindings (used by tests).
  static Future<HiveStore> openAt(String path) async {
    Hive.init(path);
    return HiveStore._(
      await Hive.openBox<dynamic>(_settingsBox),
      await Hive.openBox<dynamic>(_sessionsBox),
      await Hive.openBox<dynamic>(_authBox),
    );
  }
}
