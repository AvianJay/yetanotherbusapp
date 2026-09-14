import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';

void main() {
  test(
    'derives Taichung cancelled departures from the daily timetable',
    () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'citybus.taichung.gov.tw');
        expect(request.url.path, '/ebus/graphql');
        final query =
            (jsonDecode(request.body) as Map<String, dynamic>)['query']
                as String;
        if (query.contains('routes(lang: "zh")')) {
          return _jsonResponse({
            'data': {
              'routes': {
                'edges': [
                  {
                    'node': {'id': 1, 'name': '1'},
                  },
                ],
              },
            },
          });
        }
        if (query.contains('schedule(xno: 1)')) {
          return _jsonResponse({
            'data': {
              'schedule': {
                'edges': [
                  {
                    'node': {
                      'goBack': 1,
                      'scheduleTime': '06:00',
                      'orderNo': 1,
                    },
                  },
                  {
                    'node': {
                      'goBack': 1,
                      'scheduleTime': '06:10',
                      'orderNo': 1,
                    },
                  },
                  {
                    'node': {
                      'goBack': 2,
                      'scheduleTime': '07:00',
                      'orderNo': 1,
                    },
                  },
                  {
                    'node': {
                      'goBack': 1,
                      'scheduleTime': '06:00',
                      'orderNo': 2,
                    },
                  },
                ],
              },
            },
          });
        }
        expect(query, contains('dailyTimeTable(xno: 1, date: "2025-01-02")'));
        return _jsonResponse({
          'data': {
            'dailyTimeTable': {
              'edges': [
                {
                  'node': {'goBack': 1, 'scheduleTime': '06:10'},
                },
                {
                  'node': {'goBack': 2, 'scheduleTime': '07:00'},
                },
              ],
            },
          },
        });
      });

      final departures = await BusRepository(client: client)
          .fetchTaichungCancelledDepartures(
            routeId: 'TXG1',
            routeName: '1',
            date: DateTime(2025, 1, 2),
          );

      expect(departures, hasLength(1));
      expect(departures.single.direction, 1);
      expect(departures.single.departureTime, '06:00');
    },
  );

  test(
    'uses the current-day schedule feed as the cancellation baseline',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/getschedule.php') {
          expect(request.url.queryParameters['xno'], '1');
          return _jsonResponse([
            {'goBack': 1, 'scheduleTime': '06:00'},
            {'goBack': 1, 'scheduleTime': '06:10'},
          ]);
        }

        final query =
            (jsonDecode(request.body) as Map<String, dynamic>)['query']
                as String;
        if (query.contains('routes(lang: "zh")')) {
          return _jsonResponse({
            'data': {
              'routes': {
                'edges': [
                  {
                    'node': {'id': 1, 'name': '1'},
                  },
                ],
              },
            },
          });
        }
        expect(query, contains('dailyTimeTable(xno: 1'));
        return _jsonResponse({
          'data': {
            'dailyTimeTable': {
              'edges': [
                {
                  'node': {'goBack': 1, 'scheduleTime': '06:10'},
                },
              ],
            },
          },
        });
      });

      final departures = await BusRepository(client: client)
          .fetchTaichungCancelledDepartures(
            routeId: 'TXG1',
            routeName: '1',
            date: DateTime.now(),
          );

      expect(departures, hasLength(1));
      expect(departures.single.direction, 1);
      expect(departures.single.departureTime, '06:00');
    },
  );
}

http.Response _jsonResponse(Object value) {
  return http.Response(
    jsonEncode(value),
    200,
    headers: const {'content-type': 'application/json'},
  );
}
