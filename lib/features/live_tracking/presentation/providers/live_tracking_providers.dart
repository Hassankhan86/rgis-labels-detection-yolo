import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../detection/presentation/providers/detection_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/repositories/live_tracking_repository_impl.dart';
import '../../domain/live_tracking_config.dart';
import '../../domain/repositories/live_tracking_repository.dart';

final liveTrackingConfigProvider = Provider<LiveTrackingConfig>((ref) {
  return const LiveTrackingConfig();
});

/// Reuses the same [DetectionEngine] instance (and its already-loaded
/// model) the capture flow uses, rather than loading the model a second
/// time for live mode.
final liveTrackingRepositoryProvider = Provider<LiveTrackingRepository>((
  ref,
) {
  return LiveTrackingRepositoryImpl(
    engine: ref.watch(detectionEngineProvider),
    config: ref.watch(liveTrackingConfigProvider),
    currentSettings: () => ref.read(settingsNotifierProvider),
  );
});
