import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../../../../core/utils/image_utils.dart';
import 'camera_image_converter.dart';

/// Input to [preprocessLiveFrame], bundled into one object because
/// `compute()` only forwards a single argument to its isolate entry point.
class LivePreprocessArgs {
  const LivePreprocessArgs({
    required this.cameraImage,
    required this.sensorOrientation,
    required this.inputSize,
  });

  final CameraImage cameraImage;
  final int sensorOrientation;
  final int inputSize;
}

/// Output of [preprocessLiveFrame]: the model-ready input tensor plus the
/// letterbox scalars needed to map detections back to the original frame.
/// Deliberately doesn't carry the padded [img.Image] itself (unlike
/// [LetterboxResult]) — that's dead weight once the tensor is built, and
/// isolate messages are copied, so leaving it out keeps the trip back to the
/// UI isolate cheap.
class LivePreprocessResult {
  const LivePreprocessResult({
    required this.inputData,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.originalWidth,
    required this.originalHeight,
  });

  final Float32List inputData;
  final double scale;
  final int padX;
  final int padY;
  final int originalWidth;
  final int originalHeight;
}

/// The full camera-frame -> model-input pipeline (YUV420/BGRA -> RGB,
/// sensor-orientation rotation, letterbox resize, NCHW float32 pack) as one
/// pure function, so [LiveTrackingRepositoryImpl] can dispatch it onto a
/// background isolate via `compute()`.
///
/// This is the CPU-heavy part of each processed frame (a handful of
/// full-image pixel passes at the model's input resolution). Run
/// synchronously on the UI isolate, it stalls Flutter's own frame scheduling
/// for its entire duration, which is what made the camera preview stutter
/// once live detection started; off the UI isolate, the preview keeps
/// rendering smoothly while a frame is being prepared in the background.
LivePreprocessResult preprocessLiveFrame(LivePreprocessArgs args) {
  final image = convertCameraImage(
    args.cameraImage,
    sensorOrientation: args.sensorOrientation,
  );
  final letterboxed = letterboxResize(image, args.inputSize);
  final inputData = imageToNchwFloat32(letterboxed.image);
  return LivePreprocessResult(
    inputData: inputData,
    scale: letterboxed.scale,
    padX: letterboxed.padX,
    padY: letterboxed.padY,
    originalWidth: letterboxed.originalWidth,
    originalHeight: letterboxed.originalHeight,
  );
}
