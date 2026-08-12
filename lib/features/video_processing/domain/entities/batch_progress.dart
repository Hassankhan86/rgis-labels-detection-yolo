import 'batch_outcome.dart';

/// Coarse-grained phase of [VideoBatchRepository.processVideo]'s pipeline,
/// in the order they always run.
enum BatchPhase { extracting, detecting, encoding, saving, done }

/// One progress tick. [current]/[total] are phase-local ("frame 120 of
/// 900" while extracting is a different 120/900 than while detecting) —
/// each phase has its own natural unit of work and its own total.
class BatchProgress {
  const BatchProgress({
    required this.phase,
    this.current = 0,
    this.total = 0,
    this.outcome,
  });

  final BatchPhase phase;
  final int current;
  final int total;

  /// Non-null only on the final event, once [phase] is [BatchPhase.done].
  final BatchOutcome? outcome;

  double get fraction => total <= 0 ? 0 : (current / total).clamp(0, 1);
}
