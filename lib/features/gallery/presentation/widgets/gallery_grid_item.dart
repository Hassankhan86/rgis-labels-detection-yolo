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
            Image.file(
              File(capture.thumbnailPath ?? capture.imagePath),
              fit: BoxFit.cover,
            ),
            if (capture.source == CaptureSource.liveSession)
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