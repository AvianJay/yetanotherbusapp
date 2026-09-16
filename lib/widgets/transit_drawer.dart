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
const double kDesktopNavigationRailBreakpoint = 1100;
