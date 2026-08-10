import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/entities/detection_result.dart';

/// Backend-agnostic inference contract.
///
/// This is the seam the project brief calls out: swap [OnnxDetectionEngine]
/// for a TFLite (or any other) implementation without touching the
/// repository, use-cases, or any UI code — they only ever see this
/// interface via [DetectionRepository].
abstract class DetectionEngine {
  bool get isLoaded;

  /// Human-readable backend name, surfaced in Settings.
  String get backendName;

  Future<void> loadModel({
    required Uint8List modelBytes,
    required List<String> labels,
  });

  /// Runs preprocessing + inference + postprocessing (confidence filtering
  /// and NMS) on a single decoded image and returns absolute-pixel
  /// detections in that image's own coordinate space.
  Future<DetectionFrame> runInference(
    img.Image image, {
    required double confidenceThreshold,
    required double iouThreshold,
  });

  void dispose();
}