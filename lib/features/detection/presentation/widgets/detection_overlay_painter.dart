import 'package:flutter/material.dart';

import '../../domain/entities/detection_result.dart';

/// Draws bounding boxes, labels, and confidence percentages over a captured
/// photo. Expects to be painted into a widget sized with the *same aspect
/// ratio* as `frame.imageWidth x frame.imageHeight` (see `CameraScreen`,
/// which wraps this in an `AspectRatio` matching the photo) so a single
/// uniform scale factor maps detection-space boxes to canvas pixels.
class DetectionOverlayPainter extends CustomPainter {
  DetectionOverlayPainter({
    required this.frame,
    this.showLabels = true,
    this.minimizeLabels = false,
    this.showConfidence = true,
  });

  final DetectionFrame frame;

  /// Whether class names are drawn on each box (from Settings).
  final bool showLabels;

  /// Collapse class names to their first letter (`small` -> `s`).
  final bool minimizeLabels;

  /// Whether the confidence percentage is drawn on each box (from Settings).
  final bool showConfidence;

  static const Color _boxColor = Color(0xFF00E676);

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.imageWidth == 0 || frame.imageHeight == 0) return;

    final scaleX = size.width / frame.imageWidth;
    final scaleY = size.height / frame.imageHeight;

    final boxPaint = Paint()
      ..color = _boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final labelBgPaint = Paint()..color = _boxColor;

    for (final detection in frame.detections) {
      final rect = Rect.fromLTRB(
        detection.box.left * scaleX,
        detection.box.top * scaleY,
        detection.box.right * scaleX,
        detection.box.bottom * scaleY,
      );
      canvas.drawRect(rect, boxPaint);

      final labelText = _labelText(detection);
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

  String _labelText(Detection detection) {
    final parts = <String>[
      if (showLabels)
        minimizeLabels && detection.label.isNotEmpty
            ? detection.label[0]
            : detection.label,
      if (showConfidence)
        '${(detection.confidence * 100).toStringAsFixed(0)}%',
    ];
    return parts.join(' ');
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.minimizeLabels != minimizeLabels ||
        oldDelegate.showConfidence != showConfidence;
  }
}