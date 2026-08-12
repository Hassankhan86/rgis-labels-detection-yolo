import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../../../../core/error/exceptions.dart';

class FrameEncodingProgress {
  FrameEncodingProgress._(this.updates, this.done);
  final Stream<int> updates;
  final Future<void> done;
}

/// Re-encodes the annotated frame sequence in [framesDir]
/// (`frame_%06d.png`) into one video at [outputPath], played back at [fps]
/// — the source video's own original frame rate — so the result plays at
/// normal speed regardless of how many frames were processed.
///
/// Encoder: `mpeg4` by default — deliberately not `libx264`, which is only
/// bundled in the GPL-licensed `ffmpeg_kit_flutter_new_gpl` package, not
/// the plain `ffmpeg_kit_flutter_new` this app depends on.
FrameEncodingProgress encodeFrameSequence({
  required String framesDir,
  required String outputPath,
  required double fps,
  String videoCodec = 'mpeg4',
}) {
  final controller = StreamController<int>();
  final completer = Completer<void>();
  final pattern = '$framesDir/frame_%06d.png';
  final command =
      '-hide_banner -y -framerate $fps -i "$pattern" '
      '-c:v $videoCodec -pix_fmt yuv420p -q:v 3 "$outputPath"';

  FFmpegKit.executeAsync(
    command,
    (session) async {
      final returnCode = await session.getReturnCode();
      if (!controller.isClosed) await controller.close();
      if (ReturnCode.isSuccess(returnCode)) {
        completer.complete();
      } else {
        final logs = await session.getAllLogsAsString();
        completer.completeError(
          VideoEncodingException('ffmpeg re-encode failed (rc=$returnCode): $logs'),
        );
      }
    },
    (log) {},
    (statistics) {
      final n = statistics.getVideoFrameNumber();
      if (n > 0 && !controller.isClosed) controller.add(n);
    },
  );

  return FrameEncodingProgress._(controller.stream, completer.future);
}
