import 'dart:math' as math;

import '../../../../core/utils/nms_utils.dart';

/// Per-raw-track-id trajectory + constant-velocity prediction.
///
/// Direct port of `live_camera_pipeline/track_history.py`'s
/// `TrackHistory` dataclass — same fields, same formulas, so `predict()`
/// extrapolates identically whether driven from a decoded video file or a
/// live camera frame.
class TrackHistory {
  TrackHistory({required this.classId});

  final int classId;
  final List<int> frames = [];
  final List<Box> boxes = [];

  int get startFrame => frames.first;
  int get endFrame => frames.last;

  (double, double) center(int index) {
    final box = boxes[_resolve(index)];
    return ((box.left + box.right) / 2, (box.top + box.bottom) / 2);
  }

  double boxDiagonal(int index) {
    final box = boxes[_resolve(index)];
    final w = box.right - box.left;
    final h = box.bottom - box.top;
    return math.sqrt(w * w + h * h);
  }

  /// Extrapolates this track's own recent velocity to [frameIdx].
  (double, double) predict(int frameIdx, {int lookback = 10}) {
    final n = math.min(lookback, frames.length - 1);
    final (cx1, cy1) = center(-1);
    if (n <= 0) return (cx1, cy1);

    final f0 = frames[frames.length - 1 - n];
    final (cx0, cy0) = center(-1 - n);
    final dframes = frames.last - f0;
    if (dframes == 0) return (cx1, cy1);

    final vx = (cx1 - cx0) / dframes;
    final vy = (cy1 - cy0) / dframes;
    final ahead = frameIdx - endFrame;
    return (cx1 + vx * ahead, cy1 + vy * ahead);
  }

  int _resolve(int index) => index < 0 ? boxes.length + index : index;
}
