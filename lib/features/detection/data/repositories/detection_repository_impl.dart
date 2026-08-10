// ignore_for_file: prefer_initializing_formals -- public param names
// (engine/datasource) are kept readable at call sites; the leading
// underscore below is only an internal field-naming convention.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../../core/error/exceptions.dart';
import '../../domain/entities/detection_result.dart';
import '../../domain/repositories/detection_repository.dart';
import '../datasources/model_asset_datasource.dart';
import '../engines/detection_engine.dart';

class DetectionRepositoryImpl implements DetectionRepository {
  DetectionRepositoryImpl({
    required DetectionEngine engine,
    required ModelAssetDatasource datasource,
  }) : _engine = engine,
       _datasource = datasource;

  final DetectionEngine _engine;
  final ModelAssetDatasource _datasource;

  @override
  bool get isModelLoaded => _engine.isLoaded;

  @override
  String get backendName => _engine.backendName;

  @override
  Future<void> loadModel() async {
    final modelBytes = await _datasource.loadModelBytes();
    final labels = await _datasource.loadLabels();
    await _engine.loadModel(modelBytes: modelBytes, labels: labels);
  }

  @override
  Future<DetectionFrame> detect(
    Uint8List imageBytes, {
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw InferenceException('Could not decode captured image.');
    }
    return _engine.runInference(
      image,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }
}