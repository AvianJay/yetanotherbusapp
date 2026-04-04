import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  test('tracked bus snapshot parses zlib xml payload', () async {
    final repository = BusRepository(
      client: MockClient((request) async {
        expect(request.url.path, '/api/bus/EAL-5957');
        return http.Response.bytes(
          zlib.encode(
            utf8.encode(
              '<?xml version="1.0" encoding="utf-8"?>'
              '<b bid="EAL-5957" lon="120.646928" lat="24.143403" '
              'key="304030" rid="4030" rzh="綠3" pid="0" '
              'pzh="往臺中市議會" sid="21827" szh="文心大墩七街口" '
              'carOnStop="true"/>',
            ),
          ),
          200,
          headers: const {'content-type': 'application/octet-stream'},
        );
      }),
    );

    final snapshot = await repository.getTrackedBusSnapshot(
      const TrackedBus(provider: BusProvider.twn, vehicleId: 'EAL-5957'),
    );

    expect(snapshot.state, TrackedBusState.online);
    expect(snapshot.currentRouteKey, 304030);
    expect(snapshot.currentRouteName, '綠3');
    expect(snapshot.currentPathId, 0);
    expect(snapshot.currentStopId, 21827);
    expect(snapshot.currentStopName, '文心大墩七街口');
    expect(snapshot.carOnStop, isTrue);
  });

  test(
    'tracked bus snapshot treats plain Offline response as offline',
    () async {
      final repository = BusRepository(
        client: MockClient((request) async {
          return http.Response('Offline', 210);
        }),
      );

      final snapshot = await repository.getTrackedBusSnapshot(
        const TrackedBus(provider: BusProvider.twn, vehicleId: '760-U1'),
      );

      expect(snapshot.state, TrackedBusState.offline);
      expect(snapshot.isOnline, isFalse);
    },
  );
}
