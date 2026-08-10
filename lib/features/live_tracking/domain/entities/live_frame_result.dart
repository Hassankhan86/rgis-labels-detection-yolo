import 'tracked_label.dart';

/// Result of processing one live-camera frame through the tracking
/// pipeline. The Dart analogue of what `process_frame()` returns in
/// `live_camera_pipeline/pipeline.py`.
class LiveFrameResult {
  const LiveFrameResult({
    required this.trackedLabels,
    required this.totalUniqueLabels,
    required this.frameIndex,
    required this.frameWidth,
    required this.frameHeight,
    required this.inferenceTime,
  });

  final List<TrackedLabel> trackedLabels;
  final int totalUniqueLabels;
  final int frameIndex;
  final int frameWidth;
  final int frameHeight;
  final Duration inferenceTime;

  double get inferenceFps {
    final micros = inferenceTime.inMicroseconds;
    return micros == 0 ? 0 : 1000000 / micros;
  }
}
