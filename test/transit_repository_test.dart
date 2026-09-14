import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/transit_repository.dart';

void main() {
  test('caches requests and de-duplicates in-flight work', () async {
    var requests = 0;
    final repository = TransitRepository(
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '[{"system":"taipei","city":"taipei","name":"Taipei Metro","name_en":"Taipei Metro"}]',
          200,
        );
      }),
    );

    final responses = await Future.wait([
      repository.getMetroSystems(),
      repository.getMetroSystems(),
    ]);
    await repository.getMetroSystems();

    expect(requests, 1);
    expect(responses.first.single.system, 'taipei');
  });

  test('invalidating a transport prefix fetches fresh data', () async {
    var requests = 0;
    final repository = TransitRepository(
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '[{"system":"taipei","city":"taipei","name":"Taipei Metro","name_en":"Taipei Metro"}]',
          200,
        );
      }),
    );

    await repository.getMetroSystems();
    repository.invalidateCache('metro_');
    await repository.getMetroSystems();

    expect(requests, 2);
  });

  test('an invalidated in-flight response cannot replace fresh data', () async {
    final firstResponse = Completer<http.Response>();
    var requests = 0;
    final repository = TransitRepository(
      client: MockClient((_) async {
        requests++;
        if (requests == 1) {
          return firstResponse.future;
        }
        return http.Response(
          '[{"system":"fresh","city":"taipei","name":"Fresh","name_en":"Fresh"}]',
          200,
        );
      }),
    );

    final staleRequest = repository.getMetroSystems();
    await Future<void>.delayed(Duration.zero);
    repository.invalidateCache('metro_');
    final fresh = await repository.getMetroSystems();
    firstResponse.complete(
      http.Response(
        '[{"system":"stale","city":"taipei","name":"Stale","name_en":"Stale"}]',
        200,
      ),
    );
    await staleRequest;
    final cached = await repository.getMetroSystems();

    expect(requests, 2);
    expect(fresh.single.system, 'fresh');
    expect(cached.single.system, 'fresh');
  });

  test('bounds cache entries for location-specific requests', () async {
    var requests = 0;
    final repository = TransitRepository(
      cacheCapacity: 1,
      client: MockClient((request) async {
        requests++;
        if (request.url.path.endsWith('/stations')) {
          return http.Response('[{"station_id":"1000"}]', 200);
        }
        return http.Response(
          '[{"system":"taipei","city":"taipei","name":"Taipei Metro","name_en":"Taipei Metro"}]',
          200,
        );
      }),
    );

    await repository.getMetroSystems();
    await repository.getTraStations();
    await repository.getMetroSystems();

    expect(requests, 3);
  });

  test('a missing station-of-line endpoint degrades to an empty list', () async {
    final repository = TransitRepository(
      client: MockClient((_) async => http.Response('Not Found', 404)),
    );

    expect(await repository.getTraStationOfLine(), isEmpty);
  });

  test('a failed station-of-line fetch is not cached', () async {
    // The try/catch has to sit outside _cached: this endpoint has a one-hour
    // TTL, so caching a momentary failure would keep the picker's line column
    // missing for an hour.
    var requests = 0;
    final repository = TransitRepository(
      client: MockClient((_) async {
        requests++;
        if (requests == 1) {
          return http.Response('Not Found', 404);
        }
        // Built from UTF-8 bytes like the real server sends: the String
        // constructor would encode these as latin1 and apiResponseText decodes
        // as UTF-8.
        return http.Response.bytes(
          utf8.encode(
            '[{"line_id":"WL","line_name":"西部幹線",'
            '"stations":[{"station_id":"1000","name":"臺北","sequence":0}]}]',
          ),
          200,
        );
      }),
    );

    expect(await repository.getTraStationOfLine(), isEmpty);
    final second = await repository.getTraStationOfLine();

    expect(requests, 2);
    expect(second.single.lineId, 'WL');
    expect(second.single.lineName, '西部幹線');
    expect(second.single.stations.single.stationId, '1000');
  });

  test('a successful station-of-line fetch is cached', () async {
    var requests = 0;
    final repository = TransitRepository(
      client: MockClient((_) async {
        requests++;
        return http.Response.bytes(
          utf8.encode('[{"line_id":"WL","line_name":"西部幹線","stations":[]}]'),
          200,
        );
      }),
    );

    await repository.getTraStationOfLine();
    await repository.getTraStationOfLine();

    expect(requests, 1);
  });
}
