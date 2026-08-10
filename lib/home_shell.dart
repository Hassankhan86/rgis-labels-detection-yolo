import 'package:flutter/material.dart';

import 'features/detection/presentation/screens/camera_screen.dart';
import 'features/live_tracking/presentation/screens/live_camera_screen.dart';

/// Bottom tab switcher between the capture-based detection flow
/// ([CameraScreen], unchanged) and the new live camera tracking flow
/// ([LiveCameraScreen]).
///
/// Deliberately a plain widget swap (`_index == 0 ? A : B`), not an
/// `IndexedStack` — both screens open an exclusive [CameraController], and
/// most platforms only allow one open at a time. A widget swap fully
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
      body: _index == 0 ? const CameraScreen() : const LiveCameraScreen(),
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
        ],
      ),
    );
  }
}
