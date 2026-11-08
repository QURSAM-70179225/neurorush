import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Opens and exposes the Hive boxes used for offline storage. Values are
/// stored as plain maps so no generated adapters are required.
class HiveStore {
  HiveStore._(this.settings, this.sessions, this.auth, this.progress);

  static const _settingsBox = 'settings';
  static const _sessionsBox = 'game_sessions';
  static const _authBox = 'local_auth';
  static const _progressBox = 'progress';

  final Box<dynamic> settings;
  final Box<dynamic> sessions;
  final Box<dynamic> auth;
  final Box<dynamic> progress;

  static Future<HiveStore> open() async {
    await Hive.initFlutter('neurorush');
    return HiveStore._(
      await Hive.openBox<dynamic>(_settingsBox),
      await Hive.openBox<dynamic>(_sessionsBox),
      await Hive.openBox<dynamic>(_authBox),
      await Hive.openBox<dynamic>(_progressBox),
    );
  }

  /// Opens boxes in [path] without Flutter bindings (used by tests).
  static Future<HiveStore> openAt(String path) async {
    Hive.init(path);
    return HiveStore._(
      await Hive.openBox<dynamic>(_settingsBox),
      await Hive.openBox<dynamic>(_sessionsBox),
      await Hive.openBox<dynamic>(_authBox),
      await Hive.openBox<dynamic>(_progressBox),
    );
  }
}
