import 'package:flutter/material.dart';

import '../../domain/entities/live_frame_result.dart';

/// Unique-label total, inference FPS, and processed-frame count, drawn as
/// an overlay badge. Mirrors `live_camera_pipeline/renderer.py`'s
/// `_draw_hud`.
class LiveHud extends StatelessWidget {
  const LiveHud({super.key, required this.result});

  final LiveFrameResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 12),
              SizedBox(width: 4),
              Text(
                'REC',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _line('Unique labels: ${r?.totalUniqueLabels ?? 0}'),
          _line('FPS: ${(r?.inferenceFps ?? 0).toStringAsFixed(1)}'),
          _line('Frame: ${r?.frameIndex ?? 0}'),
        ],
      ),
    );
  }

  Widget _line(String text) {
    return Text(text, style: const TextStyle(color: Colors.white, fontSize: 12));
  }
}
