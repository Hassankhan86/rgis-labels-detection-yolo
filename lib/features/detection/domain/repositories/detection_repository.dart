import 'dart:typed_data';

import '../entities/detection_result.dart';

/// Domain-facing contract for running detection on a captured photo.
///
/// The presentation layer only ever talks to this interface, never to a
/// concrete inference backend — that indirection is what lets
/// [DetectionEngine] implementations (ONNX today, TFLite later) be swapped
/// without touching UI or use-case code.
abstract class DetectionRepository {
  bool get isModelLoaded;

  /// Name of the active inference backend, for display in Settings.
  String get backendName;

  Future<void> loadModel();

  Future<DetectionFrame> detect(
    Uint8List imageBytes, {
    required double confidenceThreshold,
    required double iouThreshold,
  });
}