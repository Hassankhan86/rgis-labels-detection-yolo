import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/live_tracking_repository_impl.dart';
import '../../domain/entities/live_frame_result.dart';
import '../../domain/entities/session_summary.dart';
import '../../domain/repositories/live_tracking_repository.dart';
import 'live_tracking_providers.dart';

enum LiveSessionPhase { idle, running }

/// UI-facing state for the live camera screen's idle -> running -> summary
/// flow (mirrors the Python pipeline's "Option 1": idle preview, Start,
/// live overlay, Stop, summary, back to idle).
class LiveUiState {
  const LiveUiState({
    this.phase = LiveSessionPhase.idle,
    this.lastResult,
    this.lastSummary,
    this.error,
  });

  final LiveSessionPhase phase;
  final LiveFrameResult? lastResult;
  final SessionSummary? lastSummary;
  final String? error;

  LiveUiState copyWith({
    LiveSessionPhase? phase,
    LiveFrameResult? lastResult,
    SessionSummary? lastSummary,
    String? error,
    bool clearError = false,
    bool clearSummary = false,
  }) {
    return LiveUiState(
      phase: phase ?? this.phase,
      lastResult: lastResult ?? this.lastResult,
      lastSummary: clearSummary ? null : (lastSummary ?? this.lastSummary),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LiveTrackingNotifier extends StateNotifier<LiveUiState> {
  LiveTrackingNotifier(this._repository) : super(const LiveUiState());

  final LiveTrackingRepository _repository;
  bool _busy = false;

  void startSession({required int sensorOrientation}) {
    _repository.startSession(sensorOrientation: sensorOrientation);
    state = const LiveUiState(phase: LiveSessionPhase.running);
  }

  /// Called from the camera image-stream callback. Drops this frame if the
  /// previous one is still being processed, so inference cadence is
  /// bounded by how fast the model actually runs rather than the raw
  /// camera frame rate.
  Future<void> processFrame(CameraImage cameraImage) async {
    if (state.phase != LiveSessionPhase.running || _busy) return;
    _busy = true;
    try {
      final result = await _repository.processFrame(cameraImage);
      if (state.phase == LiveSessionPhase.running) {
        state = state.copyWith(lastResult: result, clearError: true);
      }
    } on SessionStoppedException {
      // Benign race: the user tapped Stop while this frame was still being
      // processed. The session already ended cleanly, so there's nothing
      // to surface to the UI.
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      _busy = false;
    }
  }

  SessionSummary stopSession() {
    final summary = _repository.stopSession();
    state = LiveUiState(phase: LiveSessionPhase.idle, lastSummary: summary);
    return summary;
  }

  void dismissSummary() {
    state = state.copyWith(clearSummary: true);
  }
}

final liveTrackingStateProvider =
    StateNotifierProvider<LiveTrackingNotifier, LiveUiState>((ref) {
      return LiveTrackingNotifier(ref.watch(liveTrackingRepositoryProvider));
    });
