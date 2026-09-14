import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/auth_token_store.dart';
import 'package:taiwanbus_flutter/core/cwa_geo_index.dart';
import 'package:taiwanbus_flutter/core/weather_service.dart';
import 'package:taiwanbus_flutter/screens/weather_screen.dart';
import 'package:taiwanbus_flutter/widgets/weather_app_bar_title.dart';

http.Response _okResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

String _two(int value) => value.toString().padLeft(2, '0');

/// CWA's timestamp shape: wall clock with the fixed Taiwan offset.
String _cwaTime(DateTime time) =>
    '${time.year}-${_two(time.month)}-${_two(time.day)}'
    'T${_two(time.hour)}:${_two(time.minute)}:00+08:00';

/// 臺北市信義區 — what 25.03, 121.56 resolves to in the bundled index.
const _taipeiLat = 25.03746;
const _taipeiLon = 121.56398;

/// A `O-A0003-001` station entry. Values are strings, as CWA sends them.
Map<String, Object?> _station({
  required String id,
  required double latitude,
  required double longitude,
  Object? temperature = '20.8',
  Object? weather = '陰',
  Object? humidity = '93',
  Object? wind = '1.7',
  String county = '臺北市',
}) => {
  'StationId': id,
  'StationName': '測試站$id',
  'ObsTime': {'DateTime': '2026-09-06T22:20:00+08:00'},
  'GeoInfo': {
    'Coordinates': [
      // TWD67 comes first in the real payload and is offset by a few hundred
      // metres, so picking the wrong one silently degrades station choice.
      {
        'CoordinateName': 'TWD67',
        'StationLatitude': '${latitude + 0.002}',
        'StationLongitude': '${longitude - 0.008}',
      },
      {
        'CoordinateName': 'WGS84',
        'StationLatitude': '$latitude',
        'StationLongitude': '$longitude',
      },
    ],
    'CountyName': county,
    'TownName': '信義區',
  },
  'WeatherElement': {
    'Weather': weather,
    'AirTemperature': temperature,
    'RelativeHumidity': humidity,
    'WindSpeed': wind,
    'VisibilityDescription': '-99',
  },
};

Map<String, Object?> _observationBody(List<Map<String, Object?>> stations) => {
  'success': 'true',
  'records': {'Station': stations},
};

/// An instantaneous element: one `DataTime` per sample, no range.
Map<String, Object?> _pointElement(
  String name,
  String key,
  List<(DateTime, Object?)> samples,
) => {
  'ElementName': name,
  'Time': [
    for (final (time, value) in samples)
      {
        'DataTime': _cwaTime(time),
        'ElementValue': [
          {key: value},
        ],
      },
  ],
};

/// A ranged element: `StartTime`/`EndTime` blocks.
Map<String, Object?> _rangeElement(
  String name,
  List<(DateTime, DateTime, Map<String, Object?>)> blocks,
) => {
  'ElementName': name,
  'Time': [
    for (final (start, end, values) in blocks)
      {
        'StartTime': _cwaTime(start),
        'EndTime': _cwaTime(end),
        'ElementValue': [values],
      },
  ],
};

Map<String, Object?> _forecastBody(
  List<Map<String, Object?>> elements, {
  String township = '信義區',
}) => {
  'success': 'true',
  'records': {
    'Locations': [
      {
        'LocationsName': '臺北市',
        'Location': [
          {
            'LocationName': township,
            'Latitude': '25.035095',
            'Longitude': '121.558742',
            'WeatherElement': elements,
          },
        ],
      },
    ],
  },
};

/// Routes a request to the right canned body by dataset id.
///
/// [observation] is `O-A0003-001`, [threeHourly] is `F-D0047-061` (臺北市) and
/// [weekly] is `F-D0047-063`.
MockClient _cwaClient({
  Object? observation,
  Object? threeHourly,
  Object? weekly,
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    final path = request.url.path;
    if (path.endsWith('O-A0003-001')) {
      return _okResponse(observation ?? _observationBody(const []));
    }
    if (path.endsWith('F-D0047-061')) {
      return _okResponse(threeHourly ?? _forecastBody(const []));
    }
    if (path.endsWith('F-D0047-063')) {
      return _okResponse(weekly ?? _forecastBody(const []));
    }
    return http.Response('unexpected dataset $path', 404);
  });
}

/// The Taiwan hour the service will compute, waiting out an imminent rollover
/// so the payload and the service's own clock read cannot land in different
/// hours.
Future<DateTime> _taiwanHour() async {
  var now = taiwanNow();
  if (now.minute == 59 && now.second >= 55) {
    await Future<void>.delayed(const Duration(seconds: 6));
    now = taiwanNow();
  }
  return DateTime.utc(now.year, now.month, now.day, now.hour);
}

void main() {
  tearDown(() {
    AuthTokenStore.token = null;
  });

  group('geo index', () {
    test('covers every county the forecast datasets are keyed by', () {
      expect(cwaStations, hasLength(greaterThan(300)));
      expect(cwaTownships, hasLength(greaterThan(300)));
      // 22 counties, each with a F-D0047 dataset id.
      expect(cwaTownships.map((t) => t.county).toSet(), hasLength(22));
      expect(
        cwaStations.every((s) => s.latitude > 20 && s.latitude < 27),
        isTrue,
      );
      expect(cwaTownships.first.label, startsWith(cwaTownships.first.county));
    });

    test('resolves a coordinate to the township that contains it', () {
      // 臺北 101, and 高雄市政府.
      expect(nearestTownship(_taipeiLat, _taipeiLon).label, '臺北市信義區');
      expect(nearestTownship(22.6273, 120.3014).county, '高雄市');
    });

    test('ranks stations by real distance, closest first', () {
      final nearest = nearestStations(_taipeiLat, _taipeiLon, count: 3);
      expect(nearest, hasLength(3));
      final distances = [
        for (final station in nearest)
          distanceKm(
            _taipeiLat,
            _taipeiLon,
            station.latitude,
            station.longitude,
          ),
      ];
      expect(distances, orderedEquals(List.of(distances)..sort()));
      expect(distances.first, lessThan(20));
    });
  });

  group('fetchCurrent', () {
    test('asks CWA for the nearest stations only', () async {
      late Uri captured;
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          onRequest: (request) => captured = request.url,
        ),
      );

      final snapshot = await service.fetchCurrent(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(captured.host, 'opendata.cwa.gov.tw');
      expect(captured.path, '/api/v1/rest/datastore/O-A0003-001');
      expect(captured.queryParameters['Authorization'], kCwaApiKey);
      expect(captured.queryParameters['format'], 'JSON');
      // A handful of station ids, not the whole 440 KB dataset.
      final ids = captured.queryParameters['StationId']!.split(',');
      expect(ids, hasLength(WeatherService.stationSearchCount));
      expect(ids, contains('466920'));
      // Coordinates never leave the device — resolution happens offline.
      expect(captured.query, isNot(contains('25.0')));
      expect(captured.query, isNot(contains('121.5')));

      expect(snapshot.temperatureC, 20.8);
      expect(snapshot.displayTemperature, 21);
      expect(snapshot.condition, '陰');
    });

    test('never sends the signed-in auth token to CWA', () async {
      AuthTokenStore.token = 'test-token';
      Map<String, String> captured = const {};
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          onRequest: (request) => captured = request.headers,
        ),
      );

      await service.fetchCurrent(latitude: _taipeiLat, longitude: _taipeiLon);

      expect(captured['Authorization'] ?? captured['authorization'], isNull);
    });

    test('prefers the nearest station that is actually reporting', () async {
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            // Nearest, but down: CWA writes -99 rather than omitting the field.
            _station(
              id: '466920',
              latitude: _taipeiLat,
              longitude: _taipeiLon,
              temperature: '-99',
            ),
            _station(
              id: '466930',
              latitude: 25.05,
              longitude: 121.58,
              temperature: '28.5',
              weather: '晴',
            ),
            _station(
              id: '466910',
              latitude: 25.17,
              longitude: 121.44,
              temperature: '18.0',
              weather: '陰',
            ),
          ]),
        ),
      );

      final snapshot = await service.fetchCurrent(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(snapshot.temperatureC, 28.5);
      expect(snapshot.condition, '晴');
    });

    test('falls back to the full dataset when no filtered station reports',
        () async {
      final requested = <String?>[];
      final service = WeatherService(
        client: MockClient((request) async {
          requested.add(request.url.queryParameters['StationId']);
          if (requested.length == 1) {
            // Every bundled id is stale or down.
            return _okResponse(_observationBody(const []));
          }
          return _okResponse(
            _observationBody([
              _station(
                id: 'C0A9F0',
                latitude: 25.04,
                longitude: 121.56,
                temperature: '30.1',
              ),
            ]),
          );
        }),
      );

      final snapshot = await service.fetchCurrent(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(requested, hasLength(2));
      expect(requested.first, isNotNull);
      // The retry drops the filter so a stale index cannot kill the feature.
      expect(requested.last, isNull);
      expect(snapshot.temperatureC, 30.1);
    });

    test('throws when nothing nearby is reporting at all', () async {
      final service = WeatherService(
        client: _cwaClient(observation: _observationBody(const [])),
      );

      await expectLater(
        service.fetchCurrent(latitude: _taipeiLat, longitude: _taipeiLon),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('觀測站'),
          ),
        ),
      );
    });

    test('serves the cache within the TTL and refetches on force', () async {
      var calls = 0;
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          onRequest: (_) => calls += 1,
        ),
      );

      await service.fetchCurrent(latitude: 25.0, longitude: 121.5);
      await service.fetchCurrent(latitude: 25.001, longitude: 121.502);
      expect(calls, 1);

      await service.fetchCurrent(
        latitude: 25.0,
        longitude: 121.5,
        force: true,
      );
      expect(calls, 2);

      await service.fetchCurrent(latitude: 22.63, longitude: 120.3);
      expect(calls, 3);
    });

    test('surfaces failed responses and malformed payloads', () async {
      final failing = WeatherService(
        client: MockClient((request) async => http.Response('nope', 503)),
      );
      await expectLater(
        failing.fetchCurrent(latitude: _taipeiLat, longitude: _taipeiLon),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('天氣'),
          ),
        ),
      );

      Future<void> expectRejects(String body) async {
        final service = WeatherService(
          client: MockClient((request) async => http.Response(body, 200)),
        );
        await expectLater(
          service.fetchCurrent(latitude: _taipeiLat, longitude: _taipeiLon),
          throwsA(isA<Exception>()),
        );
      }

      await expectRejects('not json');
      await expectRejects('[]');
      await expectRejects('{"records":"x"}');
    });
  });

  group('fetchForecast', () {
    test('asks for one township, filtered to the elements it uses', () async {
      final urls = <Uri>[];
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          onRequest: (request) => urls.add(request.url),
        ),
      );

      await service.fetchForecast(latitude: _taipeiLat, longitude: _taipeiLon);

      expect(urls, hasLength(3));
      final datasets = urls.map((url) => url.pathSegments.last).toList();
      // 臺北市 is 061; the weekly feed for the same county is always +2.
      expect(datasets, containsAll(['O-A0003-001', 'F-D0047-061', 'F-D0047-063']));

      final hourly = urls.firstWhere((u) => u.path.endsWith('F-D0047-061'));
      expect(hourly.queryParameters['LocationName'], '信義區');
      expect(hourly.queryParameters['ElementName'], contains('溫度'));
      expect(hourly.queryParameters['ElementName'], contains('天氣現象'));
      expect(hourly.queryParameters['ElementName'], contains('3小時降雨機率'));

      final weekly = urls.firstWhere((u) => u.path.endsWith('F-D0047-063'));
      expect(weekly.queryParameters['LocationName'], '信義區');
      expect(weekly.queryParameters['ElementName'], contains('最高溫度'));
      expect(weekly.queryParameters['ElementName'], contains('12小時降雨機率'));
    });

    test('reads current conditions from the station, not the model', () async {
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(
              id: '466920',
              latitude: 25.0377,
              longitude: 121.5149,
              temperature: '32.4',
              weather: '晴',
              humidity: '68',
              // m/s on the wire.
              wind: '3.4',
            ),
          ]),
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(forecast.current.displayTemperature, 32);
      expect(forecast.current.condition, '晴');
      expect(forecast.locationLabel, '臺北市信義區');
      expect(forecast.relativeHumidity, 68);
      // 3.4 m/s is 12.24 km/h.
      expect(forecast.windSpeedKph, closeTo(12.24, 0.001));
      // Sunrise and sunset are computed locally, so they need no payload.
      expect(forecast.sunrise, isNotNull);
      expect(forecast.sunset!.isAfter(forecast.sunrise!), isTrue);
      // Missing forecast elements degrade to empty rather than throwing.
      expect(forecast.hourly, isEmpty);
      expect(forecast.daily, isEmpty);
      expect(forecast.apparentTemperatureC, isNull);
    });

    test('drops observation sentinels instead of showing them', () async {
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(
              id: '466920',
              latitude: 25.0377,
              longitude: 121.5149,
              weather: '-99',
              humidity: '-99',
              wind: '-99.0',
            ),
          ]),
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(forecast.current.condition, isNull);
      expect(forecast.relativeHumidity, isNull);
      expect(forecast.windSpeedKph, isNull);
      // A station with no reported sky still gets a readable label.
      expect(weatherConditionLabel(forecast.current.condition), '多雲');
    });

    test('opens the hourly strip on the slot in progress and caps the run',
        () async {
      final base = await _taiwanHour();
      // CWA samples hourly for the first day, and every hour is a candidate,
      // so 30 samples starting three hours ago overruns the 24 hour window.
      final start = base.subtract(const Duration(hours: 3));
      final samples = [
        for (var i = 0; i < 30; i++)
          (start.add(Duration(hours: i)), '${20 + i}'),
      ];

      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          threeHourly: _forecastBody([
            _pointElement('溫度', 'Temperature', samples),
            _pointElement('體感溫度', 'ApparentTemperature', [
              for (final (time, _) in samples) (time, '30'),
            ]),
            _pointElement('相對濕度', 'RelativeHumidity', [
              for (final (time, _) in samples) (time, '70'),
            ]),
            _rangeElement('天氣現象', [
              for (var i = 0; i < 10; i++)
                (
                  start.add(Duration(hours: i * 3)),
                  start.add(Duration(hours: i * 3 + 3)),
                  {'Weather': '短暫陣雨', 'WeatherCode': '08'},
                ),
            ]),
            _rangeElement('3小時降雨機率', [
              for (var i = 0; i < 10; i++)
                (
                  start.add(Duration(hours: i * 3)),
                  start.add(Duration(hours: i * 3 + 3)),
                  {'ProbabilityOfPrecipitation': '${i * 10}'},
                ),
            ]),
          ]),
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      // Exactly one stale slot is kept: the one the user is standing in.
      expect(forecast.hourly.first.time, base);
      expect(forecast.hourly.first.temperatureC, 23.0);
      expect(
        forecast.hourly.every(
          (hour) => !hour.time.isAfter(
            base.add(const Duration(hours: WeatherService.forecastHours)),
          ),
        ),
        isTrue,
      );
      // Ranged blocks line up with the finer temperature series.
      expect(forecast.hourly.first.condition, '短暫陣雨');
      expect(forecast.hourly.first.precipitationProbability, 10);
      // The instantaneous extras are read from the same slot.
      expect(forecast.apparentTemperatureC, 30.0);
    });

    test('aggregates the week across both 12 hour blocks', () async {
      final today = await _taiwanHour();
      final day = DateTime.utc(today.year, today.month, today.day);

      List<(DateTime, DateTime, Map<String, Object?>)> blocks(
        String key,
        List<Object?> values,
      ) => [
        for (var i = 0; i < values.length; i++)
          (
            day.add(Duration(hours: 6 + i * 12)),
            day.add(Duration(hours: 18 + i * 12)),
            {key: values[i]},
          ),
      ];

      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          weekly: _forecastBody([
            // Day 1 daytime then day 1 night, so both fold into one date.
            _rangeElement('最高溫度', blocks('MaxTemperature', ['31', '27', '33'])),
            _rangeElement('最低溫度', blocks('MinTemperature', ['26', '24', '28'])),
            _rangeElement(
              '12小時降雨機率',
              // CWA writes `-` once it stops forecasting rain.
              blocks('ProbabilityOfPrecipitation', ['20', '70', '-']),
            ),
            _rangeElement('天氣現象', [
              (
                day.add(const Duration(hours: 6)),
                day.add(const Duration(hours: 18)),
                {'Weather': '晴時多雲', 'WeatherCode': '02'},
              ),
              (
                day.add(const Duration(hours: 18)),
                day.add(const Duration(hours: 30)),
                {'Weather': '陰時多雲短暫陣雨', 'WeatherCode': '10'},
              ),
            ]),
          ]),
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(forecast.daily, hasLength(2));
      final first = forecast.daily.first;
      expect(first.date, day);
      // max over both blocks, min over both blocks.
      expect(first.displayHigh, 31);
      expect(first.displayLow, 24);
      expect(first.precipitationProbability, 70);
      // The daytime block wins the icon even though night sorts later.
      expect(first.condition, '晴時多雲');

      // `-` means unknown, which is not the same claim as 0%.
      expect(forecast.daily.last.precipitationProbability, isNull);
    });

    test('widens the near days with the finer hourly series', () async {
      final base = await _taiwanHour();
      final day = DateTime.utc(base.year, base.month, base.day);

      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          threeHourly: _forecastBody([
            _pointElement('溫度', 'Temperature', [
              (base, '35'),
              (base.add(const Duration(hours: 1)), '19'),
            ]),
          ]),
          weekly: _forecastBody([
            _rangeElement('最高溫度', [
              (
                day.add(const Duration(hours: 6)),
                day.add(const Duration(hours: 18)),
                {'MaxTemperature': '30'},
              ),
            ]),
            _rangeElement('最低溫度', [
              (
                day.add(const Duration(hours: 6)),
                day.add(const Duration(hours: 18)),
                {'MinTemperature': '25'},
              ),
            ]),
          ]),
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      // The hourly samples exceed the official block on both ends.
      expect(forecast.daily.single.displayHigh, 35);
      expect(forecast.daily.single.displayLow, 19);
    });

    test('caps the week and drops days already past', () async {
      final today = await _taiwanHour();
      final day = DateTime.utc(today.year, today.month, today.day);
      final start = day.subtract(const Duration(days: 2));

      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          weekly: _forecastBody([
            _rangeElement('最高溫度', [
              for (var i = 0; i < 12; i++)
                (
                  start.add(Duration(days: i, hours: 6)),
                  start.add(Duration(days: i, hours: 18)),
                  {'MaxTemperature': '${30 + i}'},
                ),
            ]),
            _rangeElement('最低溫度', [
              for (var i = 0; i < 12; i++)
                (
                  start.add(Duration(days: i, hours: 6)),
                  start.add(Duration(days: i, hours: 18)),
                  {'MinTemperature': '24'},
                ),
            ]),
          ]),
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(forecast.daily, hasLength(WeatherService.forecastDayCount));
      expect(forecast.daily.first.date, day);
      // Index 2 of the payload is today, so its high is the one that shows.
      expect(forecast.daily.first.displayHigh, 32);
    });

    test('caches, honours force, and also satisfies the chip', () async {
      var calls = 0;
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(
              id: '466920',
              latitude: 25.0377,
              longitude: 121.5149,
              temperature: '28.6',
              weather: '多雲',
            ),
          ]),
          onRequest: (_) => calls += 1,
        ),
      );

      await service.fetchForecast(latitude: 25.0, longitude: 121.5);
      expect(calls, 3);

      await service.fetchForecast(latitude: 25.001, longitude: 121.502);
      expect(calls, 3);

      // The forecast's own observation fills the chip's cache too.
      final snapshot = await service.fetchCurrent(
        latitude: 25.0,
        longitude: 121.5,
      );
      expect(calls, 3);
      expect(snapshot.displayTemperature, 29);
      expect(snapshot.condition, '多雲');

      await service.fetchForecast(
        latitude: 25.0,
        longitude: 121.5,
        force: true,
      );
      expect(calls, 6);
    });

    test('surfaces a failure from any of the three requests', () async {
      Future<void> expectFails(String failing) async {
        final service = WeatherService(
          client: MockClient((request) async {
            if (request.url.path.endsWith(failing)) {
              return http.Response('nope', 503);
            }
            if (request.url.path.endsWith('O-A0003-001')) {
              return _okResponse(
                _observationBody([
                  _station(
                    id: '466920',
                    latitude: 25.0377,
                    longitude: 121.5149,
                  ),
                ]),
              );
            }
            return _okResponse(_forecastBody(const []));
          }),
        );

        await expectLater(
          service.fetchForecast(latitude: _taipeiLat, longitude: _taipeiLon),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('天氣'),
            ),
          ),
        );
      }

      await expectFails('O-A0003-001');
      await expectFails('F-D0047-061');
      await expectFails('F-D0047-063');
    });

    test('picks the requested township even if CWA returns more', () async {
      final base = await _taiwanHour();
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          threeHourly: {
            'records': {
              'Locations': [
                {
                  'Location': [
                    {
                      'LocationName': '中正區',
                      'WeatherElement': [
                        _pointElement('溫度', 'Temperature', [(base, '10')]),
                      ],
                    },
                    {
                      'LocationName': '信義區',
                      'WeatherElement': [
                        _pointElement('溫度', 'Temperature', [(base, '30')]),
                      ],
                    },
                  ],
                },
              ],
            },
          },
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      expect(forecast.hourly.single.temperatureC, 30.0);
    });
  });

  group('time handling', () {
    test('parses CWA timestamps as Taiwan wall clock, not local time',
        () async {
      // Digits must survive whatever timezone the test machine is in, and
      // 2026-03-08T02:30 does not exist in US zones (spring forward), so
      // parsing as local time would shift it an hour.
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(id: '466920', latitude: 25.0377, longitude: 121.5149),
          ]),
          weekly: _forecastBody([
            _rangeElement('最高溫度', [
              (
                DateTime.utc(2026, 3, 8, 2, 30),
                DateTime.utc(2026, 3, 8, 14, 30),
                {'MaxTemperature': '20'},
              ),
            ]),
            _rangeElement('最低溫度', [
              (
                DateTime.utc(2026, 3, 8, 2, 30),
                DateTime.utc(2026, 3, 8, 14, 30),
                {'MinTemperature': '12'},
              ),
            ]),
          ]),
        ),
      );

      final forecast = await service.fetchForecast(
        latitude: _taipeiLat,
        longitude: _taipeiLon,
      );

      // 2026-03-08 is long past, so the day itself is filtered out — the point
      // is that parsing it did not throw or shift into a neighbouring date.
      expect(forecast.daily, isEmpty);
      expect(taiwanNow().isUtc, isTrue);
    });

    test('computes sunrise and sunset from coordinates', () {
      // 2026-06-21 in Taipei: sunrise about 05:05, sunset about 18:47 local.
      final midsummer = sunTimes(
        latitude: 25.0377,
        longitude: 121.5149,
        now: DateTime.utc(2026, 6, 21, 4),
      );
      expect(midsummer, isNotNull);
      expect(midsummer!.sunrise.hour, 5);
      expect(midsummer.sunrise.minute, closeTo(5, 4));
      expect(midsummer.sunset.hour, 18);
      expect(midsummer.sunset.minute, closeTo(47, 4));

      // Midwinter days are shorter, and the pair stays ordered.
      final midwinter = sunTimes(
        latitude: 25.0377,
        longitude: 121.5149,
        now: DateTime.utc(2026, 12, 21, 4),
      )!;
      expect(midwinter.sunset.difference(midwinter.sunrise).inMinutes,
          lessThan(midsummer.sunset.difference(midsummer.sunrise).inMinutes));

      // Polar night has no sunrise to report, rather than a bogus one.
      expect(
        sunTimes(
          latitude: 78.2,
          longitude: 15.6,
          now: DateTime.utc(2026, 12, 21, 4),
        ),
        isNull,
      );
    });
  });

  group('presentation', () {
    test('weatherConditionLabel passes CWA text through', () {
      expect(weatherConditionLabel('晴'), '晴');
      expect(weatherConditionLabel('陰時多雲短暫陣雨'), '陰時多雲短暫陣雨');
      // Blank, sentinel and absent all fall back rather than showing junk.
      expect(weatherConditionLabel('  '), '多雲');
      expect(weatherConditionLabel('-99'), '多雲');
      expect(weatherConditionLabel(null), '多雲');
    });

    test('weatherConditionIcon reads CWA descriptions', () {
      expect(weatherConditionIcon(null), Icons.cloud_outlined);
      expect(weatherConditionIcon(''), Icons.cloud_outlined);

      // The four exact states CWA reports most often.
      expect(weatherConditionIcon('晴'), Icons.wb_sunny);
      expect(weatherConditionIcon('多雲'), Icons.wb_cloudy);
      expect(weatherConditionIcon('晴時多雲'), Icons.wb_cloudy);
      expect(weatherConditionIcon('陰'), Icons.cloud);

      // Composed descriptions resolve on keywords, precipitation first.
      expect(weatherConditionIcon('多雲午後短暫雷陣雨'), Icons.flash_on);
      expect(weatherConditionIcon('陰時多雲短暫陣雨'), Icons.grain);
      expect(weatherConditionIcon('多雲短暫雨'), Icons.grain);
      expect(weatherConditionIcon('陰有雨'), Icons.opacity);
      expect(weatherConditionIcon('豪雨'), Icons.opacity);
      expect(weatherConditionIcon('陰有霧'), Icons.blur_on);
      expect(weatherConditionIcon('積冰或雪'), Icons.ac_unit);
      expect(weatherConditionIcon('晴午後短暫陣雨'), Icons.grain);
      expect(weatherConditionIcon('晴時多雲短暫陣雨'), Icons.grain);
      expect(weatherConditionIcon('多雲時晴'), Icons.wb_cloudy);
      // Anything unrecognised still renders something plausible.
      expect(weatherConditionIcon('沙塵暴'), Icons.wb_cloudy);
    });

    testWidgets('weather screen shows failures without exception noise', (
      tester,
    ) async {
      final service = WeatherService(
        client: MockClient((request) async => http.Response('nope', 503)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WeatherScreen(
            latitude: _taipeiLat,
            longitude: _taipeiLon,
            serviceOverride: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('天氣資料載入失敗。'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('weather screen renders a CWA forecast', (tester) async {
      final base = await _taiwanHour();
      final day = DateTime.utc(base.year, base.month, base.day);
      final service = WeatherService(
        client: _cwaClient(
          observation: _observationBody([
            _station(
              id: '466920',
              latitude: 25.0377,
              longitude: 121.5149,
              temperature: '32.4',
              weather: '晴',
            ),
          ]),
          threeHourly: _forecastBody([
            _pointElement('溫度', 'Temperature', [
              (base, '32'),
              (base.add(const Duration(hours: 1)), '31'),
            ]),
          ]),
          weekly: _forecastBody([
            _rangeElement('最高溫度', [
              (
                day.add(const Duration(hours: 6)),
                day.add(const Duration(hours: 18)),
                {'MaxTemperature': '33'},
              ),
            ]),
            _rangeElement('最低溫度', [
              (
                day.add(const Duration(hours: 6)),
                day.add(const Duration(hours: 18)),
                {'MinTemperature': '26'},
              ),
            ]),
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: WeatherScreen(
            latitude: _taipeiLat,
            longitude: _taipeiLon,
            serviceOverride: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('32°C'), findsOneWidget);
      expect(find.text('晴'), findsOneWidget);
      expect(find.text('臺北市信義區'), findsOneWidget);
      expect(find.text('現在'), findsOneWidget);
      expect(find.textContaining('中央氣象署'), findsOneWidget);
      expect(find.textContaining('Open-Meteo'), findsNothing);
    });

    test('weather screen labels avoid needing a date formatting package', () {
      expect(clockLabel(null), '--:--');
      expect(clockLabel(DateTime.utc(2026, 9, 6, 7, 5)), '07:05');

      // The first two days read as words; the rest use the weekday.
      expect(dayLabel(DateTime.utc(2026, 9, 6), 0), '今天');
      expect(dayLabel(DateTime.utc(2026, 9, 7), 1), '明天');
      // 2026-09-08 is a Tuesday, 2026-09-13 a Sunday.
      expect(dayLabel(DateTime.utc(2026, 9, 8), 2), '週二');
      expect(dayLabel(DateTime.utc(2026, 9, 13), 6), '週日');
    });

    test('weather chip fit arithmetic', () {
      final chipWidth = weatherChipWidth(40);
      expect(
        chipWidth,
        kWeatherChipIconSize + kWeatherChipIconGap + 40 + kWeatherChipHPad * 2,
      );
      // Wider labels need more room.
      expect(weatherChipWidth(60), greaterThan(chipWidth));

      expect(
        weatherChipFits(slotWidth: 968, titleWidth: 68, chipWidth: chipWidth),
        isTrue,
      );
      expect(
        weatherChipFits(slotWidth: 88, titleWidth: 68, chipWidth: chipWidth),
        isFalse,
      );
      // Exactly filling the slot still counts as fitting.
      expect(
        weatherChipFits(
          slotWidth: 68 + kWeatherChipGap + chipWidth,
          titleWidth: 68,
          chipWidth: chipWidth,
        ),
        isTrue,
      );
    });
  });
}
