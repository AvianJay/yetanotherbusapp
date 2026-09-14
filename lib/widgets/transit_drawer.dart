import 'package:flutter/material.dart';

/// Which top-level transit mode is active.
enum TransitMode { bus, metro, thsr, tra, youbike }

class TransitModeDestination {
  const TransitModeDestination({
    required this.mode,
    required this.icon,
    required this.label,
  });

  final TransitMode mode;
  final IconData icon;
  final String label;
}

const kTransitModeDestinations = <TransitModeDestination>[
  TransitModeDestination(
    mode: TransitMode.bus,
    icon: Icons.directions_bus_rounded,
    label: '公車',
  ),
  TransitModeDestination(
    mode: TransitMode.metro,
    icon: Icons.subway_rounded,
    label: '捷運',
  ),
  TransitModeDestination(
    mode: TransitMode.thsr,
    icon: Icons.train_rounded,
    label: '高鐵',
  ),
  TransitModeDestination(
    mode: TransitMode.tra,
    icon: Icons.tram_rounded,
    label: '台鐵',
  ),
  TransitModeDestination(
    mode: TransitMode.youbike,
    icon: Icons.pedal_bike_rounded,
    label: 'YouBike',
  ),
];

/// Minimum screen width to show the persistent desktop navigation rail.
/// Below this width, transit screens fall back to the hamburger drawer.
const double kDesktopNavigationRailBreakpoint = 1100;

/// Shared drawer used across all top-level transit screens.
///
/// Uses [onModeChanged] callback for in-place switching without navigation.
class TransitDrawer extends StatelessWidget {
  const TransitDrawer({
    required this.currentMode,
    required this.onModeChanged,
    super.key,
  });

  final TransitMode currentMode;
  final ValueChanged<TransitMode> onModeChanged;

  void _switchTo(BuildContext context, TransitMode mode) {
    Navigator.of(context).pop(); // close drawer
    if (mode != currentMode) {
      onModeChanged(mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: colorScheme.primaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Image.asset(
                  'assets/branding/icon_transparent.png',
                  width: 48,
                  height: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  'YABus',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (final destination in kTransitModeDestinations)
            ListTile(
              leading: Icon(destination.icon),
              title: Text(destination.label),
              selected: destination.mode == currentMode,
              onTap: () => _switchTo(context, destination.mode),
            ),
        ],
      ),
    );
  }
}
