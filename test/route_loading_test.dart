import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('route topology is available while realtime remains pending', () async {
    final realtimeResponse = Completer<http.Response>();
    var stopRequests = 0;
    var realtimeRequests = 0;
    final client = MockClient((request) {
      if (request.url.path.endsWith('/api/v1/routes/TXG5000/stops')) {
        stopRequests += 1;
        return Future.value(_jsonResponse(_routeStopsPayload));
      }
      if (request.url.path.endsWith('/api/v1/routes/TXG5000/realtime')) {
        realtimeRequests += 1;
        return realtimeResponse.future;
      }
      return Future.value(http.Response('not found', 404));
    });
    final repository = BusRepository(client: client);

    var completeDetailFinished = false;
    final completeDetail = repository
        .getCompleteBusInfo(
          500,
          provider: BusProvider.txg,
          routeIdHint: 'TXG5000',
          routeNameHint: '500',
        )
        .then((detail) {
          completeDetailFinished = true;
          return detail;
        });

    final topology = await repository.getRouteTopology(
      500,
      provider: BusProvider.txg,
      routeIdHint: 'TXG5000',
      routeNameHint: '500',
    );

    expect(topology.route.routeName, '500');
    expect(topology.stopsByPath[0]!.single.stopName, '測試站');
    expect(topology.hasLiveData, isFalse);
    expect(completeDetailFinished, isFalse);
    expect(stopRequests, 1);
    expect(realtimeRequests, 1);

    final canonicalTopology = await repository.getRouteTopology(
      500,
      provider: BusProvider.txg,
      routeIdHint: 'TXG5000',
    );
    expect(canonicalTopology.route.routeName, '500 官方');

    realtimeResponse.complete(_jsonResponse(_routeRealtimePayload));
    final detail = await completeDetail;

    expect(detail.hasLiveData, isTrue);
    expect(detail.stopsByPath[0]!.single.sec, 45);
    expect(stopRequests, 1);
  });

  test('route family lookup outlives the short search cache', () async {
    var searchRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/cities/Taichung/routes')) {
        searchRequests += 1;
        return _jsonResponse([
          {
            'routeid': 'TXG5000',
            'route_name': '500',
            'pathid': 0,
            'path_name': '主線',
          },
          {
            'routeid': 'TXG5002',
            'route_name': '500延',
            'pathid': 0,
            'path_name': '延駛',
          },
        ]);
      }
      return http.Response('not found', 404);
    });
    final repository = BusRepository(client: client);
    const selected = RouteSummary(
      sourceProvider: 'TXG',
      hashMd5: '',
      routeKey: 500,
      routeId: 'TXG5000',
      routeName: '500',
      officialRouteName: '500',
      description: '',
      category: '',
      sequence: 0,
      rtrip: 0,
    );

    final first = await repository.getRouteFamily(
      selected,
      provider: BusProvider.txg,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    final second = await repository.getRouteFamily(
      selected,
      provider: BusProvider.txg,
    );

    expect(first.map((route) => route.routeId), ['TXG5000', 'TXG5002']);
    expect(second.map((route) => route.routeId), ['TXG5000', 'TXG5002']);
    expect(searchRequests, 1);
  });

  test('failed route family lookups are not cached', () async {
    var searchRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/cities/Taichung/routes')) {
        searchRequests += 1;
        if (searchRequests == 1) {
          return http.Response('unavailable', 503);
        }
        return _jsonResponse([
          {
            'routeid': 'TXG5000',
            'route_name': '500',
            'pathid': 0,
            'path_name': '主線',
          },
        ]);
      }
      return http.Response('not found', 404);
    });
    final repository = BusRepository(client: client);
    const selected = RouteSummary(
      sourceProvider: 'TXG',
      hashMd5: '',
      routeKey: 500,
      routeId: 'TXG5000',
      routeName: '500',
      officialRouteName: '500',
      description: '',
      category: '',
      sequence: 0,
      rtrip: 0,
    );

    await expectLater(
      repository.getRouteFamily(selected, provider: BusProvider.txg),
      throwsA(isA<HttpException>()),
    );
    final family = await repository.getRouteFamily(
      selected,
      provider: BusProvider.txg,
    );

    expect(family.single.routeId, 'TXG5000');
    expect(searchRequests, 2);
  });
}

http.Response _jsonResponse(Object body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

const _routeStopsPayload = <String, Object>{
  'routeid': 'TXG5000',
  'name': '500 官方',
  'paths': <Object>[
    <String, Object>{
      'pathid': 0,
      'name': '主線',
      'stops': <Object>[
        <String, Object>{
          'stopid': 'STOP-1',
          'seq': 1,
          'name': '測試站',
          'lat': 24.1,
          'lon': 120.6,
        },
      ],
    },
  ],
};

const _routeRealtimePayload = <String, Object>{
  'routeid': 'TXG5000',
  'paths': <Object>[
    <String, Object>{
      'pathid': 0,
      'stops': <Object>[
        <String, Object>{
          'stopid': 'STOP-1',
          'eta': 45,
          'message': '',
          'updated_at': '2026-09-18T12:00:00+08:00',
          'buses': <Object>[],
          'etas': <Object>[],
        },
      ],
    },
  ],
};
