import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_user_agent.dart';
import 'cwa_geo_index.dart';
import 'http_error_utils.dart';

/// Key for the CWA (中央氣象署) open data platform.
///
/// It is a read-only key for the free public datasets at
/// https://opendata.cwa.gov.tw and grants nothing that is not already
/// published there, so shipping it in the client is intended rather than a
/// leaked secret. Regenerate it at the CWA member area if it ever needs
/// rotating.
const String kCwaApiKey = 'CWA-F8711576-A85E-4BF0-A98C-529387E3FA64';

/// Taiwan has been on UTC+8 year round since 1980, with no DST, so every CWA
/// timestamp can be handled as a fixed offset.
const Duration kTaiwanUtcOffset = Duration(hours: 8);

/// A single "current weather" reading, taken from the CWA station nearest the
/// user rather than from a forecast model.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.condition,
    required this.fetchedAt,
  });

  final double temperatureC;

  /// CWA's own description of the sky, e.g. `晴`, `多雲`, `陣雨`.
  /// Null when the station reported no observation.
  final String? condition;

  final DateTime fetchedAt;

  /// Temperature rounded for display, e.g. `32` for `32.4`.
  int get displayTemperature => temperatureC.round();
}

/// One slot of the township forecast.
///
/// CWA samples hourly for the first day and every three hours after that.
/// [time] carries Taiwan wall clock inside a UTC flagged [DateTime], so
/// `.hour` reads the local hour there and comparisons never pick up the
/// device's own timezone offset.
class WeatherHourly {
  const WeatherHourly({
    required this.time,
    required this.temperatureC,
    required this.condition,
    required this.precipitationProbability,
  });

  final DateTime time;
  final double temperatureC;

  /// CWA 天氣現象 description for the slot, e.g. `多雲時陰短暫陣雨`.
  final String? condition;

  /// Chance of precipitation, 0-100, or null when CWA published none.
  final int? precipitationProbability;

  int get displayTemperature => temperatureC.round();
}

/// One day of the weekly forecast. [date] follows [WeatherHourly.time].
class WeatherDaily {
  const WeatherDaily({
    required this.date,
    required this.highC,
    required this.lowC,
    required this.condition,
    required this.precipitationProbability,
  });

  final DateTime date;
  final double highC;
  final double lowC;
  final String? condition;

  /// Highest chance of precipitation that day, 0-100, or null when CWA has not
  /// published one yet — it stops forecasting rain past about a week out.
  final int? precipitationProbability;

  int get displayHigh => highC.round();
  int get displayLow => lowC.round();
}

/// Everything the weather screen renders: current conditions plus the hourly
/// and daily forecasts.
class WeatherForecast {
  const WeatherForecast({
    required this.current,
    required this.locationLabel,
    required this.apparentTemperatureC,
    required this.relativeHumidity,
    required this.windSpeedKph,
    required this.hourly,
    required this.daily,
    required this.sunrise,
    required this.sunset,
  });

  final WeatherSnapshot current;

  /// The township the forecast is for, e.g. `臺北市信義區`.
  final String locationLabel;

  /// "Feels like" temperature in Celsius.
  final double? apparentTemperatureC;

  /// Relative humidity in percent.
  final int? relativeHumidity;

  /// Wind speed in km/h. CWA reports m/s, converted on the way in.
  final double? windSpeedKph;

  /// Upcoming slots, starting with the one already in progress.
  final List<WeatherHourly> hourly;

  /// Upcoming days, starting with today.
  final List<WeatherDaily> daily;

  final DateTime? sunrise;
  final DateTime? sunset;

  DateTime get fetchedAt => current.fetchedAt;
}

/// Which township forecast dataset covers each county.
///
/// The id is the "future 3 days, 3-hourly" feed; the "next week, 12-hourly"
/// feed for the same county is always that id plus two, e.g. 臺中市 is
/// `F-D0047-073` and `F-D0047-075`.
const Map<String, int> _countyDatasetNumbers = {
  '宜蘭縣': 1,
  '桃園市': 5,
  '新竹縣': 9,
  '苗栗縣': 13,
  '彰化縣': 17,
  '南投縣': 21,
  '雲林縣': 25,
  '嘉義縣': 29,
  '屏東縣': 33,
  '臺東縣': 37,
  '花蓮縣': 41,
  '澎湖縣': 45,
  '基隆市': 49,
  '新竹市': 53,
  '嘉義市': 57,
  '臺北市': 61,
  '高雄市': 65,
  '新北市': 69,
  '臺中市': 73,
  '臺南市': 77,
  '連江縣': 81,
  '金門縣': 85,
};

String _datasetId(int number) => 'F-D0047-${number.toString().padLeft(3, '0')}';

/// Human readable condition text, falling back to 多雲 when CWA reported
/// nothing — the same default the upstream weather app uses.
String weatherConditionLabel(String? condition) {
  final trimmed = condition?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed.startsWith('-')) {
    return '多雲';
  }
  return trimmed;
}

/// Rounds a coordinate to ~1.1km, which is the granularity the cache keys on.
///
/// Coordinates themselves never leave the device: CWA is addressed by station
/// id and township name, both resolved offline from [cwaStations] and
/// [cwaTownships].
double roundCoordinate(double value) => (value * 100).roundToDouble() / 100;

double _toRadians(double degrees) => degrees * math.pi / 180;

/// Great circle distance in kilometres.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * earthRadiusKm * math.asin(math.min(1.0, math.sqrt(a)));
}

/// The bundled stations nearest [latitude]/[longitude], closest first.
List<CwaStation> nearestStations(
  double latitude,
  double longitude, {
  int count = 3,
}) {
  final ranked = cwaStations.toList()
    ..sort((a, b) {
      final da = distanceKm(latitude, longitude, a.latitude, a.longitude);
      final db = distanceKm(latitude, longitude, b.latitude, b.longitude);
      return da.compareTo(db);
    });
  return ranked.take(count).toList(growable: false);
}

/// The bundled township whose centroid is nearest [latitude]/[longitude].
CwaTownship nearestTownship(double latitude, double longitude) {
  var best = cwaTownships.first;
  var bestDistance = distanceKm(
    latitude,
    longitude,
    best.latitude,
    best.longitude,
  );
  for (final township in cwaTownships.skip(1)) {
    final distance = distanceKm(
      latitude,
      longitude,
      township.latitude,
      township.longitude,
    );
    if (distance < bestDistance) {
      best = township;
      bestDistance = distance;
    }
  }
  return best;
}

/// Fetches observations and forecasts from the CWA open data platform.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  /// Shared instance so the cache survives remounts and is reused between the
  /// app bar chip and the weather screen.
  static final WeatherService shared = WeatherService();

  final http.Client _client;

  static const _host = 'opendata.cwa.gov.tw';
  static const _basePath = '/api/v1/rest/datastore/';
  static const _observationDataset = 'O-A0003-001';
  static const _timeout = Duration(seconds: 15);

  /// How long a reading stays fresh before another request is made.
  static const cacheTtl = Duration(minutes: 15);

  /// How far ahead the hourly strip runs. CWA samples the first day hourly and
  /// every three hours after that, so this is 24 cells at most.
  static const forecastHours = 24;

  /// Days kept from the weekly forecast.
  static const forecastDayCount = 7;

  /// How many nearby stations to ask for at once. About 3% of CWA's stations
  /// are offline at any moment, so asking for a handful and taking the nearest
  /// one that answered avoids a second round trip almost every time.
  static const stationSearchCount = 3;

  WeatherSnapshot? _cached;
  String? _cachedKey;
  Future<WeatherSnapshot>? _inFlight;
  String? _inFlightKey;

  WeatherForecast? _cachedForecast;
  String? _cachedForecastKey;
  Future<WeatherForecast>? _inFlightForecast;
  String? _inFlightForecastKey;

  /// Observed temperature and sky only — the cheap call behind the app bar
  /// chip. One filtered request, a couple of kilobytes.
  Future<WeatherSnapshot> fetchCurrent({
    required double latitude,
    required double longitude,
    bool force = false,
  }) {
    // The rounded pair doubles as the cache key.
    final lat = roundCoordinate(latitude);
    final lon = roundCoordinate(longitude);
    final key = '$lat,$lon';

    final cached = _cached;
    if (!force &&
        cached != null &&
        _cachedKey == key &&
        DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return Future.value(cached);
    }

    final inFlight = _inFlight;
    if (inFlight != null && _inFlightKey == key) {
      return inFlight;
    }

    final request = _fetchCurrent(lat: latitude, lon: longitude, key: key);
    _inFlight = request;
    _inFlightKey = key;
    return request.whenComplete(() {
      _inFlight = null;
      _inFlightKey = null;
    });
  }

  /// Current conditions plus the hourly and weekly forecasts — the heavier
  /// call behind the weather screen.
  Future<WeatherForecast> fetchForecast({
    required double latitude,
    required double longitude,
    bool force = false,
  }) {
    final lat = roundCoordinate(latitude);
    final lon = roundCoordinate(longitude);
    final key = '$lat,$lon';

    final cached = _cachedForecast;
    if (!force &&
        cached != null &&
        _cachedForecastKey == key &&
        DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return Future.value(cached);
    }

    final inFlight = _inFlightForecast;
    if (inFlight != null && _inFlightForecastKey == key) {
      return inFlight;
    }

    final request = _fetchForecast(lat: latitude, lon: longitude, key: key);
    _inFlightForecast = request;
    _inFlightForecastKey = key;
    return request.whenComplete(() {
      _inFlightForecast = null;
      _inFlightForecastKey = null;
    });
  }

  Future<WeatherSnapshot> _fetchCurrent({
    required double lat,
    required double lon,
    required String key,
  }) async {
    final snapshot = (await _observe(lat, lon)).toSnapshot();
    _cached = snapshot;
    _cachedKey = key;
    return snapshot;
  }

  Future<WeatherForecast> _fetchForecast({
    required double lat,
    required double lon,
    required String key,
  }) async {
    final township = nearestTownship(lat, lon);
    final number = _countyDatasetNumbers[township.county];
    if (number == null) {
      // Every bundled township maps to a county, so this only fires if the
      // index and the table drift apart.
      throw const FormatException('找不到所在地區的天氣預報。');
    }

    // The observation and both forecast feeds are independent, so fetch them
    // together rather than in series. Future.wait rather than three awaits:
    // it listens to all three up front, so whichever fails first is the error
    // that surfaces and the others do not go unhandled.
    final results = await Future.wait<Object>([
      _observe(lat, lon),
      _getJson(_datasetId(number), {
        'LocationName': township.name,
        'ElementName': '溫度,天氣現象,3小時降雨機率,體感溫度,相對濕度',
      }),
      _getJson(_datasetId(number + 2), {
        'LocationName': township.name,
        'ElementName': '最高溫度,最低溫度,天氣現象,12小時降雨機率',
      }),
    ]);
    final reading = results[0] as _StationReading;
    final threeHourly = results[1] as Map<Object?, Object?>;
    final weekly = results[2] as Map<Object?, Object?>;

    // One reading serves both the chip and the screen.
    final snapshot = reading.toSnapshot();
    _cached = snapshot;
    _cachedKey = key;

    final hourlyElements = _elementsFor(threeHourly, township.name);
    final weeklyElements = _elementsFor(weekly, township.name);

    final now = taiwanNow();
    final latest = now.add(const Duration(hours: forecastHours));

    final temperatures = _timeEntries(hourlyElements['溫度']);
    final conditions = _timeEntries(hourlyElements['天氣現象']);
    final rain = _timeEntries(hourlyElements['3小時降雨機率']);
    final apparent = _timeEntries(hourlyElements['體感溫度']);
    final humidity = _timeEntries(hourlyElements['相對濕度']);

    final slots = <WeatherHourly>[];
    for (final entry in temperatures) {
      final time = _entryStart(entry);
      final temperature = _asDouble(_valueOf(entry, 'Temperature'));
      if (time == null || temperature == null || time.isAfter(latest)) {
        continue;
      }
      final condition = _entryCovering(conditions, time);
      slots.add(
        WeatherHourly(
          time: time,
          temperatureC: temperature,
          condition: _asText(_valueOf(condition, 'Weather')),
          precipitationProbability: _asPercent(
            _valueOf(
              _entryCovering(rain, time),
              'ProbabilityOfPrecipitation',
            ),
          ),
        ),
      );
    }
    slots.sort((a, b) => a.time.compareTo(b.time));

    // The strip opens on 現在, which is the newest slot that has already
    // started — CWA samples hourly for the first day, so simply dropping
    // everything before now would skip the slot the user is standing in.
    var start = 0;
    for (var index = 0; index < slots.length; index++) {
      if (slots[index].time.isAfter(now)) {
        break;
      }
      start = index;
    }
    final hourly = slots.sublist(slots.isEmpty ? 0 : start);

    // The strip is anchored on "now", so read the extras from the same slot.
    final currentSlot = hourly.isNotEmpty ? hourly.first.time : now;
    final apparentNow = _asDouble(
      _valueOf(_entryCovering(apparent, currentSlot), 'ApparentTemperature'),
    );
    final humidityNow = _asInt(
      _valueOf(_entryCovering(humidity, currentSlot), 'RelativeHumidity'),
    );

    final daily = _buildDaily(weeklyElements, hourly, now);
    final sun = sunTimes(latitude: lat, longitude: lon);

    final forecast = WeatherForecast(
      current: snapshot,
      locationLabel: township.label,
      apparentTemperatureC: apparentNow,
      // The station's own humidity beats the forecast's when it reported one.
      relativeHumidity: reading.humidity ?? humidityNow,
      windSpeedKph: reading.windSpeedKph,
      hourly: List<WeatherHourly>.unmodifiable(hourly),
      daily: List<WeatherDaily>.unmodifiable(daily),
      sunrise: sun?.sunrise,
      sunset: sun?.sunset,
    );
    _cachedForecast = forecast;
    _cachedForecastKey = key;
    return forecast;
  }

  /// Reads the nearest station that is actually reporting a temperature.
  Future<_StationReading> _observe(double lat, double lon) async {
    final candidates = nearestStations(lat, lon, count: stationSearchCount);
    var decoded = await _getJson(_observationDataset, {
      'StationId': candidates.map((station) => station.id).join(','),
    });
    var reading = _pickStation(decoded, lat, lon);

    if (reading == null) {
      // Either every nearby station is down or the bundled ids have gone
      // stale. Fall back to the unfiltered dataset, which is ~440 KB but at
      // least keeps the feature alive until the index is regenerated.
      decoded = await _getJson(_observationDataset, const {});
      reading = _pickStation(decoded, lat, lon);
    }

    if (reading == null) {
      throw const FormatException('附近沒有可用的氣象觀測站。');
    }
    return reading;
  }

  _StationReading? _pickStation(
    Map<Object?, Object?> decoded,
    double lat,
    double lon,
  ) {
    final records = decoded['records'];
    if (records is! Map<Object?, Object?>) {
      throw const FormatException('天氣資料格式錯誤。');
    }
    final stations = _asList(records['Station']);

    _StationReading? best;
    double? bestDistance;
    for (final raw in stations) {
      if (raw is! Map<Object?, Object?>) {
        continue;
      }
      final elements = raw['WeatherElement'];
      if (elements is! Map<Object?, Object?>) {
        continue;
      }
      // CWA marks missing observations with sentinels like -99 and -998.
      final temperature = _asObservation(elements['AirTemperature']);
      if (temperature == null) {
        continue;
      }
      final geo = raw['GeoInfo'];
      final coordinates = geo is Map<Object?, Object?>
          ? _wgs84(geo['Coordinates'])
          : null;
      final distance = coordinates == null
          ? double.maxFinite
          : distanceKm(lat, lon, coordinates.$1, coordinates.$2);
      if (bestDistance != null && distance >= bestDistance) {
        continue;
      }
      final wind = _asObservation(elements['WindSpeed']);
      best = _StationReading(
        temperatureC: temperature,
        condition: _asText(elements['Weather']),
        humidity: _asObservation(elements['RelativeHumidity'])?.round(),
        // CWA publishes observed wind in m/s; the UI shows km/h.
        windSpeedKph: wind == null ? null : wind * 3.6,
      );
      bestDistance = distance;
    }
    return best;
  }

  List<WeatherDaily> _buildDaily(
    Map<String, Object?> elements,
    List<WeatherHourly> hourly,
    DateTime now,
  ) {
    // A calendar day spans two 12-hour blocks (06-18 and 18-06), so the real
    // high and low have to be aggregated across both rather than read off the
    // first block that starts that day. The overnight block is grouped with the
    // day it starts on, so "tonight" belongs to today.
    final highs = <DateTime, double>{};
    final lows = <DateTime, double>{};
    final rain = <DateTime, int>{};
    final conditions = <DateTime, ({String text, bool daytime})>{};

    void collect(
      Object? element,
      String key,
      void Function(DateTime date, double value) apply,
    ) {
      for (final entry in _timeEntries(element)) {
        final start = _entryStart(entry);
        final value = _asDouble(_valueOf(entry, key));
        if (start == null || value == null) {
          continue;
        }
        apply(DateTime.utc(start.year, start.month, start.day), value);
      }
    }

    collect(elements['最高溫度'], 'MaxTemperature', (date, value) {
      final current = highs[date];
      highs[date] = current == null ? value : math.max(current, value);
    });
    collect(elements['最低溫度'], 'MinTemperature', (date, value) {
      final current = lows[date];
      lows[date] = current == null ? value : math.min(current, value);
    });

    for (final entry in _timeEntries(elements['12小時降雨機率'])) {
      final start = _entryStart(entry);
      final percent = _asPercent(_valueOf(entry, 'ProbabilityOfPrecipitation'));
      if (start == null || percent == null) {
        continue;
      }
      final date = DateTime.utc(start.year, start.month, start.day);
      final current = rain[date];
      rain[date] = current == null ? percent : math.max(current, percent);
    }

    for (final entry in _timeEntries(elements['天氣現象'])) {
      final start = _entryStart(entry);
      final text = _asText(_valueOf(entry, 'Weather'));
      if (start == null || text == null) {
        continue;
      }
      final date = DateTime.utc(start.year, start.month, start.day);
      // The daily icon should show what the daytime looks like.
      final daytime = start.hour >= 6 && start.hour < 18;
      final existing = conditions[date];
      if (existing == null || (daytime && !existing.daytime)) {
        conditions[date] = (text: text, daytime: daytime);
      }
    }

    // The 3-hourly feed resolves a wider real range for the near days, and it
    // covers today even when the weekly feed's first block already passed.
    for (final hour in hourly) {
      final date = DateTime.utc(hour.time.year, hour.time.month, hour.time.day);
      final high = highs[date];
      highs[date] = high == null
          ? hour.temperatureC
          : math.max(high, hour.temperatureC);
      final low = lows[date];
      lows[date] = low == null
          ? hour.temperatureC
          : math.min(low, hour.temperatureC);
    }

    final today = DateTime.utc(now.year, now.month, now.day);
    final dates = highs.keys.toList()..sort();
    final daily = <WeatherDaily>[];
    for (final date in dates) {
      if (date.isBefore(today) || daily.length >= forecastDayCount) {
        continue;
      }
      final high = highs[date];
      final low = lows[date];
      if (high == null || low == null) {
        continue;
      }
      final condition = conditions[date];
      daily.add(
        WeatherDaily(
          date: date,
          highC: high,
          lowC: low,
          condition: condition?.text,
          precipitationProbability: rain[date],
        ),
      );
    }
    return daily;
  }

  /// Pulls one township's weather elements out of a `F-D0047-*` response,
  /// keyed by CWA's Chinese element name.
  ///
  /// The `LocationName` filter is applied server side, but the response is
  /// still matched by name here so a filter that silently stops working
  /// degrades into picking the right township rather than the first one.
  Map<String, Object?> _elementsFor(
    Map<Object?, Object?> decoded,
    String township,
  ) {
    final records = decoded['records'];
    if (records is! Map<Object?, Object?>) {
      throw const FormatException('天氣資料格式錯誤。');
    }
    final locations = <Object?>[];
    for (final group in _asList(records['Locations'])) {
      if (group is Map<Object?, Object?>) {
        locations.addAll(_asList(group['Location']));
      }
    }
    if (locations.isEmpty) {
      throw const FormatException('天氣資料格式錯誤。');
    }

    Map<Object?, Object?>? match;
    for (final location in locations) {
      if (location is! Map<Object?, Object?>) {
        continue;
      }
      if (_asText(location['LocationName']) == township) {
        match = location;
        break;
      }
    }
    match ??= locations.first as Map<Object?, Object?>;

    final elements = <String, Object?>{};
    for (final element in _asList(match['WeatherElement'])) {
      if (element is! Map<Object?, Object?>) {
        continue;
      }
      final name = _asText(element['ElementName']);
      if (name != null) {
        elements[name] = element;
      }
    }
    return elements;
  }

  Future<Map<Object?, Object?>> _getJson(
    String dataset,
    Map<String, String> query,
  ) async {
    final uri = Uri.https(_host, '$_basePath$dataset', {
      'Authorization': kCwaApiKey,
      'format': 'JSON',
      ...query,
    });

    // Built by hand on purpose: ApiUserAgent.applyTo would attach the signed
    // in user's bearer token, and CWA is a third party.
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            // User-Agent is a forbidden header in browsers.
            if (!kIsWeb) 'User-Agent': ApiUserAgent.value,
          },
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(httpStatusMessage(response.statusCode, '天氣資料載入失敗。'));
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('天氣資料格式錯誤。');
    }
    return decoded;
  }
}

/// One station's observation, before it is narrowed to what each caller needs.
///
/// Humidity and wind stay here rather than on [WeatherSnapshot] because the app
/// bar chip never shows them.
class _StationReading {
  const _StationReading({
    required this.temperatureC,
    required this.condition,
    required this.humidity,
    required this.windSpeedKph,
  });

  final double temperatureC;
  final String? condition;
  final int? humidity;
  final double? windSpeedKph;

  WeatherSnapshot toSnapshot() => WeatherSnapshot(
    temperatureC: temperatureC,
    condition: condition,
    fetchedAt: DateTime.now(),
  );
}

/// Now, as Taiwan wall clock inside a UTC flagged [DateTime].
DateTime taiwanNow() => DateTime.now().toUtc().add(kTaiwanUtcOffset);

double? _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

int? _asInt(Object? value) {
  final parsed = _asDouble(value);
  return parsed?.toInt();
}

/// Reads a numeric observation, rejecting CWA's missing-data sentinels.
///
/// The platform reports gaps as large negative values (-99, -98, -999), which
/// would otherwise render as a plausible sub-zero temperature.
double? _asObservation(Object? value) {
  final parsed = _asDouble(value);
  if (parsed == null || parsed <= -90) {
    return null;
  }
  return parsed;
}

/// Reads a string field, treating blanks and sentinels as absent.
String? _asText(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.startsWith('-9')) {
    return null;
  }
  return trimmed;
}

/// Reads a 0-100 percentage, clamping anything out of range to the ends.
///
/// Null when CWA has no figure. It publishes `-` for the far end of the weekly
/// forecast, where a real 0% and "we do not know yet" are different claims.
int? _asPercent(Object? value) {
  final parsed = _asInt(value);
  if (parsed == null) {
    return null;
  }
  if (parsed < 0) {
    return 0;
  }
  return parsed > 100 ? 100 : parsed;
}

List<Object?> _asList(Object? value) =>
    value is List<Object?> ? value : const <Object?>[];

/// Pulls the WGS84 pair out of a station's coordinate list. CWA also ships
/// TWD67, which is offset by hundreds of metres.
(double, double)? _wgs84(Object? coordinates) {
  Map<Object?, Object?>? fallback;
  for (final entry in _asList(coordinates)) {
    if (entry is! Map<Object?, Object?>) {
      continue;
    }
    fallback ??= entry;
    if (_asText(entry['CoordinateName']) == 'WGS84') {
      final lat = _asDouble(entry['StationLatitude']);
      final lon = _asDouble(entry['StationLongitude']);
      return lat == null || lon == null ? null : (lat, lon);
    }
  }
  if (fallback == null) {
    return null;
  }
  final lat = _asDouble(fallback['StationLatitude']);
  final lon = _asDouble(fallback['StationLongitude']);
  return lat == null || lon == null ? null : (lat, lon);
}

List<Object?> _timeEntries(Object? element) {
  if (element is! Map<Object?, Object?>) {
    return const <Object?>[];
  }
  return _asList(element['Time']);
}

/// The instant an entry applies from. Instantaneous elements carry `DataTime`,
/// ranged ones carry `StartTime`.
DateTime? _entryStart(Object? entry) {
  if (entry is! Map<Object?, Object?>) {
    return null;
  }
  return _parseTaiwanWallClock(entry['DataTime'] ?? entry['StartTime']);
}

/// The entry applying at [time]: the latest one starting at or before it, else
/// the nearest one starting after it, else the first.
///
/// Used to line the phenomenon and rain blocks up with the temperature series,
/// which CWA samples more finely — hourly for the first day, then every three
/// hours, while 天氣現象 and 降雨機率 stay on three hour blocks throughout. It
/// also has to work for the instantaneous elements, which carry a `DataTime`
/// and no end, so the newest sample at or before [time] is the answer rather
/// than the first one that happens to precede it.
Map<Object?, Object?>? _entryCovering(List<Object?> entries, DateTime time) {
  Map<Object?, Object?>? first;
  Map<Object?, Object?>? current;
  DateTime? currentStart;
  Map<Object?, Object?>? nextUp;
  DateTime? nextStart;
  for (final entry in entries) {
    if (entry is! Map<Object?, Object?>) {
      continue;
    }
    first ??= entry;
    final start = _entryStart(entry);
    if (start == null) {
      continue;
    }
    if (start.isAfter(time)) {
      if (nextStart == null || start.isBefore(nextStart)) {
        nextUp = entry;
        nextStart = start;
      }
      continue;
    }
    // A ranged entry only counts while it is still running.
    final end = _parseTaiwanWallClock(entry['EndTime']);
    if (end != null && !end.isAfter(time)) {
      continue;
    }
    if (currentStart == null || start.isAfter(currentStart)) {
      current = entry;
      currentStart = start;
    }
  }
  return current ?? nextUp ?? first;
}

/// Reads a value out of an entry's `ElementValue` list by key.
Object? _valueOf(Object? entry, String key) {
  if (entry is! Map<Object?, Object?>) {
    return null;
  }
  for (final value in _asList(entry['ElementValue'])) {
    if (value is Map<Object?, Object?> && value[key] != null) {
      return value[key];
    }
  }
  return null;
}

final RegExp _wallClockPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?',
);

/// Parses a CWA timestamp such as `2026-09-06T18:00:00+08:00`.
///
/// The digits are read straight into a UTC value so the result always reads
/// back as Taiwan wall clock whatever the device's own timezone is. The
/// trailing offset is deliberately ignored: it is always +08:00, and
/// `DateTime.parse` would hand back a local time that shifts an hour for
/// anyone whose zone is mid DST transition.
DateTime? _parseTaiwanWallClock(Object? value) {
  if (value is! String) {
    return null;
  }
  final match = _wallClockPattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4) ?? '0'),
    int.parse(match.group(5) ?? '0'),
  );
}

/// Sunrise and sunset for a location, as Taiwan wall clock.
typedef SunTimes = ({DateTime sunrise, DateTime sunset});

/// Computes today's sunrise and sunset from coordinates.
///
/// CWA publishes a sunrise/sunset dataset, but it is keyed by county and date
/// and would cost another request per refresh for two values that are pure
/// astronomy. This is the standard NOAA sunrise equation; it is accurate to
/// well under a minute at Taiwan's latitudes.
///
/// Returns null inside a polar day or night, which cannot happen for Taiwan
/// but keeps the function honest if it is ever reused.
SunTimes? sunTimes({
  required double latitude,
  required double longitude,
  DateTime? now,
}) {
  const julianUnixEpoch = 2440587.5;
  const julianJ2000 = 2451545.0;
  const leapSecondCorrection = 0.0009;

  final instant = (now ?? DateTime.now()).toUtc();
  final julianNow =
      instant.millisecondsSinceEpoch / Duration.millisecondsPerDay +
      julianUnixEpoch;

  // West longitude is positive in the classic formulation.
  final west = -longitude / 360;
  final cycle = (julianNow - julianJ2000 - leapSecondCorrection - west)
      .roundToDouble();
  final meanSolarNoon = julianJ2000 + leapSecondCorrection + west + cycle;

  final meanAnomalyDeg = (357.5291 + 0.98560028 * (meanSolarNoon - julianJ2000)) % 360;
  final meanAnomaly = _toRadians(meanAnomalyDeg);
  final centre =
      1.9148 * math.sin(meanAnomaly) +
      0.02 * math.sin(2 * meanAnomaly) +
      0.0003 * math.sin(3 * meanAnomaly);
  final eclipticLongitude = _toRadians((meanAnomalyDeg + centre + 282.9372) % 360);

  final solarTransit =
      meanSolarNoon +
      0.0053 * math.sin(meanAnomaly) -
      0.0069 * math.sin(2 * eclipticLongitude);

  final declination = math.asin(
    math.sin(eclipticLongitude) * math.sin(_toRadians(23.44)),
  );
  // -0.833° puts the sun's upper limb on the horizon, allowing for refraction.
  final hourAngleCos =
      (math.sin(_toRadians(-0.833)) -
          math.sin(_toRadians(latitude)) * math.sin(declination)) /
      (math.cos(_toRadians(latitude)) * math.cos(declination));
  if (hourAngleCos.abs() > 1) {
    return null;
  }
  final hourAngle = math.acos(hourAngleCos) * 180 / math.pi;

  DateTime toWallClock(double julian) {
    final millis = ((julian - julianUnixEpoch) * Duration.millisecondsPerDay)
        .round();
    return DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ).add(kTaiwanUtcOffset);
  }

  return (
    sunrise: toWallClock(solarTransit - hourAngle / 360),
    sunset: toWallClock(solarTransit + hourAngle / 360),
  );
}
