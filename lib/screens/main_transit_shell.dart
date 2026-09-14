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

  static const _desktopRailExtendedBreakpoint = 1280.0;
  static const _switchDuration = Duration(milliseconds: 220);
  static const _hiddenOffset = Offset(0.035, 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_syncDesktopPresenceForMode(_currentMode));
  }

  void _setMode(TransitMode mode) {
    if (!kTransitModeDestinations.any(
      (destination) => destination.mode == mode,
    )) {
      mode = TransitMode.bus;
    }
    if (mode == _currentMode) {
      return;
    }

    setState(() {
      _loadedModes.add(mode);
      _currentMode = mode;
    });
    unawaited(_syncDesktopPresenceForMode(mode));
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
    final screens = kTransitModeDestinations
        .where((destination) => _loadedModes.contains(destination.mode))
        .map(
          (destination) => (
            mode: destination.mode,
            child: _buildScreenForMode(destination.mode),
          ),
        )
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
    if (screenWidth < kDesktopNavigationRailBreakpoint) {
      return modeStack;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isExtendedRail = screenWidth >= _desktopRailExtendedBreakpoint;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          extended: isExtendedRail,
          minExtendedWidth: 184,
          backgroundColor: colorScheme.surfaceContainerLow,
          groupAlignment: -0.82,
          leading: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
            child: isExtendedRail
                ? Text(
                    '交通工具',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Icon(
                    Icons.directions_transit_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
          ),
          selectedIndex: kTransitModeDestinations.indexWhere(
            (destination) => destination.mode == _currentMode,
          ),
          onDestinationSelected: (index) {
            if (index >= 0 && index < kTransitModeDestinations.length) {
              _setMode(kTransitModeDestinations[index].mode);
            }
          },
          labelType: isExtendedRail ? null : NavigationRailLabelType.all,
          destinations: [
            for (final destination in kTransitModeDestinations)
              NavigationRailDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.icon),
                label: Text(destination.label),
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
      TransitMode.metro => MetroScreen(
        onModeChanged: _setMode,
        isActive: mode == _currentMode,
      ),
      TransitMode.thsr => ThsrScreen(
        onModeChanged: _setMode,
        isActive: mode == _currentMode,
      ),
      TransitMode.tra => TraScreen(
        onModeChanged: _setMode,
        isActive: mode == _currentMode,
      ),
      TransitMode.youbike => YouBikeScreen(
        onModeChanged: _setMode,
        isActive: mode == _currentMode,
      ),
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
