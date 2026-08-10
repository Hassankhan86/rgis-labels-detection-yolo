import '../../../../core/utils/nms_utils.dart';

class _ActiveTrack {
  _ActiveTrack({
    required this.classId,
    required this.lastBox,
  });

  final int classId;
  final Box lastBox;
}

/// Frame-to-frame detection association, filling the same architectural
/// seam `StreamTracker` fills in `live_camera_pipeline/tracker.py` — but
/// with a from-scratch greedy IoU tracker instead of Ultralytics'
/// BoT-SORT, which has no Dart/Flutter port (see this feature's module
/// docs / the plan this was built from). Everything downstream
/// ([IncrementalDuplicateResolver], `LabelCounter`, `BoxSmoother`) is
/// unaware of which tracker produced the id stream, which is exactly why
/// swapping this one piece is safe.
///
/// Trade-off: no Kalman filtering or camera-motion compensation, so a fast
/// pan can produce more id switches than BoT-SORT would. The downstream
/// `IncrementalDuplicateResolver` exists precisely to stitch reacquired
/// ids back together, same as it does for BoT-SORT's own occasional
/// switches.
class SimpleIouTracker {
  SimpleIouTracker({
    this.iouMatchThreshold = 0.3,
    this.maxMissedFrames = 5,
  });

  final double iouMatchThreshold;
  final int maxMissedFrames;

  final Map<int, _ActiveTrack> _tracks = {};
  final Map<int, int> _missed = {};
  int _nextId = 1;

  /// Matches this frame's raw `(box, classId)` detections against active
  /// tracks and returns one tracker id per input detection, in the same
  /// order as [detections].
  List<int> update(List<(Box, int)> detections) {
    final candidatePairs = <(double, int, int)>[]; // (iou, detectionIndex, trackId)
    for (var di = 0; di < detections.length; di++) {
      final (box, classId) = detections[di];
      for (final entry in _tracks.entries) {
        if (entry.value.classId != classId) continue;
        final iou = intersectionOverUnion(box, entry.value.lastBox);
        if (iou >= iouMatchThreshold) {
          candidatePairs.add((iou, di, entry.key));
        }
      }
    }
    candidatePairs.sort((a, b) => b.$1.compareTo(a.$1));

    final assigned = List<int?>.filled(detections.length, null);
    final claimedTracks = <int>{};
    for (final pair in candidatePairs) {
      final di = pair.$2;
      final tid = pair.$3;
      if (assigned[di] != null || claimedTracks.contains(tid)) continue;
      assigned[di] = tid;
      claimedTracks.add(tid);
    }

    for (var di = 0; di < detections.length; di++) {
      final (box, classId) = detections[di];
      final tid = assigned[di] ?? _nextId++;
      assigned[di] = tid;
      _tracks[tid] = _ActiveTrack(classId: classId, lastBox: box);
      _missed[tid] = 0;
    }

    final toRemove = <int>[];
    for (final tid in _tracks.keys) {
      if (claimedTracks.contains(tid)) continue;
      final missed = (_missed[tid] ?? 0) + 1;
      if (missed > maxMissedFrames) {
        toRemove.add(tid);
      } else {
        _missed[tid] = missed;
      }
    }
    for (final tid in toRemove) {
      _tracks.remove(tid);
      _missed.remove(tid);
    }

    return assigned.cast<int>();
  }

  /// Clears all track state. Called once per new session, same as
  /// `StreamTracker.reset()`.
  void reset() {
    _tracks.clear();
    _missed.clear();
    _nextId = 1;
  }
}
