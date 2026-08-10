import 'package:camera/camera.dart';

import '../entities/live_frame_result.dart';
import '../entities/session_summary.dart';

/// Domain-facing contract for a live-camera tracking session. The same
/// three-call shape `live_camera_pipeline/pipeline.py`'s README calls out
/// as the durable boundary: `startSession()` / `processFrame()` /
/// `stopSession()`.
abstract class LiveTrackingRepository {
  bool get isSessionActive;

  /// Resets all per-session state (tracker, duplicate resolver, counter,
  /// smoother) so a new session never inherits ids from a previous one.
  ///
  /// [sensorOrientation] is the active camera's
  /// `CameraDescription.sensorOrientation`, used to rotate each raw camera
  /// frame upright before inference (see `camera_image_converter.dart`).
  void startSession({required int sensorOrientation});

  /// Runs detection -> tracking -> duplicate resolution -> counting ->
  /// smoothing on one live camera frame. Must be called within an active
  /// session.
  Future<LiveFrameResult> processFrame(CameraImage cameraImage);

  /// Ends the session and returns its summary.
  SessionSummary stopSession();
}
