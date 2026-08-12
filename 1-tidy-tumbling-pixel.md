# Record-Then-Batch-Process Video Mode

## Context

The live tracking feature currently drops most camera frames (only ~1-8 of ~30fps actually get processed, per a busy-guard in `LiveTrackingNotifier.processFrame`). The user wants a second mode: record a video with **no inference at all during recording** (smooth, uninterrupted capture), then after stopping, decode the saved video and run the **existing, unmodified** detection model + tracker + counter on every frame in order, showing progress, then save an annotated result video into the app's in-app gallery for review. This trades real-time feedback for completeness — every frame gets processed instead of most being dropped.

Hard constraint from the user: the trained detection model and the tracking (`SimpleIouTracker`/`IncrementalDuplicateResolver`/`LabelCounter`/`BoxSmoother`) logic must not change — only the frame *source* and orchestration timing change, from a live camera stream to a decoded video file.

## Architecture overview

A new sibling feature, `lib/features/video_processing/`, follows the same `domain/{entities,repositories}` → `data/{video,repositories}` → `presentation/{providers,screens,widgets}` layout as `live_tracking`/`gallery`/`detection`. It **imports `live_tracking`'s tracking classes and `LiveTrackingConfig` unchanged** and calls into `gallery`'s repository to persist its result via file-copy (not bytes-in-memory, since a video can be large).

Two new screens: one **3rd tab** in `HomeShell` (record-only, no `CameraController` streaming) and one **pushed route** (processing progress → results). This follows `home_shell.dart`'s existing documented discipline: screens owning a `CameraController` must be mutually exclusive tabs in a widget-swap (not `IndexedStack`), never simultaneously mounted.

**Video decode/encode**: no such package exists in this project today. Added dependency: **`ffmpeg_kit_flutter_new: ^4.6.2`** — the actively maintained fork of the retired `arthenica/ffmpeg-kit` (original binaries pulled April 2025; confirmed via live web search, not stale memory). Frames are extracted to PNG files on disk (streamed by ffmpeg natively, never loading the whole video into memory) and re-encoded the same way. Also added: **`video_player: ^2.14.0`** (official Flutter team package, for reviewing the saved video in the gallery detail screen — none exists today).

**Encoder decision (confirmed with user)**: use `mpeg4` (bundled in the plain non-GPL `ffmpeg_kit_flutter_new`), not `libx264`. Verify Android playback works during implementation; iOS playback is explicitly unverified (no Mac/Xcode in this environment) and flagged as a follow-up risk, not blocking.

**Recording**: `camera: ^0.12.0+2` (already a dependency) already exposes `CameraController.startVideoRecording()`/`stopVideoRecording()` — no new dependency needed for recording itself. The record screen never calls `startImageStream`/touches `DetectionEngine`, so "no inference during recording" is structural, not just policy.

---

## 1. New files

### Domain
- **`lib/features/video_processing/domain/entities/batch_progress.dart`** — `enum BatchPhase { extracting, detecting, encoding, saving, done }` + `BatchProgress{phase, current, total, outcome}` with `fraction` getter.
- **`lib/features/video_processing/domain/entities/batch_outcome.dart`** — `BatchOutcome{summary: SessionSummary, savedCapture: SavedCapture}` (reuses existing `SessionSummary` from `live_tracking` and `SavedCapture` from `gallery` unchanged).
- **`lib/features/video_processing/domain/repositories/video_batch_repository.dart`** — `abstract class VideoBatchRepository { Stream<BatchProgress> processVideo({required String sourceVideoPath, int frameStep = 1}); }`. `frameStep` is a reserved seam for later — only `frameStep == 1` (every frame) is implemented now, per the user's explicit "start with every frame; configurable later."

### Data — video helpers (all new, no existing precedent)
- **`lib/features/video_processing/data/video/video_probe.dart`** — wraps `FFprobeKit.getMediaInformation()` to get source fps + frame count (for re-encode timing and progress denominator). `probeVideo(String path) -> Future<VideoProbeResult{fps, frameCount, durationSeconds}>`.
- **`lib/features/video_processing/data/video/ffmpeg_frame_extractor.dart`** — `extractFrames({required sourceVideoPath, required outputDir}) -> FrameExtractionProgress{Stream<int> updates, Future<FrameExtractionResult> done}`. Runs `ffmpeg -i <src> -vsync 0 <outputDir>/frame_%06d.png`, one file per frame, streamed to disk (not memory). Progress via `Statistics.getVideoFrameNumber()` in the `executeAsync` statistics callback.
- **`lib/features/video_processing/data/video/ffmpeg_video_encoder.dart`** — `encodeFrameSequence({required framesDir, required outputPath, required fps, videoCodec = 'mpeg4'}) -> FrameEncodingProgress`. Runs `ffmpeg -framerate <fps> -i <framesDir>/frame_%06d.png -c:v mpeg4 -pix_fmt yuv420p <outputPath>`.
- **`lib/features/video_processing/data/video/frame_annotator.dart`** — `annotateFrame({required img.Image frame, required List<DrawableTrack> drawables, required Map<int,int> displayIds, required Map<int,String> labelNames}) -> img.Image`. Burns box + `id:N label conf%` label onto the frame in place using `package:image`'s own `drawRect`/`fillRect`/`drawString` (with bundled `img.arial14` bitmap font) — **not** Flutter `Canvas`/`CustomPainter`, since this runs in a plain loop with no widget tree nearby. Verified against the installed `image-4.9.1` source: `drawRect(Image, {x1,y1,x2,y2,color,thickness})`, `drawString(Image, String, {font,x,y,color})`, `arial14`/`arial24` bitmap fonts all confirmed present.

### Data — repository
- **`lib/features/video_processing/data/repositories/video_batch_repository_impl.dart`** — the orchestrator; full algorithm in §2 below. Constructor takes the existing `DetectionEngine`, `LiveTrackingConfig`, an `AppSettings Function()`, and `GalleryRepository` — all reused, none modified.

### Presentation
- **`lib/features/video_processing/presentation/providers/video_processing_providers.dart`** — `videoBatchRepositoryProvider`, wiring `ref.watch(detectionEngineProvider)` (existing, already-loaded model), `ref.watch(liveTrackingConfigProvider)` (existing config, unchanged), `ref.watch(galleryRepositoryProvider)`.
- **`lib/features/video_processing/presentation/providers/video_processing_state_provider.dart`** — `VideoProcessingNotifier extends StateNotifier<VideoProcessingUiState>` with `start({required sourceVideoPath})`, listening to the repository's `Stream<BatchProgress>` and republishing as UI state (mirrors `LiveTrackingNotifier`'s "repository emits raw progress → notifier reshapes for UI" split, but via `Stream.listen` instead of a live per-frame callback). `.autoDispose` so leaving the processing screen cancels the subscription, which via the repository's `try/finally` (§2) triggers temp-file cleanup.
- **`lib/features/video_processing/presentation/screens/video_record_screen.dart`** — record-only screen; owns a `CameraController` with **no** `startImageStream` call; record/stop button calls `startVideoRecording()`/`stopVideoRecording()`; on stop, navigates to the processing route with the recorded file path.
- **`lib/features/video_processing/presentation/screens/video_processing_screen.dart`** — triggers `VideoProcessingNotifier.start()` on mount (post-frame callback), shows `BatchProgressIndicator` while running, `BatchSummaryView` when done, an error view on failure.
- **`lib/features/video_processing/presentation/widgets/batch_progress_indicator.dart`** — "Frame N / Total" + phase label + `LinearProgressIndicator`.
- **`lib/features/video_processing/presentation/widgets/batch_summary_view.dart`** — total unique labels, per-class breakdown, frames processed, "View in gallery" / "Done" buttons (mirrors the existing live-session summary dialog's content).
- **`lib/features/gallery/presentation/widgets/video_preview_player.dart`** — wraps `video_player`'s `VideoPlayerController`/`VideoPlayer`/`VideoProgressIndicator` with a simple tap-to-play/pause UI, used by the modified detail screen (§3).

---

## 2. The batch-processing algorithm (core of `VideoBatchRepositoryImpl.processVideo`)

```
1. Create a temp working dir (Directory.systemTemp.createTemp), with
   extracted/ and annotated/ subdirs. Wrap everything below in try/finally
   that deletes this temp dir recursively — runs on success AND on stream
   cancellation (Dart async* + subscription.cancel() still runs finally).

2. Probe source video (fps, frame count) via ffprobe.

3. EXTRACT: ffmpeg decodes every frame to extracted/frame_NNNNNN.png,
   streamed to disk (ffmpeg's own native pipeline, never the whole video
   in memory). Yield BatchProgress(extracting, current, total) from the
   Statistics callback as it runs.

4. DETECT+TRACK (sequential, one frame at a time — the memory-safety-
   critical loop): construct FRESH SimpleIouTracker/IncrementalDuplicate-
   Resolver/LabelCounter/BoxSmoother instances (same construction as
   LiveTrackingRepositoryImpl.startSession(), same config values). List
   and sort extracted frame files by filename (chronological, since
   %06d numbering sorts correctly as strings). For each file, in order:
     a. Read + decode PNG (one frame's bytes in memory at a time).
     b. letterboxResize() + imageToNchwFloat32() — reused unchanged from
        core/utils/image_utils.dart.
     c. engine.runInferenceOnTensor(...) — reused unchanged, same
        OnnxDetectionEngine instance/loaded model the live/capture flows
        already use.
     d. VERBATIM reuse of LiveTrackingRepositoryImpl.processFrame's
        tracking block: tracker.update() -> per-detection
        resolver.observe()/counter.registerHit()/smoother.update() ->
        smoother.drawable(). Same frameIndex semantics (monotonic,
        1-per-frame, no skips) that the tracker/resolver/smoother's
        gap-based logic (coastFrames/maxMissedFrames/mergeMaxGap) depends
        on.
     e. annotateFrame() burns boxes+labels onto the decoded frame; write
        to annotated/frame_NNNNNN.png.
     f. DELETE the now-unneeded source frame file immediately (bounds
        peak disk usage — never holds more than the frames still queued
        plus the one just annotated).
     g. Yield BatchProgress(detecting, frameIndex, totalFrames).

5. ENCODE: ffmpeg re-encodes annotated/*.png into one output.mp4 at the
   SOURCE video's original fps (from step 2's probe), via the mpeg4
   encoder. Yield BatchProgress(encoding, ...) from its Statistics
   callback.

6. SAVE: copy output.mp4 (File.copy(), not bytes-in-memory) into the
   gallery's captures/ directory via a new GalleryRepository.save-
   RecordedVideo() method; copy one annotated frame as a poster
   thumbnail the same way. Yield BatchProgress(saving, ...) then
   BatchProgress(done, outcome: BatchOutcome(summary, savedCapture)).

7. finally: delete the whole temp working dir.
```

Runs entirely on the root isolate (no `compute()`), unlike live mode — there's no live camera preview to protect from stutter here, only a progress bar, and the tracker/resolver/counter/smoother must persist on one isolate across the whole loop anyway. If on-device testing shows the progress UI hangs unacceptably, decode/letterbox/pack and annotate/encode/write can be lifted to `compute()` later, following `live_frame_preprocessor.dart`'s existing pattern as precedent.

---

## 3. Modified files

- **`pubspec.yaml`** — add `video_player: ^2.14.0` and `ffmpeg_kit_flutter_new: ^4.6.2`. No version bumps needed for `camera`/`image`/`path_provider`/`path`. Flutter's default `minSdkVersion` (24) already satisfies ffmpeg_kit's Android requirement — no `build.gradle.kts` change needed.
- **`lib/home_shell.dart`** — add a 3rd `NavigationDestination` ("Record") and a 3rd branch in the widget-swap body (`VideoRecordScreen`), following the file's existing documented single-camera-controller discipline.
- **`lib/core/router/app_router.dart`** — add one route, `AppRoutes.videoProcessing`, taking the recorded file path as a typed string argument (mirrors the existing `captureDetail` typed-argument pattern).
- **`lib/core/error/exceptions.dart`** — add `VideoProbeException`/`VideoExtractionException`/`VideoEncodingException`, matching the file's existing 3-class pattern exactly (verified against current file content).
- **`lib/features/gallery/domain/entities/saved_capture.dart`** — add `CaptureSource.recordedVideo` to the enum; generalize `fromJson`'s current binary ternary (`json['source'] == 'liveSession' ? ... : ...`, confirmed as current code) to `CaptureSource.values.firstWhere((v) => v.name == json['source'], orElse: () => CaptureSource.capture)` so a 3rd value round-trips correctly. No field changes — `imagePath` holds the video path, `thumbnailPath` holds the poster frame, same overloaded-field convention already used for GIFs.
- **`lib/features/gallery/domain/repositories/gallery_repository.dart`** + **`data/repositories/gallery_repository_impl.dart`** + **`data/datasources/local_storage_datasource.dart`** — add `saveRecordedVideo({videoFilePath, thumbnailFilePath?, totalUniqueLabels, perClassBreakdown, framesProcessed})`, implemented with `File.copy()` (not `writeAsBytes` of an in-memory blob, unlike the two existing save methods) — necessary since a video file shouldn't be fully materialized in RAM first.
- **`lib/features/gallery/presentation/screens/capture_detail_screen.dart`** — branch on `capture.source == CaptureSource.recordedVideo` to render the new `VideoPreviewPlayer` instead of `Image.file`.
- **`lib/features/gallery/presentation/widgets/gallery_grid_item.dart`** — render `thumbnailPath ?? imagePath` with an `errorBuilder` fallback icon (guards against `Image.file` trying to decode an `.mp4` if thumbnail generation ever fails), plus the existing video-camera badge extended to also cover `recordedVideo`.
- **No changes**: `simple_iou_tracker.dart`, `duplicate_resolver.dart`, `label_counter.dart`, `box_smoother.dart`, `live_tracking_config.dart`, `onnx_detection_engine.dart`, `detection_engine.dart`, `image_utils.dart`, `nms_utils.dart`, `detection_providers.dart`, `gallery_providers.dart` (the new repository calls `GalleryRepository.saveRecordedVideo` directly rather than through the notifier, since this is a background/automatic save rather than a user-initiated button; the processing notifier just invalidates `galleryNotifierProvider` afterward so the gallery list picks it up).

---

## 4. Verification plan

1. `flutter analyze` after adding dependencies and all new/modified files — catches import/signature drift early.
2. Dependency smoke test: a one-off `FFmpegKit.execute('-version')` / `-encoders` call, checked via `adb logcat`, to confirm native binaries actually linked, **and** to settle exactly which video codec is available (confirm `mpeg4` before relying on it in `ffmpeg_video_encoder.dart`).
3. End-to-end manual pass on the already-working Android emulator setup (Flutter build + install + `adb screencap`/`logcat`, as used earlier in this project):
   - Record ~10-15s on the new "Record" tab — confirm the preview is smooth (nothing streams into Dart during recording).
   - Watch progress advance through extracting → detecting → encoding → saving without long unexplained stalls.
   - Confirm the summary screen's counts look plausible, then confirm `VideoPreviewPlayer` actually plays the saved `.mp4` with visible burned-in annotations.
   - Return to the Gallery tab directly and confirm the new entry appears (exercises the `galleryNotifierProvider` invalidation).
4. Logcat check: no uncaught exceptions; extracted frame count matches the count fed into the detect/track loop; no `VideoExtractionException`/`VideoEncodingException`.
5. Temp-file cleanup check: inspect the app's cache dir after a completed run (should be empty of `rgis_batch_*` dirs), and again after deliberately backing out of the processing screen mid-run (exercises the cancellation → `finally` cleanup path).
6. Regression check: open an existing plain-capture and existing live-session gallery entry afterward to confirm the detail-screen/grid-item diffs didn't break the two pre-existing `CaptureSource` cases.

## 5. Known risks / open items (confirmed with user, not blocking)

- **Encoder**: using `mpeg4` (non-GPL). iOS playback compatibility is unverified — no Mac/Xcode available in this environment. If iOS playback later proves unreliable, the fallback is switching to `ffmpeg_kit_flutter_new_gpl` for `libx264`, which is a licensing decision, not a code change.
- **`ffmpeg_kit_flutter_new`'s exact `MediaInformation`/`StreamInformation` getter names** (`video_probe.dart`) are carried over from the original ffmpeg-kit's documented API on a stated-compatibility assumption — confirm against the actually-installed package source (`<pub-cache>/ffmpeg_kit_flutter_new-*/lib/media_information.dart`) once added, before relying on it.
- **iOS build impact** (CocoaPods install time, IPA size) of adding `ffmpeg_kit_flutter_new` is unmeasured — no `ios/Podfile` has been generated yet in this project.
- Raw (un-annotated) recordings from `stopVideoRecording()` are left at the camera plugin's own temp location after a successful run — not cleaned up in this plan (acceptable for v1, flagged as a follow-up).
