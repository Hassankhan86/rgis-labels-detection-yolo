import 'package:flutter/material.dart';

import '../providers/video_processing_state_provider.dart';

class BatchProgressIndicator extends StatelessWidget {
  const BatchProgressIndicator({
    super.key,
    required this.phase,
    required this.current,
    required this.total,
  });

  final VideoProcessingPhase phase;
  final int current;
  final int total;

  String get _phaseLabel => switch (phase) {
    VideoProcessingPhase.extracting => 'Extracting frames',
    VideoProcessingPhase.detecting => 'Detecting & tracking',
    VideoProcessingPhase.encoding => 'Encoding result video',
    VideoProcessingPhase.saving => 'Saving to gallery',
    _ => 'Processing',
  };

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? null : (current / total).clamp(0, 1).toDouble();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_phaseLabel, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction),
            const SizedBox(height: 8),
            if (total > 0) Text('Frame $current / $total'),
          ],
        ),
      ),
    );
  }
}
