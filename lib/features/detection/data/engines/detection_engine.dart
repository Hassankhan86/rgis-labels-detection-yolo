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

  /// Square side (pixels) this engine's loaded model expects its input
  /// tensor to be. Callers that pre-letterbox off the UI isolate (see
  /// [runInferenceOnTensor]) need this to letterbox to the right size.
  int get inputSize;

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

  /// Same as [runInference], but skips this engine's own letterbox/NCHW-pack
  /// step in favor of an already-built input tensor and its letterbox
  /// metadata — for callers (the live tracking pipeline) that build the
  /// tensor themselves on a background isolate so that per-pixel work never
  /// blocks the UI isolate that's also driving the camera preview.
  Future<DetectionFrame> runInferenceOnTensor({
    required Float32List inputData,
    required double scale,
    required int padX,
    required int padY,
    required int originalWidth,
    required int originalHeight,
    required double confidenceThreshold,
    required double iouThreshold,
  });

  void dispose();
}