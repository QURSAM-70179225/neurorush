import '../entities/progress_state.dart';

/// Per-player progression stored on the device.
abstract interface class ProgressRepository {
  ProgressState load(String uid);
  Future<void> save(String uid, ProgressState state);
}
