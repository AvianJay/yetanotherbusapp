import 'package:flutter/material.dart';

import '../widgets/transit_drawer.dart';
import 'home_screen.dart';
import 'thsr_screen.dart';
import 'tra_screen.dart';
import 'youbike_screen.dart';

/// Main shell that manages in-place switching between transit modes.
///
/// Uses [IndexedStack] to preserve state of all screens and avoid
/// re-initialization when switching modes.
class MainTransitShell extends StatefulWidget {
  const MainTransitShell({super.key});

  @override
  State<MainTransitShell> createState() => _MainTransitShellState();
}

class _MainTransitShellState extends State<MainTransitShell> {
  TransitMode _currentMode = TransitMode.bus;

  void _setMode(TransitMode mode) {
    if (mode == TransitMode.metro) {
      mode = TransitMode.bus;
    }
    if (mode != _currentMode) {
      setState(() => _currentMode = mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleModes = [
      TransitMode.bus,
      TransitMode.thsr,
      TransitMode.tra,
      TransitMode.youbike,
    ];
    final currentIndex = visibleModes.indexOf(_currentMode);

    return IndexedStack(
      index: currentIndex >= 0 ? currentIndex : 0,
      children: [
        HomeScreen(onModeChanged: _setMode),
        ThsrScreen(onModeChanged: _setMode),
        TraScreen(onModeChanged: _setMode),
        YouBikeScreen(onModeChanged: _setMode),
      ],
    );
  }
}
