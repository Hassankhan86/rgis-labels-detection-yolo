/// Returned by `stopSession()` — the Dart analogue of the dict
/// `LiveCountingPipeline.stop_session()` returns in
/// `live_camera_pipeline/pipeline.py`.
class SessionSummary {
  const SessionSummary({
    required this.totalUniqueLabels,
    required this.perClass,
    required this.framesProcessed,
  });

  final int totalUniqueLabels;
  final Map<String, int> perClass;
  final int framesProcessed;
}
