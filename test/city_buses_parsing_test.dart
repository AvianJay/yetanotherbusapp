import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/http_error_utils.dart';
import 'package:taiwanbus_flutter/core/models.dart';

/// The city feed is the one place where a bus may legitimately arrive without a
/// route, so these tests are mostly about that half-known state staying usable.

const _snapshot = {
  'city': 'Taipei',
  'prefix': 'TPE',
  'updated_at': 1757145600,
  'ttl': 15,
  'stale': false,
  'truncated': false,
  'buses': [
    {
      'id': 'KKA-1234',
      'routeid': 'TPE101320',
      'route_uid': 'TPE10132',
      'direction': 0,
      'lat': 25.03,
      'lon': 121.56,
      'speed': 23,
      'azimuth': 90,
      'status': 0,
      'time': 1757145590,
    },
    {
      'id': 'EAL-0562',
      'routeid': null,
      'route_uid': 'TPE10231',
      'direction': 1,
      'lat': 25.06,
      'lon': 121.53,
      'speed': 0,
      'azimuth': 180,
      'status': 0,
      'time': 1757145592,
    },
  ],
  'routes': {
    'TPE101320': {'name': '234', 'route_uid': 'TPE10132'},
  },
  'families': {
    'TPE10231': {
      'name': '民權幹線',
      'stops_routeid': 'TPE10231',
      'geometry_routeid': 'TPE10272',
      'routeids': ['TPE10231', 'TPE162593'],
    },
  },
};

BusRepository _repository(http.Client client) => BusRepository(client: client);

MockClient _serving(
  Map<String, Object?> body, {
  int status = 200,
  List<int>? hits,
}) {
  return MockClient((request) async {
    hits?.add(1);
    if (!request.url.path.endsWith('/api/v1/cities/TPE/buses')) {
      return http.Response('{}', 404);
    }
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a resolved bus keeps its route and name', () async {
    final repository = _repository(_serving(_snapshot));

    final snapshot = await repository.getCityRealtimeBuses(BusProvider.tpe);

    final bus = snapshot.buses.first;
    expect(bus.routeId, 'TPE101320');
    expect(bus.routeUid, 'TPE10132');
    expect(bus.bus.pathId, 0);
    expect(bus.bus.speedKph, 23);
    expect(bus.bus.azimuth, 90);
    expect(bus.bus.updatedAt, isNotNull);
    expect(snapshot.displayNameFor(bus), '234');
    expect(snapshot.isAmbiguous(bus), isFalse);
    expect(snapshot.detailRouteIdFor(bus), 'TPE101320');
    expect(snapshot.geometryRouteIdFor(bus), 'TPE101320');
  });

  test('an unresolved bus is still named, drawable and openable', () async {
    final repository = _repository(_serving(_snapshot));

    final snapshot = await repository.getCityRealtimeBuses(BusProvider.tpe);

    final bus = snapshot.buses[1];
    expect(bus.routeId, isNull);
    expect(snapshot.isAmbiguous(bus), isTrue);
    expect(snapshot.displayNameFor(bus), '民權幹線');
    // Stops come from a real route; the line may come from a stop-less shape.
    expect(snapshot.detailRouteIdFor(bus), 'TPE10231');
    expect(snapshot.geometryRouteIdFor(bus), 'TPE10272');
    expect(snapshot.families['TPE10231']!.routeIds, ['TPE10231', 'TPE162593']);
    expect(snapshot.families['TPE10231']!.isBareCode, isFalse);
  });

  test(
    'buses are keyed per route so a shared plate does not collide',
    () async {
      final body = Map<String, Object?>.from(_snapshot);
      body['buses'] = [
        {..._snapshot['buses']! as List<dynamic>}.first,
        {
          'id': 'KKA-1234',
          'routeid': null,
          'route_uid': 'TPE10231',
          'direction': 0,
          'lat': 25.06,
          'lon': 121.53,
          'time': 1757145592,
        },
      ];
      final repository = _repository(_serving(body));

      final snapshot = await repository.getCityRealtimeBuses(BusProvider.tpe);

      expect(snapshot.buses.length, 2);
      expect(
        snapshot.buses.map((bus) => bus.stateKey).toSet().length,
        2,
        reason: 'the same plate on two routes must stay two markers',
      );
      expect(snapshot.siblingCountFor(snapshot.buses.first), 1);
    },
  );

  test(
    'unusable rows are skipped rather than failing the whole snapshot',
    () async {
      final body = Map<String, Object?>.from(_snapshot);
      body['buses'] = [
        {'id': '', 'route_uid': 'TPE10132'},
        {'id': 'NO-ROUTE', 'lat': 25.0, 'lon': 121.5},
        {'id': 'BAD-COORD', 'route_uid': 'TPE10132', 'lat': 0, 'lon': 0},
        {
          'id': 'GOOD-1',
          'routeid': 'TPE101320',
          'route_uid': 'TPE10132',
          'lat': 25.03,
          'lon': 121.56,
        },
      ];
      final repository = _repository(_serving(body));

      final snapshot = await repository.getCityRealtimeBuses(BusProvider.tpe);

      expect(snapshot.buses.map((bus) => bus.bus.id), ['GOOD-1']);
    },
  );

  test('a stale or truncated snapshot says so', () async {
    final body = Map<String, Object?>.from(_snapshot);
    body['stale'] = true;
    body['truncated'] = true;
    final repository = _repository(_serving(body));

    final snapshot = await repository.getCityRealtimeBuses(BusProvider.tpe);

    expect(snapshot.stale, isTrue);
    expect(snapshot.truncated, isTrue);
    expect(snapshot.ttlSeconds, 15);
  });

  test('repeat calls within the cache window make one request', () async {
    final hits = <int>[];
    final repository = _repository(_serving(_snapshot, hits: hits));

    await Future.wait([
      repository.getCityRealtimeBuses(BusProvider.tpe),
      repository.getCityRealtimeBuses(BusProvider.tpe),
    ]);
    await repository.getCityRealtimeBuses(BusProvider.tpe);

    expect(hits.length, 1);
  });

  test('rate limiting surfaces as the shared message', () async {
    final repository = _repository(_serving(const {}, status: 429));

    expect(
      () => repository.getCityRealtimeBuses(BusProvider.tpe),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains(rateLimitedErrorMessage),
        ),
      ),
    );
  });

  test(
    'a server without the endpoint reads as unsupported, not broken',
    () async {
      final repository = _repository(_serving(const {}, status: 404));

      expect(
        () => repository.getCityRealtimeBuses(BusProvider.tpe),
        throwsA(isA<CityBusFeedUnavailableException>()),
      );
    },
  );

  test(
    'routeKeyForRouteId matches what route detail is addressed by',
    () async {
      final repository = _repository(_serving(_snapshot));

      // Same routeid must always give the same key, or deep links break.
      expect(
        repository.routeKeyForRouteId('TPE101320'),
        repository.routeKeyForRouteId('TPE101320'),
      );
      expect(
        repository.routeKeyForRouteId('TPE101320'),
        isNot(repository.routeKeyForRouteId('TPE10231')),
      );
    },
  );
}
