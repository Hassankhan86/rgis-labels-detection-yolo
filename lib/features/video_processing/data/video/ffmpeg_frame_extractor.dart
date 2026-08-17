import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../../../../core/error/exceptions.dart';

class FrameExtractionResult {
  const FrameExtractionResult(this.frameCount);
  final int frameCount;
}

/// Bundles a live progress `Stream<int>` (one event per ffmpeg statistics
/// tick) with a `Future` that resolves once the ffmpeg session itself
/// finishes, so the repository can `await for` the former and then `await`
/// the latter inside its own `async*` method without managing a separate
/// `StreamController` lifecycle itself.
class FrameExtractionProgress {
  FrameExtractionProgress._(this.updates, this.done);
  final Stream<int> updates;
  final Future<FrameExtractionResult> done;
}

/// Extracts every frame of [sourceVideoPath] into [outputDir] as
/// `frame_000001.png`, `frame_000002.png`, ... (zero-padded to 6 digits so
/// filename order always matches chronological order — the ordering the
/// processing loop relies on).
///
/// Streams frames to disk one at a time via ffmpeg's own native pipeline
/// (`-vsync 0`: one output file per input frame) rather than decoding the
/// whole video into memory first, so the source video is never fully
/// resident in memory during extraction.
///
/// Downscales to fit within 960x960 (ffmpeg's own SIMD-accelerated scaler,
/// not Dart) if the source is larger -- this is the model's own working
/// resolution anyway (`AppConstants.modelInputSize`), so it costs nothing
/// detection-wise, but it matters a lot for wall-clock time: every frame
/// gets decoded and re-encoded as PNG in pure Dart later in the pipeline
/// (`img.decodePng`/`img.encodePng`), unconditionally on every frame
/// regardless of `frameStep` or which model is loaded -- extracting at full
/// phone-camera resolution (e.g. 1080p+) made that Dart-side codec work the
/// actual bottleneck, not model inference. `force_divisible_by=2` keeps
/// dimensions even, which `-pix_fmt yuv420p` in the re-encode step requires.
FrameExtractionProgress extractFrames({
  required String sourceVideoPath,
  required String outputDir,
}) {
  final controller = StreamController<int>();
  final completer = Completer<FrameExtractionResult>();
  final pattern = '$outputDir/frame_%06d.png';
  const scaleFilter =
      "scale='min(960,iw)':'min(960,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2";
  final command =
      '-hide_banner -y -i "$sourceVideoPath" -vf "$scaleFilter" -vsync 0 "$pattern"';

  FFmpegKit.executeAsync(
    command,
    (session) async {
      final returnCode = await session.getReturnCode();
      if (!controller.isClosed) await controller.close();
      if (ReturnCode.isSuccess(returnCode)) {
        final count = await Directory(outputDir)
            .list()
            .where((e) => e is File && e.path.endsWith('.png'))
            .length;
        completer.complete(FrameExtractionResult(count));
      } else {
        final logs = await session.getAllLogsAsString();
        completer.completeError(
          VideoExtractionException('ffmpeg extraction failed (rc=$returnCode): $logs'),
        );
      }
    },
    (log) {},
    (statistics) {
      final n = statistics.getVideoFrameNumber();
      if (n > 0 && !controller.isClosed) controller.add(n);
    },
  );

  return FrameExtractionProgress._(controller.stream, completer.future);
}
