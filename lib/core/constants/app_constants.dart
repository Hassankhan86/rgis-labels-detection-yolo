/// App-wide constants: asset locations and detector defaults.
class AppConstants {
  AppConstants._();

  static const String appName = 'RGIS Detector';

  // Model assets. Drop your exported files at these exact paths.
  static const String modelAssetPath = 'assets/models/model.onnx';
  static const String labelsAssetPath = 'assets/models/labels.txt';

  /// Square input side the bundled model was exported with
  /// (`yolo export imgsz=960` — model.onnx declares `[1, 3, 960, 960]`).
  static const int modelInputSize = 960;

  static const double defaultConfidenceThreshold = 0.5;
  static const double defaultIouThreshold = 0.45;

  static const String capturesDirName = 'captures';
  static const String capturesIndexFileName = 'captures_index.json';

  static const String prefsConfidenceKey = 'settings.confidenceThreshold';
  static const String prefsIouKey = 'settings.iouThreshold';
  static const String prefsShowLabelsKey = 'settings.showLabels';
  static const String prefsMinimizeLabelsKey = 'settings.minimizeLabels';
  static const String prefsShowConfidenceKey = 'settings.showConfidence';
}