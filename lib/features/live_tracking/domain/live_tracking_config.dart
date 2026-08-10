/// Tuning knobs for the live tracking pipeline. Mirrors
/// `live_camera_pipeline/config.py`'s counting-related fields, but retuned
/// for a mobile, inference-bound processed-frame cadence (likely 1-8fps on
/// CPU) rather than the desktop pipeline's every-frame-of-30fps-video
/// cadence -- the Python defaults (`merge_max_gap=150`, `coast_frames=10`)
/// are frame *counts*, so at a much lower processed-fps they'd correspond
/// to a much longer wall-clock window than intended.
class LiveTrackingConfig {
  const LiveTrackingConfig({
    this.minHits = 3,
    this.mergeMaxGap = 20,
    this.mergeDistanceFactor = 4.0,
    this.smoothAlpha = 0.5,
    this.coastFrames = 3,
    this.iouMatchThreshold = 0.3,
    this.maxMissedFrames = 5,
  });

  /// Frames a canonical track needs before it counts as a confirmed unique
  /// label.
  final int minHits;

  /// Max frame gap between a track ending and a same-class candidate
  /// starting for them to be considered the same reacquired label.
  final int mergeMaxGap;

  /// Merge distance threshold, as a multiple of box diagonal.
  final double mergeDistanceFactor;

  /// EMA smoothing factor for drawn boxes (higher = more responsive, less
  /// smooth).
  final double smoothAlpha;

  /// How many frames a track keeps drawing its last known box after a
  /// missed detection before it's dropped.
  final int coastFrames;

  /// Minimum IoU for `SimpleIouTracker` to associate a detection with an
  /// existing track.
  final double iouMatchThreshold;

  /// How many consecutive unmatched frames `SimpleIouTracker` tolerates
  /// before dropping a track (its analogue of BoT-SORT's track buffer).
  final int maxMissedFrames;
}
