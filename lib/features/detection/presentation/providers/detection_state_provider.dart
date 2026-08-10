import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/entities/detection_result.dart';
import 'detection_providers.dart';

/// UI-facing state for the capture → detect → review flow on the camera
/// screen. `null` fields mean "no capture yet" (still showing the live
/// preview).
class DetectionUiState {
  const DetectionUiState({
    this.imageBytes,
    this.frame,
    this.isProcessing = false,
    this.error,
  });

  final Uint8List? imageBytes;
  final DetectionFrame? frame;
  final bool isProcessing;
  final String? error;

  DetectionUiState copyWith({
    Uint8List? imageBytes,
    DetectionFrame? frame,
    bool? isProcessing,
    String? error,
    bool clearError = false,
  }) {
    return DetectionUiState(
      imageBytes: imageBytes ?? this.imageBytes,
      frame: frame ?? this.frame,
      isProcessing: isProcessing ?? this.isProcessing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DetectionNotifier extends StateNotifier<DetectionUiState> {
  DetectionNotifier(this._ref) : super(const DetectionUiState());

  final Ref _ref;

  Future<void> processCapture(Uint8List imageBytes) async {
    state = DetectionUiState(imageBytes: imageBytes, isProcessing: true);
    try {
      final useCase = _ref.read(runDetectionUseCaseProvider);
      final settings = _ref.read(settingsNotifierProvider);
      final frame = await useCase(
        imageBytes,
        confidenceThreshold: settings.confidenceThreshold,
        iouThreshold: settings.iouThreshold,
      );
      state = state.copyWith(frame: frame, isProcessing: false);
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
    }
  }

  /// Discards the current capture/result and returns to the live preview.
  void reset() {
    state = const DetectionUiState();
  }
}

final detectionStateProvider =
    StateNotifierProvider<DetectionNotifier, DetectionUiState>((ref) {
      return DetectionNotifier(ref);
    });