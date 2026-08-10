import 'package:flutter_test/flutter_test.dart';
import 'package:rgis_detector/core/utils/nms_utils.dart';
import 'package:rgis_detector/features/live_tracking/data/tracking/duplicate_resolver.dart';

void main() {
  group('IncrementalDuplicateResolver', () {
    test('merges a same-class track reacquired within gap+distance', () {
      final resolver = IncrementalDuplicateResolver(20, 4.0);

      // tid 1: moves +10px/frame in x across frames 1..3, then disappears.
      resolver.observe(1, 0, const Box(left: 100, top: 100, right: 120, bottom: 120), 1);
      resolver.observe(1, 0, const Box(left: 110, top: 100, right: 130, bottom: 120), 2);
      final canonicalBeforeReappear = resolver.observe(
        1,
        0,
        const Box(left: 120, top: 100, right: 140, bottom: 120),
        3,
      );
      expect(canonicalBeforeReappear, 1);

      // tid 2 appears at frame 8 (gap = 5, well within max_gap=20) exactly
      // where tid 1's own velocity (10px/frame) predicts it should be:
      // center (130,110) + 10*5 = (180, 110).
      final canonical = resolver.observe(
        2,
        0,
        const Box(left: 170, top: 100, right: 190, bottom: 120),
        8,
      );

      expect(canonical, 1, reason: 'tid 2 should be merged into tid 1');
    });

    test('does not merge across a class mismatch', () {
      final resolver = IncrementalDuplicateResolver(20, 4.0);
      resolver.observe(1, 0, const Box(left: 100, top: 100, right: 120, bottom: 120), 1);
      resolver.observe(1, 0, const Box(left: 110, top: 100, right: 130, bottom: 120), 2);
      resolver.observe(1, 0, const Box(left: 120, top: 100, right: 140, bottom: 120), 3);

      // Same predicted position, but a different class -> must not merge.
      final canonical = resolver.observe(
        2,
        1,
        const Box(left: 170, top: 100, right: 190, bottom: 120),
        8,
      );

      expect(canonical, 2);
    });

    test('does not merge once the gap exceeds maxGap', () {
      final resolver = IncrementalDuplicateResolver(5, 4.0);
      resolver.observe(1, 0, const Box(left: 100, top: 100, right: 120, bottom: 120), 1);
      resolver.observe(1, 0, const Box(left: 110, top: 100, right: 130, bottom: 120), 2);
      resolver.observe(1, 0, const Box(left: 120, top: 100, right: 140, bottom: 120), 3);

      // Same predicted position, but the gap (100 frames) is far beyond
      // maxGap=5 -> must not merge.
      final canonical = resolver.observe(
        2,
        0,
        const Box(left: 1130, top: 100, right: 1150, bottom: 120),
        103,
      );

      expect(canonical, 2);
    });
  });
}
