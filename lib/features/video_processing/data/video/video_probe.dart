import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

import '../../../../core/error/exceptions.dart';

class VideoProbeResult {
  const VideoProbeResult({
    required this.fps,
    required this.frameCount,
    required this.durationSeconds,
  });

  final double fps;
  final int frameCount;
  final double durationSeconds;
}

/// Isolates the rest of the pipeline from ffmpeg_kit's session/log
/// plumbing, same spirit as `convertCameraImage` isolating camera pixel
/// formats from the rest of the live pipeline.
Future<VideoProbeResult> probeVideo(String path) async {
  final session = await FFprobeKit.getMediaInformation(path);
  final info = session.getMediaInformation();
  if (info == null) {
    throw VideoProbeException('ffprobe returned no media information for $path');
  }
  final videoStreams = info.getStreams().where((s) => s.getType() == 'video');
  if (videoStreams.isEmpty) {
    throw VideoProbeException('No video stream found in $path');
  }
  final videoStream = videoStreams.first;

  final fpsString =
      videoStream.getAverageFrameRate() ?? videoStream.getRealFrameRate() ?? '30/1';
  final fps = _parseFraction(fpsString);
  final durationSeconds = double.tryParse(info.getDuration() ?? '') ?? 0;
  final nbFramesRaw = videoStream.getAllProperties()?['nb_frames'];
  final frameCount =
      int.tryParse('$nbFramesRaw') ?? (fps * durationSeconds).round();

  return VideoProbeResult(
    fps: fps <= 0 ? 30 : fps,
    frameCount: frameCount <= 0 ? 1 : frameCount,
    durationSeconds: durationSeconds,
  );
}

double _parseFraction(String value) {
  final parts = value.split('/');
  if (parts.length != 2) return double.tryParse(value) ?? 30;
  final n = double.tryParse(parts[0]) ?? 30;
  final d = double.tryParse(parts[1]) ?? 1;
  return d == 0 ? 30 : n / d;
}
