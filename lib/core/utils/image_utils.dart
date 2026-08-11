import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'nms_utils.dart';

/// Result of [letterboxResize]: the padded square image plus everything
/// needed to map a detection box back to the original image's pixel space.
class LetterboxResult {
  const LetterboxResult({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.originalWidth,
    required this.originalHeight,
  });

  final img.Image image;
  final double scale;
  final int padX;
  final int padY;
  final int originalWidth;
  final int originalHeight;
}

/// Resizes [src] to fit inside a [targetSize]x[targetSize] square while
/// preserving aspect ratio, padding the remainder with mid-gray (114,114,114)
/// — the same convention Ultralytics uses, so a stock YOLO export decodes
/// correctly.
LetterboxResult letterboxResize(img.Image src, int targetSize) {
  // Bake EXIF orientation ourselves first: `copyResize` also bakes it
  // internally, but only after we'd already have computed scale/dimensions
  // from the *unrotated* storage width/height, which would then mismatch a
  // 90°-rotated photo (very common straight out of a phone camera).
  final oriented =
      src.exif.imageIfd.hasOrientation && src.exif.imageIfd.orientation != 1
          ? img.bakeOrientation(src)
          : src;

  final scale = (targetSize / oriented.width < targetSize / oriented.height)
      ? targetSize / oriented.width
      : targetSize / oriented.height;

  final newWidth = (oriented.width * scale).round().clamp(1, targetSize);
  final newHeight = (oriented.height * scale).round().clamp(1, targetSize);

  final resized = img.copyResize(
    oriented,
    width: newWidth,
    height: newHeight,
    interpolation: img.Interpolation.linear,
  );

  final canvas = img.Image(width: targetSize, height: targetSize);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

  final padX = ((targetSize - newWidth) / 2).floor();
  final padY = ((targetSize - newHeight) / 2).floor();
  img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

  return LetterboxResult(
    image: canvas,
    scale: scale,
    padX: padX,
    padY: padY,
    originalWidth: oriented.width,
    originalHeight: oriented.height,
  );
}

/// Converts a letterboxed RGB image into an NCHW `Float32List` (shape
/// `[1, 3, size, size]`), pixel values normalized to `[0, 1]` — the standard
/// input tensor layout for a YOLO ONNX export.
Float32List imageToNchwFloat32(img.Image image) {
  final size = image.width;
  final plane = size * size;
  final data = Float32List(3 * plane);

  var i = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final pixel = image.getPixel(x, y);
      data[i] = pixel.r / 255.0; // R plane
      data[plane + i] = pixel.g / 255.0; // G plane
      data[2 * plane + i] = pixel.b / 255.0; // B plane
      i++;
    }
  }
  return data;
}

/// Maps a box from letterboxed model-input space back to the original
/// image's pixel space, clamping to the image bounds.
///
/// Takes the plain letterbox scalars rather than a [LetterboxResult] so
/// callers that build their input tensor on a background isolate (see the
/// live tracking pipeline) can carry just these across the isolate boundary
/// instead of the padded [img.Image] itself, which is no longer needed once
/// the tensor is built.
Box unletterboxBox(
  Box modelSpaceBox, {
  required double scale,
  required int padX,
  required int padY,
  required int originalWidth,
  required int originalHeight,
}) {
  double toOriginalX(double x) =>
      ((x - padX) / scale).clamp(0, originalWidth.toDouble());
  double toOriginalY(double y) =>
      ((y - padY) / scale).clamp(0, originalHeight.toDouble());

  return Box(
    left: toOriginalX(modelSpaceBox.left),
    top: toOriginalY(modelSpaceBox.top),
    right: toOriginalX(modelSpaceBox.right),
    bottom: toOriginalY(modelSpaceBox.bottom),
  );
}