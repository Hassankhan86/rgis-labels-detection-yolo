import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/saved_capture.dart';

/// Decodes just the first frame of a GIF and re-encodes it as a standalone
/// PNG — top-level so it can run via [compute] on a background isolate
/// (still real decode/encode work, just for one frame instead of the whole
/// session). Returns `null` if [gifBytes] doesn't decode as a GIF.
Uint8List? _decodeFirstGifFrameAsPng(Uint8List gifBytes) {
  final frame = img.GifDecoder().decode(gifBytes, frame: 0);
  if (frame == null) return null;
  return img.encodePng(frame);
}

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
  /// [LiveCameraScreen._gifCaptureTimer] tick) — `Image.file`/`Image.memory`
  /// autoplay animated GIFs, so the detail screen needs no special handling
  /// to play it back, but the gallery grid needs a static
  /// [SavedCapture.thumbnailPath] instead (see its doc comment) or every
  /// saved session would play at once in the grid.
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

    String? thumbnailPath;
    try {
      final thumbBytes = await compute(_decodeFirstGifFrameAsPng, imageBytes);
      if (thumbBytes != null) {
        final path = p.join(dir.path, '${id}_thumb.png');
        await File(path).writeAsBytes(thumbBytes);
        thumbnailPath = path;
      }
    } catch (_) {
      // Thumbnail is a nice-to-have; grid items fall back to the GIF
      // itself (autoplaying) if this fails, same as before it existed.
    }

    final capture = SavedCapture(
      id: id,
      imagePath: imagePath,
      thumbnailPath: thumbnailPath,
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
    final thumbnailPath = capture.thumbnailPath;
    if (thumbnailPath != null) {
      final thumbnailFile = File(thumbnailPath);
      if (await thumbnailFile.exists()) {
        await thumbnailFile.delete();
      }
    }
    final captures = await readIndex();
    captures.removeWhere((c) => c.id == capture.id);
    await _writeIndex(captures);
  }
}