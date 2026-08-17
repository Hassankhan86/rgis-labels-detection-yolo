import 'dart:typed_data';

import '../../domain/entities/saved_capture.dart';
import '../../domain/repositories/gallery_repository.dart';
import '../datasources/local_storage_datasource.dart';

class GalleryRepositoryImpl implements GalleryRepository {
  const GalleryRepositoryImpl(this._datasource);

  final LocalStorageDatasource _datasource;

  @override
  Future<SavedCapture> saveCapture({
    required Uint8List imageBytes,
    required int detectionCount,
  }) {
    return _datasource.saveCapture(
      imageBytes: imageBytes,
      detectionCount: detectionCount,
    );
  }

  @override
  Future<SavedCapture> saveLiveSession({
    required Uint8List imageBytes,
    required int totalUniqueLabels,
    required Map<String, int> perClassBreakdown,
    required int framesProcessed,
  }) {
    return _datasource.saveLiveSession(
      imageBytes: imageBytes,
      totalUniqueLabels: totalUniqueLabels,
      perClassBreakdown: perClassBreakdown,
      framesProcessed: framesProcessed,
    );
  }

  @override
  Future<SavedCapture> saveRecordedVideo({
    required String videoFilePath,
    String? thumbnailFilePath,
    required int totalUniqueLabels,
    required Map<String, int> perClassBreakdown,
    required int framesProcessed,
    double? processingDurationSeconds,
    double? videoDurationSeconds,
  }) {
    return _datasource.saveRecordedVideo(
      videoFilePath: videoFilePath,
      thumbnailFilePath: thumbnailFilePath,
      totalUniqueLabels: totalUniqueLabels,
      perClassBreakdown: perClassBreakdown,
      framesProcessed: framesProcessed,
      processingDurationSeconds: processingDurationSeconds,
      videoDurationSeconds: videoDurationSeconds,
    );
  }

  @override
  Future<List<SavedCapture>> listCaptures() => _datasource.readIndex();

  @override
  Future<void> deleteCapture(SavedCapture capture) =>
      _datasource.deleteCapture(capture);
}