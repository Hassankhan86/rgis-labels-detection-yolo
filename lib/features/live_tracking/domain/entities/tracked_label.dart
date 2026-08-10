import '../../../../core/utils/nms_utils.dart';

/// One tracked, on-screen price label in the current live session, already
/// resolved to its canonical (post-merge) identity.
class TrackedLabel {
  const TrackedLabel({
    required this.canonicalId,
    required this.displayId,
    required this.classId,
    required this.label,
    required this.box,
    required this.confidence,
  });

  /// Internal merged-track id (Union-Find root). Stable for this session,
  /// but not meant for display.
  final int canonicalId;

  /// The 1..N id shown to the user, assigned the moment this track is first
  /// confirmed (see `LabelCounter`). Never changes or gets renumbered once
  /// assigned.
  final int displayId;

  final int classId;
  final String label;
  final Box box;
  final double confidence;
}
