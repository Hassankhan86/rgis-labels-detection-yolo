import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/image_utils.dart';
import '../../../../core/utils/nms_utils.dart';
import '../../domain/entities/detection_result.dart';
import 'detection_engine.dart';

/// [DetectionEngine] backed by `package:flutter_onnxruntime`, which wraps the
/// official `com.microsoft.onnxruntime:onnxruntime-android` / iOS ONNX
/// Runtime Mobile binaries — unlike some community ONNX plugins, these cover
/// every ABI (arm64-v8a, armeabi-v7a, x86, x86_64), so it also runs on the
/// standard x86_64 Android emulator, not just physical ARM devices.
///
/// Expects a stock Ultralytics export (`yolo export model=... format=onnx
/// imgsz=960`, i.e. *without* `nms=True`): output tensor shape
/// `[1, 4 + numClasses, numBoxes]`, box coordinates as `cx, cy, w, h` in
/// model-input pixel space, followed by one raw class-score row per class
/// (no separate objectness row — that's the YOLOv8/YOLO11 head layout).
class OnnxDetectionEngine implements DetectionEngine {
  final OnnxRuntime _runtime = OnnxRuntime();
  OrtSession? _session;
  List<String> _labels = const [];

  /// Square side the model actually expects, read from the ONNX file's own
  /// declared input shape at load time (falls back to
  /// [AppConstants.modelInputSize] if that can't be determined) — this way
  /// the app adapts to whatever `imgsz` the model was exported with (640,
  /// 960, 1280, ...) instead of assuming one fixed size.
  int _inputSize = AppConstants.modelInputSize;

  @override
  bool get isLoaded => _session != null;

  @override
  String get backendName => 'ONNX Runtime';

  @override
  Future<void> loadModel({
    required Uint8List modelBytes,
    required List<String> labels,
  }) async {
    try {
      // This backend's session API takes a file path rather than raw bytes,
      // so spill the asset bytes to a temp file once at startup.
      final tempDir = await getTemporaryDirectory();
      final modelFile = File('${tempDir.path}/rgis_model.onnx');
      await modelFile.writeAsBytes(modelBytes, flush: true);

      final session = await _runtime.createSession(
        modelFile.path,
        options: OrtSessionOptions(intraOpNumThreads: 2),
      );
      _session = session;
      _labels = labels;
      _inputSize = await _detectInputSize(session);
    } catch (e) {
      throw ModelLoadException('Failed to load ONNX model: $e');
    }
  }

  /// Reads the declared shape of the model's first input (NCHW: `[batch,
  /// channels, height, width]`) and returns its height, assuming a square
  /// input as Ultralytics exports by default. Any quirk in the plugin's
  /// shape reporting falls back to [AppConstants.modelInputSize].
  Future<int> _detectInputSize(OrtSession session) async {
    try {
      final inputInfo = await session.getInputInfo();
      if (inputInfo.isEmpty) return AppConstants.modelInputSize;

      final shape = (inputInfo.first['shape'] as List?)
          ?.map((d) => d is num ? d.toInt() : int.tryParse('$d') ?? -1)
          .toList();
      if (shape == null || shape.length != 4) return AppConstants.modelInputSize;

      final height = shape[2];
      return height > 0 ? height : AppConstants.modelInputSize;
    } catch (_) {
      return AppConstants.modelInputSize;
    }
  }

  @override
  Future<DetectionFrame> runInference(
    img.Image image, {
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    final session = _session;
    if (session == null) {
      throw InferenceException('Model not loaded. Call loadModel() first.');
    }

    final stopwatch = Stopwatch()..start();
    final letterboxed = letterboxResize(image, _inputSize);
    final inputData = imageToNchwFloat32(letterboxed.image);
    final inputShape = [1, 3, _inputSize, _inputSize];

    final inputTensor = await OrtValue.fromList(inputData, inputShape);
    Map<String, OrtValue> outputs;
    try {
      outputs = await session.run({session.inputNames.first: inputTensor});
    } catch (e) {
      throw InferenceException('ONNX Runtime inference failed: $e');
    } finally {
      await inputTensor.dispose();
    }

    if (outputs.isEmpty) {
      throw InferenceException('Model produced no output.');
    }
    final rawOutput = await outputs[session.outputNames.first]!.asList();
    for (final output in outputs.values) {
      await output.dispose();
    }

    final detections = _decode(
      rawOutput,
      letterboxed,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
    stopwatch.stop();

    return DetectionFrame(
      detections: detections,
      imageWidth: letterboxed.originalWidth,
      imageHeight: letterboxed.originalHeight,
      inferenceTime: stopwatch.elapsed,
    );
  }

  List<Detection> _decode(
    List<dynamic> rawOutput,
    LetterboxResult letterboxed, {
    required double confidenceThreshold,
    required double iouThreshold,
  }) {
    // Shape [1, 4 + numClasses, numBoxes].
    final batch = rawOutput;
    final channels = batch[0] as List;
    final numClasses = channels.length - 4;
    final numBoxes = (channels[0] as List).length;

    final boxes = <Box>[];
    final scores = <double>[];
    final classIds = <int>[];

    for (var i = 0; i < numBoxes; i++) {
      var bestClass = 0;
      var bestScore = double.negativeInfinity;
      for (var c = 0; c < numClasses; c++) {
        final score = (channels[4 + c][i] as num).toDouble();
        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
        }
      }
      if (bestScore < confidenceThreshold) continue;

      final cx = (channels[0][i] as num).toDouble();
      final cy = (channels[1][i] as num).toDouble();
      final w = (channels[2][i] as num).toDouble();
      final h = (channels[3][i] as num).toDouble();

      final modelSpaceBox = Box(
        left: cx - w / 2,
        top: cy - h / 2,
        right: cx + w / 2,
        bottom: cy + h / 2,
      );
      boxes.add(unletterboxBox(modelSpaceBox, letterboxed));
      scores.add(bestScore);
      classIds.add(bestClass);
    }

    final keep = nonMaxSuppression(
      boxes: boxes,
      scores: scores,
      classIds: classIds,
      iouThreshold: iouThreshold,
    );

    return keep.map((i) {
      final label = classIds[i] < _labels.length
          ? _labels[classIds[i]]
          : 'class_${classIds[i]}';
      return Detection(
        box: boxes[i],
        classId: classIds[i],
        label: label,
        confidence: scores[i],
      );
    }).toList();
  }

  @override
  void dispose() {
    _session?.close();
    _session = null;
  }
}
