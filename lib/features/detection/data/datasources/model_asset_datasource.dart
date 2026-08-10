import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';

/// Loads the bundled model weights and label file from Flutter assets.
class ModelAssetDatasource {
  const ModelAssetDatasource();

  Future<Uint8List> loadModelBytes() async {
    try {
      final buffer = await rootBundle.load(AppConstants.modelAssetPath);
      return buffer.buffer.asUint8List(
        buffer.offsetInBytes,
        buffer.lengthInBytes,
      );
    } catch (e) {
      throw ModelLoadException(
        'Could not read ${AppConstants.modelAssetPath}. Export your model to '
        'ONNX and place it at that path (see README.md). Original error: $e',
      );
    }
  }

  Future<List<String>> loadLabels() async {
    try {
      final raw = await rootBundle.loadString(AppConstants.labelsAssetPath);
      return raw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (e) {
      throw ModelLoadException(
        'Could not read ${AppConstants.labelsAssetPath}. Add one class name '
        'per line (see README.md). Original error: $e',
      );
    }
  }
}