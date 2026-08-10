/// Distinguishes a single annotated photo (the capture flow) from a live
/// tracking session's summary snapshot, so both can live in the same
/// gallery grid without the grid/detail UI needing two separate models.
enum CaptureSource { capture, liveSession }

class SavedCapture {
  const SavedCapture({
    required this.id,
    required this.imagePath,
    required this.timestamp,
    required this.detectionCount,
    this.source = CaptureSource.capture,
    this.perClassBreakdown,
    this.framesProcessed,
  });

  final String id;
  final String imagePath;
  final DateTime timestamp;

  /// Detections in the photo (capture) or total unique labels counted
  /// across the session (live session).
  final int detectionCount;

  final CaptureSource source;

  /// Only set for [CaptureSource.liveSession] entries.
  final Map<String, int>? perClassBreakdown;

  /// Only set for [CaptureSource.liveSession] entries.
  final int? framesProcessed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'timestamp': timestamp.toIso8601String(),
    'detectionCount': detectionCount,
    'source': source.name,
    if (perClassBreakdown != null) 'perClassBreakdown': perClassBreakdown,
    if (framesProcessed != null) 'framesProcessed': framesProcessed,
  };

  factory SavedCapture.fromJson(Map<String, dynamic> json) => SavedCapture(
    id: json['id'] as String,
    imagePath: json['imagePath'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    detectionCount: json['detectionCount'] as int,
    // Missing key (captures saved before this field existed) defaults to
    // a plain capture, which is what they all were.
    source: json['source'] == 'liveSession'
        ? CaptureSource.liveSession
        : CaptureSource.capture,
    perClassBreakdown: (json['perClassBreakdown'] as Map<String, dynamic>?)
        ?.map((key, value) => MapEntry(key, value as int)),
    framesProcessed: json['framesProcessed'] as int?,
  );
}
