import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/entities/detection_result.dart';
import 'detection_engine.dart';

/// Swap-point for a future TensorFlow Lite backend.
///
/// Intentionally unimplemented: the brief asks for the *seam*
/// ([DetectionEngine]) so a `tflite_flutter`-based implementation can be
/// dropped in later without touching the repository, use-cases, or UI —
/// not for a TFLite runtime today. To activate it: add `tflite_flutter` to
/// pubspec.yaml, implement the three methods below the same way
/// [OnnxDetectionEngine] does, and swap the constructor in
/// `detection_providers.dart`.
class TFLiteDetectionEngine implements DetectionEngine {
  @override
  bool get isLoaded => false;

  @override
  String get backendName => 'TensorFlow Lite (not implemented)';

  @override
  int get inputSize => throw UnimplementedError(
    'TFLiteDetectionEngine is a swap-point stub; implement with '
    'tflite_flutter before use.',
  );

  @override
  Future<void> loadModel({
    required Uint8List modelBytes,
    required List<String> labels,
  }) {
    throw UnimplementedError(
      'TFLiteDetectionEngine is a swap-point stub; implement with '
      'tflite_flutter before use.',
    );
  }

  @override
  Future<DetectionFrame> runInference(
    img.Image image, {
    required double confidenceThreshold,
    required double iouThreshold,
  }) {
    throw UnimplementedError(
      'TFLiteDetectionEngine is a swap-point stub; implement with '
      'tflite_flutter before use.',
    );
  }

  @override
  Future<DetectionFrame> runInferenceOnTensor({
    required Float32List inputData,
    required double scale,
    required int padX,
    required int padY,
    required int originalWidth,
    required int originalHeight,
    required double confidenceThreshold,
    required double iouThreshold,
  }) {
    throw UnimplementedError(
      'TFLiteDetectionEngine is a swap-point stub; implement with '
      'tflite_flutter before use.',
    );
  }

  @override
  void dispose() {}
}