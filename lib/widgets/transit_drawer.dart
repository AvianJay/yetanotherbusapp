import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/metro_screen.dart';
import '../screens/thsr_screen.dart';
import '../screens/tra_screen.dart';
import '../screens/youbike_screen.dart';

/// Which top-level transit mode is active.
enum TransitMode { bus, metro, thsr, tra, youbike }

/// Shared drawer used across all top-level transit screens.
///
/// Switching modes uses [Navigator.pushAndRemoveUntil] so only one top-level
/// screen is on the stack at a time (the bus HomeScreen always remains as the
/// first route underneath).
class TransitDrawer extends StatelessWidget {
  const TransitDrawer({required this.currentMode, super.key});

  final TransitMode currentMode;

  static const _modes = [
    (TransitMode.bus, Icons.directions_bus_rounded, 'YABus'),
    (TransitMode.metro, Icons.subway_rounded, 'YAMetro'),
    (TransitMode.thsr, Icons.train_rounded, 'YAHSR'),
    (TransitMode.tra, Icons.tram_rounded, 'YATRA'),
    (TransitMode.youbike, Icons.pedal_bike_rounded, 'YABike'),
  ];

  void _switchTo(BuildContext context, TransitMode mode) {
    Navigator.of(context).pop(); // close drawer

    if (mode == currentMode) return;

    if (mode == TransitMode.bus) {
      // Bus HomeScreen is always the first route.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final screen = switch (mode) {
      TransitMode.metro => const MetroScreen(),
      TransitMode.thsr => const ThsrScreen(),
      TransitMode.tra => const TraScreen(),
      TransitMode.youbike => const YouBikeScreen(),
      TransitMode.bus => const HomeScreen(), // unreachable
    };

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => screen),
      (route) => route.isFirst,
    );
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
                Icon(Icons.directions_transit_rounded,
                    size: 40, color: colorScheme.onPrimaryContainer),
                const SizedBox(height: 8),
                Text(
                  'YABus',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '多模式大眾運輸',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer
                            .withValues(alpha: 0.7),
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
