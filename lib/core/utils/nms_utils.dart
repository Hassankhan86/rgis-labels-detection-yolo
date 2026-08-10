/// A plain axis-aligned box in pixel space, independent of any feature layer.
///
/// Kept primitive (no Flutter/Rect dependency) so `core/` never has to import
/// a feature's domain layer just to run detection post-processing.
class Box {
  const Box({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get area => width.clamp(0, double.infinity) * height.clamp(0, double.infinity);
}

double intersectionOverUnion(Box a, Box b) {
  final interLeft = a.left > b.left ? a.left : b.left;
  final interTop = a.top > b.top ? a.top : b.top;
  final interRight = a.right < b.right ? a.right : b.right;
  final interBottom = a.bottom < b.bottom ? a.bottom : b.bottom;

  final interWidth = (interRight - interLeft).clamp(0, double.infinity);
  final interHeight = (interBottom - interTop).clamp(0, double.infinity);
  final interArea = interWidth * interHeight;

  final unionArea = a.area + b.area - interArea;
  if (unionArea <= 0) return 0;
  return interArea / unionArea;
}

/// Greedy, per-class non-maximum suppression.
///
/// Returns the indices (into [boxes]/[scores]/[classIds]) to keep, highest
/// score first.
List<int> nonMaxSuppression({
  required List<Box> boxes,
  required List<double> scores,
  required List<int> classIds,
  required double iouThreshold,
}) {
  assert(boxes.length == scores.length && scores.length == classIds.length);

  final order = List<int>.generate(boxes.length, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));

  final kept = <int>[];
  final suppressed = List<bool>.filled(boxes.length, false);

  for (final i in order) {
    if (suppressed[i]) continue;
    kept.add(i);
    for (final j in order) {
      if (j == i || suppressed[j]) continue;
      if (classIds[j] != classIds[i]) continue;
      if (intersectionOverUnion(boxes[i], boxes[j]) > iouThreshold) {
        suppressed[j] = true;
      }
    }
  }
  return kept;
}