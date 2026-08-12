import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/app_router.dart';
import '../../../detection/presentation/providers/detection_providers.dart';

/// Record-only screen: owns its own [CameraController] but deliberately
/// never calls `startImageStream`/touches `DetectionEngine` — recording is
/// fully decoupled from inference, so the preview stays smooth regardless
/// of model speed. All AI processing happens afterward, in
/// [VideoProcessingScreen], on the file this screen hands off.
///
/// `HomeShell` only ever mounts one of its three camera-owning tabs at a
/// time (a plain widget swap, not an `IndexedStack`) so two
/// `CameraController`s never try to hold the physical camera open at once
/// — see that file's doc comment.
class VideoRecordScreen extends ConsumerStatefulWidget {
  const VideoRecordScreen({super.key});

  @override
  ConsumerState<VideoRecordScreen> createState() => _VideoRecordScreenState();
}

class _VideoRecordScreenState extends ConsumerState<VideoRecordScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _permissionError;
  bool _recording = false;
  DateTime? _recordingStartedAt;
  Duration _elapsed = Duration.zero;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFuture = _initCamera();
    // Warms model loading during recording so it's likely already loaded
    // by the time the user reaches the processing screen — not gated on,
    // just triggered early.
    ref.read(modelLoaderProvider);
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _permissionError = 'Camera permission is required for recording.';
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

    final controller = CameraController(rearCamera, ResolutionPreset.medium, enableAudio: false);
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
    if (appState == AppLifecycleState.inactive || appState == AppLifecycleState.paused) {
      if (_recording) {
        // Best-effort: discard rather than try to hand off a recording
        // while the app is backgrounding.
        controller.stopVideoRecording();
        _recording = false;
        _elapsedTimer?.cancel();
      }
      controller.dispose();
      _controller = null;
    } else if (appState == AppLifecycleState.resumed) {
      setState(() => _initializeFuture = _initCamera());
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || _recording) return;
    await controller.startVideoRecording();
    setState(() {
      _recording = true;
      _recordingStartedAt = DateTime.now();
      _elapsed = Duration.zero;
    });
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _elapsed = DateTime.now().difference(_recordingStartedAt!)),
    );
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    if (controller == null || !_recording) return;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    final file = await controller.stopVideoRecording();
    setState(() => _recording = false);
    if (!mounted) return;
    await Navigator.of(context).pushNamed(AppRoutes.videoProcessing, arguments: file.path);
  }

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_recording) {
      _controller?.stopVideoRecording();
    }
    _controller?.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record'),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.gallery),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_permissionError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_permissionError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: openAppSettings, child: const Text('Open app settings')),
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

        final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
        final previewAspectRatio = isPortrait
            ? 1 / controller.value.aspectRatio
            : controller.value.aspectRatio;

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(aspectRatio: previewAspectRatio, child: CameraPreview(controller)),
            ),
            if (_recording)
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _formatElapsed(_elapsed),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _recording
                    ? FloatingActionButton.extended(
                        onPressed: _stopRecording,
                        backgroundColor: Colors.red,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      )
                    : FloatingActionButton.extended(
                        onPressed: _startRecording,
                        icon: const Icon(Icons.fiber_manual_record),
                        label: const Text('Record'),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
