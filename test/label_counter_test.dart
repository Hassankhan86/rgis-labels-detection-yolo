import 'package:flutter_test/flutter_test.dart';
import 'package:rgis_detector/features/live_tracking/data/tracking/label_counter.dart';

void main() {
  group('LabelCounter', () {
    test('confirms a track only once it reaches minHits', () {
      final counter = LabelCounter(3);

      var (justConfirmed, displayId) = counter.registerHit(1, 0);
      expect(justConfirmed, false);
      expect(displayId, null);

      (justConfirmed, displayId) = counter.registerHit(1, 0);
      expect(justConfirmed, false);
      expect(displayId, null);
      expect(counter.total, 0);

      (justConfirmed, displayId) = counter.registerHit(1, 0);
      expect(justConfirmed, true);
      expect(displayId, 1);
      expect(counter.total, 1);
    });

    test('display ids are assigned once and never renumbered', () {
      final counter = LabelCounter(1);
      counter.registerHit(1, 0);
      final firstDisplayId = counter.displayId[1];

      // Further hits on the same canonical id must not change its display id.
      for (var i = 0; i < 5; i++) {
        counter.registerHit(1, 0);
      }

      expect(counter.displayId[1], firstDisplayId);
    });

    test('assigns sequential display ids in confirmation order', () {
      final counter = LabelCounter(1);
      counter.registerHit(10, 0);
      counter.registerHit(20, 0);
      counter.registerHit(30, 0);

      expect(counter.displayId[10], 1);
      expect(counter.displayId[20], 2);
      expect(counter.displayId[30], 3);
      expect(counter.total, 3);
    });

    test('perClass breaks down confirmed labels by name', () {
      final counter = LabelCounter(1);
      counter.registerHit(1, 0);
      counter.registerHit(2, 0);
      counter.registerHit(3, 1);

      final counts = counter.perClass({0: 'price_label', 1: 'other'});
      expect(counts, {'price_label': 2, 'other': 1});
    });
  });
}
