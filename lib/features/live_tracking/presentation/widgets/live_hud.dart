import 'package:flutter/material.dart';

import '../../domain/entities/live_frame_result.dart';

/// Unique-label total, measured FPS, per-stage timing breakdown, and
/// processed-frame count, drawn as an overlay badge. Mirrors
/// `live_camera_pipeline/renderer.py`'s `_draw_hud`, extended with the
/// stage timings so perf regressions are visible on-device without a
/// profiler attached.
class LiveHud extends StatelessWidget {
  const LiveHud({super.key, required this.result, this.measuredFps = 0});

  final LiveFrameResult? result;

  /// Directly-measured FPS from wall-clock gaps between processed frames
  /// (see [LiveUiState.measuredFps]) — the number that reflects what's
  /// actually updating on screen, as opposed to [LiveFrameResult.totalFps]
  /// which only reflects one frame's own processing cost.
  final double measuredFps;

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
          _line('FPS: ${measuredFps.toStringAsFixed(1)}'),
          _line('Frame: ${r?.frameIndex ?? 0}'),
          if (r != null) ...[
            _line('Total: ${_ms(r.totalTime)}'),
            _line(
              'Pre ${_ms(r.preprocessTime)} · '
              'Inf ${_ms(r.inferenceTime)} · '
              'Trk ${_ms(r.trackingTime)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(String text) {
    return Text(text, style: const TextStyle(color: Colors.white, fontSize: 12));
  }

  String _ms(Duration d) => '${d.inMilliseconds}ms';
}
