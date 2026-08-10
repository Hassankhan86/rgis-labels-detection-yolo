import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/model_asset_datasource.dart';
import '../../data/engines/detection_engine.dart';
import '../../data/engines/onnx_detection_engine.dart';
import '../../data/repositories/detection_repository_impl.dart';
import '../../domain/repositories/detection_repository.dart';
import '../../domain/usecases/run_detection_usecase.dart';

/// The active inference backend. This is the one line you'd change to swap
/// in `TFLiteDetectionEngine` once it's implemented.
final detectionEngineProvider = Provider<DetectionEngine>((ref) {
  final engine = OnnxDetectionEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final modelAssetDatasourceProvider = Provider<ModelAssetDatasource>((ref) {
  return const ModelAssetDatasource();
});

final detectionRepositoryProvider = Provider<DetectionRepository>((ref) {
  return DetectionRepositoryImpl(
    engine: ref.watch(detectionEngineProvider),
    datasource: ref.watch(modelAssetDatasourceProvider),
  );
});

final runDetectionUseCaseProvider = Provider<RunDetectionUseCase>((ref) {
  return RunDetectionUseCase(ref.watch(detectionRepositoryProvider));
});

/// Loads the model once. The UI watches this to gate the camera screen on
/// readiness and surface load errors (e.g. missing asset files).
final modelLoaderProvider = FutureProvider<void>((ref) async {
  final repository = ref.watch(detectionRepositoryProvider);
  await repository.loadModel();
});