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
