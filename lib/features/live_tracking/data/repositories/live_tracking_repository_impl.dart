// ignore_for_file: prefer_initializing_formals -- public param names are
// kept readable at call sites; the leading underscore below is only an
// internal field-naming convention.
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../../detection/data/engines/detection_engine.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/live_frame_result.dart';
import '../../domain/entities/session_summary.dart';
import '../../domain/entities/tracked_label.dart';
import '../../domain/live_tracking_config.dart';
import '../../domain/repositories/live_tracking_repository.dart';
import '../camera/live_frame_preprocessor.dart';
import '../tracking/box_smoother.dart';
import '../tracking/duplicate_resolver.dart';
import '../tracking/label_counter.dart';
import '../tracking/simple_iou_tracker.dart';

/// Wires [DetectionEngine] -> [SimpleIouTracker] ->
/// [IncrementalDuplicateResolver] -> [LabelCounter] -> [BoxSmoother] into
/// the same per-frame flow `live_camera_pipeline/pipeline.py`'s
/// `LiveCountingPipeline` runs, live off a Flutter camera image stream
/// instead of a decoded OpenCV frame.
class LiveTrackingRepositoryImpl implements LiveTrackingRepository {
  LiveTrackingRepositoryImpl({
    required DetectionEngine engine,
    required this.config,
    required AppSettings Function() currentSettings,
  }) : _engine = engine,
       _currentSettings = currentSettings;

  final DetectionEngine _engine;
  final LiveTrackingConfig config;
  final AppSettings Function() _currentSettings;

  SimpleIouTracker? _tracker;
  IncrementalDuplicateResolver? _resolver;
  LabelCounter? _counter;
  BoxSmoother? _smoother;

  /// Built up as detections arrive this session (each already carries its
  /// own resolved label from [DetectionEngine]) so the summary can name
  /// classes without needing a separate label-list dependency.
  final Map<int, String> _labelNames = {};

  int _frameIndex = 0;
  bool _active = false;
  int _sensorOrientation = 0;

  /// Bumped on every [startSession]/[stopSession] so an in-flight
  /// [processFrame] that resumes after `await`ing inference can tell its
  /// session was stopped in the meantime (the user tapped Stop while the
  /// last frame was still running) and bail out cleanly instead of hitting
  /// the now-null tracker/resolver/counter/smoother fields.
  int _generation = 0;

  @override
  bool get isSessionActive => _active;

  @override
  void startSession({required int sensorOrientation}) {
    _tracker = SimpleIouTracker(
      iouMatchThreshold: config.iouMatchThreshold,
      maxMissedFrames: config.maxMissedFrames,
    );
    _resolver = IncrementalDuplicateResolver(
      config.mergeMaxGap,
      config.mergeDistanceFactor,
    );
    _counter = LabelCounter(config.minHits);
    _smoother = BoxSmoother(config.smoothAlpha, config.coastFrames);
    _labelNames.clear();
    _frameIndex = 0;
    _sensorOrientation = sensorOrientation;
    _active = true;
    _generation++;
  }

  @override
  Future<LiveFrameResult> processFrame(CameraImage cameraImage) async {
    if (!_active) {
      throw StateError('processFrame() called outside an active session');
    }
    final generation = _generation;
    _frameIndex++;

    final totalStopwatch = Stopwatch()..start();

    // The heavy pixel work (YUV->RGB, rotate, letterbox, NCHW pack) runs on
    // a background isolate via `compute()` so it never blocks the UI
    // isolate that's also rendering the camera preview — doing this
    // synchronously here was what made the preview stutter/drop frames the
    // moment live detection started.
    final preprocessStopwatch = Stopwatch()..start();
    final preprocessed = await compute(
      preprocessLiveFrame,
      LivePreprocessArgs(
        cameraImage: cameraImage,
        sensorOrientation: _sensorOrientation,
        inputSize: _engine.inputSize,
      ),
    );
    preprocessStopwatch.stop();
    if (_generation != generation) {
      throw const SessionStoppedException();
    }

    final settings = _currentSettings();
    final frame = await _engine.runInferenceOnTensor(
      inputData: preprocessed.inputData,
      scale: preprocessed.scale,
      padX: preprocessed.padX,
      padY: preprocessed.padY,
      originalWidth: preprocessed.originalWidth,
      originalHeight: preprocessed.originalHeight,
      confidenceThreshold: settings.confidenceThreshold,
      iouThreshold: settings.iouThreshold,
    );

    if (_generation != generation) {
      throw const SessionStoppedException();
    }

    final trackingStopwatch = Stopwatch()..start();
    final tracker = _tracker!;
    final resolver = _resolver!;
    final counter = _counter!;
    final smoother = _smoother!;

    final detectionPairs = frame.detections
        .map((d) => (d.box, d.classId))
        .toList();
    final trackIds = tracker.update(detectionPairs);

    for (var i = 0; i < frame.detections.length; i++) {
      final detection = frame.detections[i];
      final tid = trackIds[i];
      _labelNames[detection.classId] = detection.label;

      final canonical = resolver.observe(
        tid,
        detection.classId,
        detection.box,
        _frameIndex,
      );
      counter.registerHit(canonical, detection.classId);
      smoother.update(
        canonical,
        detection.classId,
        detection.box,
        detection.confidence,
        _frameIndex,
      );
    }

    final drawables = smoother.drawable(_frameIndex);
    final trackedLabels = drawables
        .map(
          (d) => TrackedLabel(
            canonicalId: d.canonicalId,
            displayId: counter.displayId[d.canonicalId] ?? 0,
            classId: d.classId,
            label: _labelNames[d.classId] ?? 'class_${d.classId}',
            box: d.box,
            confidence: d.confidence,
          ),
        )
        .toList();
    trackingStopwatch.stop();
    totalStopwatch.stop();

    return LiveFrameResult(
      trackedLabels: trackedLabels,
      totalUniqueLabels: counter.total,
      frameIndex: _frameIndex,
      frameWidth: frame.imageWidth,
      frameHeight: frame.imageHeight,
      preprocessTime: preprocessStopwatch.elapsed,
      inferenceTime: frame.inferenceTime,
      trackingTime: trackingStopwatch.elapsed,
      totalTime: totalStopwatch.elapsed,
    );
  }

  @override
  SessionSummary stopSession() {
    if (!_active) {
      throw StateError('stopSession() called with no active session');
    }
    final counter = _counter!;
    final summary = SessionSummary(
      totalUniqueLabels: counter.total,
      perClass: counter.perClass(_labelNames),
      framesProcessed: _frameIndex,
    );
    _active = false;
    _generation++;
    _tracker = null;
    _resolver = null;
    _counter = null;
    _smoother = null;
    return summary;
  }
}

/// Thrown by [LiveTrackingRepositoryImpl.processFrame] when the session was
/// stopped while that frame's inference was still in flight. Callers should
/// treat this as a benign, expected race rather than a real error.
class SessionStoppedException implements Exception {
  const SessionStoppedException();
}
