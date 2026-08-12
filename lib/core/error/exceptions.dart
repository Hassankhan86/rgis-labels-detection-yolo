/// Thrown by the data layer; caught at the repository boundary and mapped to a [Failure].
class ModelLoadException implements Exception {
  ModelLoadException(this.message);
  final String message;
  @override
  String toString() => 'ModelLoadException: $message';
}

class InferenceException implements Exception {
  InferenceException(this.message);
  final String message;
  @override
  String toString() => 'InferenceException: $message';
}

class StorageException implements Exception {
  StorageException(this.message);
  final String message;
  @override
  String toString() => 'StorageException: $message';
}

class VideoProbeException implements Exception {
  VideoProbeException(this.message);
  final String message;
  @override
  String toString() => 'VideoProbeException: $message';
}

class VideoExtractionException implements Exception {
  VideoExtractionException(this.message);
  final String message;
  @override
  String toString() => 'VideoExtractionException: $message';
}

class VideoEncodingException implements Exception {
  VideoEncodingException(this.message);
  final String message;
  @override
  String toString() => 'VideoEncodingException: $message';
}