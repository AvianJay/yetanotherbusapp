import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:xml/xml.dart';

import 'models.dart';

class DatabaseNotReadyException implements Exception {
  DatabaseNotReadyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BusRepository {
  BusRepository({http.Client? client}) : _client = client ?? http.Client();

  static const _busFileBaseUrl = 'https://files.bus.yahoo.com/';
  static const _busServerBaseUrl = 'https://busserver.bus.yahoo.com/';
  static const _webLocalDatabaseUnsupportedMessage =
      'Web does not support the local SQLite database used by this app yet. '
      'Use Windows or Android for database-backed features.';

  final http.Client _client;

  Future<bool> databaseExists(BusProvider provider) async {
    if (!_supportsLocalDatabase) {
      return false;
    }
    final file = await _databaseFile(provider);
    return file.exists();
  }

  Future<Map<BusProvider, int?>> checkForUpdates() async {
    final localVersions = _supportsLocalDatabase
        ? await _readVersionMap()
        : {for (final provider in BusProvider.values) provider.name: 0};
    final results = <BusProvider, int?>{};

    for (final provider in BusProvider.values) {
      final response = await _client.get(
        Uri.parse(
          '$_busFileBaseUrl'
          'bustracker/data/${provider.dataUrlTextFile}',
        ),
      );
      if (response.statusCode != 200) {
        throw HttpException(
          '無法檢查 ${provider.label} 資料庫版本 (${response.statusCode})',
        );
      }

      final baseUrl = response.body.trim();
      final remoteVersion = _extractVersionFromBaseUrl(baseUrl);
      final localVersion = localVersions[provider.name] ?? 0;
      results[provider] = remoteVersion > localVersion ? remoteVersion : null;
    }

    return results;
  }

  Future<int?> getLocalVersion(BusProvider provider) async {
    if (!_supportsLocalDatabase) {
      return null;
    }
    final versions = await _readVersionMap();
    return versions[provider.name];
  }

  Future<void> downloadDatabase(BusProvider provider) async {
    _ensureLocalDatabaseSupported();
    final response = await _client.get(
      Uri.parse(
        '$_busFileBaseUrl'
        'bustracker/data/${provider.dataUrlTextFile}',
      ),
    );
    if (response.statusCode != 200) {
      throw HttpException(
        '無法取得 ${provider.label} 資料庫下載資訊 (${response.statusCode})',
      );
    }

    final baseUrl = response.body.trim();
    final archiveResponse = await _client.get(
      Uri.parse('$baseUrl${provider.archiveFileName}'),
    );
    if (archiveResponse.statusCode != 200) {
      throw HttpException(
        '無法下載 ${provider.label} 資料庫 (${archiveResponse.statusCode})',
      );
    }

    final databaseFile = await _databaseFile(provider);
    await databaseFile.parent.create(recursive: true);
    final bytes = zlib.decode(archiveResponse.bodyBytes);
    await databaseFile.writeAsBytes(bytes, flush: true);

    final versions = await _readVersionMap();
    versions[provider.name] = _extractVersionFromBaseUrl(baseUrl);
    await _writeVersionMap(versions);
  }

  Future<List<RouteSummary>> searchRoutes(
    String query, {
    required BusProvider provider,
    int limit = 80,
  }) async {
    final database = await _openDatabase(provider);
    try {
      final rows = await database.query(
        'routes',
        where: 'route_name LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'sequence ASC',
        limit: limit,
      );
      return rows.map(RouteSummary.fromMap).toList();
    } finally {
      await database.close();
    }
  }

  Future<RouteSummary?> getRoute(
    int routeKey, {
    required BusProvider provider,
  }) async {
    final database = await _openDatabase(provider);
    try {
      final rows = await database.query(
        'routes',
        where: 'route_key = ?',
        whereArgs: [routeKey],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }

      return RouteSummary.fromMap(rows.first);
    } finally {
      await database.close();
    }
  }

  Future<List<PathInfo>> getPaths(
    int routeKey, {
    required BusProvider provider,
  }) async {
    final database = await _openDatabase(provider);
    try {
      final rows = await database.query(
        'paths',
        where: 'route_key = ?',
        whereArgs: [routeKey],
        orderBy: 'path_id ASC',
      );
      return rows.map(PathInfo.fromMap).toList();
    } finally {
      await database.close();
    }
  }

  Future<List<StopInfo>> getStopsByRoute(
    int routeKey, {
    required BusProvider provider,
  }) async {
    if (provider == BusProvider.twn) {
      return _fetchRouteStopsFromXml(routeKey);
    }

    final database = await _openDatabase(provider);
    try {
      final rows = await database.query(
        'stops',
        where: 'route_key = ?',
        whereArgs: [routeKey],
        orderBy: 'path_id ASC, sequence ASC',
      );
      return rows.map(StopInfo.fromMap).toList();
    } finally {
      await database.close();
    }
  }

  Future<RouteDetailData> getCompleteBusInfo(
    int routeKey, {
    required BusProvider provider,
  }) async {
    final route = await getRoute(routeKey, provider: provider);
    if (route == null) {
      throw StateError('找不到路線 $routeKey');
    }

    final paths = await getPaths(routeKey, provider: provider);
    final stops = await getStopsByRoute(routeKey, provider: provider);
    var hasLiveData = true;
    Map<int, _LiveStopPayload> liveMap;
    try {
      liveMap = await _getLiveStopMap(routeKey);
    } catch (_) {
      hasLiveData = false;
      liveMap = const <int, _LiveStopPayload>{};
    }
    final stopsByPath = <int, List<StopInfo>>{
      for (final path in paths) path.pathId: <StopInfo>[],
    };

    for (final stop in stops) {
      final livePayload = liveMap[stop.stopId];
      final enriched = livePayload == null
          ? stop
          : stop.copyWith(
              sec: livePayload.sec,
              msg: livePayload.msg,
              t: livePayload.t,
              buses: livePayload.buses,
            );
      stopsByPath.putIfAbsent(stop.pathId, () => <StopInfo>[]).add(enriched);
    }

    for (final entry in stopsByPath.entries) {
      entry.value.sort(
        (left, right) => left.sequence.compareTo(right.sequence),
      );
    }

    return RouteDetailData(
      route: route,
      paths: paths,
      stopsByPath: stopsByPath,
      hasLiveData: hasLiveData,
    );
  }

  Future<TrackedBusSnapshot> getTrackedBusSnapshot(
    TrackedBus trackedBus,
  ) async {
    final response = await _client.get(
      Uri.parse(
        '${_busServerBaseUrl}api/bus/${Uri.encodeComponent(trackedBus.vehicleId)}',
      ),
    );
    final plainText = utf8
        .decode(response.bodyBytes, allowMalformed: true)
        .trim();
    if (response.statusCode == 210 || plainText.toLowerCase() == 'offline') {
      return TrackedBusSnapshot(
        trackedBus: trackedBus,
        state: TrackedBusState.offline,
      );
    }
    if (response.statusCode != 200) {
      throw HttpException(
        '無法取得 ${trackedBus.vehicleId} 的車輛資訊 (${response.statusCode})',
      );
    }

    final xmlText = _decodeBusServerPayload(response.bodyBytes);
    if (xmlText.trim().toLowerCase() == 'offline') {
      return TrackedBusSnapshot(
        trackedBus: trackedBus,
        state: TrackedBusState.offline,
      );
    }

    final document = XmlDocument.parse(xmlText);
    final busElement = document.rootElement.name.local == 'b'
        ? document.rootElement
        : _firstWhereOrNull(
            document.findAllElements('b'),
            (element) => element.name.local == 'b',
          );
    if (busElement == null) {
      throw const FormatException('Unexpected tracked bus payload.');
    }

    return TrackedBusSnapshot(
      trackedBus: trackedBus,
      state: TrackedBusState.online,
      currentRouteKey: int.tryParse(busElement.getAttribute('key') ?? ''),
      currentRouteName: busElement.getAttribute('rzh'),
      currentPathId: int.tryParse(busElement.getAttribute('pid') ?? ''),
      currentPathName: busElement.getAttribute('pzh'),
      currentStopId: int.tryParse(busElement.getAttribute('sid') ?? ''),
      currentStopName: busElement.getAttribute('szh'),
      longitude: double.tryParse(busElement.getAttribute('lon') ?? ''),
      latitude: double.tryParse(busElement.getAttribute('lat') ?? ''),
      carOnStop: busElement.getAttribute('carOnStop')?.toLowerCase() == 'true',
    );
  }

  Future<List<NearbyStopResult>> fetchNearbyStops({
    required BusProvider provider,
    required double latitude,
    required double longitude,
    double radiusMeters = 500,
    int limit = 20,
  }) async {
    if (provider == BusProvider.twn) {
      throw UnsupportedError('全台資料庫沒有站點座標索引，附近站牌請改用雙北或台中 provider。');
    }

    final latDelta = radiusMeters / 111320;
    final lonDelta =
        radiusMeters / (111320 * math.cos(latitude * math.pi / 180)).abs();
    final database = await _openDatabase(provider);

    try {
      final rows = await database.rawQuery(
        '''
        SELECT
          stops.route_key,
          stops.path_id,
          stops.stop_id,
          stops.stop_name,
          stops.sequence,
          stops.lon,
          stops.lat,
          routes.provider,
          routes.hash_md5,
          routes.route_id,
          routes.route_name,
          routes.official_route_name,
          routes.description,
          routes.category,
          routes.sequence AS route_sequence,
          routes.rtrip
        FROM stops
        INNER JOIN routes ON routes.route_key = stops.route_key
        WHERE ABS(stops.lat - ?) <= ?
          AND ABS(stops.lon - ?) <= ?
        LIMIT 500
        ''',
        [latitude, latDelta, longitude, lonDelta],
      );

      final results = <NearbyStopResult>[];
      final seen = <String>{};

      for (final row in rows) {
        final stop = StopInfo(
          routeKey: (row['route_key'] as num?)?.toInt() ?? 0,
          pathId: (row['path_id'] as num?)?.toInt() ?? 0,
          stopId: (row['stop_id'] as num?)?.toInt() ?? 0,
          stopName: row['stop_name'] as String? ?? '',
          sequence: (row['sequence'] as num?)?.toInt() ?? 0,
          lon: (row['lon'] as num?)?.toDouble() ?? 0,
          lat: (row['lat'] as num?)?.toDouble() ?? 0,
        );
        final distance = calculateDistanceMeters(
          latitude,
          longitude,
          stop.lat,
          stop.lon,
        );
        if (distance > radiusMeters) {
          continue;
        }

        final dedupeKey = '${stop.routeKey}-${stop.pathId}-${stop.stopId}';
        if (!seen.add(dedupeKey)) {
          continue;
        }

        final route = RouteSummary(
          sourceProvider: row['provider'] as String? ?? '',
          hashMd5: row['hash_md5'] as String? ?? '',
          routeKey: (row['route_key'] as num?)?.toInt() ?? 0,
          routeId: (row['route_id'] as num?)?.toInt() ?? 0,
          routeName: row['route_name'] as String? ?? '',
          officialRouteName: row['official_route_name'] as String? ?? '',
          description: row['description'] as String? ?? '',
          category: row['category'] as String? ?? '',
          sequence: (row['route_sequence'] as num?)?.toInt() ?? 0,
          rtrip: (row['rtrip'] as num?)?.toInt() ?? 0,
        );

        results.add(
          NearbyStopResult(route: route, stop: stop, distanceMeters: distance),
        );
      }

      results.sort(
        (left, right) => left.distanceMeters.compareTo(right.distanceMeters),
      );
      return results.take(limit).toList();
    } finally {
      await database.close();
    }
  }

  Future<FavoriteResolvedItem?> resolveFavorite(FavoriteStop reference) async {
    final route = await getRoute(
      reference.routeKey,
      provider: reference.provider,
    );
    if (route == null) {
      return null;
    }

    final stops = await getStopsByRoute(
      reference.routeKey,
      provider: reference.provider,
    );
    final stop = _firstWhereOrNull(
      stops,
      (item) =>
          item.stopId == reference.stopId && item.pathId == reference.pathId,
    );
    if (stop == null) {
      return null;
    }

    return FavoriteResolvedItem(reference: reference, route: route, stop: stop);
  }

  Future<List<FavoriteResolvedItem>> resolveFavoriteGroup(
    List<FavoriteStop> references,
  ) async {
    final items = await Future.wait(references.map(resolveFavorite));
    return items.whereType<FavoriteResolvedItem>().toList();
  }

  double calculateDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6378.137;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c * 1000;
  }

  Future<List<StopInfo>> _fetchRouteStopsFromXml(int routeKey) async {
    final response = await _client.get(
      Uri.parse(
        '$_busFileBaseUrl'
        'bustracker/routes/${routeKey}_zh.dat',
      ),
    );
    if (response.statusCode != 200) {
      throw HttpException('無法載入路線站牌 (${response.statusCode})');
    }

    final xmlText = utf8.decode(zlib.decode(response.bodyBytes));
    final document = XmlDocument.parse(xmlText);
    final routes = document.findAllElements('r');
    final stops = <StopInfo>[];

    for (final routeElement in routes) {
      final currentRouteKey =
          int.tryParse(routeElement.getAttribute('key') ?? '') ?? routeKey;
      for (final pathElement in routeElement.findElements('p')) {
        final pathId = int.tryParse(pathElement.getAttribute('id') ?? '') ?? 0;
        for (final stopElement in pathElement.findElements('s')) {
          stops.add(
            StopInfo(
              routeKey: currentRouteKey,
              pathId: pathId,
              stopId: int.tryParse(stopElement.getAttribute('id') ?? '') ?? 0,
              stopName: stopElement.getAttribute('nm') ?? '',
              sequence:
                  int.tryParse(stopElement.getAttribute('seq') ?? '') ?? 0,
              lon: double.tryParse(stopElement.getAttribute('lon') ?? '') ?? 0,
              lat: double.tryParse(stopElement.getAttribute('lat') ?? '') ?? 0,
            ),
          );
        }
      }
    }

    return stops;
  }

  Future<Map<int, _LiveStopPayload>> _getLiveStopMap(int routeKey) async {
    final response = await _client.get(
      Uri.parse('${_busServerBaseUrl}api/route/$routeKey'),
    );
    if (response.statusCode != 200) {
      throw HttpException('即時資料暫時無法取得 (${response.statusCode})');
    }

    final xmlText = utf8.decode(zlib.decode(response.bodyBytes));
    final document = XmlDocument.parse(xmlText);
    final result = <int, _LiveStopPayload>{};

    for (final stopElement in document.findAllElements('e')) {
      final stopId = int.tryParse(stopElement.getAttribute('id') ?? '') ?? 0;
      result[stopId] = _LiveStopPayload(
        sec: int.tryParse(stopElement.getAttribute('sec') ?? ''),
        msg: stopElement.getAttribute('msg'),
        t: stopElement.getAttribute('t'),
        buses: stopElement
            .findElements('b')
            .map(
              (busElement) => BusVehicle(
                id: busElement.getAttribute('id') ?? '',
                type: busElement.getAttribute('type') ?? '',
                note: busElement.getAttribute('note') ?? '',
                full: busElement.getAttribute('full') == '1',
                carOnStop:
                    busElement.getAttribute('carOnStop')?.toLowerCase() ==
                    'true',
              ),
            )
            .toList(),
      );
    }

    return result;
  }

  String _decodeBusServerPayload(List<int> bytes) {
    final plainText = utf8.decode(bytes, allowMalformed: true).trim();
    if (plainText.startsWith('<?xml') ||
        plainText.toLowerCase() == 'offline' ||
        plainText.startsWith('<b')) {
      return plainText;
    }

    try {
      return utf8.decode(zlib.decode(bytes));
    } catch (_) {
      return plainText;
    }
  }

  Future<Database> _openDatabase(BusProvider provider) async {
    _ensureLocalDatabaseSupported();
    final file = await _databaseFile(provider);
    if (!await file.exists()) {
      throw DatabaseNotReadyException('尚未下載 ${provider.label} 資料庫。');
    }

    return openDatabase(file.path, readOnly: true, singleInstance: false);
  }

  Future<File> _databaseFile(BusProvider provider) async {
    final directory = await _databaseDirectory();
    return File(p.join(directory.path, provider.databaseFileName));
  }

  Future<Directory> _databaseDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, '.taiwanbus'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Map<String, int>> _readVersionMap() async {
    final directory = await _databaseDirectory();
    final file = File(p.join(directory.path, 'version.json'));
    if (!await file.exists()) {
      return {for (final provider in BusProvider.values) provider.name: 0};
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final provider in BusProvider.values)
          provider.name: (decoded[provider.name] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return {for (final provider in BusProvider.values) provider.name: 0};
    }
  }

  Future<void> _writeVersionMap(Map<String, int> versions) async {
    final directory = await _databaseDirectory();
    final file = File(p.join(directory.path, 'version.json'));
    await file.writeAsString(jsonEncode(versions), flush: true);
  }

  bool get _supportsLocalDatabase => !kIsWeb;

  void _ensureLocalDatabaseSupported() {
    if (!_supportsLocalDatabase) {
      throw UnsupportedError(_webLocalDatabaseUnsupportedMessage);
    }
  }

  int _extractVersionFromBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) {
      return 0;
    }

    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
    for (final segment in segments.toList().reversed) {
      final value = int.tryParse(segment);
      if (value != null) {
        return value;
      }
    }

    return 0;
  }

  double _degreesToRadians(double degree) => degree * math.pi / 180;

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
    for (final item in items) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }
}

class _LiveStopPayload {
  const _LiveStopPayload({
    required this.sec,
    required this.msg,
    required this.t,
    required this.buses,
  });

  final int? sec;
  final String? msg;
  final String? t;
  final List<BusVehicle> buses;
}
