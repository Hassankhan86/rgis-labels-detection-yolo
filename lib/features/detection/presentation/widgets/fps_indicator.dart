import 'package:flutter/material.dart';

import '../../domain/entities/detection_result.dart';

/// Shows inference latency and its frames-per-second equivalent. This
/// pipeline runs once per capture rather than as a continuous stream, so
/// "FPS" here means "how many of these inferences could run per second",
/// not a live camera frame rate.
class FpsIndicator extends StatelessWidget {
  const FpsIndicator({super.key, required this.frame});

  final DetectionFrame frame;

  @override
  Widget build(BuildContext context) {
    final ms = frame.inferenceTime.inMilliseconds;
    final fps = frame.inferenceFps;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$ms ms  •  ${fps.toStringAsFixed(1)} FPS',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}