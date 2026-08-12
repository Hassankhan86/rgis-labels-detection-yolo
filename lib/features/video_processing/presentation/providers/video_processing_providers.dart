import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../detection/presentation/providers/detection_providers.dart';
import '../../../gallery/presentation/providers/gallery_providers.dart';
import '../../../live_tracking/presentation/providers/live_tracking_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../data/repositories/video_batch_repository_impl.dart';
import '../../domain/repositories/video_batch_repository.dart';

/// Reuses the same loaded [DetectionEngine] instance and the same
/// [LiveTrackingConfig] tuning constants live mode uses — the model and
/// tracking/counting logic must stay unchanged, including its config.
final videoBatchRepositoryProvider = Provider<VideoBatchRepository>((ref) {
  return VideoBatchRepositoryImpl(
    engine: ref.watch(detectionEngineProvider),
    config: ref.watch(liveTrackingConfigProvider),
    currentSettings: () => ref.read(settingsNotifierProvider),
    galleryRepository: ref.watch(galleryRepositoryProvider),
  );
});
