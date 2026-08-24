import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';

http.Response _passbyResponse({
  required String stopId,
  required String stopName,
  required List<Map<String, Object?>> routes,
}) {
  return http.Response(
    jsonEncode({'stopid': stopId, 'stop_name': stopName, 'routes': routes}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, Object?> _passbyRoute(
  String routeId, {
  int pathId = 0,
  int? eta,
}) {
  return {
    'routeid': routeId,
    'route_name': routeId.substring(3),
    'route_name_en': routeId.substring(3),
    'pathid': pathId,
    'path_name': 'Outbound',
    'path_name_en': 'Outbound',
    'seq': 3,
    'stopid': '39',
    'eta': eta,
    'message': '',
    'updated_at': 1000,
    'buses': <Object?>[],
    'etas': <Object?>[],
  };
}

void main() {
  test('getStopPassby scopes the request to the provider city', () async {
    Uri? requestedUrl;
    final client = MockClient((request) async {
      requestedUrl = request.url;
      return _passbyResponse(
        stopId: '39',
        stopName: '中臺科技大學',
        routes: [_passbyRoute('TXG0001', eta: 120)],
      );
    });

    final repository = BusRepository(client: client);
    final results = await repository.getStopPassby(
      '39',
      provider: BusProvider.txg,
      expectedStopName: '中臺科技大學',
    );

    expect(requestedUrl, isNotNull);
    expect(requestedUrl!.path, '/api/v1/stops/39/passby');
    expect(requestedUrl!.queryParameters['city'], 'TXG');
    expect(results, hasLength(1));
    expect(results.single.route.routeId, 'TXG0001');
    expect(results.single.matchedStop.sec, 120);
    expect(results.single.matchedStop.stopName, '中臺科技大學');
  });

  test(
    'getStopPassby discards a response for a different stop name '
    '(legacy server ignoring the city parameter)',
    () async {
      final client = MockClient((request) async {
        // An old server ignores ?city= and answers with whichever city's
        // stop happens to share the numeric id — here Matsu instead of
        // Taichung.
        return _passbyResponse(
          stopId: '39',
          stopName: '福澳碼頭',
          routes: [_passbyRoute('LIE16'), _passbyRoute('LIE18')],
        );
      });

      final repository = BusRepository(client: client);
      final results = await repository.getStopPassby(
        '39',
        provider: BusProvider.txg,
        expectedStopName: '中臺科技大學',
      );

      expect(results, isEmpty);
    },
  );

  test('getStopPassby ignores case and whitespace when matching names', () async {
    final client = MockClient((request) async {
      return _passbyResponse(
        stopId: '39',
        stopName: ' Chung Tai  University ',
        routes: [_passbyRoute('TXG0001')],
      );
    });

    final repository = BusRepository(client: client);
    final results = await repository.getStopPassby(
      '39',
      provider: BusProvider.txg,
      expectedStopName: 'chungtai university',
    );

    expect(results, hasLength(1));
  });

  test('getStopPassby without an expected name keeps the response', () async {
    final client = MockClient((request) async {
      return _passbyResponse(
        stopId: '39',
        stopName: '福澳碼頭',
        routes: [_passbyRoute('LIE16')],
      );
    });

    final repository = BusRepository(client: client);
    final results = await repository.getStopPassby(
      '39',
      provider: BusProvider.lie,
    );

    expect(results, hasLength(1));
    expect(results.single.route.routeId, 'LIE16');
  });

  test('getStopPassby returns empty on 404', () async {
    final client = MockClient((request) async {
      return http.Response('{"detail":"Stop 39 was not found."}', 404);
    });

    final repository = BusRepository(client: client);
    final results = await repository.getStopPassby(
      '39',
      provider: BusProvider.tpe,
      expectedStopName: '任何站',
    );

    expect(results, isEmpty);
  });
}
