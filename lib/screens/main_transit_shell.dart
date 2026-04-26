import 'package:flutter/material.dart';

import '../widgets/transit_drawer.dart';
import 'home_screen.dart';
import 'thsr_screen.dart';
import 'tra_screen.dart';
import 'youbike_screen.dart';

/// Main shell that manages in-place switching between transit modes.
///
/// Lazily mounts top-level screens and animates between visited ones in place.
class MainTransitShell extends StatefulWidget {
  const MainTransitShell({super.key});

  @override
  State<MainTransitShell> createState() => _MainTransitShellState();
}

class _MainTransitShellState extends State<MainTransitShell> {
  TransitMode _currentMode = TransitMode.bus;
  final Set<TransitMode> _loadedModes = {TransitMode.bus};

  static const _visibleModes = [
    TransitMode.bus,
    TransitMode.thsr,
    TransitMode.tra,
    TransitMode.youbike,
  ];
  static const _switchDuration = Duration(milliseconds: 220);
  static const _hiddenOffset = Offset(0.035, 0);

  void _setMode(TransitMode mode) {
    if (!_visibleModes.contains(mode) || mode == TransitMode.metro) {
      mode = TransitMode.bus;
    }
    if (mode == _currentMode) {
      return;
    }

    if (_loadedModes.contains(mode)) {
      setState(() => _currentMode = mode);
      return;
    }

    setState(() => _loadedModes.add(mode));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _currentMode = mode);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = _visibleModes
        .where(_loadedModes.contains)
        .map((mode) => (mode: mode, child: _buildScreenForMode(mode)))
        .toList();
    final orderedScreens = [
      ...screens.where((screen) => screen.mode != _currentMode),
      ...screens.where((screen) => screen.mode == _currentMode),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final screen in orderedScreens)
          KeyedSubtree(
            key: ValueKey(screen.mode),
            child: _buildModeLayer(
              mode: screen.mode,
              child: screen.child,
            ),
          ),
      ],
    );
  }

  Widget _buildScreenForMode(TransitMode mode) {
    return switch (mode) {
      TransitMode.bus => HomeScreen(onModeChanged: _setMode),
      TransitMode.thsr => ThsrScreen(onModeChanged: _setMode),
      TransitMode.tra => TraScreen(onModeChanged: _setMode),
      TransitMode.youbike => YouBikeScreen(onModeChanged: _setMode),
      TransitMode.metro => HomeScreen(onModeChanged: _setMode),
    };
  }

  Widget _buildModeLayer({required TransitMode mode, required Widget child}) {
    final isActive = mode == _currentMode;

    return IgnorePointer(
      ignoring: !isActive,
      child: ExcludeSemantics(
        excluding: !isActive,
        child: TickerMode(
          enabled: isActive,
          child: AnimatedSlide(
            duration: _switchDuration,
            curve: Curves.easeOutCubic,
            offset: isActive ? Offset.zero : _hiddenOffset,
            child: AnimatedOpacity(
              duration: _switchDuration,
              curve: Curves.easeOutCubic,
              opacity: isActive ? 1 : 0,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
