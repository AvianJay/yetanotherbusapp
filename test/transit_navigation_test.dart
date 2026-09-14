import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/widgets/transit_drawer.dart';

void main() {
  test('transit destinations use the canonical navigation order', () {
    expect(
      kTransitModeDestinations.map((destination) => destination.mode),
      orderedEquals(const [
        TransitMode.bus,
        TransitMode.metro,
        TransitMode.thsr,
        TransitMode.tra,
        TransitMode.youbike,
      ]),
    );
    expect(
      kTransitModeDestinations.map((destination) => destination.label),
      orderedEquals(const ['公車', '捷運', '高鐵', '台鐵', 'YouBike']),
    );
  });
}
