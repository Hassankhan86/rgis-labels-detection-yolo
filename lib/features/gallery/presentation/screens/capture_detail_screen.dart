import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/saved_capture.dart';
import '../providers/gallery_providers.dart';

class CaptureDetailScreen extends ConsumerWidget {
  const CaptureDetailScreen({super.key, required this.capture});

  final SavedCapture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          capture.source == CaptureSource.liveSession
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
        child: InteractiveViewer(child: Image.file(File(capture.imagePath))),
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
}