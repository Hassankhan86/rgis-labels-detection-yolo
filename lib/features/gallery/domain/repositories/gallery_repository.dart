import 'dart:typed_data';

import '../entities/saved_capture.dart';

abstract class GalleryRepository {
  Future<SavedCapture> saveCapture({
    required Uint8List imageBytes,
    required int detectionCount,
  });

  Future<SavedCapture> saveLiveSession({
    required Uint8List imageBytes,
    required int totalUniqueLabels,
    required Map<String, int> perClassBreakdown,
    required int framesProcessed,
  });

  /// Unlike [saveCapture]/[saveLiveSession], takes a file path rather than
  /// in-memory bytes — a batch-processed video can be far larger than a
  /// photo or GIF, so it's copied on disk instead of being fully
  /// materialized in RAM first.
  Future<SavedCapture> saveRecordedVideo({
    required String videoFilePath,
    String? thumbnailFilePath,
    required int totalUniqueLabels,
    required Map<String, int> perClassBreakdown,
    required int framesProcessed,
    double? processingDurationSeconds,
    double? videoDurationSeconds,
  });

  Future<List<SavedCapture>> listCaptures();

  Future<void> deleteCapture(SavedCapture capture);
}