/// Distinguishes a single annotated photo (the capture flow), a live
/// tracking session's summary snapshot, and a batch-processed recorded
/// video, so all three can live in the same gallery grid without the
/// grid/detail UI needing separate models.
enum CaptureSource { capture, liveSession, recordedVideo }

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
    this.processingDurationSeconds,
    this.videoDurationSeconds,
  });

  final String id;
  final String imagePath;
  final DateTime timestamp;

  /// A static preview image: for [CaptureSource.liveSession] (a `.gif`),
  /// the first frame — `Image.file`/`Image.memory` autoplay animated GIFs,
  /// so the gallery grid — which would otherwise show every saved session
  /// looping at once — renders this instead and reserves the full animated
  /// GIF for the detail screen. For [CaptureSource.recordedVideo] (an
  /// `.mp4`, [imagePath] holds the video file path), a poster frame from
  /// the annotated result, since `Image.file` can't decode video at all.
  /// Null for plain [CaptureSource.capture] entries (already a still PNG,
  /// nothing to extract) and for older entries saved before this field
  /// existed; callers should fall back to [imagePath] in both cases (never
  /// safe for [CaptureSource.recordedVideo] specifically — see
  /// `gallery_grid_item.dart`'s `errorBuilder`).
  final String? thumbnailPath;

  /// Detections in the photo (capture), or total unique labels counted
  /// across the session (live session / recorded video).
  final int detectionCount;

  final CaptureSource source;

  /// Only set for [CaptureSource.liveSession]/[CaptureSource.recordedVideo] entries.
  final Map<String, int>? perClassBreakdown;

  /// Only set for [CaptureSource.liveSession]/[CaptureSource.recordedVideo] entries.
  final int? framesProcessed;

  /// Wall-clock time the batch pipeline spent extracting, detecting, and
  /// re-encoding -- not including the final gallery copy. Only set for
  /// [CaptureSource.recordedVideo] entries.
  final double? processingDurationSeconds;

  /// The source recording's own length, from `ffprobe`. Only set for
  /// [CaptureSource.recordedVideo] entries.
  final double? videoDurationSeconds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'timestamp': timestamp.toIso8601String(),
    'detectionCount': detectionCount,
    'source': source.name,
    if (perClassBreakdown != null) 'perClassBreakdown': perClassBreakdown,
    if (framesProcessed != null) 'framesProcessed': framesProcessed,
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
    if (processingDurationSeconds != null)
      'processingDurationSeconds': processingDurationSeconds,
    if (videoDurationSeconds != null) 'videoDurationSeconds': videoDurationSeconds,
  };

  factory SavedCapture.fromJson(Map<String, dynamic> json) => SavedCapture(
    id: json['id'] as String,
    imagePath: json['imagePath'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    detectionCount: json['detectionCount'] as int,
    // Missing/unrecognized key (captures saved before this field existed,
    // or by a future/older version) defaults to a plain capture.
    source: CaptureSource.values.firstWhere(
      (v) => v.name == json['source'],
      orElse: () => CaptureSource.capture,
    ),
    perClassBreakdown: (json['perClassBreakdown'] as Map<String, dynamic>?)
        ?.map((key, value) => MapEntry(key, value as int)),
    framesProcessed: json['framesProcessed'] as int?,
    thumbnailPath: json['thumbnailPath'] as String?,
    processingDurationSeconds: (json['processingDurationSeconds'] as num?)?.toDouble(),
    videoDurationSeconds: (json['videoDurationSeconds'] as num?)?.toDouble(),
  );
}
