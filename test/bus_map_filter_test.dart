import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/bus_map_filter.dart';
import 'package:taiwanbus_flutter/core/models.dart';

/// The filters decide what a rider sees on a map holding hundreds of buses, so
/// the edge cases here are the ones where a bus would wrongly vanish.

CityBus _bus({
  required String id,
  String? routeId,
  required String routeUid,
  double lat = 25.03,
  double lon = 121.56,
}) {
  return CityBus(
    bus: RouteRealtimeBus(
      id: id,
      routeId: routeId ?? routeUid,
      pathId: 0,
      lat: lat,
      lon: lon,
    ),
    routeUid: routeUid,
    routeId: routeId,
  );
}

CityBusSnapshot _snapshot(List<CityBus> buses) {
  return CityBusSnapshot(
    provider: BusProvider.tpe,
    buses: buses,
    routes: const {
      'TPE101320': CityBusRouteInfo(
        routeId: 'TPE101320',
        name: '234',
        routeUid: 'TPE10132',
      ),
      'TPE108440': CityBusRouteInfo(
        routeId: 'TPE108440',
        name: '652',
        routeUid: 'TPE10844',
      ),
    },
    families: const {
      'TPE10231': CityBusFamily(
        routeUid: 'TPE10231',
        name: '民權幹線',
        routeIds: ['TPE10231', 'TPE162593'],
        stopsRouteId: 'TPE10231',
        geometryRouteId: 'TPE10231',
      ),
    },
    ttlSeconds: 15,
  );
}

bool _always(CityBus bus) => true;

void main() {
  final resolved = _bus(id: 'KKA-1234', routeId: 'TPE101320', routeUid: 'TPE10132');
  final other = _bus(id: 'EAL-0001', routeId: 'TPE108440', routeUid: 'TPE10844');
  final ambiguous = _bus(id: 'EAL-0562', routeUid: 'TPE10231');
  final snapshot = _snapshot([resolved, other, ambiguous]);

  group('favoriteRouteIdsFor', () {
    test('collects both favourite kinds for the right authority only', () {
      final groups = {
        '路線': <FavoriteItem>[
          const FavoriteRoute(
            provider: BusProvider.tpe,
            routeKey: 1,
            routeId: 'TPE101320',
            routeName: '234',
          ),
          // Another city's favourite must not leak into this map.
          const FavoriteRoute(
            provider: BusProvider.txg,
            routeKey: 2,
            routeId: 'TXG73',
            routeName: '73',
          ),
        ],
        '站牌': <FavoriteItem>[
          const FavoriteStop(
            provider: BusProvider.tpe,
            routeKey: 3,
            pathId: 0,
            stopId: 9,
            routeId: 'TPE108440',
          ),
          // Saved before routeids were stored: nothing to match on.
          const FavoriteStop(
            provider: BusProvider.tpe,
            routeKey: 4,
            pathId: 0,
            stopId: 10,
          ),
        ],
      };

      expect(
        favoriteRouteIdsFor(groups, BusProvider.tpe),
        {'TPE101320', 'TPE108440'},
      );
    });
  });

  group('busMatchesFilters', () {
    test('without filters every bus passes', () {
      for (final bus in snapshot.buses) {
        expect(
          busMatchesFilters(
            snapshot,
            bus,
            favoritesOnly: false,
            favoriteRouteIds: const {},
            normalizedQuery: '',
          ),
          isTrue,
        );
      }
    });

    test('favourites-only matches an unpinned bus by any family member', () {
      // The rider favourited a 區間 variant, not the route the feed reports.
      const favorites = {'TPE162593'};

      expect(
        busMatchesFilters(
          snapshot,
          ambiguous,
          favoritesOnly: true,
          favoriteRouteIds: favorites,
          normalizedQuery: '',
        ),
        isTrue,
      );
      expect(
        busMatchesFilters(
          snapshot,
          resolved,
          favoritesOnly: true,
          favoriteRouteIds: favorites,
          normalizedQuery: '',
        ),
        isFalse,
      );
    });

    test('favourites-only with nothing favourited hides everything', () {
      expect(
        busMatchesFilters(
          snapshot,
          resolved,
          favoritesOnly: true,
          favoriteRouteIds: const {},
          normalizedQuery: '',
        ),
        isFalse,
      );
    });

    test('the query matches a route name or a plate', () {
      expect(
        busMatchesFilters(
          snapshot,
          resolved,
          favoritesOnly: false,
          favoriteRouteIds: const {},
          normalizedQuery: '234',
        ),
        isTrue,
      );
      expect(
        busMatchesFilters(
          snapshot,
          resolved,
          favoritesOnly: false,
          favoriteRouteIds: const {},
          normalizedQuery: 'kka',
        ),
        isTrue,
      );
      expect(
        busMatchesFilters(
          snapshot,
          other,
          favoritesOnly: false,
          favoriteRouteIds: const {},
          normalizedQuery: '234',
        ),
        isFalse,
      );
    });
  });

  group('normalizeRouteQuery', () {
    test('folds full-width input so a Chinese keyboard still matches', () {
      expect(normalizeRouteQuery('２３４'), '234');
      expect(normalizeRouteQuery('  ６５２  '), '652');
      expect(normalizeRouteQuery('Ｒ１０'), 'r10');
      expect(normalizeRouteQuery('民權幹線'), '民權幹線');
    });
  });

  group('clusterBuses', () {
    test('groups nearby buses and counts them', () {
      final buses = [
        _bus(id: 'A', routeUid: 'U1', lat: 25.030, lon: 121.560),
        _bus(id: 'B', routeUid: 'U2', lat: 25.031, lon: 121.561),
        // Far enough away to land in its own cell.
        _bus(id: 'C', routeUid: 'U3', lat: 25.200, lon: 121.700),
      ];

      final clusters = clusterBuses(buses, 0.05);

      expect(clusters.length, 2);
      expect(clusters.map((cluster) => cluster.count).toList()..sort(), [1, 2]);
      expect(
        clusters.fold<int>(0, (sum, cluster) => sum + cluster.count),
        buses.length,
        reason: 'clustering must not lose or invent buses',
      );
    });

    test('a cluster sits on its members, not on a grid corner', () {
      final clusters = clusterBuses([
        _bus(id: 'A', routeUid: 'U1', lat: 25.040, lon: 121.560),
        _bus(id: 'B', routeUid: 'U2', lat: 25.060, lon: 121.580),
      ], 0.5);

      expect(clusters.single.count, 2);
      expect(clusters.single.lat, closeTo(25.05, 1e-9));
      expect(clusters.single.lon, closeTo(121.57, 1e-9));
    });

    test('cells stay the same size on screen as zoom changes', () {
      // Each zoom level halves the ground covered by a screen pixel.
      expect(
        clusterCellDegrees(12),
        closeTo(clusterCellDegrees(11) / 2, 1e-9),
      );
      expect(clusterCellDegrees(11), closeTo(0.0549, 1e-3));
      expect(clusterBuses(const [], clusterCellDegrees(11)), isEmpty);
    });

    test('is stable, so bubbles do not jump between refreshes', () {
      final buses = [
        _bus(id: 'A', routeUid: 'U1', lat: 25.030, lon: 121.560),
        _bus(id: 'B', routeUid: 'U2', lat: 25.031, lon: 121.561),
      ];

      final first = clusterBuses(buses, 0.05);
      final second = clusterBuses(buses.reversed.toList(), 0.05);

      expect(first.map((c) => c.key), second.map((c) => c.key));
    });
  });

  group('visibleBusesFor', () {
    test('hides what the viewport excludes', () {
      final buses = visibleBusesFor(
        snapshot,
        favoritesOnly: false,
        favoriteRouteIds: const {},
        query: '',
        visible: (bus) => bus.bus.id != 'EAL-0001',
      );

      expect(buses.map((bus) => bus.bus.id), ['KKA-1234', 'EAL-0562']);
    });

    test('under a cap it keeps the watched route, then favourites', () {
      final crowd = [
        for (var index = 0; index < 10; index++)
          _bus(
            id: 'FILLER-$index',
            routeId: 'TPE108440',
            routeUid: 'TPE10844',
            lat: 25.2 + index / 100,
          ),
        resolved,
        ambiguous,
      ];
      final crowded = _snapshot(crowd);

      final kept = visibleBusesFor(
        crowded,
        favoritesOnly: false,
        favoriteRouteIds: const {'TPE162593'},
        query: '',
        visible: _always,
        selectedGroupKey: 'TPE101320',
        limit: 2,
        centerLat: 25.03,
        centerLon: 121.56,
      );

      // The bus being watched first, then the favourite family.
      expect(kept.map((bus) => bus.bus.id), ['KKA-1234', 'EAL-0562']);
    });

    test('without a cap nothing is dropped or reordered', () {
      final kept = visibleBusesFor(
        snapshot,
        favoritesOnly: false,
        favoriteRouteIds: const {},
        query: '',
        visible: _always,
      );

      expect(kept.length, 3);
      expect(kept.first.bus.id, 'KKA-1234');
    });
  });
}
