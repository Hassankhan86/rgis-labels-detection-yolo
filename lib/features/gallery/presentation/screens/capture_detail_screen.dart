import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/saved_capture.dart';
import '../providers/gallery_providers.dart';
import '../widgets/video_preview_player.dart';

class CaptureDetailScreen extends ConsumerWidget {
  const CaptureDetailScreen({super.key, required this.capture});

  final SavedCapture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          capture.source == CaptureSource.liveSession || capture.source == CaptureSource.recordedVideo
              ? '${capture.detectionCount} unique price label(s)'
              : '${capture.detectionCount} price label(s)',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await ref
                  .read(galleryNotifierProvider.notifier)
                  .deleteCapture(capture);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Center(
        child: capture.source == CaptureSource.recordedVideo
            ? VideoPreviewPlayer(videoPath: capture.imagePath)
            : InteractiveViewer(child: Image.file(File(capture.imagePath))),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Captured ${capture.timestamp.toLocal()}',
                textAlign: TextAlign.center,
              ),
              if (capture.source == CaptureSource.recordedVideo &&
                  (capture.videoDurationSeconds != null ||
                      capture.processingDurationSeconds != null)) ...[
                const SizedBox(height: 8),
                if (capture.videoDurationSeconds != null)
                  Text('Video length: ${_formatDuration(capture.videoDurationSeconds!)}'),
                if (capture.processingDurationSeconds != null)
                  Text('Processing time: ${_formatDuration(capture.processingDurationSeconds!)}'),
              ],
              if (capture.perClassBreakdown != null &&
                  capture.perClassBreakdown!.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (capture.framesProcessed != null)
                  Text('Frames processed: ${capture.framesProcessed}'),
                const SizedBox(height: 4),
                ...capture.perClassBreakdown!.entries.map(
                  (e) => Text('${e.key}: ${e.value}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// `4m 47s` above a minute, `7.1s` below -- matches how the timing is
  /// actually reported at each scale (sub-minute values want a decimal to
  /// be meaningful; minutes-plus values don't).
  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final totalSeconds = seconds.round();
    return '${totalSeconds ~/ 60}m ${totalSeconds % 60}s';
  }
}