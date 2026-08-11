import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../detection/presentation/providers/detection_providers.dart';
import '../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final backendName = ref.watch(detectionRepositoryProvider).backendName;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Inference backend',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(backendName, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text(
            'Confidence threshold: ${settings.confidenceThreshold.toStringAsFixed(2)}',
          ),
          Slider(
            value: settings.confidenceThreshold,
            min: 0.05,
            max: 0.95,
            divisions: 18,
            label: settings.confidenceThreshold.toStringAsFixed(2),
            onChanged: notifier.setConfidenceThreshold,
          ),
          const SizedBox(height: 16),
          Text(
            'NMS IoU threshold: ${settings.iouThreshold.toStringAsFixed(2)}',
          ),
          Slider(
            value: settings.iouThreshold,
            min: 0.1,
            max: 0.9,
            divisions: 16,
            label: settings.iouThreshold.toStringAsFixed(2),
            onChanged: notifier.setIouThreshold,
          ),
          const SizedBox(height: 24),
          Text(
            'Box annotations',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable labels'),
            value: settings.showLabels,
            onChanged: notifier.setShowLabels,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Minimize labels'),
            subtitle: const Text('Show just the first letter (small → s)'),
            value: settings.minimizeLabels,
            onChanged: settings.showLabels ? notifier.setMinimizeLabels : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable confidence'),
            value: settings.showConfidence,
            onChanged: notifier.setShowConfidence,
          ),
          const SizedBox(height: 24),
          Text(
            'Lower the confidence threshold to catch more distant or partially '
            'occluded price labels, at the cost of a few extra false '
            'positives. Lower the IoU threshold to suppress overlapping boxes '
            'more aggressively.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}