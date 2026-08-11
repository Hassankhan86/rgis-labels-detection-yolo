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
    required this.preprocessTime,
    required this.inferenceTime,
    required this.trackingTime,
    required this.totalTime,
  });

  final List<TrackedLabel> trackedLabels;
  final int totalUniqueLabels;
  final int frameIndex;
  final int frameWidth;
  final int frameHeight;

  /// Wall-clock time of the `compute()` round trip that does YUV->RGB
  /// conversion, rotation, letterbox resize, and NCHW packing on a
  /// background isolate (see `LiveTrackingRepositoryImpl.processFrame`).
  final Duration preprocessTime;

  /// Wall-clock time of the ONNX Runtime call plus decode/NMS
  /// (`DetectionEngine.runInferenceOnTensor`).
  final Duration inferenceTime;

  /// Wall-clock time of the tracker -> duplicate-resolver -> counter ->
  /// smoother chain that turns raw detections into [trackedLabels].
  final Duration trackingTime;

  /// Wall-clock time of the whole `processFrame()` call — i.e.
  /// [preprocessTime] + [inferenceTime] + [trackingTime] plus whatever
  /// small overhead falls between them. This is what actually bounds how
  /// often a new frame can be processed, since frames are dropped while
  /// one is in flight (see `LiveTrackingNotifier.processFrame`).
  final Duration totalTime;

  /// Equivalent frames-per-second implied by [totalTime] alone — an
  /// instantaneous, single-frame figure. Prefer
  /// `LiveUiState.measuredFps` where available: that's derived from actual
  /// wall-clock gaps between processed frames as observed by the UI, so it
  /// also reflects any time spent waiting on the camera stream itself
  /// rather than just this one frame's processing cost.
  double get totalFps {
    final micros = totalTime.inMicroseconds;
    return micros == 0 ? 0 : 1000000 / micros;
  }
}
