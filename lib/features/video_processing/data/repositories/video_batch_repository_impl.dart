import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../core/utils/image_utils.dart';
import '../../../detection/data/engines/detection_engine.dart';
import '../../../gallery/domain/repositories/gallery_repository.dart';
import '../../../live_tracking/data/tracking/box_smoother.dart';
import '../../../live_tracking/data/tracking/duplicate_resolver.dart';
import '../../../live_tracking/data/tracking/label_counter.dart';
import '../../../live_tracking/data/tracking/simple_iou_tracker.dart';
import '../../../live_tracking/domain/entities/session_summary.dart';
import '../../../live_tracking/domain/live_tracking_config.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/batch_outcome.dart';
import '../../domain/entities/batch_progress.dart';
import '../../domain/repositories/video_batch_repository.dart';
import '../video/ffmpeg_frame_extractor.dart';
import '../video/ffmpeg_video_encoder.dart';
import '../video/frame_annotator.dart';
import '../video/video_probe.dart';

class VideoBatchRepositoryImpl implements VideoBatchRepository {
  // Not using initializing formals (`this._engine`, etc.) deliberately:
  // that would rename these public named parameters to their private
  // field names (`_engine:`/`_galleryRepository:`), which callers outside
  // this library couldn't reference. Same pattern as
  // LiveTrackingRepositoryImpl's constructor.
  VideoBatchRepositoryImpl({
    required DetectionEngine engine,
    required this.config,
    required AppSettings Function() currentSettings,
    required GalleryRepository galleryRepository,
  }) : _engine = engine,
       _currentSettings = currentSettings,
       _galleryRepository = galleryRepository;

  final DetectionEngine _engine;
  final LiveTrackingConfig config;
  final AppSettings Function() _currentSettings;
  final GalleryRepository _galleryRepository;

  @override
  Stream<BatchProgress> processVideo({
    required String sourceVideoPath,
    int frameStep = 1,
  }) async* {
    assert(frameStep >= 1, 'frameStep must be >= 1.');

    final tempRoot = await Directory.systemTemp.createTemp('rgis_batch_');
    final extractedDir = Directory(p.join(tempRoot.path, 'extracted'))..createSync();
    final annotatedDir = Directory(p.join(tempRoot.path, 'annotated'))..createSync();

    try {
      // ---- Phase 0: probe (fps + estimated frame count) ----
      final probe = await probeVideo(sourceVideoPath);

      // ---- Phase 1: extraction (ffmpeg -> disk, one file per frame) ----
      final extraction = extractFrames(
        sourceVideoPath: sourceVideoPath,
        outputDir: extractedDir.path,
      );
      await for (final n in extraction.updates) {
        yield BatchProgress(phase: BatchPhase.extracting, current: n, total: probe.frameCount);
      }
      await extraction.done; // rethrows VideoExtractionException on failure

      // ---- Phase 2: sequential per-frame detect -> track -> count ----
      final tracker = SimpleIouTracker(
        iouMatchThreshold: config.iouMatchThreshold,
        maxMissedFrames: config.maxMissedFrames,
      );
      final resolver = IncrementalDuplicateResolver(config.mergeMaxGap, config.mergeDistanceFactor);
      final counter = LabelCounter(config.minHits);
      final smoother = BoxSmoother(config.smoothAlpha, config.coastFrames);
      final labelNames = <int, String>{};
      final settings = _currentSettings();

      final frameFiles = extractedDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)); // frame_000001.png < 000002.png < ...

      String? posterFramePath;
      for (var i = 0; i < frameFiles.length; i++) {
        final frameIndex = i + 1; // matches frame_%06d's 1-based numbering;
        // always increments once per extracted frame (decode failures
        // included), so the gap-based tracking logic below sees the
        // correct elapsed-frame count either way.
        final srcFile = frameFiles[i];
        final decoded = img.decodePng(await srcFile.readAsBytes());
        if (decoded == null) {
          await srcFile.delete();
          continue; // corrupt/unreadable frame — should not happen from a
          // clean ffmpeg PNG sequence; skip rather than abort the run.
        }

        // Only every frameStep-th frame pays for a real inference; the
        // rest just draw BoxSmoother's coasted box (still keyed by the
        // real frameIndex, so its gap math is unaffected by skipping)
        // so the output video stays full-length/smooth without running
        // the model on every single frame.
        if ((frameIndex - 1) % frameStep == 0) {
          final letterboxed = letterboxResize(decoded, _engine.inputSize);
          final inputData = imageToNchwFloat32(letterboxed.image);
          final frame = await _engine.runInferenceOnTensor(
            inputData: inputData,
            scale: letterboxed.scale,
            padX: letterboxed.padX,
            padY: letterboxed.padY,
            originalWidth: letterboxed.originalWidth,
            originalHeight: letterboxed.originalHeight,
            confidenceThreshold: settings.confidenceThreshold,
            iouThreshold: settings.iouThreshold,
          );

          // ---- verbatim reuse of LiveTrackingRepositoryImpl.processFrame's
          // tracker -> resolver -> counter -> smoother sequence, unchanged ----
          final detectionPairs = frame.detections.map((d) => (d.box, d.classId)).toList();
          final trackIds = tracker.update(detectionPairs);
          for (var j = 0; j < frame.detections.length; j++) {
            final detection = frame.detections[j];
            final tid = trackIds[j];
            labelNames[detection.classId] = detection.label;
            final canonical = resolver.observe(tid, detection.classId, detection.box, frameIndex);
            counter.registerHit(canonical, detection.classId);
            smoother.update(canonical, detection.classId, detection.box, detection.confidence, frameIndex);
          }
        }
        final drawables = smoother.drawable(frameIndex);

        annotateFrame(
          frame: decoded,
          drawables: drawables,
          displayIds: counter.displayId,
          labelNames: labelNames,
        );

        final annotatedPath = p.join(annotatedDir.path, p.basename(srcFile.path));
        await File(annotatedPath).writeAsBytes(img.encodePng(decoded));
        if (drawables.isNotEmpty) posterFramePath ??= annotatedPath;

        await srcFile.delete(); // bounds disk usage — the pre-annotation
        // frame is never needed again once its annotated copy is written.

        yield BatchProgress(phase: BatchPhase.detecting, current: frameIndex, total: frameFiles.length);
      }
      posterFramePath ??= frameFiles.isEmpty
          ? null
          : p.join(annotatedDir.path, p.basename(frameFiles.last.path)); // fallback: nothing ever detected

      final summary = SessionSummary(
        totalUniqueLabels: counter.total,
        perClass: counter.perClass(labelNames),
        framesProcessed: frameFiles.length,
      );

      // ---- Phase 3: re-encode annotated frames at the source video's fps ----
      final outputVideoPath = p.join(tempRoot.path, 'output.mp4');
      final encoding = encodeFrameSequence(
        framesDir: annotatedDir.path,
        outputPath: outputVideoPath,
        fps: probe.fps,
      );
      await for (final n in encoding.updates) {
        yield BatchProgress(phase: BatchPhase.encoding, current: n, total: frameFiles.length);
      }
      await encoding.done;

      // ---- Phase 4: persist into the gallery (file-copy, not bytes) ----
      yield const BatchProgress(phase: BatchPhase.saving, current: 0, total: 1);
      String? thumbnailPath;
      if (posterFramePath != null) {
        thumbnailPath = p.join(tempRoot.path, 'poster.png');
        await File(posterFramePath).copy(thumbnailPath);
      }
      final savedCapture = await _galleryRepository.saveRecordedVideo(
        videoFilePath: outputVideoPath,
        thumbnailFilePath: thumbnailPath,
        totalUniqueLabels: summary.totalUniqueLabels,
        perClassBreakdown: summary.perClass,
        framesProcessed: summary.framesProcessed,
      );

      yield BatchProgress(
        phase: BatchPhase.done,
        current: 1,
        total: 1,
        outcome: BatchOutcome(summary: summary, savedCapture: savedCapture),
      );
    } finally {
      // Runs on success AND on early termination from the subscriber
      // cancelling — an `async*` function's `finally` still runs when its
      // stream is cancelled mid-yield.
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    }
  }
}
