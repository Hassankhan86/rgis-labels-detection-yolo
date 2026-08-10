import 'dart:typed_data';

import '../entities/detection_result.dart';
import '../repositories/detection_repository.dart';

/// Runs detection on a captured photo through whichever [DetectionRepository]
/// is wired up.
class RunDetectionUseCase {
  const RunDetectionUseCase(this._repository);

  final DetectionRepository _repository;

  Future<DetectionFrame> call(
    Uint8List imageBytes, {
    required double confidenceThreshold,
    required double iouThreshold,
  }) {
    return _repository.detect(
      imageBytes,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }
}