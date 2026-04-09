import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  test('eta presentation keeps seconds when enabled', () {
    final stop = StopInfo(
      routeKey: 1,
      pathId: 0,
      stopId: 10,
      stopName: 'Main Station',
      sequence: 1,
      lon: 121.5,
      lat: 25.0,
      sec: 125,
    );

    final eta = buildEtaPresentation(stop, alwaysShowSeconds: true);

    expect(eta.text, '2m\n5s');
  });

  test('distance formatter switches to km over one kilometer', () {
    expect(formatDistance(320), '320m');
    expect(formatDistance(1530), '1.5km');
  });
}
