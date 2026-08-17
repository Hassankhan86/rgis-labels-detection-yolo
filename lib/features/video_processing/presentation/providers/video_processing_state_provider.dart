import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../gallery/presentation/providers/gallery_providers.dart';
import '../../domain/entities/batch_outcome.dart';
import '../../domain/entities/batch_progress.dart';
import '../../domain/repositories/video_batch_repository.dart';
import 'video_processing_providers.dart';

enum VideoProcessingPhase { idle, extracting, detecting, encoding, saving, done, error }

class VideoProcessingUiState {
  const VideoProcessingUiState({
    this.phase = VideoProcessingPhase.idle,
    this.current = 0,
    this.total = 0,
    this.outcome,
    this.error,
  });

  final VideoProcessingPhase phase;
  final int current;
  final int total;
  final BatchOutcome? outcome;
  final String? error;

  double get fraction => total <= 0 ? 0 : (current / total).clamp(0, 1);
}

class VideoProcessingNotifier extends StateNotifier<VideoProcessingUiState> {
  VideoProcessingNotifier(this._repository, this._ref) : super(const VideoProcessingUiState());

  final VideoBatchRepository _repository;
  final Ref _ref;
  StreamSubscription<BatchProgress>? _subscription;

  Future<void> start({required String sourceVideoPath}) async {
    await _subscription?.cancel();
    state = const VideoProcessingUiState(phase: VideoProcessingPhase.extracting);
    final completer = Completer<void>();
    _subscription = _repository.processVideo(sourceVideoPath: sourceVideoPath, frameStep: 3).listen(
      (progress) {
        state = VideoProcessingUiState(
          phase: _mapPhase(progress.phase),
          current: progress.current,
          total: progress.total,
          outcome: progress.outcome,
        );
        if (progress.phase == BatchPhase.done) {
          // The repository already wrote the row via GalleryRepository
          // directly (a background/automatic save, not a user-tapped
          // "Save" button) — invalidate the gallery list so it picks the
          // new entry up.
          _ref.invalidate(galleryNotifierProvider);
          if (!completer.isCompleted) completer.complete();
        }
      },
      onError: (Object e, StackTrace st) {
        state = VideoProcessingUiState(phase: VideoProcessingPhase.error, error: e.toString());
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  VideoProcessingPhase _mapPhase(BatchPhase phase) => switch (phase) {
    BatchPhase.extracting => VideoProcessingPhase.extracting,
    BatchPhase.detecting => VideoProcessingPhase.detecting,
    BatchPhase.encoding => VideoProcessingPhase.encoding,
    BatchPhase.saving => VideoProcessingPhase.saving,
    BatchPhase.done => VideoProcessingPhase.done,
  };

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// `.autoDispose`: leaving the processing screen tears the notifier down,
/// cancelling any still-running stream subscription — which (via the
/// repository's try/finally) is what actually stops the underlying
/// pipeline and triggers its temp-file cleanup if the user backs out
/// mid-run.
final videoProcessingStateProvider =
    StateNotifierProvider.autoDispose<VideoProcessingNotifier, VideoProcessingUiState>((ref) {
      return VideoProcessingNotifier(ref.watch(videoBatchRepositoryProvider), ref);
    });
