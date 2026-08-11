import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/app_router.dart';
import '../../../gallery/presentation/providers/gallery_providers.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../domain/entities/detection_result.dart';
import '../providers/detection_providers.dart';
import '../providers/detection_state_provider.dart';
import '../widgets/capture_button.dart';
import '../widgets/detection_overlay_painter.dart';
import '../widgets/fps_indicator.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _permissionError;
  final GlobalKey _captureBoundaryKey = GlobalKey();

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
            'Camera permission is required to use the detector.';
      });
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _permissionError = 'No camera available on this device.');
      return;
    }
    final rearCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      rearCamera,
      ResolutionPreset.high,
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
      controller.dispose();
      _controller = null;
    } else if (appState == AppLifecycleState.resumed) {
      setState(() => _initializeFuture = _initCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    final file = await controller.takePicture();
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await ref.read(detectionStateProvider.notifier).processCapture(bytes);
  }

  Future<void> _saveToGallery(DetectionFrame frame) async {
    final boundary =
        _captureBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;

    final uiImage = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    await ref
        .read(galleryNotifierProvider.notifier)
        .saveCapture(
          imageBytes: byteData.buffer.asUint8List(),
          detectionCount: frame.detections.length,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved to gallery')));
    ref.read(detectionStateProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final modelState = ref.watch(modelLoaderProvider);
    final detectionState = ref.watch(detectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RGIS Detector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.gallery),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
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
        data: (_) => _buildBody(detectionState),
      ),
    );
  }

  Widget _buildBody(DetectionUiState state) {
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

    if (state.imageBytes != null) {
      return _buildReview(state);
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
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
            Center(
              child: AspectRatio(
                aspectRatio: previewAspectRatio,
                child: CameraPreview(controller),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(child: CaptureButton(onPressed: _capture)),
            ),
          ],
        );
      },
    );
  }

  /// e.g. "3 price label(s) found (2 small, 1 large)" -- a per-class
  /// breakdown alongside the total, since a flat count can't distinguish
  /// which of the (now multiple) classes were actually found.
  String _summaryText(DetectionFrame frame) {
    if (frame.detections.isEmpty) return 'No price labels found';

    final counts = <String, int>{};
    for (final detection in frame.detections) {
      counts[detection.label] = (counts[detection.label] ?? 0) + 1;
    }
    final breakdown = counts.entries.map((e) => '${e.value} ${e.key}').join(', ');
    return '${frame.detections.length} price label(s) found ($breakdown)';
  }

  Widget _buildReview(DetectionUiState state) {
    final frame = state.frame;
    final settings = ref.watch(settingsNotifierProvider);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: (frame != null && frame.imageHeight > 0)
                  ? frame.imageWidth / frame.imageHeight
                  : 1,
              child: RepaintBoundary(
                key: _captureBoundaryKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(state.imageBytes!, fit: BoxFit.contain),
                    if (frame != null)
                      CustomPaint(
                        painter: DetectionOverlayPainter(
                          frame: frame,
                          showLabels: settings.showLabels,
                          minimizeLabels: settings.minimizeLabels,
                          showConfidence: settings.showConfidence,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (state.isProcessing) const LinearProgressIndicator(),
        if (frame != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_summaryText(frame)),
                FpsIndicator(frame: frame),
              ],
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              state.error!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        ref.read(detectionStateProvider.notifier).reset(),
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: frame == null
                        ? null
                        : () => _saveToGallery(frame),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
