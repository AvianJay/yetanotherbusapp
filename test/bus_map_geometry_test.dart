import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/widgets/bus_map_geometry.dart';
import 'package:taiwanbus_flutter/widgets/bus_map_motion.dart';

/// Pins the behaviour that moved out of `route_bus_map_sheet.dart`, so the
/// route sheet and the city map cannot drift apart later.

// Roughly 1 km of Dunhua S. Road, running north.
const _south = LatLng(25.0300, 121.5490);
const _mid = LatLng(25.0350, 121.5490);
const _north = LatLng(25.0400, 121.5490);

RouteGeometry _line() => RouteGeometry.fromPoints(const [
  RoutePathPoint(lat: 25.0300, lon: 121.5490),
  RoutePathPoint(lat: 25.0350, lon: 121.5490),
  RoutePathPoint(lat: 25.0400, lon: 121.5490),
]);

RouteRealtimeBus _bus({
  String id = 'KKA-1234',
  required double lat,
  required double lon,
  double? speedKph,
  double? azimuth,
  DateTime? updatedAt,
}) {
  return RouteRealtimeBus(
    id: id,
    routeId: 'TPE101320',
    pathId: 0,
    lat: lat,
    lon: lon,
    speedKph: speedKph,
    azimuth: azimuth,
    statusCode: 0,
    updatedAt: updatedAt,
  );
}

void main() {
  group('RouteGeometry', () {
    test('measures the line and walks along it by distance', () {
      final geometry = _line();

      // ~1.1 km for one hundredth of a degree of latitude.
      expect(geometry.totalLengthMeters, closeTo(1112, 5));
      expect(
        geometry.pointAtDistance(0).latitude,
        closeTo(_south.latitude, 1e-6),
      );
      expect(
        geometry.pointAtDistance(geometry.totalLengthMeters).latitude,
        closeTo(_north.latitude, 1e-6),
      );
      expect(
        geometry.pointAtDistance(geometry.totalLengthMeters / 2).latitude,
        closeTo(_mid.latitude, 1e-4),
      );
    });

    test('projects an off-line point onto its nearest segment', () {
      final geometry = _line();

      final projection = geometry.project(const LatLng(25.0350, 121.5500));

      expect(projection.distanceToRouteMeters, closeTo(101, 15));
      expect(projection.snappedPoint.longitude, closeTo(121.5490, 1e-4));
      expect(
        projection.distanceAlongRouteMeters,
        closeTo(geometry.totalLengthMeters / 2, 30),
      );
    });

    test('degenerate geometry never throws', () {
      final empty = RouteGeometry.fromPoints(const []);

      expect(empty.totalLengthMeters, 0);
      expect(empty.pointAtDistance(500), const LatLng(0, 0));
      expect(empty.project(_mid).distanceToRouteMeters, double.infinity);
    });
  });

  group('buildAnimatedBusStates', () {
    final now = DateTime(2026, 9, 6, 21, 40);

    test('a bus near the line rides it', () {
      // ~100 m east of the route.
      final states = buildAnimatedBusStates(
        _line(),
        [_bus(lat: 25.0350, lon: 121.5500)],
        const {},
        now: now,
        refreshSeconds: 10,
      );

      final state = states['KKA-1234']!;
      expect(state.mode, BusMotionMode.snappedToRoute);
      expect(state.routeDistanceAtSampleMeters, isNotNull);
      expect(
        state.positionAt(now, geometry: _line()).longitude,
        closeTo(121.5490, 1e-4),
      );
    });

    test('a bus far off the line free-floats at its own position', () {
      // ~2 km east: a bad fix or a detour, not this route.
      final states = buildAnimatedBusStates(
        _line(),
        [_bus(lat: 25.0350, lon: 121.5690)],
        const {},
        now: now,
        refreshSeconds: 10,
      );

      final state = states['KKA-1234']!;
      expect(state.mode, BusMotionMode.freeFloating);
      expect(state.routeDistanceAtSampleMeters, isNull);
      expect(state.rawPoint.longitude, closeTo(121.5690, 1e-6));
    });

    test('without geometry every bus free-floats', () {
      final states = buildAnimatedBusStates(
        null,
        [_bus(lat: 25.0350, lon: 121.5490)],
        const {},
        now: now,
        refreshSeconds: 10,
      );

      expect(states['KKA-1234']!.mode, BusMotionMode.freeFloating);
      expect(states['KKA-1234']!.distanceToRouteMeters, double.infinity);
    });

    test('buses without a usable position are skipped', () {
      final states = buildAnimatedBusStates(
        _line(),
        [
          _bus(lat: 999, lon: 121.5490),
          _bus(id: 'OK-1', lat: 25.035, lon: 121.549),
        ],
        const {},
        now: now,
        refreshSeconds: 10,
      );

      expect(states.keys, ['OK-1']);
    });

    test('keys default to the plate and can be qualified per route', () {
      final buses = [_bus(lat: 25.0350, lon: 121.5490)];

      expect(
        buildAnimatedBusStates(
          _line(),
          buses,
          const {},
          now: now,
          refreshSeconds: 10,
        ).keys,
        ['KKA-1234'],
      );
      // A city-wide map must qualify: one plate can serve two routes at once.
      expect(
        buildAnimatedBusStates(
          _line(),
          buses,
          const {},
          now: now,
          refreshSeconds: 10,
          keyOf: (bus) => '${bus.routeId}|${bus.id}',
        ).keys,
        ['TPE101320|KKA-1234'],
      );
    });

    test('a moving off-route bus is dead-reckoned forward', () {
      final state = buildAnimatedBusStates(
        null,
        [_bus(lat: 25.0350, lon: 121.5690, speedKph: 36, azimuth: 0)],
        const {},
        now: now,
        refreshSeconds: 10,
      )['KKA-1234']!;

      final later = state.positionAt(now.add(const Duration(seconds: 10)));

      // 10 m/s north for 10 s, so it should have advanced, not jumped.
      expect(later.latitude, greaterThan(25.0350));
      expect(later.latitude, lessThan(25.0362));
    });

    test('a stationary bus stays put however long it has been', () {
      final state = buildAnimatedBusStates(
        null,
        [_bus(lat: 25.0350, lon: 121.5690, speedKph: 0, azimuth: 90)],
        const {},
        now: now,
        refreshSeconds: 10,
      )['KKA-1234']!;

      expect(
        state.positionAt(now.add(const Duration(minutes: 5))),
        state.rawPoint,
      );
    });
  });

  group('animation cost', () {
    final now = DateTime(2026, 9, 6, 21, 40);

    test('a still bus yields the identical point every tick', () {
      // The map reuses marker objects between animation ticks, which only
      // works while an unwatched bus reports the same position.
      final state = buildAnimatedBusStates(
        null,
        [_bus(lat: 25.0350, lon: 121.5690, speedKph: 0, azimuth: 45)],
        const {},
        now: now,
        refreshSeconds: 10,
      )['KKA-1234']!;

      final first = state.positionAt(now.add(const Duration(seconds: 1)));
      final second = state.positionAt(now.add(const Duration(seconds: 2)));

      expect(first, second);
      expect(first, state.rawPoint);
    });

    test('dead reckoning is capped so a stale fix cannot fly away', () {
      final state = buildAnimatedBusStates(
        null,
        [_bus(lat: 25.0350, lon: 121.5690, speedKph: 90, azimuth: 0)],
        const {},
        now: now,
        refreshSeconds: 10,
      )['KKA-1234']!;

      final far = state.positionAt(now.add(const Duration(minutes: 10)));

      // 240 m is the hard ceiling, about 0.0022 degrees of latitude.
      expect(far.latitude - 25.0350, lessThan(0.0025));
    });
  });

  group('effectiveBusSampleTime', () {
    final now = DateTime(2026, 9, 6, 21, 40);

    test('a missing or future timestamp is treated as right now', () {
      expect(effectiveBusSampleTime(null, now, refreshSeconds: 10), now);
      expect(
        effectiveBusSampleTime(
          now.add(const Duration(minutes: 1)),
          now,
          refreshSeconds: 10,
        ),
        now,
      );
    });

    test('a fresh timestamp is kept as reported', () {
      final reported = now.subtract(const Duration(seconds: 5));

      expect(
        effectiveBusSampleTime(reported, now, refreshSeconds: 10),
        reported,
      );
    });

    test(
      'a stale timestamp is clamped so the bus cannot sprint to catch up',
      () {
        final ancient = now.subtract(const Duration(minutes: 10));

        expect(
          effectiveBusSampleTime(ancient, now, refreshSeconds: 30),
          now.subtract(const Duration(seconds: 30)),
        );
        // The floor never drops below 12 s, however fast the caller refreshes.
        expect(
          effectiveBusSampleTime(ancient, now, refreshSeconds: 5),
          now.subtract(const Duration(seconds: 12)),
        );
      },
    );
  });
}
