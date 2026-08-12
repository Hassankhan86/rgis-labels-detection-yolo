import 'package:flutter/material.dart';

import 'features/detection/presentation/screens/camera_screen.dart';
import 'features/live_tracking/presentation/screens/live_camera_screen.dart';
import 'features/video_processing/presentation/screens/video_record_screen.dart';

/// Bottom tab switcher between the capture-based detection flow
/// ([CameraScreen], unchanged), the live camera tracking flow
/// ([LiveCameraScreen]), and the record-then-batch-process flow
/// ([VideoRecordScreen]).
///
/// Deliberately a plain widget swap (`switch (_index) { ... }`), not an
/// `IndexedStack` — all three screens open an exclusive [CameraController],
/// and most platforms only allow one open at a time. A widget swap fully
/// disposes the inactive screen (releasing its camera) and creates the
/// newly-active one fresh, so there is never more than one camera session
/// alive at once.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_index) {
        0 => const CameraScreen(),
        1 => const LiveCameraScreen(),
        _ => const VideoRecordScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Capture',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_creation_outlined),
            selectedIcon: Icon(Icons.movie_creation),
            label: 'Record',
          ),
        ],
      ),
    );
  }
}
