# Live Camera Label Counting Pipeline

Live-camera adaptation of [`yolo11/track_and_count.py`](../yolo11/track_and_count.py).
**That file is unchanged** — this is a separate package that reuses the
exact same detection/tracking/counting algorithms, restructured to run
causally, frame by frame, off a camera instead of two passes over a
prerecorded video.

No Flutter/Dart code here — this is the Python pipeline meant to run on
an edge device (a Windows PC today, and later embedded/bridged into the
mobile app; see "Future Android/Flutter integration" below).

## Why this couldn't be a drop-in swap of the video source

`track_and_count.py` is a deliberate **two-pass, offline** algorithm:

1. **Pass 1** tracks the entire video and records each raw BoT-SORT ID's
   full trajectory (`TrackHistory`).
2. **`merge_tracks()`** then runs *once*, globally, using every track's
   *final* start/end frame to decide which raw IDs are really the same
   physical label reacquired under a new ID.
3. **`build_draw_frames()`** smooths and coasts each merged track's boxes
   over its *known, complete* frame range.
4. **Pass 2** re-reads the video and draws the result.

A live camera has no "end of video" — there is no point at which you can
look at a track's *final* end frame before deciding whether to draw it.
So the one necessary change is turning `merge_tracks()` from a single
batch decision into an **incremental, causal** one: the exact same
predicate (same class, predecessor already ended, gap ≤
`merge_max_gap`, predicted position within `merge_distance_factor` box
diagonals, non-overlapping intervals) is evaluated the moment each new
raw track ID first appears, instead of after the fact. `IncrementalDuplicateResolver`
documents why this is mathematically equivalent to the offline pass in
the vast majority of cases, and the one edge case where it can't be (see
its docstring). The EMA smoothing and coasting in `build_draw_frames`
were *already* a forward-only, causal computation — `BoxSmoother` just
runs that same math one frame at a time instead of after the fact.

Nothing about the detection model, BoT-SORT/GMC, the Union-Find merge
predicate, the interval-overlap guard, constant-velocity extrapolation,
EMA smoothing, coasting, or the min-hits confirmation threshold was
redesigned. Only *when* each step runs changed.

## Module map

| File | Role | Mirrors |
|---|---|---|
| `config.py` | `PipelineConfig` — every tuning knob, same defaults as `parse_args()` in the original, plus camera/output/display settings. | `parse_args()` |
| `track_history.py` | `TrackHistory` — per-raw-ID trajectory + constant-velocity `predict()`. Byte-for-byte identical math. | `TrackHistory` |
| `duplicate_resolver.py` | `IncrementalDuplicateResolver` — online Union-Find merge, causal version of the merge predicate. | `merge_tracks()` |
| `counter.py` | `LabelCounter` — min-hits confirmation, running total, per-class breakdown, display-ID assignment. | the counting bookkeeping in `main()` |
| `smoother.py` | `BoxSmoother` — EMA smoothing + coasting, one frame at a time. | `build_draw_frames()` |
| `camera_manager.py` | `CameraManager` — opens/reads a webcam, handles disconnects/empty frames with bounded reconnect retries. | (new — the video source) |
| `detector.py` | `Detector` — loads the YOLO model, resolves `cuda`/`cpu`, falls back to CPU if GPU init fails. | `YOLO(args.model)` |
| `tracker.py` | `StreamTracker` — calls `model.track(persist=..., tracker=..., conf=...)` per frame; owns *when* tracker state resets (once per session) vs. persists (every other frame). | the `model.track(...)` call in the loop |
| `renderer.py` | `Renderer` — draws boxes, track ID, class name, confidence, and the HUD (FPS, total count, frame number, REC indicator). | Pass 2's `cv2.rectangle`/`cv2.putText` calls |
| `session_recorder.py` | `SessionRecorder` — wraps `cv2.VideoWriter` for one record→stop session (Option 1). | the `cv2.VideoWriter` in `main()` |
| `fps_meter.py` | `FPSMeter` — rolling FPS for the HUD. | — |
| `pipeline.py` | `LiveCountingPipeline` — the "Application" class wiring everything together; `process_frame()` is the reusable core, `run_camera_loop()` is the desktop demo harness. | `main()` |
| `main.py` | CLI entry point (argparse + logging setup). | `if __name__ == "__main__"` |
| `errors.py` | `CameraError`, `ModelLoadError`, `TrackerError`. | — |
| `utils.py` | `unique_output_path()` (duplicated intentionally so this package stays self-contained). | `unique_output_path()` |

## How a session works (Option 1 from the brief)

1. Start the app → camera opens → **idle preview** (raw frames, no
   detection/tracking running, to save power/heat on an edge device).
2. Press **`r`** → `start_session()`: fresh `IncrementalDuplicateResolver`,
   `LabelCounter`, `BoxSmoother`; tracker state is reset (`StreamTracker.reset()`)
   so a new session never inherits IDs from a previous one; a new output
   video file is opened. From here every frame runs the full pipeline —
   detect → track → resolve duplicates → count → smooth → draw → write —
   and tracker state is kept alive (`persist=True`) for the rest of the
   session; it is **never** reset mid-session.
3. Press **`s`** → `stop_session()`: video writer is closed, the final
   summary (total unique labels + per-class breakdown) is returned, app
   goes back to idle preview, ready for the next `r`.
4. **`q` / `Esc`** → graceful exit (auto-stops an active session first,
   releases the camera, closes windows).

## Running on Windows

From the `RGIS_Flutter` repo root, using the existing `venv314`
environment (already has `ultralytics`, `opencv-python`, `torch`):

```powershell
& "venv314\Scripts\python.exe" -m live_camera_pipeline.main --camera 0
```

Or activate the venv first:

```powershell
venv314\Scripts\Activate.ps1
python -m live_camera_pipeline.main --camera 0
```

Useful flags (all optional — defaults match `track_and_count.py`'s
counting-related defaults exactly):

```powershell
python -m live_camera_pipeline.main `
  --camera 0 `
  --capture-width 1280 --capture-height 720 `
  --imgsz 480 `
  --conf 0.5 --min-hits 3 `
  --merge-max-gap 150 --merge-distance-factor 4.0 `
  --smooth-alpha 0.5 --coast-frames 10
```

Recordings are saved to `live_camera_pipeline/recordings/` by default
(`--output-dir` to change it).

Run it as a module (`-m live_camera_pipeline.main`), not as a bare
script — the files use package-relative imports (`from .config import
...`) so the package stays self-contained and portable.

## Performance recommendations (target: 20–30 FPS)

- **Model**: already yolo11n (nano) — the right choice for edge/mobile.
  `artifacts/yolo11n-best.onnx` already exists in this repo; ONNX Runtime
  is typically faster than PyTorch on CPU-only Windows/edge boxes. Wiring
  an ONNX/`ultralytics` `.onnx` backend is a drop-in change inside
  `Detector`/`StreamTracker` if PyTorch inference isn't fast enough.
- **`--imgsz`**: lower inference resolution (e.g. 480 or 416 instead of
  the model's default) is the single biggest lever on CPU. Detection
  quality on small labels degrades gracefully down to a point — tune
  against your own footage.
- **GPU**: `Detector` auto-selects CUDA if available and falls back to
  CPU automatically; a discrete/laptop GPU will comfortably clear 20–30
  FPS at this model size.
- **Capture resolution**: `--capture-width/--capture-height` requests a
  lower resolution *from the camera itself* (cheaper than capturing 4K
  and downscaling every frame).
- **Half precision**: on CUDA, `model.model.half()` after `.to(device)`
  roughly doubles throughput on supported GPUs — not enabled by default
  since not all GPUs support it cleanly; worth adding once you know the
  target hardware.
- **Avoid the display**: `cv2.imshow` + `waitKey` cost real time per
  frame. For a true edge deployment (no monitor), drop the `imshow` call
  in `run_camera_loop()` — the pipeline doesn't need it, only the demo
  harness does.
- **I/O off the hot path**: `CameraManager.read()` is currently a
  blocking call on the main thread. If capture I/O ever becomes the
  bottleneck (rare for USB webcams, more likely for network/RTSP
  sources), move it to a producer thread feeding a 1-deep queue so
  inference never waits on frame grabbing.

## Future changes needed for Android/Flutter integration

This package proves the pipeline works live; it is **not** yet something
a shipped Flutter app runs as-is. Two realistic paths, in order of
effort:

1. **Companion Python process, phone-side (Android only)** — Package this
   with [Chaquopy](https://chaquo.com/chaquopy/) so Android runs a real
   Python interpreter in-process. Flutter's `camera` plugin streams
   `CameraImage` frames (YUV420) across a `MethodChannel`/`EventChannel`
   into `LiveCountingPipeline.process_frame()` (it already accepts a
   decoded BGR array — convert YUV420→BGR on the Dart or Kotlin side, or
   inside a small Chaquopy shim), and results (annotated JPEG bytes or
   just the box/count JSON) flow back over the channel to a Flutter
   overlay widget. `start_session()`/`stop_session()` map directly to the
   record/stop buttons. **No path for iOS** (Chaquopy is Android-only).
2. **Fully native, cross-platform (the real long-term answer)** —
   Export the model to TFLite (Android) / Core ML (iOS) — `artifacts/yolo11n-best.onnx`
   already exists as an intermediate step toward TFLite via
   `onnx2tf`/`ai-edge-torch`. Port the *algorithm*, not the framework:
   `TrackHistory`, `IncrementalDuplicateResolver`, `LabelCounter`, and
   `BoxSmoother` in this package are pure, dependency-free Python (just
   dataclasses, `Counter`, arithmetic) — they translate to Dart
   line-for-line with no ML-library dependency, so they could live
   directly in the Flutter app's domain layer, fed by a Dart or
   platform-channel wrapper around TFLite's own tracking output (or a
   small native tracking shim, since BoT-SORT/GMC itself has no
   off-the-shelf Dart or TFLite implementation — that piece would need a
   native Kotlin/Swift or C++ port, or a from-scratch Dart port of
   BoT-SORT if you want to avoid a per-platform native module).
3. Either way, the useful boundary this package already establishes is
   `process_frame(frame) -> annotated_frame, summary` plus
   `start_session()`/`stop_session()` — whatever the mobile bridge ends
   up being, it should preserve that same three-call shape so the
   counting logic (steps 2 above) doesn't need to change again.
