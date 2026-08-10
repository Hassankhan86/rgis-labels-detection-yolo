// Unit tests for the hand-rolled detection post-processing math
// (core/utils/nms_utils.dart), since a mistake there silently produces
// wrong boxes rather than a crash.

import 'package:flutter_test/flutter_test.dart';
import 'package:rgis_detector/core/utils/nms_utils.dart';

void main() {
  group('intersectionOverUnion', () {
    test('identical boxes have IoU 1.0', () {
      const box = Box(left: 0, top: 0, right: 10, bottom: 10);
      expect(intersectionOverUnion(box, box), closeTo(1.0, 1e-9));
    });

    test('disjoint boxes have IoU 0.0', () {
      const a = Box(left: 0, top: 0, right: 10, bottom: 10);
      const b = Box(left: 20, top: 20, right: 30, bottom: 30);
      expect(intersectionOverUnion(a, b), 0.0);
    });

    test('half-overlapping boxes give the expected ratio', () {
      const a = Box(left: 0, top: 0, right: 10, bottom: 10);
      const b = Box(left: 5, top: 0, right: 15, bottom: 10);
      // intersection = 5x10 = 50, union = 100+100-50 = 150
      expect(intersectionOverUnion(a, b), closeTo(50 / 150, 1e-9));
    });
  });

  group('nonMaxSuppression', () {
    test('suppresses the lower-scoring of two overlapping same-class boxes', () {
      final boxes = [
        const Box(left: 0, top: 0, right: 10, bottom: 10),
        const Box(left: 1, top: 1, right: 11, bottom: 11), // heavy overlap
      ];
      final kept = nonMaxSuppression(
        boxes: boxes,
        scores: [0.9, 0.6],
        classIds: [0, 0],
        iouThreshold: 0.5,
      );
      expect(kept, [0]);
    });

    test('keeps both boxes when they belong to different classes', () {
      final boxes = [
        const Box(left: 0, top: 0, right: 10, bottom: 10),
        const Box(left: 1, top: 1, right: 11, bottom: 11),
      ];
      final kept = nonMaxSuppression(
        boxes: boxes,
        scores: [0.9, 0.6],
        classIds: [0, 1],
        iouThreshold: 0.5,
      );
      expect(kept.toSet(), {0, 1});
    });

    test('keeps both boxes when they barely overlap', () {
      final boxes = [
        const Box(left: 0, top: 0, right: 10, bottom: 10),
        const Box(left: 9, top: 9, right: 19, bottom: 19),
      ];
      final kept = nonMaxSuppression(
        boxes: boxes,
        scores: [0.9, 0.8],
        classIds: [0, 0],
        iouThreshold: 0.5,
      );
      expect(kept.toSet(), {0, 1});
    });
  });
}
