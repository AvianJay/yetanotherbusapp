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

    expect(eta.text, '2分\n5秒');
  });

  test('distance formatter switches to km over one kilometer', () {
    expect(formatDistance(320), '320m');
    expect(formatDistance(1530), '1.5km');
  });

  test('app settings persist mobile map provider', () {
    final settings = AppSettings.defaults().copyWith(
      mobileMapProvider: MobileMapProvider.osm,
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.mobileMapProvider, MobileMapProvider.osm);
  });

  test('app settings persist read route alerts', () {
    final settings = AppSettings.defaults().copyWith(
      readRouteAlerts: const [
        ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-a'),
        ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-b'),
      ],
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.readRouteAlerts, const [
      ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-a'),
      ReadRouteAlert(routeId: 'TPE123', alertId: 'alert-b'),
    ]);
  });

  test('favorite usage profile prunes entries older than seven days', () {
    final now = DateTime(2026, 4, 10, 18, 10);
    final profile = FavoriteUsageProfile(
      provider: BusProvider.nwt,
      routeKey: 12,
      pathId: 1,
      stopId: 1001,
      selectionTimestampsMs: <int>[
        now.subtract(const Duration(days: 8)).millisecondsSinceEpoch,
        now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      ],
    );

    final updated = profile.recordSelection(now);

    expect(updated.totalSelectionsAt(now: now), 2);
    expect(updated.selectionCountAtHour(18, now: now), 2);
  });
}
