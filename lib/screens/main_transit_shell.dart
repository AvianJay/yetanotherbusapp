import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/desktop_discord_presence_service.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/transit_drawer.dart';
import 'home_screen.dart';
import 'metro_dashboard_screen.dart';
import 'thsr_dashboard_screen.dart';
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
    TransitMode.metro,
    TransitMode.thsr,
    TransitMode.tra,
    TransitMode.youbike,
  ];
  static const _railDestinations = [
    (TransitMode.bus, Icons.directions_bus_rounded, '公車'),
    (TransitMode.metro, Icons.subway_rounded, '捷運'),
    (TransitMode.thsr, Icons.train_rounded, '高鐵'),
    (TransitMode.tra, Icons.tram_rounded, '台鐵'),
    (TransitMode.youbike, Icons.pedal_bike_rounded, 'YouBike'),
  ];
  static const _desktopRailBreakpoint = 1100.0;
  static const _desktopRailExtendedBreakpoint = 1280.0;
  static const _switchDuration = Duration(milliseconds: 220);
  static const _hiddenOffset = Offset(0.035, 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_syncDesktopPresenceForMode(_currentMode));
  }

  void _setMode(TransitMode mode) {
    if (!_visibleModes.contains(mode)) {
      mode = TransitMode.bus;
    }
    if (mode == _currentMode) {
      return;
    }

    if (_loadedModes.contains(mode)) {
      setState(() => _currentMode = mode);
      unawaited(_syncDesktopPresenceForMode(mode));
      return;
    }

    setState(() => _loadedModes.add(mode));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _currentMode = mode);
      unawaited(_syncDesktopPresenceForMode(mode));
    });
  }

  Future<void> _syncDesktopPresenceForMode(TransitMode mode) async {
    final controller = AppControllerScope.read(context);
    final screenLabel = switch (mode) {
      TransitMode.bus => '公車首頁',
      TransitMode.metro => '捷運',
      TransitMode.thsr => '高鐵',
      TransitMode.tra => '台鐵',
      TransitMode.youbike => 'YouBike',
    };
    final provider = switch (mode) {
      TransitMode.bus => controller.settings.provider,
      _ => null,
    };
    await desktopDiscordPresenceService.updateScreen(
      settings: controller.settings,
      screenLabel: screenLabel,
      provider: provider,
    );
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

    final modeStack = Stack(
      fit: StackFit.expand,
      children: [
        for (final screen in orderedScreens)
          KeyedSubtree(
            key: ValueKey(screen.mode),
            child: _buildModeLayer(mode: screen.mode, child: screen.child),
          ),
      ],
    );

    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth < _desktopRailBreakpoint) {
      return modeStack;
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          extended: screenWidth >= _desktopRailExtendedBreakpoint,
          backgroundColor: colorScheme.surfaceContainerLow,
          selectedIndex: _visibleModes.indexOf(_currentMode),
          onDestinationSelected: (index) {
            if (index >= 0 && index < _visibleModes.length) {
              _setMode(_visibleModes[index]);
            }
          },
          labelType: screenWidth >= _desktopRailExtendedBreakpoint
              ? null
              : NavigationRailLabelType.all,
          destinations: [
            for (final (_, icon, label) in _railDestinations)
              NavigationRailDestination(
                icon: Icon(icon),
                selectedIcon: Icon(icon),
                label: Text(label),
              ),
          ],
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant,
        ),
        Expanded(child: modeStack),
      ],
    );
  }

  Widget _buildScreenForMode(TransitMode mode) {
    return switch (mode) {
      TransitMode.bus => HomeScreen(onModeChanged: _setMode),
      TransitMode.metro => MetroScreen(onModeChanged: _setMode),
      TransitMode.thsr => ThsrScreen(onModeChanged: _setMode),
      TransitMode.tra => TraScreen(onModeChanged: _setMode),
      TransitMode.youbike => YouBikeScreen(onModeChanged: _setMode),
    };
  }

  Widget _buildModeLayer({required TransitMode mode, required Widget child}) {
    final isActive = mode == _currentMode;
    // All 5 transit modes share the 'bus' (main/home) page key
    // so the background image is shared across the home page tabs.
    const pageKey = 'bus';

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
              child: BackgroundImageWrapper(pageKey: pageKey, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
