import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/shared_preferences_provider.dart';
import '../../data/datasources/settings_local_datasource.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

final settingsLocalDatasourceProvider = Provider<SettingsLocalDatasource>((
  ref,
) {
  return SettingsLocalDatasource(ref.watch(sharedPreferencesProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl(ref.watch(settingsLocalDatasourceProvider));
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._repository) : super(_repository.load());

  final SettingsRepository _repository;

  Future<void> setConfidenceThreshold(double value) async {
    state = state.copyWith(confidenceThreshold: value);
    await _repository.save(state);
  }

  Future<void> setIouThreshold(double value) async {
    state = state.copyWith(iouThreshold: value);
    await _repository.save(state);
  }

  Future<void> setShowLabels(bool value) async {
    state = state.copyWith(showLabels: value);
    await _repository.save(state);
  }

  Future<void> setMinimizeLabels(bool value) async {
    state = state.copyWith(minimizeLabels: value);
    await _repository.save(state);
  }

  Future<void> setShowConfidence(bool value) async {
    state = state.copyWith(showConfidence: value);
    await _repository.save(state);
  }
}

final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
      return SettingsNotifier(ref.watch(settingsRepositoryProvider));
    });