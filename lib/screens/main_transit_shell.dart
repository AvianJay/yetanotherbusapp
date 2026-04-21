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

class _MainTransitShellState extends State<MainTransitShell>
    with SingleTickerProviderStateMixin {
  TransitMode _currentMode = TransitMode.bus;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  static const _visibleModes = [
    TransitMode.bus,
    TransitMode.thsr,
    TransitMode.tra,
    TransitMode.youbike,
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _setMode(TransitMode mode) {
    if (mode == TransitMode.metro) mode = TransitMode.bus;
    if (mode == _currentMode) return;

    _fadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() => _currentMode = mode);
      _fadeController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _visibleModes.indexOf(_currentMode);

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: IndexedStack(
          index: currentIndex >= 0 ? currentIndex : 0,
          children: [
            HomeScreen(onModeChanged: _setMode),
            ThsrScreen(onModeChanged: _setMode),
            TraScreen(onModeChanged: _setMode),
            YouBikeScreen(onModeChanged: _setMode),
          ],
        ),
      ),
    );
  }
}
