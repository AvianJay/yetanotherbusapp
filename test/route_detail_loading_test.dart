import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object> stopsPayload(
  String id, {
  String name = '500',
  String stopName = '共用站',
}) => {
  'routeid': id,
  'name': name,
  'paths': [
    for (final path in [0, 1])
      {
        'pathid': path,
        'name': path == 0 ? '去程' : '返程',
        'stops': [
          {
            'stopid': 'S$path',
            'seq': 1,
            'name': '$stopName$path',
            'lat': 24.1,
            'lon': 120.65,
          },
        ],
      },
  ],
};

Map<String, Object> livePayload(String id, int eta) => {
  'routeid': id,
  'paths': [
    {
      'pathid': 0,
      'stops': [
        {
          'stopid': 'S0',
          'eta': eta,
          'message': '',
          'updated_at': DateTime.now().toIso8601String(),
          'buses': [
            {'id': '$id-bus', 'type': 'normal'},
          ],
        },
      ],
    },
  ],
};

List<Map<String, Object>> familyPayload() => [
  {'routeid': 'TXG500', 'route_name': '500', 'pathid': 0, 'path_name': '去程'},
  {'routeid': 'TXG501', 'route_name': '500延', 'pathid': 0, 'path_name': '去程'},
];

Stream<RouteDetailUpdate> watch(BusRepository repository) =>
    repository.watchRouteDetail(
      500,
      provider: BusProvider.txg,
      routeIdHint: 'TXG500',
      routeNameHint: '500',
    );

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue, reason: 'Expected asynchronous work did not start');
}

void main() {
  late Directory directory;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('route-loading-');
    await databaseFactory.setDatabasesPath(directory.path);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'stops and selected ETA render independently of slow family requests',
    () async {
      final stops = Completer<http.Response>();
      final live = Completer<http.Response>();
      final family = Completer<http.Response>();
      final siblingLive = Completer<http.Response>();
      final paths = <String>[];
      final repository = BusRepository(
        client: MockClient((request) async {
          final path = request.url.path;
          paths.add(path);
          if (path.endsWith('/TXG500/stops')) return stops.future;
          if (path.endsWith('/TXG500/realtime')) return live.future;
          if (path.endsWith('/routes')) return family.future;
          if (path.endsWith('/TXG501/stops')) {
            return jsonResponse(stopsPayload('TXG501', name: '500延'));
          }
          if (path.contains('/batchroutes/')) return siblingLive.future;
          throw StateError('Unexpected request: $path');
        }),
      );
      final updates = <RouteDetailUpdate>[];
      final finished = watch(repository).forEach(updates.add);
      await until(() => paths.length == 2);
      expect(
        paths,
        containsAll([
          '/api/v1/routes/TXG500/stops',
          '/api/v1/routes/TXG500/realtime',
        ]),
      );
      stops.complete(jsonResponse(stopsPayload('TXG500')));
      await until(() => updates.isNotEmpty);
      expect(updates.single.phase, RouteDetailPhase.stops);
      expect(updates.single.detail.paths.map((p) => p.pathId), [0, 1]);
      expect(updates.single.detail.stopsByPath[0]!.single.sec, isNull);
      live.complete(jsonResponse(livePayload('TXG500', 300)));
      await until(() => updates.length == 2);
      expect(updates.last.phase, RouteDetailPhase.realtime);
      expect(updates.last.detail.stopsByPath[0]!.single.sec, 300);
      expect(paths.where((p) => p.contains('/batchroutes/')), isEmpty);
      family.complete(jsonResponse(familyPayload()));
      await until(() => paths.any((p) => p.contains('/batchroutes/')));
      expect(paths.last, '/api/v1/batchroutes/TXG501/realtime');
      siblingLive.complete(
        jsonResponse({
          'routes': {'TXG501': livePayload('TXG501', 120)},
        }),
      );
      await finished;
      expect(updates.last.phase, RouteDetailPhase.family);
      expect(updates.last.detail.stopsByPath[0]!.single.sec, 120);
      expect(updates.last.detail.stopsByPath[0]!.single.buses, hasLength(2));
      expect(updates.first.detail.stopsByPath[0]!.single.buses, isEmpty);
      expect(updates[1].detail.stopsByPath[0]!.single.sec, 300);

      final before = paths.length;
      final reopened = await watch(repository).toList();
      expect(paths.length, before);
      expect(reopened.first.detail.stopsByPath[0]!.single.sec, isNull);
      expect(reopened.last.detail.stopsByPath[0]!.single.buses, hasLength(2));
    },
  );

  test(
    'concurrent watchers coalesce stops, realtime and negative family lookups',
    () async {
      final paths = <String>[];
      final repository = BusRepository(
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/stops')) {
            return jsonResponse(stopsPayload('TXG500'));
          }
          if (request.url.path.endsWith('/realtime')) {
            return jsonResponse(livePayload('TXG500', 90));
          }
          return jsonResponse([]);
        }),
      );
      final results = await Future.wait([
        watch(repository).toList(),
        watch(repository).toList(),
      ]);
      expect(
        results.every((updates) => updates.last.detail.hasLiveData),
        isTrue,
      );
      expect(paths, hasLength(3));
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      await watch(repository).toList();
      expect(paths.where((p) => p.endsWith('/stops')), hasLength(1));
      expect(paths.where((p) => p.endsWith('/routes')), hasLength(1));
      expect(paths.where((p) => p.endsWith('/realtime')), hasLength(2));
    },
  );

  test(
    'batch shares overlapping pending requests and excludes cached routes',
    () async {
      final single = Completer<http.Response>();
      final batch = Completer<http.Response>();
      final paths = <String>[];
      final repository = BusRepository(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return request.url.path.contains('/batchroutes/')
              ? batch.future
              : single.future;
        }),
      );
      repository.preloadRealtimeCache('TXG500', {});
      final singleWork = repository.getLiveStopMap('TXG501');
      final batchWork = repository.getBatchLiveStopMaps([
        'TXG500',
        'TXG501',
        'TXG502',
      ]);
      final overlapping = repository.getBatchLiveStopMaps(['TXG501', 'TXG502']);
      final sharedSingle = repository.getLiveStopMap('TXG502');
      await until(() => paths.length == 2);
      expect(paths, [
        '/api/v1/routes/TXG501/realtime',
        '/api/v1/batchroutes/TXG502/realtime',
      ]);
      single.complete(jsonResponse(livePayload('TXG501', 60)));
      batch.complete(
        jsonResponse({
          'routes': {'TXG502': livePayload('TXG502', 120)},
        }),
      );
      await singleWork;
      expect(
        (await batchWork).keys,
        containsAll(['TXG500', 'TXG501', 'TXG502']),
      );
      expect((await overlapping).keys, containsAll(['TXG501', 'TXG502']));
      expect(await sharedSingle, isNotEmpty);
      expect(paths, hasLength(2));
    },
  );

  test(
    'missing batch routes remain retryable without discarding successful routes',
    () async {
      var requests = 0;
      final repository = BusRepository(
        client: MockClient((request) async {
          requests++;
          if (request.url.path.contains('/batchroutes/')) {
            return jsonResponse({
              'routes': {'TXG500': livePayload('TXG500', 120)},
            });
          }
          return jsonResponse(livePayload('TXG501', 60));
        }),
      );
      final partial = await repository.getBatchLiveStopMaps([
        'TXG500',
        'TXG501',
      ]);
      expect(partial.keys, ['TXG500']);
      expect(await repository.getLiveStopMap('TXG501'), isNotEmpty);
      expect(requests, 2);
    },
  );

  test(
    'early realtime error is handled while stops are still loading',
    () async {
      final stops = Completer<http.Response>();
      final repository = BusRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/stops')) return stops.future;
          if (request.url.path.endsWith('/realtime')) {
            return jsonResponse({}, 429);
          }
          return jsonResponse([]);
        }),
      );
      final work = watch(repository).toList();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      stops.complete(jsonResponse(stopsPayload('TXG500')));
      final updates = await work;
      expect(updates.map((u) => u.phase), [
        RouteDetailPhase.stops,
        RouteDetailPhase.realtime,
        RouteDetailPhase.family,
      ]);
      expect(updates.last.detail.hasLiveData, isFalse);
      expect(updates.last.detail.stopsByPath[0]!.single.stopName, '共用站0');
    },
  );

  test(
    'family failures keep selected data and are not cached as no siblings',
    () async {
      var searches = 0;
      final repository = BusRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/stops')) {
            return jsonResponse(stopsPayload('TXG500'));
          }
          if (request.url.path.endsWith('/realtime')) {
            return jsonResponse(livePayload('TXG500', 120));
          }
          searches++;
          return searches == 1 ? jsonResponse({}, 503) : jsonResponse([]);
        }),
      );
      final first = await watch(repository).last;
      expect(first.familyUnavailable, isTrue);
      expect(first.detail.stopsByPath[0]!.single.sec, 120);
      await watch(repository).last;
      expect(searches, 2);
    },
  );

  test(
    'database invalidation prevents old responses repopulating caches',
    () async {
      final oldStops = Completer<http.Response>();
      final oldLive = Completer<http.Response>();
      var stopRequests = 0;
      var liveRequests = 0;
      final repository = BusRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/stops')) {
            stopRequests++;
            return stopRequests == 1
                ? oldStops.future
                : jsonResponse(stopsPayload('TXG500', stopName: '新站'));
          }
          if (request.url.path.endsWith('/realtime')) {
            liveRequests++;
            return liveRequests == 1
                ? oldLive.future
                : jsonResponse(livePayload('TXG500', 60));
          }
          return jsonResponse([]);
        }),
      );
      final obsolete = watch(repository).toList();
      await until(() => stopRequests == 1 && liveRequests == 1);
      repository.invalidateRouteData();
      final fresh = await watch(repository).last;
      oldStops.complete(jsonResponse(stopsPayload('TXG500', stopName: '舊站')));
      oldLive.complete(jsonResponse(livePayload('TXG500', 900)));
      expect(await obsolete, isEmpty);
      final reopened = await watch(repository).last;
      expect(fresh.detail.stopsByPath[0]!.single.stopName, '新站0');
      expect(reopened.detail.stopsByPath[0]!.single.stopName, '新站0');
      expect(reopened.detail.stopsByPath[0]!.single.sec, 60);
      expect(stopRequests, 2);
      expect(liveRequests, 2);
    },
  );

  test('local database supplies the first stage without a stops request', () async {
    final folder = await Directory('${directory.path}/.yabus_backend').create();
    final metadata = await openDatabase(
      '${folder.path}/routes_metadata_v1.sqlite',
    );
    await metadata.execute(
      'CREATE TABLE routes(routeid TEXT, name TEXT, name_en TEXT, path_name TEXT)',
    );
    await metadata.execute(
      'CREATE TABLE paths(routeid TEXT, pathid INTEGER, name TEXT, name_en TEXT)',
    );
    await metadata.insert('routes', {
      'routeid': 'TXG500',
      'name': '500',
      'name_en': '500',
      'path_name': '去程',
    });
    await metadata.insert('paths', {
      'routeid': 'TXG500',
      'pathid': 0,
      'name': '去程',
      'name_en': 'Outbound',
    });
    await metadata.close();
    final city = await openDatabase('${folder.path}/bus_txg_v2.sqlite');
    await city.execute(
      'CREATE TABLE stops(routeid TEXT, pathid INTEGER, stopid TEXT, name TEXT, seq INTEGER, lon REAL, lat REAL)',
    );
    await city.insert('stops', {
      'routeid': 'TXG500',
      'pathid': 0,
      'stopid': 'S0',
      'name': '離線站',
      'seq': 1,
      'lon': 120.65,
      'lat': 24.1,
    });
    await city.close();
    final live = Completer<http.Response>();
    final paths = <String>[];
    final repository = BusRepository(
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/realtime')) return live.future;
        if (request.url.path.endsWith('/routes')) return jsonResponse([]);
        throw StateError('Local stops unexpectedly requested via API');
      }),
    );
    final updates = <RouteDetailUpdate>[];
    final work = watch(repository).forEach(updates.add);
    await until(() => updates.isNotEmpty);
    expect(updates.first.detail.stopsByPath[0]!.single.stopName, '離線站');
    live.complete(jsonResponse(livePayload('TXG500', 30)));
    await work;
    expect(paths.any((p) => p.endsWith('/stops')), isFalse);
  });
}
