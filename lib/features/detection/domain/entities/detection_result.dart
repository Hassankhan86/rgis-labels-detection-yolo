import '../../../../core/utils/nms_utils.dart';

/// A single detected object, in the coordinate space of the image it was
/// detected in (i.e. the original captured photo, not the model's input).
class Detection {
  const Detection({
    required this.box,
    required this.classId,
    required this.label,
    required this.confidence,
  });

  final Box box;
  final int classId;
  final String label;
  final double confidence;
}

/// The result of running the [DetectionEngine] once on a captured photo.
class DetectionFrame {
  const DetectionFrame({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.inferenceTime,
  });

  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;
  final Duration inferenceTime;

  /// Inference speed expressed as an equivalent frames-per-second, purely as
  /// an intuitive readout — this pipeline runs once per capture, not as a
  /// continuous stream.
  double get inferenceFps {
    final micros = inferenceTime.inMicroseconds;
    return micros == 0 ? 0 : 1000000 / micros;
  }

  factory DetectionFrame.empty({int imageWidth = 0, int imageHeight = 0}) {
    return DetectionFrame(
      detections: const [],
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      inferenceTime: Duration.zero,
    );
  }
}