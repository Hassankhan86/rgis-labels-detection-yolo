import 'package:flutter/material.dart';

import '../../domain/entities/tracked_label.dart';

/// Draws tracked boxes, display id, class name, and confidence over the
/// live camera preview. Same visual language as the capture flow's
/// `DetectionOverlayPainter`; the label format (`id:N name conf%`) mirrors
/// `live_camera_pipeline/renderer.py`'s box labels.
///
/// Boxes are painted in the camera frame's own coordinate space, scaled to
/// fill this painter's canvas. That frame is already rotated upright by
/// `convertCameraImage` (see its doc comment), so `frameWidth`/`frameHeight`
/// here match the portrait preview and boxes line up correctly, assuming
/// the device is held in natural upright portrait.
class LiveOverlayPainter extends CustomPainter {
  LiveOverlayPainter({
    required this.trackedLabels,
    required this.frameWidth,
    required this.frameHeight,
    this.showLabels = true,
    this.minimizeLabels = false,
    this.showConfidence = true,
  });

  final List<TrackedLabel> trackedLabels;
  final int frameWidth;
  final int frameHeight;

  /// Whether class names are drawn on each box (from Settings).
  final bool showLabels;

  /// Collapse class names to their first letter (`price_label` -> `p`).
  final bool minimizeLabels;

  /// Whether the confidence percentage is drawn on each box (from Settings).
  final bool showConfidence;

  static const Color _boxColor = Color(0xFF00E676);

  @override
  void paint(Canvas canvas, Size size) {
    if (frameWidth == 0 || frameHeight == 0) return;

    final scaleX = size.width / frameWidth;
    final scaleY = size.height / frameHeight;

    final boxPaint = Paint()
      ..color = _boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final labelBgPaint = Paint()..color = _boxColor;

    for (final tracked in trackedLabels) {
      final rect = Rect.fromLTRB(
        tracked.box.left * scaleX,
        tracked.box.top * scaleY,
        tracked.box.right * scaleX,
        tracked.box.bottom * scaleY,
      );
      canvas.drawRect(rect, boxPaint);

      final labelText = _labelText(tracked);
      if (labelText.isEmpty) continue;

      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTop = (rect.top - textPainter.height - 2).clamp(
        0,
        size.height,
      );
      final labelRect = Rect.fromLTWH(
        rect.left,
        labelTop.toDouble(),
        textPainter.width + 6,
        textPainter.height + 2,
      );
      canvas.drawRect(labelRect, labelBgPaint);
      textPainter.paint(canvas, Offset(labelRect.left + 3, labelRect.top + 1));
    }
  }

  String _labelText(TrackedLabel tracked) {
    final parts = <String>[
      'id:${tracked.displayId}',
      if (showLabels)
        minimizeLabels && tracked.label.isNotEmpty
            ? tracked.label[0]
            : tracked.label,
      if (showConfidence)
        '${(tracked.confidence * 100).toStringAsFixed(0)}%',
    ];
    return parts.join(' ');
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter oldDelegate) {
    return oldDelegate.trackedLabels != trackedLabels ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.minimizeLabels != minimizeLabels ||
        oldDelegate.showConfidence != showConfidence;
  }
}
