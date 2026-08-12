import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/entities/saved_capture.dart';

class GalleryGridItem extends StatelessWidget {
  const GalleryGridItem({
    super.key,
    required this.capture,
    required this.onTap,
  });

  final SavedCapture capture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Static thumbnail for live sessions (falls back to the GIF
            // itself — and its autoplay — only for older entries saved
            // before thumbnails existed). Plain captures have no
            // thumbnailPath and are already a still image either way.
            // Recorded videos always have a poster thumbnailPath in
            // practice, but the errorBuilder guards the rare case that
            // failed and this would otherwise try to decode an .mp4 as an
            // image.
            Image.file(
              File(capture.thumbnailPath ?? capture.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black12,
                child: const Icon(Icons.videocam, size: 32),
              ),
            ),
            if (capture.source == CaptureSource.liveSession ||
                capture.source == CaptureSource.recordedVideo)
              const Positioned(
                left: 4,
                top: 4,
                child: Icon(
                  Icons.videocam,
                  color: Colors.white,
                  size: 16,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black87)],
                ),
              ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${capture.detectionCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}