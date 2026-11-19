import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/telemetry/telemetry.dart';

/// Overridden in main() with Firebase Analytics when available.
final analyticsProvider = Provider<Analytics>((ref) => const NoopAnalytics());
