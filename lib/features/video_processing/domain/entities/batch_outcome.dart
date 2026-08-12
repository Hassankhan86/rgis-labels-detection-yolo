import '../../../gallery/domain/entities/saved_capture.dart';
import '../../../live_tracking/domain/entities/session_summary.dart';

/// Final result of a completed batch run: the same [SessionSummary] shape
/// the live pipeline produces, plus the [SavedCapture] row for the
/// annotated output video now sitting in the gallery.
class BatchOutcome {
  const BatchOutcome({required this.summary, required this.savedCapture});

  final SessionSummary summary;
  final SavedCapture savedCapture;
}
