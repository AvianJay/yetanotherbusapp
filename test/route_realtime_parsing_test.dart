import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test('route detail parsing preserves backfilled eta and bus metadata', () async {
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/api/v1/routes/TXG307/stops')) {
        return http.Response(
          jsonEncode({
            'routeid': 'TXG307',
            'name': '307',
            'paths': [
              {
                'pathid': 0,
                'name': 'Outbound',
                'stops': [
                  {
                    'stopid': 'STOP2',
                    'seq': 2,
                    'name': 'Stop 2',
                    'lat': 24.1006,
                    'lon': 120.6500,
                  },
                  {
                    'stopid': 'STOP3',
                    'seq': 3,
                    'name': 'Stop 3',
                    'lat': 24.1012,
                    'lon': 120.6500,
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.endsWith('/api/v1/routes/TXG307/realtime')) {
        return http.Response(
          jsonEncode({
            'routeid': 'TXG307',
            'paths': [
              {
                'pathid': 0,
                'stops': [
                  {
                    'stopid': 'STOP2',
                    'eta': 0,
                    'message': '',
                    'updated_at': '2026-06-22T10:00:05+08:00',
                    'buses': [
                      {
                        'id': 'BBB-0002',
                        'type': 'normal',
                        'source': 'backfill_buses',
                      },
                    ],
                    'etas': [
                      {
                        'plate': 'BBB-0002',
                        'eta': 0,
                        'is_arriving': true,
                        'source': 'backfill_buses',
                        'estimated': true,
                      },
                    ],
                  },
                  {
                    'stopid': 'STOP3',
                    'eta': 90,
                    'message': '',
                    'updated_at': '2026-06-22T10:00:05+08:00',
                    'buses': const [],
                    'etas': [
                      {
                        'plate': 'BBB-0002',
                        'eta': 90,
                        'is_arriving': false,
                        'source': 'backfill_buses',
                        'estimated': true,
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final repository = BusRepository(client: client);
    final detail = await repository.getCompleteBusInfo(
      307,
      provider: BusProvider.txg,
      routeIdHint: 'TXG307',
      routeNameHint: '307',
    );

    final pathStops = detail.stopsByPath[0]!;
    final stop2 = pathStops.firstWhere((stop) => stop.stopName == 'Stop 2');
    final stop3 = pathStops.firstWhere((stop) => stop.stopName == 'Stop 3');

    expect(stop2.buses.single.id, 'BBB-0002');
    expect(stop2.buses.single.source, 'backfill_buses');
    expect(stop2.etas.single.vehicleId, 'BBB-0002');
    expect(stop2.etas.single.source, 'backfill_buses');
    expect(stop2.etas.single.estimated, isTrue);
    expect(effectiveStopEtaSecondsForVehicle(stop3, 'BBB-0002'), 90);
  });
}
