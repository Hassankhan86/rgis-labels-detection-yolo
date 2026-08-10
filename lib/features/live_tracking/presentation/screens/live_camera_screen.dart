import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/app_router.dart';
import '../../../detection/presentation/providers/detection_providers.dart';
import '../../../gallery/presentation/providers/gallery_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/entities/session_summary.dart';
import '../providers/live_tracking_state_provider.dart';
import '../widgets/live_hud.dart';
import '../widgets/live_overlay_painter.dart';

/// Idle preview -> Start -> live detection+tracking overlay -> Stop ->
/// summary -> back to idle. Mirrors the Python pipeline's "Option 1"
/// session model (see `live_camera_pipeline/README.md`).
///
/// Owns its own [CameraController], separate from the capture flow's
/// `CameraScreen` — `HomeShell` only ever mounts one of the two screens at
/// a time (a plain widget swap, not an `IndexedStack`) specifically so two
/// `CameraController`s never try to hold the physical camera open at once.
class LiveCameraScreen extends ConsumerStatefulWidget {
  const LiveCameraScreen({super.key});

  @override
  ConsumerState<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends ConsumerState<LiveCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _permissionError;
  bool _streaming = false;
  final GlobalKey _captureBoundaryKey = GlobalKey();

  /// Accumulates one frame (camera + boxes + HUD, exactly what's on screen)
  /// per processed detection result for the whole session, so Save produces
  /// an animated GIF of the session rather than a single still image. Fresh
  /// per session (created in [_start], finished in [_stop]).
  img.GifEncoder? _gifEncoder;
  bool _capturingGifFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _permissionError =
            'Camera permission is required for live detection.';
      });
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(
        () => _permissionError = 'No camera available on this device.',
      );
      return;
    }
    final rearCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      rearCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (appState == AppLifecycleState.inactive ||
        appState == AppLifecycleState.paused) {
      _endSessionIfRunning();
      controller.dispose();
      _controller = null;
    } else if (appState == AppLifecycleState.resumed) {
      setState(() => _initializeFuture = _initCamera());
    }
  }

  void _endSessionIfRunning() {
    if (ref.read(liveTrackingStateProvider).phase ==
        LiveSessionPhase.running) {
      if (_streaming) {
        _controller?.stopImageStream();
        _streaming = false;
      }
      ref.read(liveTrackingStateProvider.notifier).stopSession();
      _gifEncoder = null;
    }
  }

  Future<void> _start() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    ref
        .read(liveTrackingStateProvider.notifier)
        .startSession(sensorOrientation: controller.description.sensorOrientation);
    _gifEncoder = img.GifEncoder(delay: 150, repeat: 0);
    await controller.startImageStream((CameraImage image) {
      ref.read(liveTrackingStateProvider.notifier).processFrame(image);
    });
    _streaming = true;
  }

  /// Renders whatever's currently in the capture boundary (camera + boxes +
  /// HUD — exactly what's on screen, since the boundary sits above the
  /// preview and below the Start/Stop button, see [_buildBody]) into the
  /// session's GIF as one more frame. Downscaled before encoding since GIF
  /// quantization cost scales with pixel count and a session can accumulate
  /// many frames.
  Future<void> _captureGifFrame() async {
    final encoder = _gifEncoder;
    if (encoder == null || _capturingGifFrame) return;
    _capturingGifFrame = true;
    try {
      final boundary =
          _captureBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final uiImage = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return;
      var frame = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: byteData.buffer,
        order: img.ChannelOrder.rgba,
      );
      if (frame.width > 480) {
        frame = img.copyResize(frame, width: 480);
      }
      encoder.addFrame(frame);
    } finally {
      _capturingGifFrame = false;
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    if (_streaming && controller != null) {
      await controller.stopImageStream();
      _streaming = false;
    }

    // One more frame *before* stopping the session: stopping clears
    // `lastResult` (so the overlay's boxes disappear on the very next
    // rebuild), so capturing after would miss the last result's boxes.
    await _captureGifFrame();
    final gifBytes = _gifEncoder?.finish();
    _gifEncoder = null;

    final summary = ref.read(liveTrackingStateProvider.notifier).stopSession();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Session summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total unique labels: ${summary.totalUniqueLabels}'),
            Text('Frames processed: ${summary.framesProcessed}'),
            if (summary.perClass.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...summary.perClass.entries.map(
                (e) => Text('${e.key}: ${e.value}'),
              ),
            ],
          ],
        ),
        actions: [
          if (gifBytes != null)
            TextButton(
              onPressed: () => _saveSession(dialogContext, gifBytes, summary),
              child: const Text('Save'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSession(
    BuildContext dialogContext,
    Uint8List gifBytes,
    SessionSummary summary,
  ) async {
    await ref
        .read(galleryNotifierProvider.notifier)
        .saveLiveSession(
          imageBytes: gifBytes,
          totalUniqueLabels: summary.totalUniqueLabels,
          perClassBreakdown: summary.perClass,
          framesProcessed: summary.framesProcessed,
        );
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved to gallery')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_streaming) {
      _controller?.stopImageStream();
    }
    if (ref.read(liveTrackingStateProvider).phase ==
        LiveSessionPhase.running) {
      try {
        ref.read(liveTrackingStateProvider.notifier).stopSession();
      } catch (_) {
        // Best-effort cleanup on dispose; nothing left to show a UI error to.
      }
    }
    _controller?.dispose();
    _gifEncoder = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelState = ref.watch(modelLoaderProvider);
    final liveState = ref.watch(liveTrackingStateProvider);

    // Add one GIF frame per processed detection result, so the saved
    // animation reflects our real (inference-bound) cadence rather than
    // sampling on a separate timer.
    ref.listen<LiveUiState>(liveTrackingStateProvider, (previous, next) {
      if (next.phase == LiveSessionPhase.running &&
          next.lastResult != null &&
          !identical(next.lastResult, previous?.lastResult)) {
        _captureGifFrame();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Detection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.gallery),
          ),
        ],
      ),
      body: modelState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load model:\n$err',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (_) => _buildBody(liveState),
      ),
    );
  }

  Widget _buildBody(LiveUiState liveState) {
    final settings = ref.watch(settingsNotifierProvider);

    if (_permissionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_permissionError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('Open app settings'),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        final result = liveState.lastResult;

        // CameraController.value.aspectRatio is always reported in the
        // sensor's landscape orientation (width > height), regardless of
        // the device's current orientation. Used as-is in a portrait
        // layout it produces a short, wide box with large empty gaps above
        // and below; inverting it in portrait makes the preview fill the
        // available space correctly.
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final previewAspectRatio = isPortrait
            ? 1 / controller.value.aspectRatio
            : controller.value.aspectRatio;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Everything a saved GIF frame should show (camera + boxes +
            // HUD) lives inside this boundary; the error banner and
            // Start/Stop button are siblings outside it so they never end
            // up baked into a saved session.
            RepaintBoundary(
              key: _captureBoundaryKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: previewAspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(controller),
                          if (result != null)
                            CustomPaint(
                              painter: LiveOverlayPainter(
                                trackedLabels: result.trackedLabels,
                                frameWidth: result.frameWidth,
                                frameHeight: result.frameHeight,
                                showLabels: settings.showLabels,
                                minimizeLabels: settings.minimizeLabels,
                                showConfidence: settings.showConfidence,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: LiveHud(result: result),
                  ),
                ],
              ),
            ),
            if (liveState.error != null)
              Positioned(
                top: 16,
                right: 16,
                left: 130,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    liveState.error!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: liveState.phase == LiveSessionPhase.running
                    ? FloatingActionButton.extended(
                        onPressed: _stop,
                        backgroundColor: Colors.red,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      )
                    : FloatingActionButton.extended(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start'),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
