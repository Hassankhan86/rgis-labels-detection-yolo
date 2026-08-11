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
    this.thumbnailPath,
  });

  final String id;
  final String imagePath;
  final DateTime timestamp;

  /// A static (non-animated) first-frame preview of [imagePath], only set
  /// for [CaptureSource.liveSession] entries (a `.gif`). `Image.file`/
  /// `Image.memory` autoplay animated GIFs, so the gallery grid — which
  /// would otherwise show every saved session looping at once — renders
  /// this instead and reserves the full animated GIF for the detail screen.
  /// Null for plain [CaptureSource.capture] entries (already a still PNG,
  /// nothing to extract) and for older live-session entries saved before
  /// this field existed; callers should fall back to [imagePath] in both
  /// cases.
  final String? thumbnailPath;

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
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
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
    thumbnailPath: json['thumbnailPath'] as String?,
  );
}
