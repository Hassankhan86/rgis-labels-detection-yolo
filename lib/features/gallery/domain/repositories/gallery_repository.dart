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

  Future<List<SavedCapture>> listCaptures();

  Future<void> deleteCapture(SavedCapture capture);
}