# Speed Up Batch Video Processing

## Context

The record-then-batch-process feature (built previously) works correctly end-to-end, but is too slow: on the user's physical Android phone it took roughly 15+ minutes to process a ~414-frame recording. Code analysis (via two Explore passes over `onnx_detection_engine.dart`, `image_utils.dart`, and the `video_processing` data layer) found the cause: the bundled model runs detection at **960×960** (not 640), and although the app already requests hardware acceleration in priority order (`NNAPI` → `CoreML` → `XNNPACK` → `CPU`, with `intraOpNumThreads: 4`), the observed ~3s/frame matches a code comment's documented "plain-CPU-only" baseline for a 960×960 frame almost exactly. Inference alone accounts for essentially all of the per-frame cost — PNG decode/encode, disk I/O, and drawing are comparatively minor.

Presented with the options this analysis surfaced, the user chose two directions to pursue now:
1. **Frame skipping** — implement the frame-interval knob that was deliberately left as a "configurable later" seam when the feature was first built (`frameStep` parameter, currently asserted to always be `1`).
2. **INT8 quantization** of the already-trained model — same weights, lower numeric precision, no retraining.

Descoped this round (real, but secondary, opportunities — revisit later if these two aren't enough): confirming whether NNAPI/XNNPACK is actually engaging on-device vs silently falling back to CPU, downscaling ffmpeg's frame extraction resolution, swapping the PNG intermediate format for something faster, and isolate-based decode/inference pipelining.

## Part A — Configurable frame-skip during detection

**Design**: keep the *output video* full-length and smooth — every extracted frame is still written to the final `.mp4` — but only run the expensive inference + tracking update on every Nth frame. Skipped frames reuse `BoxSmoother`'s existing "coasting" mechanism (`smoother.drawable(frameIndex)`), which already exists for exactly this situation — it's the same mechanism live tracking relies on when frames get dropped because inference is busy. Net effect: inference calls drop from `frameCount` to `ceil(frameCount / frameStep)`, a direct, proportional cut in the dominant cost, with no change to `SimpleIouTracker`/`IncrementalDuplicateResolver`/`LabelCounter`/`BoxSmoother` internals (same hard constraint as the original feature) and no choppy/fast-forwarded playback.

Key implementation detail: `frameIndex` stays the *real* 1-based extracted-frame number (unchanged from today). That's what makes this correct without touching tracker/smoother internals — gaps between processed detections are expressed in real frame numbers, exactly like a live-tracking busy-drop already is.

### Files to modify

- **`lib/features/video_processing/domain/repositories/video_batch_repository.dart`** — remove the `frameStep == 1` restriction from the interface doc/assert; it's no longer a "reserved, not implemented" seam.
- **`lib/features/video_processing/data/repositories/video_batch_repository_impl.dart`** (the per-frame loop, currently ~lines 88-143) — wrap the block from `letterboxResize(...)` through the tracker/resolver/counter/smoother `update()` calls in `if (i % frameStep == 0) { ... }`. Leave `smoother.drawable(frameIndex)` and everything after it (annotate/write/delete/yield progress) unconditional, exactly as today. Remove the `assert(frameStep == 1, ...)` line.
- **`lib/features/settings/domain/entities/app_settings.dart`** — add `final int videoFrameStep;` + `copyWith` support, defaulting to `3` in `AppSettings.defaults` (mirrors `confidenceThreshold`/`iouThreshold` exactly).
- **`lib/features/settings/data/datasources/settings_local_datasource.dart`** + **`lib/features/settings/data/repositories/settings_repository_impl.dart`** — add get/set + load/save wiring for the new field, same pattern as the existing threshold fields.
- **`lib/features/settings/presentation/providers/settings_providers.dart`** — add `setVideoFrameStep(int value)` to `SettingsNotifier`, same pattern as `setConfidenceThreshold`.
- **`lib/features/settings/presentation/screens/settings_screen.dart`** — add a `Slider` (min 1, max 5, divisions 4) under a new "Video processing" section: "Process every Nth frame: 3 (higher = faster, but boxes may lag slightly between detections)".
- **`lib/features/video_processing/presentation/providers/video_processing_providers.dart`** (or wherever `processVideo(...)` is invoked from the notifier) — pass `frameStep: settings.videoFrameStep` instead of the implicit default of `1`.

## Part B — INT8-quantize the existing trained model

Weights are not retrained — only numeric precision changes. The trained checkpoint (`yolo/yolo11n-best.pt`) and its calibration data (`yolo/dataset2_training/`, `data.yaml`) are already in the repo, and `ultralytics` (8.4.117), `onnxruntime` (1.28.0), and `torch` (2.13.0+cpu) are already installed in the project's embedded Python (`venv314/python.exe`) — no new tooling needed.

Because the calibration/training set is very small (33 images — `yolo/README.md` already flags this as a general accuracy ceiling) and mobile ONNX Runtime builds don't always ship every quantized-op kernel, this is a **gated experiment with an easy rollback**, not a one-way change:

1. **Export**: run Ultralytics' export with `int8=True`, calibrated on `yolo/dataset2_training/data.yaml`, to a *new* file (`yolo/yolo11n-best-int8.onnx`) — never overwrite the existing fp32 export directly.
2. **Shape check**: load the new ONNX with `onnxruntime.InferenceSession` and confirm the output shape is still `[1, 7, N]` (4 box coords + 3 classes, no baked-in NMS) — the same check `yolo/README.md`'s `export.py` workflow already calls out, since a shape mismatch would silently corrupt `onnx_detection_engine.dart`'s decode loop.
3. **Accuracy sanity check**: reuse the existing `yolo/2-test_model.py` (already accepts `--weights <path>`, and Ultralytics' `YOLO()` loader accepts `.onnx` paths directly) to run both the fp32 and int8 exports over `yolo/dataset2_training/valid/images` and compare per-image detection counts/confidences side by side. Flag it clearly if int8 is missing detections the fp32 model catches.
4. **Swap in + on-device timing**: back up the current `assets/models/model.onnx` (copy alongside as `model_fp32_backup.onnx`, excluded from the asset bundle), copy the validated int8 export over `assets/models/model.onnx`, hot-restart (asset changes need a full restart per `yolo/README.md`), and time the "Detecting & tracking" phase on a same-length test recording, before vs. after.
5. **Rollback path**: if on-device inference throws (missing quantized-op kernel in the mobile ORT build) or timing doesn't actually improve, restore the backed-up fp32 `model.onnx`. No Dart code changes are needed either way — the engine already reads input size/shape from the ONNX file at load time.

## Verification

- `flutter analyze` after the Part A code changes.
- On-device timing comparison: record a same-length test video before/after, compare wall-clock time for the "Detecting & tracking" phase and the "Frame N/Total" pacing.
- Confirm tracking/counting output (unique label count, per-class breakdown) stays sane with `videoFrameStep > 1` — not necessarily identical to `frameStep=1` (fewer fresh detections shifts exactly when `LabelCounter.minHits` gets satisfied), but not wildly different.
- For Part B, the shape + accuracy checks in steps 2-3 are the correctness gate before the bundled asset is ever touched; step 4's on-device timing is the actual go/no-go for keeping it.
