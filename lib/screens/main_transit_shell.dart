import 'package:flutter/material.dart';

import '../widgets/transit_drawer.dart';
import 'home_screen.dart';
import 'metro_screen.dart';
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
    if (mode != _currentMode) {
      setState(() => _currentMode = mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _currentMode.index,
      children: [
        HomeScreen(onModeChanged: _setMode),
        MetroScreen(onModeChanged: _setMode),
        ThsrScreen(onModeChanged: _setMode),
        TraScreen(onModeChanged: _setMode),
        YouBikeScreen(onModeChanged: _setMode),
      ],
    );
  }
}
