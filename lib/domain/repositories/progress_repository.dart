import '../entities/progress_state.dart';

abstract interface class ProgressRepository {
  ProgressState load();
  Future<void> save(ProgressState state);
}
