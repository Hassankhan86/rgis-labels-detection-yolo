import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';

class SettingsLocalDatasource {
  const SettingsLocalDatasource(this._prefs);

  final SharedPreferences _prefs;

  double? getConfidenceThreshold() =>
      _prefs.getDouble(AppConstants.prefsConfidenceKey);

  double? getIouThreshold() => _prefs.getDouble(AppConstants.prefsIouKey);

  bool? getShowLabels() => _prefs.getBool(AppConstants.prefsShowLabelsKey);

  bool? getMinimizeLabels() =>
      _prefs.getBool(AppConstants.prefsMinimizeLabelsKey);

  bool? getShowConfidence() =>
      _prefs.getBool(AppConstants.prefsShowConfidenceKey);

  Future<void> setConfidenceThreshold(double value) =>
      _prefs.setDouble(AppConstants.prefsConfidenceKey, value);

  Future<void> setIouThreshold(double value) =>
      _prefs.setDouble(AppConstants.prefsIouKey, value);

  Future<void> setShowLabels(bool value) =>
      _prefs.setBool(AppConstants.prefsShowLabelsKey, value);

  Future<void> setMinimizeLabels(bool value) =>
      _prefs.setBool(AppConstants.prefsMinimizeLabelsKey, value);

  Future<void> setShowConfidence(bool value) =>
      _prefs.setBool(AppConstants.prefsShowConfidenceKey, value);
}