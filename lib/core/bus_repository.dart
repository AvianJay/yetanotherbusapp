import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class DatabaseNotReadyException implements Exception {
  DatabaseNotReadyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BusRepository {
  BusRepository({http.Client? client}) : _client = client ?? http.Client();

  static const _apiBaseUrl = 'https://bus.avianjay.sbs';
  static const _userAgent = 'Mozilla/5.0 (YABus Flutter)';
  static const _webLocalDatabaseUnsupportedMessage =
      'Web does not support the local SQLite database used by this app.';

  final http.Client _client;

  Future<bool> databaseExists(BusProvider provider) async {
    if (!_supportsLocalDatabase) {
      return false;
    }
    final file = await _databaseFile(provider);
    return file.exists();
  }

  Future<Map<BusProvider, int?>> checkForUpdates() async {
    final remoteVersion = await _fetchRemoteDatabaseVersion();
    final localVersions = _supportsLocalDatabase
        ? await _readVersionMap()
        : {for (final provider in BusProvider.values) provider.name: 0};

    return {
      for (final provider in BusProvider.values)
        provider: remoteVersion > (localVersions[provider.name] ?? 0)
            ? remoteVersion
            : null,
    };
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
    final remoteVersion = await _fetchRemoteDatabaseVersion();
    final masterFile = await _masterDatabaseFile();
    final localVersions = await _readVersionMap();
    final localVersion = localVersions[provider.name] ?? 0;

    if (!await masterFile.exists() || localVersion < remoteVersion) {
      await _downloadMasterDatabase(masterFile);
    }

    await _buildRegionalDatabase(
      provider: provider,
      masterFile: masterFile,
      version: remoteVersion,
    );

    localVersions[provider.name] = remoteVersion;
    await _writeVersionMap(localVersions);
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
        orderBy: 'sequence ASC, route_name ASC',
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
      throw StateError('Route $routeKey was not found.');
    }

    final paths = await getPaths(routeKey, provider: provider);
    final stops = await getStopsByRoute(routeKey, provider: provider);
    var hasLiveData = true;
    Map<String, _LiveStopPayload> liveMap;

    try {
      liveMap = await _getLiveStopMap(route.routeId);
    } catch (_) {
      hasLiveData = false;
      liveMap = const <String, _LiveStopPayload>{};
    }

    final stopsByPath = <int, List<StopInfo>>{
      for (final path in paths) path.pathId: <StopInfo>[],
    };

    for (final stop in stops) {
      final livePayload = liveMap[_stopCompositeKey(stop.pathId, stop.stopId)];
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

  Future<List<NearbyStopResult>> fetchNearbyStops({
    required BusProvider provider,
    required double latitude,
    required double longitude,
    double radiusMeters = 500,
    int limit = 20,
  }) async {
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
          routeId: row['route_id']?.toString() ?? '',
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

  Future<int> _fetchRemoteDatabaseVersion() async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/downloads/bus.db'),
      headers: const {'Range': 'bytes=0-0', 'User-Agent': _userAgent},
    );

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException(
        'Failed to check remote database version (${response.statusCode}).',
      );
    }

    return _buildVersionFromHeaders(response.headers);
  }

  Future<void> _downloadMasterDatabase(File targetFile) async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/downloads/bus.db'),
      headers: const {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download the master database (${response.statusCode}).',
      );
    }

    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(response.bodyBytes, flush: true);
  }

  Future<void> _buildRegionalDatabase({
    required BusProvider provider,
    required File masterFile,
    required int version,
  }) async {
    final tempPath = p.join(
      (await _databaseDirectory()).path,
      'tmp_${provider.name}_${DateTime.now().millisecondsSinceEpoch}.sqlite',
    );
    await deleteDatabase(tempPath);

    final masterDatabase = await openDatabase(
      masterFile.path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      final routeRows = await masterDatabase.query(
        'routes',
        where: 'SUBSTR(routeid, 1, 3) = ?',
        whereArgs: [provider.prefix],
        orderBy: 'routeid ASC',
      );
      if (routeRows.isEmpty) {
        throw StateError('No routes were found for ${provider.label}.');
      }

      final pathRows = await masterDatabase.query(
        'paths',
        where: 'SUBSTR(routeid, 1, 3) = ?',
        whereArgs: [provider.prefix],
        orderBy: 'routeid ASC, pathid ASC',
      );

      final routeEntries = routeRows
          .map(
            (row) => _RouteEntry(
              routeId: row['routeid'] as String? ?? '',
              name: row['name'] as String? ?? '',
              nameEn: row['name_en'] as String? ?? '',
            ),
          )
          .where((entry) => entry.routeId.isNotEmpty)
          .toList();

      final routeKeys = {
        for (final entry in routeEntries)
          entry.routeId: _routeKeyForRouteId(entry.routeId),
      };

      final database = await openDatabase(
        tempPath,
        version: 1,
        onCreate: (db, version) async {
          await _createRegionalSchema(db);
        },
      );

      try {
        final routeBatch = database.batch();
        for (var index = 0; index < routeEntries.length; index++) {
          final entry = routeEntries[index];
          routeBatch.insert('routes', {
            'provider': provider.name,
            'hash_md5': version.toString(),
            'route_key': routeKeys[entry.routeId],
            'route_id': entry.routeId,
            'route_name': entry.name,
            'official_route_name': entry.nameEn,
            'description': provider.label,
            'category': provider.label,
            'sequence': index + 1,
            'rtrip': 0,
          });
        }

        for (final row in pathRows) {
          final routeId = row['routeid'] as String? ?? '';
          final routeKey = routeKeys[routeId];
          if (routeKey == null) {
            continue;
          }
          routeBatch.insert('paths', {
            'route_key': routeKey,
            'path_id': (row['pathid'] as num?)?.toInt() ?? 0,
            'path_name': row['name'] as String? ?? '',
          });
        }
        await routeBatch.commit(noResult: true);

        final stopResponses = <_RouteStopsResponse>[];
        for (final chunk in _chunk(routeEntries, 10)) {
          final fetched = await Future.wait(
            chunk.map((entry) => _fetchRouteStops(entry.routeId)),
          );
          stopResponses.addAll(fetched);
        }

        final stopBatch = database.batch();
        for (final response in stopResponses) {
          final routeKey = routeKeys[response.routeId];
          if (routeKey == null) {
            continue;
          }
          for (final path in response.paths) {
            stopBatch.update(
              'paths',
              {'path_name': path.name},
              where: 'route_key = ? AND path_id = ?',
              whereArgs: [routeKey, path.pathId],
            );
            for (final stop in path.stops) {
              stopBatch.insert('stops', {
                'route_key': routeKey,
                'path_id': path.pathId,
                'stop_id': stop.stopId,
                'stop_name': stop.stopName,
                'sequence': stop.sequence,
                'lon': stop.lon,
                'lat': stop.lat,
              });
            }
          }
        }
        await stopBatch.commit(noResult: true);
      } finally {
        await database.close();
      }
    } finally {
      await masterDatabase.close();
    }

    final databaseFile = await _databaseFile(provider);
    await databaseFile.parent.create(recursive: true);
    if (await databaseFile.exists()) {
      await databaseFile.delete();
    }
    await File(tempPath).rename(databaseFile.path);
  }

  Future<void> _createRegionalSchema(Database db) async {
    await db.execute('''
      CREATE TABLE routes (
        provider TEXT NOT NULL,
        hash_md5 TEXT NOT NULL,
        route_key INTEGER PRIMARY KEY,
        route_id TEXT NOT NULL UNIQUE,
        route_name TEXT NOT NULL,
        official_route_name TEXT NOT NULL,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        rtrip INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_routes_name ON routes(route_name)');

    await db.execute('''
      CREATE TABLE paths (
        route_key INTEGER NOT NULL,
        path_id INTEGER NOT NULL,
        path_name TEXT NOT NULL,
        PRIMARY KEY (route_key, path_id)
      )
    ''');
    await db.execute('CREATE INDEX idx_paths_route_key ON paths(route_key)');

    await db.execute('''
      CREATE TABLE stops (
        route_key INTEGER NOT NULL,
        path_id INTEGER NOT NULL,
        stop_id INTEGER NOT NULL,
        stop_name TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        lon REAL NOT NULL,
        lat REAL NOT NULL,
        PRIMARY KEY (route_key, path_id, stop_id)
      )
    ''');
    await db.execute('CREATE INDEX idx_stops_route_key ON stops(route_key)');
    await db.execute('CREATE INDEX idx_stops_location ON stops(lat, lon)');
  }

  Future<_RouteStopsResponse> _fetchRouteStops(String routeId) async {
    final response = await _client.get(
      Uri.parse(
        '$_apiBaseUrl/api/v1/routes/${Uri.encodeComponent(routeId)}/stops',
      ),
      headers: const {'Accept': 'application/json', 'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch stops for $routeId (${response.statusCode}).',
      );
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final pathPayloads = (decoded['paths'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (path) => _RoutePathStopsPayload(
            pathId: _toInt(path['pathid']),
            name: path['name']?.toString() ?? '',
            stops: (path['stops'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map(
                  (stop) => _RouteStopPayload(
                    stopId: _parseStopId(stop['stopid']),
                    stopName: stop['name']?.toString() ?? '',
                    sequence: _toInt(stop['seq']),
                    lat: _toDouble(stop['lat']),
                    lon: _toDouble(stop['lon']),
                  ),
                )
                .toList(),
          ),
        )
        .toList();

    return _RouteStopsResponse(
      routeId: decoded['routeid']?.toString() ?? routeId,
      paths: pathPayloads,
    );
  }

  Future<Map<String, _LiveStopPayload>> _getLiveStopMap(String routeId) async {
    final response = await _client.get(
      Uri.parse(
        '$_apiBaseUrl/api/v1/routes/${Uri.encodeComponent(routeId)}/realtime',
      ),
      headers: const {'Accept': 'application/json', 'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to fetch live route data for $routeId (${response.statusCode}).',
      );
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final result = <String, _LiveStopPayload>{};

    for (final rawPath in decoded['paths'] as List<dynamic>? ?? const []) {
      if (rawPath is! Map) {
        continue;
      }
      final pathId = _toInt(rawPath['pathid']);
      for (final rawStop in rawPath['stops'] as List<dynamic>? ?? const []) {
        if (rawStop is! Map) {
          continue;
        }
        final stopId = _parseStopId(rawStop['stopid']);
        result[_stopCompositeKey(pathId, stopId)] = _LiveStopPayload(
          sec: _nullableInt(rawStop['eta']),
          msg: rawStop['message']?.toString(),
          t: rawStop['updated_at']?.toString(),
          buses: (rawStop['buses'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(_parseBusVehicle)
              .toList(),
        );
      }
    }

    return result;
  }

  BusVehicle _parseBusVehicle(Map<dynamic, dynamic> payload) {
    final id =
        payload['id']?.toString() ??
        payload['vehicle_id']?.toString() ??
        payload['plate']?.toString() ??
        '';
    final note =
        payload['note']?.toString() ?? payload['message']?.toString() ?? '';
    final fullValue = payload['full'];
    final carOnStopValue = payload['carOnStop'] ?? payload['car_on_stop'];
    return BusVehicle(
      id: id,
      type: payload['type']?.toString() ?? '',
      note: note,
      full: fullValue == true || fullValue?.toString() == '1',
      carOnStop: carOnStopValue == true || carOnStopValue?.toString() == '1',
    );
  }

  Future<Database> _openDatabase(BusProvider provider) async {
    _ensureLocalDatabaseSupported();
    final file = await _databaseFile(provider);
    if (!await file.exists()) {
      throw DatabaseNotReadyException(
        'The ${provider.label} database has not been downloaded yet.',
      );
    }

    return openDatabase(file.path, readOnly: true, singleInstance: false);
  }

  Future<File> _databaseFile(BusProvider provider) async {
    final directory = await _databaseDirectory();
    return File(p.join(directory.path, provider.databaseFileName));
  }

  Future<File> _masterDatabaseFile() async {
    final directory = await _databaseDirectory();
    return File(p.join(directory.path, 'master_bus.db'));
  }

  Future<Directory> _databaseDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, '.yabus_backend'));
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

  int _buildVersionFromHeaders(Map<String, String> headers) {
    final lastModified = headers['last-modified'];
    if (lastModified != null && lastModified.isNotEmpty) {
      final parsed = HttpDate.parse(lastModified).toUtc();
      return parsed.year * 100000000 +
          parsed.month * 1000000 +
          parsed.day * 10000 +
          parsed.hour * 100 +
          parsed.minute;
    }

    final contentLength = int.tryParse(headers['content-length'] ?? '');
    return contentLength ?? 0;
  }

  int _routeKeyForRouteId(String routeId) {
    const offset = 0x811c9dc5;
    const prime = 0x01000193;
    var hash = offset;
    for (final codeUnit in routeId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & 0x7fffffff;
    }
    return hash;
  }

  int _parseStopId(Object? raw) {
    if (raw is num) {
      return raw.toInt();
    }
    final text = raw?.toString().trim() ?? '';
    final parsed = int.tryParse(text);
    if (parsed != null) {
      return parsed;
    }
    var hash = 17;
    for (final codeUnit in text.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  int _toInt(Object? value) => _nullableInt(value) ?? 0;

  int? _nullableInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _degreesToRadians(double degree) => degree * math.pi / 180;

  String _stopCompositeKey(int pathId, int stopId) => '$pathId:$stopId';

  Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (var index = 0; index < items.length; index += size) {
      final end = math.min(index + size, items.length);
      yield items.sublist(index, end);
    }
  }

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
    for (final item in items) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }
}

class _RouteEntry {
  const _RouteEntry({
    required this.routeId,
    required this.name,
    required this.nameEn,
  });

  final String routeId;
  final String name;
  final String nameEn;
}

class _RouteStopsResponse {
  const _RouteStopsResponse({required this.routeId, required this.paths});

  final String routeId;
  final List<_RoutePathStopsPayload> paths;
}

class _RoutePathStopsPayload {
  const _RoutePathStopsPayload({
    required this.pathId,
    required this.name,
    required this.stops,
  });

  final int pathId;
  final String name;
  final List<_RouteStopPayload> stops;
}

class _RouteStopPayload {
  const _RouteStopPayload({
    required this.stopId,
    required this.stopName,
    required this.sequence,
    required this.lon,
    required this.lat,
  });

  final int stopId;
  final String stopName;
  final int sequence;
  final double lon;
  final double lat;
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
