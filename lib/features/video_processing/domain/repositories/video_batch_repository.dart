import '../entities/batch_progress.dart';

/// Contract for the record-then-process workflow's batch half. Unlike
/// `LiveTrackingRepository`'s start/process/stop trio (driven one frame at
/// a time by a live camera stream), this is one long-running operation
/// over an already-recorded file, modeled as a single stream of progress
/// events ending in a [BatchPhase.done] event that carries the outcome.
abstract class VideoBatchRepository {
  /// Runs extraction -> per-frame detect/track/count -> annotated
  /// re-encode -> gallery save on [sourceVideoPath]. The last event has
  /// `phase: BatchPhase.done` and a non-null `outcome`; the stream errors
  /// if any phase fails.
  ///
  /// [frameStep] selects every Nth extracted frame for detection (1 =
  /// every frame). Only `frameStep == 1` is implemented today — the
  /// parameter exists as a reserved seam for a later configurable
  /// frame-interval option.
  ///
  /// Cancelling the returned stream's subscription stops the pipeline at
  /// its next checkpoint and cleans up temp files.
  Stream<BatchProgress> processVideo({
    required String sourceVideoPath,
    int frameStep = 1,
  });
}
