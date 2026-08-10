import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

import '../../../../core/error/exceptions.dart';

/// Decodes a raw [CameraImage] from `CameraController.startImageStream`
/// into a `package:image` [img.Image], the same pixel representation the
/// existing capture-flow `DetectionEngine` already consumes.
///
/// Isolated behind this one function so the rest of the live pipeline
/// never touches platform pixel formats directly — mirrors how
/// `live_camera_pipeline/camera_manager.py` isolates `cv2.VideoCapture`
/// from the rest of that pipeline.
///
/// [sensorOrientation] is the camera's `CameraDescription.sensorOrientation`
/// (degrees clockwise the sensor's raw buffer is rotated relative to an
/// upright, portrait-held device — typically 90 on most Android phones).
/// `startImageStream` delivers that raw, un-rotated buffer — unlike
/// `takePicture()`'s JPEG, which carries EXIF orientation that
/// [letterboxResize] already bakes in — so without correcting it here, a
/// real-world upright price label arrives at the model rotated 90°, which
/// tanks detection confidence even though nothing crashes. Assumes the
/// device is held in natural upright portrait (this screen has no
/// landscape layout); revisit if landscape support is added.
img.Image convertCameraImage(CameraImage cameraImage, {int sensorOrientation = 0}) {
  img.Image image;
  switch (cameraImage.format.group) {
    case ImageFormatGroup.yuv420:
      image = _convertYuv420(cameraImage);
      break;
    case ImageFormatGroup.bgra8888:
      image = _convertBgra8888(cameraImage);
      break;
    default:
      throw InferenceException(
        'Unsupported camera image format: ${cameraImage.format.group}',
      );
  }
  return sensorOrientation == 0
      ? image
      : img.copyRotate(image, angle: sensorOrientation);
}

/// Android's `camera` plugin delivers YUV_420_888: a full-resolution Y
/// plane plus half-resolution U and V planes (each plane's `bytesPerRow`
/// may include padding, and `bytesPerPixel` may be 1 or 2 depending on the
/// device, so both are read from the plane rather than assumed).
img.Image _convertYuv420(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;
  final yPlane = cameraImage.planes[0];
  final uPlane = cameraImage.planes[1];
  final vPlane = cameraImage.planes[2];

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  final out = img.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    final yRow = y * yRowStride;
    final uvRow = (y >> 1) * uvRowStride;
    for (var x = 0; x < width; x++) {
      final yValue = yPlane.bytes[yRow + x];
      final uvIndex = uvRow + (x >> 1) * uvPixelStride;
      final uValue = uPlane.bytes[uvIndex];
      final vValue = vPlane.bytes[uvIndex];

      // BT.601 YUV -> RGB.
      final c = yValue - 16;
      final d = uValue - 128;
      final e = vValue - 128;
      final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
      final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
      final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

      out.setPixelRgb(x, y, r, g, b);
    }
  }
  return out;
}

/// iOS delivers a single interleaved BGRA8888 plane.
img.Image _convertBgra8888(CameraImage cameraImage) {
  final plane = cameraImage.planes.first;
  return img.Image.fromBytes(
    width: cameraImage.width,
    height: cameraImage.height,
    bytes: plane.bytes.buffer,
    bytesOffset: plane.bytes.offsetInBytes,
    rowStride: plane.bytesPerRow,
    order: img.ChannelOrder.bgra,
  );
}
