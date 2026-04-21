import 'package:flutter/material.dart';

/// Which top-level transit mode is active.
enum TransitMode { bus, metro, thsr, tra, youbike }

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

  static const _modes = [
    (TransitMode.bus, Icons.directions_bus_rounded, '公車'),
    (TransitMode.youbike, Icons.pedal_bike_rounded, 'YouBike'),
    (TransitMode.tra, Icons.tram_rounded, '台鐵'),
    (TransitMode.thsr, Icons.train_rounded, '高鐵'),
  ];

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
          for (final (mode, icon, label) in _modes)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              selected: mode == currentMode,
              onTap: () => _switchTo(context, mode),
            ),
        ],
      ),
    );
  }
}
