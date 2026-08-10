import '../../../../core/constants/app_constants.dart';

class AppSettings {
  const AppSettings({
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.showLabels,
    required this.minimizeLabels,
    required this.showConfidence,
  });

  final double confidenceThreshold;
  final double iouThreshold;

  /// Whether class names are drawn on detection boxes.
  final bool showLabels;

  /// When [showLabels] is on, collapse each class name to its first letter
  /// (`price_label` -> `p`) so dense shelf scenes stay readable.
  final bool minimizeLabels;

  /// Whether the confidence percentage is drawn on detection boxes.
  final bool showConfidence;

  static const defaults = AppSettings(
    confidenceThreshold: AppConstants.defaultConfidenceThreshold,
    iouThreshold: AppConstants.defaultIouThreshold,
    showLabels: true,
    minimizeLabels: false,
    showConfidence: true,
  );

  AppSettings copyWith({
    double? confidenceThreshold,
    double? iouThreshold,
    bool? showLabels,
    bool? minimizeLabels,
    bool? showConfidence,
  }) {
    return AppSettings(
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      iouThreshold: iouThreshold ?? this.iouThreshold,
      showLabels: showLabels ?? this.showLabels,
      minimizeLabels: minimizeLabels ?? this.minimizeLabels,
      showConfidence: showConfidence ?? this.showConfidence,
    );
  }
}
