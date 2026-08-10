import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local_storage_datasource.dart';
import '../../data/repositories/gallery_repository_impl.dart';
import '../../domain/entities/saved_capture.dart';
import '../../domain/repositories/gallery_repository.dart';

final localStorageDatasourceProvider = Provider<LocalStorageDatasource>((
  ref,
) {
  return const LocalStorageDatasource();
});

final galleryRepositoryProvider = Provider<GalleryRepository>((ref) {
  return GalleryRepositoryImpl(ref.watch(localStorageDatasourceProvider));
});

class GalleryNotifier extends AsyncNotifier<List<SavedCapture>> {
  @override
  Future<List<SavedCapture>> build() {
    return ref.watch(galleryRepositoryProvider).listCaptures();
  }

  Future<void> saveCapture({
    required Uint8List imageBytes,
    required int detectionCount,
  }) async {
    await ref
        .read(galleryRepositoryProvider)
        .saveCapture(imageBytes: imageBytes, detectionCount: detectionCount);
    ref.invalidateSelf();
    await future;
  }

  Future<void> saveLiveSession({
    required Uint8List imageBytes,
    required int totalUniqueLabels,
    required Map<String, int> perClassBreakdown,
    required int framesProcessed,
  }) async {
    await ref
        .read(galleryRepositoryProvider)
        .saveLiveSession(
          imageBytes: imageBytes,
          totalUniqueLabels: totalUniqueLabels,
          perClassBreakdown: perClassBreakdown,
          framesProcessed: framesProcessed,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> deleteCapture(SavedCapture capture) async {
    await ref.read(galleryRepositoryProvider).deleteCapture(capture);
    ref.invalidateSelf();
    await future;
  }
}

final galleryNotifierProvider =
    AsyncNotifierProvider<GalleryNotifier, List<SavedCapture>>(
      GalleryNotifier.new,
    );