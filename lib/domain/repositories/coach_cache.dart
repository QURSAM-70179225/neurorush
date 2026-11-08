import '../entities/ai_models.dart';

/// Keeps AI coach tips on the device so they stay visible offline.
abstract interface class CoachTipCache {
  CoachTip? read(String uid, String day);
  Future<void> write(String uid, String day, CoachTip tip);
}
