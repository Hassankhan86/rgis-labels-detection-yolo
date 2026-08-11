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
  int get inputSize => _inputSize;

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

      // Hardware-accelerated execution providers, tried in order with the
      // plain CPU provider as the guaranteed final fallback (ORT falls back
      // per-node to the next provider in this list for anything the
      // preceding one can't run) — plain CPU alone was measured at ~3.3s of
      // inference time per 960x960 frame on a mid-range Android phone,
      // which is what made live detection feel like it was updating once
      // every several seconds. NNAPI/CoreML are platform-specific (the
      // plugin's iOS side errors on an unrecognized provider name like
      // "NNAPI", so this can't be a single cross-platform list); XNNPACK is
      // a faster CPU kernel implementation available on both.
      final providers = <OrtProvider>[
        if (Platform.isAndroid) OrtProvider.NNAPI,
        if (Platform.isIOS) OrtProvider.CORE_ML,
        OrtProvider.XNNPACK,
        OrtProvider.CPU,
      ];

      final session = await _runtime.createSession(
        modelFile.path,
        options: OrtSessionOptions(intraOpNumThreads: 4, providers: providers),
      );
      _session = session;
      _labels = labels;
      _inputSize = await _detectInputSize(session);

      // Diagnostic only: requesting a provider doesn't guarantee it
      // actually accelerates anything (ORT silently falls back per-node to
      // the next provider in the list for ops it can't run), so this is
      // the only way to see from the device's own log whether NNAPI/
      // XNNPACK are really present here, as opposed to guessing from
      // inference-time measurements alone.
      try {
        final available = await _runtime.getAvailableProviders();
        // ignore: avoid_print
        print('[OnnxDetectionEngine] requested=$providers available=$available');
      } catch (e) {
        // ignore: avoid_print
        print('[OnnxDetectionEngine] getAvailableProviders failed: $e');
      }
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
  }) {
    final letterboxed = letterboxResize(image, _inputSize);
    final inputData = imageToNchwFloat32(letterboxed.image);
    return _runOnTensor(
      inputData: inputData,
      scale: letterboxed.scale,
      padX: letterboxed.padX,
      padY: letterboxed.padY,
      originalWidth: letterboxed.originalWidth,
      originalHeight: letterboxed.originalHeight,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }

  @override
  Future<DetectionFrame> runInferenceOnTensor({
    required Float32List inputData,
    required double scale,
    required int padX,
    required int padY,
    required int originalWidth,
    required int originalHeight,
    required double confidenceThreshold,
    required double iouThreshold,
  }) {
    return _runOnTensor(
      inputData: inputData,
      scale: scale,
      padX: padX,
      padY: padY,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }

  /// Shared by [runInference] (which builds the tensor itself from a decoded
  /// image) and [runInferenceOnTensor] (which takes an already-built one) —
  /// everything from here on out (the actual ONNX Runtime call, decode, and
  /// NMS) is identical either way.
  Future<DetectionFrame> _runOnTensor({
    required Float32List inputData,
    required double scale,
    required int padX,
    required int padY,
    required int originalWidth,
    required int originalHeight,
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    final session = _session;
    if (session == null) {
      throw InferenceException('Model not loaded. Call loadModel() first.');
    }

    final stopwatch = Stopwatch()..start();
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
      scale: scale,
      padX: padX,
      padY: padY,
      originalWidth: originalWidth,
      originalHeight: originalHeight,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
    stopwatch.stop();

    return DetectionFrame(
      detections: detections,
      imageWidth: originalWidth,
      imageHeight: originalHeight,
      inferenceTime: stopwatch.elapsed,
    );
  }

  List<Detection> _decode(
    List<dynamic> rawOutput, {
    required double scale,
    required int padX,
    required int padY,
    required int originalWidth,
    required int originalHeight,
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
      boxes.add(
        unletterboxBox(
          modelSpaceBox,
          scale: scale,
          padX: padX,
          padY: padY,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
        ),
      );
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
