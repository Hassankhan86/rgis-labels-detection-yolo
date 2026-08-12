import 'package:flutter/material.dart';

import '../../features/gallery/domain/entities/saved_capture.dart';
import '../../features/gallery/presentation/screens/capture_detail_screen.dart';
import '../../features/gallery/presentation/screens/gallery_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/video_processing/presentation/screens/video_processing_screen.dart';
import '../../home_shell.dart';

class AppRoutes {
  AppRoutes._();

  static const String camera = '/';
  static const String gallery = '/gallery';
  static const String captureDetail = '/gallery/detail';
  static const String settings = '/settings';
  static const String videoProcessing = '/video-processing';
}

class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.camera:
        return MaterialPageRoute(builder: (_) => const HomeShell());
      case AppRoutes.gallery:
        return MaterialPageRoute(builder: (_) => const GalleryScreen());
      case AppRoutes.captureDetail:
        final capture = settings.arguments as SavedCapture;
        return MaterialPageRoute(
          builder: (_) => CaptureDetailScreen(capture: capture),
        );
      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case AppRoutes.videoProcessing:
        final sourceVideoPath = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => VideoProcessingScreen(sourceVideoPath: sourceVideoPath),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('Unknown route: ${settings.name}')),
          ),
        );
    }
  }
}