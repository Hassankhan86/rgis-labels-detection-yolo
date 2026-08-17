# CLAUDE.md

## Project overview

--



This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`RGIS Detector` — a Flutter app that detects shelf-edge price labels with a
custom YOLO11n model, entirely on-device (ONNX Runtime, no network calls at
inference time). Three capture modes off one bottom nav (`lib/home_shell.dart`):
single-photo capture+detect, live camera tracking, and record-then-batch-process
video. A `yolo/` sibling directory holds the (Python) training pipeline for the
bundled model — this is two projects in one repo: the Flutter app and the model
training tooling that feeds it.

## Commands

Run from the repo root unless noted.

```bash
flutter pub get              # install/sync Dart deps after a pubspec.yaml change
flutter analyze              # static analysis (flutter_lints); run after any Dart edit
flutter test                 # run all tests in test/
flutter test test/label_counter_test.dart   # run a single test file
flutter run                  # pick a device/emulator; Android works from this machine
flutter run -d ios           # iOS — requires a Mac with Xcode, cannot build/run on Windows/Linux
```

Model asset (`assets/models/model.onnx`, `assets/models/labels.txt`) is not
committed — see `assets/models/README.md`. Without it, the camera screen shows
a "failed to load model" message instead of crashing; the rest of the app is
still runnable. Asset *directory* contents (a new/changed `model.onnx`) need a
full restart to pick up, not hot reload.

Python side (`yolo/`) uses an embedded venv at `venv314/` (Python 3.14,
already has `ultralytics`, `onnxruntime`, `torch` installed) — invoke scripts
with `venv314/python.exe yolo/<script>.py` or activate it. `yolo/requirements.txt`
lists the pip deps if setting up fresh.

## Architecture (Flutter app)

Clean Architecture, feature-first, with Riverpod for state/DI. Every feature
under `lib/features/<name>/` follows `domain/{entities,repositories,usecases}`
→ `data/{datasources,repositories,...}` → `presentation/{providers,screens,widgets}`.
`lib/core/` is the shared kernel — constants, DI (`sharedPreferencesProvider`,
overridden in `main.dart`), error types, router, theme, and per-pixel image
utils (letterbox resize, NCHW tensor packing, NMS) — and no feature imports
into it in the other direction.

### Features

- **`detection`** — the capture-then-detect flow. `DetectionEngine` (in
  `data/engines/`) is the inference backend abstraction; `OnnxDetectionEngine`
  is the only real implementation, `TfliteDetectionEngine` is an intentionally
  unimplemented swap-point stub. UI/use-cases only ever depend on
  `DetectionRepository`, which wraps whichever engine is bound in
  `detection_providers.dart` — swapping backends means implementing the stub
  and changing one provider, nothing else.
- **`live_tracking`** — continuous camera-stream detection with tracking.
  `SimpleIouTracker` assigns/holds track IDs across frames,
  `IncrementalDuplicateResolver` merges a track that briefly disappears and
  reappears (predicted position + class match) into its earlier canonical ID,
  `LabelCounter` confirms a track as a counted unique label only after
  `minHits` consecutive hits and assigns permanent, never-renumbered display
  IDs, `BoxSmoother` EMA-smooths drawn boxes and "coasts" (keeps drawing the
  last known box) for a few frames after a missed detection. All tuning knobs
  live in `LiveTrackingConfig` (`domain/live_tracking_config.dart`) — it's a
  mobile-retuned port of a desktop pipeline's config, so frame-count-based
  knobs (`mergeMaxGap`, `coastFrames`) are deliberately much smaller than the
  desktop originals since mobile CPU inference only processes ~1-8 of ~30fps.
  Heavy per-frame work (letterbox/pack) runs off the UI isolate
  (`live_frame_preprocessor.dart`) so the camera preview doesn't stutter.
- **`video_processing`** — record a video with **zero inference during
  recording** (the record screen never calls `startImageStream`), then decode
  every frame via `ffmpeg_kit_flutter_new` and run the *same, unmodified*
  detection engine + `live_tracking` tracker/resolver/counter/smoother classes
  over each frame in order, burning boxes in with `package:image` (not
  `Canvas`), re-encoding to mp4, and saving into the gallery. This whole
  feature was designed to reuse `live_tracking`'s tracking logic verbatim —
  never duplicate or fork tracker/resolver/counter/smoother logic here; if it
  needs to change, change it in `live_tracking` and both flows pick it up.
  `videoFrameStep` in `AppSettings` (default 3) skips inference on most
  frames to cut wall-clock time — output video stays full-length/smooth
  because skipped frames still get written, just with `BoxSmoother`'s
  existing "coasting" box instead of a fresh detection.
- **`gallery`** — save/list/delete annotated captures (photos, GIFs, and
  recorded videos) in the app's sandboxed documents directory
  (`captures/`), not the shared photo library. `SavedCapture.source`
  (`CaptureSource` enum) distinguishes capture/liveSession/recordedVideo
  entries sharing the same `imagePath`/`thumbnailPath` fields.
- **`settings`** — confidence threshold, NMS IoU threshold, label display
  options, video frame-step, persisted via `shared_preferences` and read live
  by the detection engine / video batch repository on every call.

### Cross-cutting notes

- `home_shell.dart`'s three tabs are a plain widget swap (`switch`), never an
  `IndexedStack` — every tab that owns a `CameraController` must be the only
  one mounted at a time, since most platforms allow just one open camera
  session. Follow this discipline for any new camera-owning screen.
- `DetectionEngine.runInferenceOnTensor` exists specifically so callers that
  pre-build their own input tensor on a background isolate (live tracking,
  video batch processing) can skip the engine's own letterbox/pack step —
  don't reintroduce a duplicate preprocessing path when adding a new caller.
- The bundled ONNX model has no baked-in NMS (`yolo export` deliberately
  *without* `nms=True`) — `onnx_detection_engine.dart` does its own confidence
  filtering + NMS (`core/utils/nms_utils.dart`) so user-adjustable thresholds
  from Settings apply without re-exporting the model.
- Model input size (`AppConstants.modelInputSize = 960`) is a fallback/
  documentation value only — the engine reads the real input size from the
  loaded ONNX file at load time, so retraining at a different `imgsz` doesn't
  require a Dart change.

## The `yolo/` training pipeline

Trains the 3-class (`small`/`medium`/`large`) detector consumed by the app.
**The numbered scripts at `yolo/*.py` (`1-prepare_dataset.py`,
`2-test_model.py`, `4-push_to_labelstudio.py`, `6-create_balanced_dataset.py`)
are the actual, current pipeline** — `yolo/README.md` documents an earlier,
differently-named `training/{prepare_dataset,train,export}.py` layout that
does not exist in the tree; treat the numbered scripts as ground truth and
the README as directional context (rationale for detect-vs-segment,
imbalance handling, hyperparameter choices) rather than an exact file map.

Key facts worth knowing before touching training:
- Dataset is small (33-43 images) and was heavily class-imbalanced
  (`small` outnumbers `large` ~15x) — oversampling of rare-class images is a
  deliberate step (`6-create_balanced_dataset.py`), not an omission.
- Detection, not segmentation/OBB — `onnx_detection_engine.dart` decodes a
  fixed `[1, 4 + numClasses, numBoxes]` tensor with no mask/angle channel. If
  you ever change the export task, the Dart decode logic must change with it.
- The Label Studio export's polygon label rows are auto-converted to their
  enclosing box by Ultralytics when `task=detect` — don't manually reformat
  `dataset*/labels/*.txt`.
- After exporting a new model, verify the ONNX output shape is
  `[1, 4 + numClasses, numBoxes]` before dropping it into
  `assets/models/model.onnx` — a shape mismatch (e.g. from an
  end-to-end/NMS-baked export) will silently corrupt the Dart decode loop
  rather than error loudly.
- `venv314/`, `yolo/dataset1/`, `yolo/dataset2/`, and `yolo/test_results/` are
  gitignored; `yolo/dataset2_training/` is intentionally tracked (its
  `.gitignore` line is commented out).
