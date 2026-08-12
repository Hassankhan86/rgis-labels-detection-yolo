import 'package:flutter/material.dart';

import '../../../../core/router/app_router.dart';
import '../../domain/entities/batch_outcome.dart';

class BatchSummaryView extends StatelessWidget {
  const BatchSummaryView({super.key, required this.outcome, required this.onDone});

  final BatchOutcome outcome;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final summary = outcome.summary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 12),
            Text('Total unique labels: ${summary.totalUniqueLabels}'),
            Text('Frames processed: ${summary.framesProcessed}'),
            if (summary.perClass.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...summary.perClass.entries.map((e) => Text('${e.key}: ${e.value}')),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pushNamed(AppRoutes.captureDetail, arguments: outcome.savedCapture),
              child: const Text('View in gallery'),
            ),
            TextButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
