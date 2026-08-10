# RGIS Detector

Flutter app for detecting shelf-edge price labels with a custom YOLO11n
model, entirely on-device (no network calls at inference time). Capture a
photo with the rear camera, the app runs on-device object detection and
draws bounding boxes + confidence over the result, and you can save the
annotated capture to an in-app gallery.

## Status

The app is fully wired and will run and build as-is, **except** it needs
your exported model file, which is not included in this repo (see below).
Until you add it, the camera screen will show a clear "failed to load
model" message instead of crashing.

## Architecture

Clean Architecture, feature-first, with Riverpod for state/DI:

```
lib/
  core/                     # shared kernel: no feature imports this
    constants/              # asset paths, model input size, thresholds
    di/                     # sharedPreferencesProvider (overridden in main())
    error/                  # Failure + Exception types
    router/                 # AppRoutes + onGenerateRoute
    theme/
    utils/                  # letterbox resize, NCHW tensor packing, NMS
  features/
    detection/
      domain/                     # Detection, DetectionFrame, RunDetectionUseCase
      data/
        engines/
          detection_engine.dart          # <- the backend abstraction
          onnx_detection_engine.dart     # ONNX Runtime implementation
          tflite_detection_engine.dart   # unimplemented swap-point stub
        datasources/model_asset_datasource.dart
        repositories/detection_repository_impl.dart
      presentation/
        screens/camera_screen.dart
        widgets/ (overlay painter, capture button, fps indicator)
        providers/ (Riverpod wiring)
    gallery/                 # save/list/delete annotated captures (domain/data/presentation)
    settings/                # confidence + NMS IoU thresholds (domain/data/presentation)
  app.dart                   # MaterialApp + theme + routes
  main.dart                  # bootstraps SharedPreferences, runApp(ProviderScope)
```

### Swapping the inference backend

The UI and use-cases only ever depend on `DetectionRepository`, which wraps
a `DetectionEngine`. To swap ONNX Runtime for TensorFlow Lite:

1. Add `tflite_flutter` to `pubspec.yaml`.
2. Implement `loadModel` / `runInference` / `dispose` in
   `tflite_detection_engine.dart` the same way `onnx_detection_engine.dart`
   does (it already has the right method signatures — it currently just
   throws `UnimplementedError`).
3. In `detection_providers.dart`, change `detectionEngineProvider` to
   construct `TFLiteDetectionEngine()` instead of `OnnxDetectionEngine()`.

Nothing else changes.

## Exporting your model to ONNX

From wherever `yolo11n-best.pt` lives (e.g. the sibling `yolo11/` training
folder in this repo):

```bash
pip install ultralytics
yolo export model=yolo11n-best.pt format=onnx imgsz=640 opset=12
```

This produces a plain (no baked-in NMS) ONNX export with output shape
`[1, 4 + numClasses, numBoxes]` — exactly what `onnx_detection_engine.dart`
decodes. **Do not** pass `nms=True` to `yolo export`; the app does its own
confidence filtering + NMS so it can apply user-adjustable thresholds from
the Settings screen.

Then:

```
mobile_app/assets/models/model.onnx   <- put the exported file here
mobile_app/assets/models/labels.txt   <- already contains "price_label"
```

Both paths are declared as a directory asset in `pubspec.yaml`, so no
pubspec edit is needed — just drop the file in and hot-restart (asset
directory contents require a full restart, not hot reload).

## Running it

```bash
cd mobile_app
flutter pub get
flutter run          # pick an Android device/emulator, or an iOS device/simulator on a Mac
```

### Android

Fully buildable and runnable from this machine as-is — `flutter doctor`
confirmed the Android SDK/toolchain is set up. Camera permission is already
declared in `android/app/src/main/AndroidManifest.xml`.

### iOS

**Requires a Mac with Xcode** — iOS apps cannot be built, run, or tested on
Windows or Linux at all; this is an Apple platform requirement, not a
limitation of this project. On a Mac:

```bash
cd mobile_app
flutter run -d ios
```

Camera usage description is already set in `ios/Runner/Info.plist`. This
project was scaffolded with Flutter's default iOS plugin resolution
(Swift Package Manager, falling back to CocoaPods per-plugin as needed) —
if Xcode prompts for `pod install`, run it from `ios/`.

## Permissions

- **Camera** — requested at runtime via `permission_handler` before the
  camera preview opens; denying it shows a message with a shortcut to the
  app's system settings.
- No storage/photo-library permission is needed — saved captures live in
  the app's own sandboxed documents directory (`captures/`), not the shared
  photo library.

## Settings

Confidence threshold and NMS IoU threshold are adjustable from the
Settings screen and persisted via `shared_preferences`. Both are read by
`OnnxDetectionEngine` on every detection call, so changes apply
immediately to the next capture.

## Notes on scope

- **Capture-then-detect, not live streaming.** The brief's feature list
  ("give prediction when photo is clicked", "Capture button", "Save
  current frame") describes a capture-triggered pipeline, so that's what's
  implemented — not a continuous per-frame video pipeline. The "Display
  FPS" requirement is shown as inference latency + its FPS-equivalent
  (`1000 / inference_ms`) on the review screen, not a live camera frame
  rate.
- **Orientation:** portrait and landscape are both supported (no
  orientation lock in `main.dart`); the camera preview and review screen
  use `AspectRatio` so they reflow with device rotation. EXIF orientation
  on captured photos is baked in before inference (`image_utils.dart`), so
  detections line up regardless of how the phone was held.
