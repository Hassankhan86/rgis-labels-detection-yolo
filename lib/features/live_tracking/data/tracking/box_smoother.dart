import '../../../../core/utils/nms_utils.dart';

class _SmoothState {
  _SmoothState(this.classId, this.box, this.confidence, this.lastFrame);
  final int classId;
  final Box box;
  final double confidence;
  final int lastFrame;
}

/// One confirmed track's smoothed box, ready to draw.
class DrawableTrack {
  const DrawableTrack({
    required this.canonicalId,
    required this.classId,
    required this.box,
    required this.confidence,
  });

  final int canonicalId;
  final int classId;
  final Box box;
  final double confidence;
}

/// Online equivalent of `build_draw_frames()` in `yolo11/track_and_count.py`.
///
/// Direct port of `live_camera_pipeline/smoother.py`'s `BoxSmoother`: folds
/// an exponential moving average over each canonical track's boxes as
/// detections arrive, and "coasts" (keeps drawing the last smoothed box)
/// for up to [coastFrames] frames whenever a detection is briefly missing.
class BoxSmoother {
  BoxSmoother(this.smoothAlpha, this.coastFrames);

  final double smoothAlpha;
  final int coastFrames;

  final Map<int, _SmoothState> _state = {};

  void update(int canonical, int classId, Box box, double confidence, int frameIdx) {
    final prev = _state[canonical];
    Box smoothed;
    if (prev == null) {
      smoothed = box;
    } else {
      final a = smoothAlpha;
      smoothed = Box(
        left: a * box.left + (1 - a) * prev.box.left,
        top: a * box.top + (1 - a) * prev.box.top,
        right: a * box.right + (1 - a) * prev.box.right,
        bottom: a * box.bottom + (1 - a) * prev.box.bottom,
      );
    }
    _state[canonical] = _SmoothState(classId, smoothed, confidence, frameIdx);
  }

  /// Every track that either has a detection this frame or is still within
  /// its coasting window. Prunes tracks that have coasted past their window
  /// so memory doesn't grow across a long session.
  ///
  /// Draws as soon as a track exists rather than waiting for it to cross
  /// [LabelCounter]'s `minHits` confirmation threshold: at this pipeline's
  /// inference-bound, likely-sub-1fps mobile cadence (see
  /// `LiveTrackingConfig`'s doc comment), gating the *visible* box on
  /// several confirmed hits made the live view show nothing for seconds at
  /// a time even while the model was detecting correctly every frame.
  /// Confirmation still gates the *unique label count* (`LabelCounter.total`
  /// / `perClass`), which is what actually needs to be robust to
  /// single-frame noise — the drawn box doesn't.
  List<DrawableTrack> drawable(int frameIdx) {
    final out = <DrawableTrack>[];
    final stale = <int>[];
    for (final entry in _state.entries) {
      final canonical = entry.key;
      final state = entry.value;
      final gap = frameIdx - state.lastFrame;
      if (gap > coastFrames) {
        stale.add(canonical);
        continue;
      }
      out.add(
        DrawableTrack(
          canonicalId: canonical,
          classId: state.classId,
          box: state.box,
          confidence: state.confidence,
        ),
      );
    }
    for (final canonical in stale) {
      _state.remove(canonical);
    }
    return out;
  }
}
