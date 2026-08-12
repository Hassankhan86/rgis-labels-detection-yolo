import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../detection/presentation/providers/detection_providers.dart';
import '../providers/video_processing_state_provider.dart';
import '../widgets/batch_progress_indicator.dart';
import '../widgets/batch_summary_view.dart';

/// Triggers the batch pipeline on mount and shows its progress, then its
/// result. The actual model+tracking work happens in
/// [VideoProcessingNotifier]/`VideoBatchRepositoryImpl` — this screen only
/// renders whatever state they report.
class VideoProcessingScreen extends ConsumerStatefulWidget {
  const VideoProcessingScreen({super.key, required this.sourceVideoPath});

  final String sourceVideoPath;

  @override
  ConsumerState<VideoProcessingScreen> createState() => _VideoProcessingScreenState();
}

class _VideoProcessingScreenState extends ConsumerState<VideoProcessingScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame so `ref.read` inside `start()` sees a fully-built widget
    // tree, matching the rest of the app's `ref.read`-in-callback style.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoProcessingStateProvider.notifier).start(sourceVideoPath: widget.sourceVideoPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final modelState = ref.watch(modelLoaderProvider);
    final uiState = ref.watch(videoProcessingStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Processing video')),
      body: modelState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) =>
            Center(child: Text('Failed to load model:\n$err', textAlign: TextAlign.center)),
        data: (_) => switch (uiState.phase) {
          VideoProcessingPhase.done => BatchSummaryView(
            outcome: uiState.outcome!,
            onDone: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          VideoProcessingPhase.error => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Processing failed:\n${uiState.error}', textAlign: TextAlign.center),
            ),
          ),
          _ => BatchProgressIndicator(
            phase: uiState.phase,
            current: uiState.current,
            total: uiState.total,
          ),
        },
      ),
    );
  }
}
