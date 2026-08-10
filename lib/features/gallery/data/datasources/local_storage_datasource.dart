import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/saved_capture.dart';

/// Persists captures as PNG files under the app's documents directory, with
/// a small JSON index file (id, path, timestamp, detection count) alongside
/// them — no database dependency needed for a gallery this size.
class LocalStorageDatasource {
  const LocalStorageDatasource();

  Future<Directory> _capturesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, AppConstants.capturesDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile() async {
    final dir = await _capturesDir();
    return File(p.join(dir.path, AppConstants.capturesIndexFileName));
  }

  Future<List<SavedCapture>> readIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedCapture.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw StorageException('Could not read captures index: $e');
    }
  }

  Future<void> _writeIndex(List<SavedCapture> captures) async {
    final file = await _indexFile();
    final raw = jsonEncode(captures.map((c) => c.toJson()).toList());
    await file.writeAsString(raw);
  }

  Future<SavedCapture> saveCapture({
    required Uint8List imageBytes,
    required int detectionCount,
  }) async {
    final dir = await _capturesDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final imagePath = p.join(dir.path, '$id.png');
    try {
      await File(imagePath).writeAsBytes(imageBytes);
    } catch (e) {
      throw StorageException('Could not write capture image: $e');
    }

    final capture = SavedCapture(
      id: id,
      imagePath: imagePath,
      timestamp: DateTime.now(),
      detectionCount: detectionCount,
    );

    final captures = await readIndex();
    captures.insert(0, capture);
    await _writeIndex(captures);
    return capture;
  }

  /// [imageBytes] is an animated GIF (camera + boxes + HUD, one frame per
  /// processed detection result — see `LiveCameraScreen._captureGifFrame`),
  /// not a still image; `Image.file`/`Image.memory` autoplay GIFs, so the
  /// gallery and detail screens need no special handling to play it back.
  Future<SavedCapture> saveLiveSession({
    required Uint8List imageBytes,
    required int totalUniqueLabels,
    required Map<String, int> perClassBreakdown,
    required int framesProcessed,
  }) async {
    final dir = await _capturesDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final imagePath = p.join(dir.path, '$id.gif');
    try {
      await File(imagePath).writeAsBytes(imageBytes);
    } catch (e) {
      throw StorageException('Could not write session video: $e');
    }

    final capture = SavedCapture(
      id: id,
      imagePath: imagePath,
      timestamp: DateTime.now(),
      detectionCount: totalUniqueLabels,
      source: CaptureSource.liveSession,
      perClassBreakdown: perClassBreakdown,
      framesProcessed: framesProcessed,
    );

    final captures = await readIndex();
    captures.insert(0, capture);
    await _writeIndex(captures);
    return capture;
  }

  Future<void> deleteCapture(SavedCapture capture) async {
    final file = File(capture.imagePath);
    if (await file.exists()) {
      await file.delete();
    }
    final captures = await readIndex();
    captures.removeWhere((c) => c.id == capture.id);
    await _writeIndex(captures);
  }
}