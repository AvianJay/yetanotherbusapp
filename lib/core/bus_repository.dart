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
      'Web 版目前不支援本 app 使用的本機 SQLite 資料庫。';

  final http.Client _client;

  Future<bool> databaseExists(BusProvider provider) async {
    if (!_supportsLocalDatabase) {
      return false;
    }
    final file = await _databaseFile(provider);
    return file.exists();
  }

  Future<List<BusProvider>> listDownloadedProviders() async {
    if (!_supportsLocalDatabase) {
      return const [];
    }
    final result = <BusProvider>[];
    for (final provider in BusProvider.values) {
      if (await databaseExists(provider)) {
        result.add(provider);
      }
    }
    return result;
  }

  Future<void> deleteProviderDatabase(BusProvider provider) async {
    _ensureLocalDatabaseSupported();
    final file = await _databaseFile(provider);
    if (await file.exists()) {
      await file.delete();
    }

    final versions = await _readVersionMap();
    versions.remove(provider.name);
    await _writeVersionMap(versions);
  }

  Future<Map<BusProvider, int?>> checkForUpdates({
    Iterable<BusProvider>? providers,
  }) async {
    final targetProviders = (providers ?? BusProvider.values).toList();
    final localVersions = _supportsLocalDatabase
        ? await _readVersionMap()
        : {for (final provider in BusProvider.values) provider.name: 0};

    final updates = <BusProvider, int?>{};
    for (final provider in targetProviders) {
      final remoteVersion = await _fetchRemoteDatabaseVersion(provider);
      final localVersion = localVersions[provider.name] ?? 0;
      updates[provider] = remoteVersion > localVersion ? remoteVersion : null;
    }
    return updates;
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
    final remoteVersion = await _fetchRemoteDatabaseVersion(provider);
    final file = await _databaseFile(provider);

    await _downloadCityDatabase(provider, file);

    final versions = await _readVersionMap();
    versions[provider.name] = remoteVersion;
    await _writeVersionMap(versions);
  }

  Future<List<RouteSummary>> searchRoutes(
    String query, {
    required BusProvider provider,
    int limit = 80,
  }) async {
    final database = await _openDatabase(provider);
    try {
      final normalized = query.trim();
      List<Map<String, Object?>> rows;
      try {
        rows = await database.rawQuery(
          '''
          SELECT
            routes.routeid AS route_id,
            routes.name AS route_name,
            routes.name_en AS route_name_en,
            routes.path_name AS path_name,
            COALESCE(
              (
                SELECT p.pathid
                FROM paths p
                WHERE p.routeid = routes.routeid
                ORDER BY p.pathid ASC
                LIMIT 1
              ),
              0
            ) AS path_id,
            routes.path_name_en AS path_name_en
          FROM routes
          WHERE routes.name LIKE ?
            OR routes.routeid LIKE ?
            OR routes.path_name LIKE ?
            OR EXISTS (
              SELECT 1
              FROM paths p
              WHERE p.routeid = routes.routeid
                AND p.name LIKE ?
            )
          ORDER BY routes.routeid ASC
          LIMIT ?
          ''',
          [
            '%$normalized%',
            '%$normalized%',
            '%$normalized%',
            '%$normalized%',
            limit,
          ],
        );
      } on DatabaseException catch (error) {
        // Backward compatibility for old city DB files without routes.path_name.
        final message = error.toString().toLowerCase();
        if (!message.contains('no such column') ||
            !message.contains('path_name')) {
          rethrow;
        }
        rows = await database.rawQuery(
          '''
          SELECT
            routes.routeid AS route_id,
            routes.name AS route_name,
            routes.name_en AS route_name_en,
            COALESCE(
              (
                SELECT p.pathid
                FROM paths p
                WHERE p.routeid = routes.routeid
                ORDER BY p.pathid ASC
                LIMIT 1
              ),
              0
            ) AS path_id,
            COALESCE(
              (
                SELECT p.name
                FROM paths p
                WHERE p.routeid = routes.routeid
                ORDER BY p.pathid ASC
                LIMIT 1
              ),
              ''
            ) AS path_name
          FROM routes
          WHERE routes.name LIKE ?
            OR routes.routeid LIKE ?
            OR EXISTS (
              SELECT 1
              FROM paths p
              WHERE p.routeid = routes.routeid
                AND p.name LIKE ?
            )
          ORDER BY routes.routeid ASC
          LIMIT ?
          ''',
          ['%$normalized%', '%$normalized%', '%$normalized%', limit],
        );
      }

      return rows
          .map(
            (row) => _routeSummaryFromPathRow(
              provider: provider,
              routeId: row['route_id']?.toString() ?? '',
              routeName: row['route_name']?.toString() ?? '',
              routeNameEn: row['route_name_en']?.toString() ?? '',
              pathId: (row['path_id'] as num?)?.toInt() ?? 0,
              pathName: row['path_name']?.toString() ?? '',
            ),
          )
          .where((summary) => summary.routeId.isNotEmpty)
          .toList();
    } finally {
      await database.close();
    }
  }

  Future<List<RouteSummary>> searchRoutesFromApi(
    String query, {
    required BusProvider provider,
    int limit = 80,
  }) async {
    final city = _providerDatabaseName(provider);
    final uri = Uri.parse(
      '$_apiBaseUrl/api/v1/cities/${Uri.encodeComponent(city)}/routes'
      '?query=${Uri.encodeQueryComponent(query)}&limit=$limit',
    );
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json', 'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException(
        '無法查詢 ${provider.label} 路線 (${response.statusCode})。',
      );
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    final summaries = decoded
        .whereType<Map>()
        .map((row) {
          return _routeSummaryFromPathRow(
            provider: provider,
            routeId: row['routeid']?.toString() ?? '',
            routeName: row['route_name']?.toString() ?? '',
            routeNameEn: row['route_name_en']?.toString() ?? '',
            pathId: _nullableInt(row['pathid']) ?? 0,
            pathName: row['path_name']?.toString() ?? '',
          );
        })
        .where((summary) => summary.routeId.isNotEmpty)
        .toList();
    return _dedupeRouteSummaries(summaries);
  }

  Future<RouteSummary?> getRoute(
    int routeKey, {
    required BusProvider provider,
    String? routeIdHint,
    int? preferredPathId,
  }) async {
    final routeId =
        routeIdHint ?? await _resolveRouteIdByRouteKey(provider, routeKey);
    if (routeId == null || routeId.isEmpty) {
      return null;
    }

    final database = await _openDatabase(provider);
    try {
      final routeRows = await database.query(
        'routes',
        where: 'routeid = ?',
        whereArgs: [routeId],
        limit: 1,
      );
      if (routeRows.isEmpty) {
        return null;
      }

      final routeRow = routeRows.first;
      final pathRows = await database.query(
        'paths',
        where: 'routeid = ?',
        whereArgs: [routeId],
        orderBy: 'pathid ASC',
      );
      final pickedPath = preferredPathId == null
          ? pathRows.firstOrNull
          : pathRows.firstWhere(
              (row) => (row['pathid'] as num?)?.toInt() == preferredPathId,
              orElse: () => pathRows.firstOrNull ?? const <String, Object?>{},
            );
      final pathId = (pickedPath?['pathid'] as num?)?.toInt() ?? 0;
      final pathName = pickedPath?['name']?.toString() ?? '';

      return _routeSummaryFromPathRow(
        provider: provider,
        routeId: routeRow['routeid']?.toString() ?? '',
        routeName: routeRow['name']?.toString() ?? '',
        routeNameEn: routeRow['name_en']?.toString() ?? '',
        pathId: pathId,
        pathName: pathName,
      );
    } finally {
      await database.close();
    }
  }

  Future<List<PathInfo>> getPaths(
    int routeKey, {
    required BusProvider provider,
    String? routeIdHint,
  }) async {
    final routeId =
        routeIdHint ?? await _resolveRouteIdByRouteKey(provider, routeKey);
    if (routeId == null || routeId.isEmpty) {
      return const [];
    }

    final database = await _openDatabase(provider);
    try {
      final rows = await database.query(
        'paths',
        where: 'routeid = ?',
        whereArgs: [routeId],
        orderBy: 'pathid ASC',
      );
      return rows
          .map(
            (row) => PathInfo(
              routeKey: routeKey,
              pathId: (row['pathid'] as num?)?.toInt() ?? 0,
              name: row['name']?.toString() ?? '',
            ),
          )
          .toList();
    } finally {
      await database.close();
    }
  }

  Future<List<StopInfo>> getStopsByRoute(
    int routeKey, {
    required BusProvider provider,
    String? routeIdHint,
  }) async {
    final routeId =
        routeIdHint ?? await _resolveRouteIdByRouteKey(provider, routeKey);
    if (routeId == null || routeId.isEmpty) {
      return const [];
    }

    final database = await _openDatabase(provider);
    try {
      final rows = await database.query(
        'stops',
        where: 'routeid = ?',
        whereArgs: [routeId],
        orderBy: 'pathid ASC, seq ASC',
      );
      return rows
          .map(
            (row) => StopInfo(
              routeKey: routeKey,
              pathId: (row['pathid'] as num?)?.toInt() ?? 0,
              stopId: _parseStopId(row['stopid']),
              stopName: row['name']?.toString() ?? '',
              sequence: (row['seq'] as num?)?.toInt() ?? 0,
              lon: (row['lon'] as num?)?.toDouble() ?? 0,
              lat: (row['lat'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList();
    } finally {
      await database.close();
    }
  }

  Future<RouteDetailData> getCompleteBusInfo(
    int routeKey, {
    required BusProvider provider,
    String? routeIdHint,
    String? routeNameHint,
  }) async {
    final routeId =
        routeIdHint ?? await _resolveRouteIdByRouteKey(provider, routeKey);
    if (routeId == null || routeId.isEmpty) {
      throw StateError('找不到路線 $routeKey');
    }

    try {
      final database = await _openDatabase(provider);
      try {
        return await _buildRouteDetailFromLocalDatabase(
          database: database,
          provider: provider,
          routeId: routeId,
          routeNameHint: routeNameHint,
        );
      } finally {
        await database.close();
      }
    } on DatabaseNotReadyException {
      return _buildRouteDetailFromApi(
        provider: provider,
        routeId: routeId,
        routeNameHint: routeNameHint,
      );
    }
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
          stops.routeid,
          stops.pathid,
          stops.stopid,
          stops.name AS stop_name,
          stops.seq,
          stops.lon,
          stops.lat,
          routes.name AS route_name,
          routes.name_en AS route_name_en,
          paths.name AS path_name
        FROM stops
        JOIN routes ON routes.routeid = stops.routeid
        JOIN paths ON paths.routeid = stops.routeid AND paths.pathid = stops.pathid
        WHERE ABS(stops.lat - ?) <= ?
          AND ABS(stops.lon - ?) <= ?
        LIMIT 500
        ''',
        [latitude, latDelta, longitude, lonDelta],
      );

      final results = <NearbyStopResult>[];
      final seen = <String>{};

      for (final row in rows) {
        final routeId = row['routeid']?.toString() ?? '';
        final pathId = (row['pathid'] as num?)?.toInt() ?? 0;
        final stopId = _parseStopId(row['stopid']);
        final stop = StopInfo(
          routeKey: _routeKeyForRouteId(routeId),
          pathId: pathId,
          stopId: stopId,
          stopName: row['stop_name']?.toString() ?? '',
          sequence: (row['seq'] as num?)?.toInt() ?? 0,
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

        final dedupeKey = '$routeId:$pathId:${stop.stopId}';
        if (!seen.add(dedupeKey)) {
          continue;
        }

        final route = _routeSummaryFromPathRow(
          provider: provider,
          routeId: routeId,
          routeName: row['route_name']?.toString() ?? '',
          routeNameEn: row['route_name_en']?.toString() ?? '',
          pathId: pathId,
          pathName: row['path_name']?.toString() ?? '',
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
      routeIdHint: reference.routeId,
      preferredPathId: reference.pathId,
    );
    if (route == null) {
      return null;
    }

    final stops = await getStopsByRoute(
      reference.routeKey,
      provider: reference.provider,
      routeIdHint: reference.routeId ?? route.routeId,
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

  Future<RouteDetailData> _buildRouteDetailFromLocalDatabase({
    required Database database,
    required BusProvider provider,
    required String routeId,
    String? routeNameHint,
  }) async {
    final routeRows = await database.query(
      'routes',
      where: 'routeid = ?',
      whereArgs: [routeId],
      limit: 1,
    );
    if (routeRows.isEmpty) {
      throw StateError('找不到路線 $routeId');
    }
    final routeRow = routeRows.first;

    final pathRows = await database.query(
      'paths',
      where: 'routeid = ?',
      whereArgs: [routeId],
      orderBy: 'pathid ASC',
    );

    final stopRows = await database.query(
      'stops',
      where: 'routeid = ?',
      whereArgs: [routeId],
      orderBy: 'pathid ASC, seq ASC',
    );

    var hasLiveData = true;
    Map<String, _LiveStopPayload> liveMap;
    try {
      liveMap = await _getLiveStopMap(routeId);
    } catch (_) {
      hasLiveData = false;
      liveMap = const <String, _LiveStopPayload>{};
    }

    final routeKey = _routeKeyForRouteId(routeId);
    final paths = pathRows
        .map(
          (row) => PathInfo(
            routeKey: routeKey,
            pathId: (row['pathid'] as num?)?.toInt() ?? 0,
            name: row['name']?.toString() ?? '',
          ),
        )
        .toList();

    final stopsByPath = <int, List<StopInfo>>{
      for (final path in paths) path.pathId: <StopInfo>[],
    };

    for (final row in stopRows) {
      final pathId = (row['pathid'] as num?)?.toInt() ?? 0;
      final stopId = _parseStopId(row['stopid']);
      final livePayload = liveMap[_stopCompositeKey(pathId, stopId)];
      final stop = StopInfo(
        routeKey: routeKey,
        pathId: pathId,
        stopId: stopId,
        stopName: row['name']?.toString() ?? '',
        sequence: (row['seq'] as num?)?.toInt() ?? 0,
        lon: (row['lon'] as num?)?.toDouble() ?? 0,
        lat: (row['lat'] as num?)?.toDouble() ?? 0,
        sec: livePayload?.sec,
        msg: livePayload?.msg,
        t: livePayload?.t,
        buses: livePayload?.buses ?? const [],
      );
      stopsByPath.putIfAbsent(pathId, () => <StopInfo>[]).add(stop);
    }

    final firstPath = pathRows.firstOrNull;
    final route = _routeSummaryFromPathRow(
      provider: provider,
      routeId: routeId,
      routeName: routeNameHint?.trim().isNotEmpty == true
          ? routeNameHint!.trim()
          : routeRow['name']?.toString() ?? routeId,
      routeNameEn: routeRow['name_en']?.toString() ?? '',
      pathId: (firstPath?['pathid'] as num?)?.toInt() ?? 0,
      pathName: firstPath?['name']?.toString() ?? '',
    );

    return RouteDetailData(
      route: route,
      paths: paths,
      stopsByPath: stopsByPath,
      hasLiveData: hasLiveData,
    );
  }

  Future<RouteDetailData> _buildRouteDetailFromApi({
    required BusProvider provider,
    required String routeId,
    String? routeNameHint,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$_apiBaseUrl/api/v1/routes/${Uri.encodeComponent(routeId)}/stops',
      ),
      headers: const {'Accept': 'application/json', 'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException('無法取得 $routeId 的路線站牌 (${response.statusCode})。');
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final routeKey = _routeKeyForRouteId(routeId);

    final rawPaths = decoded['paths'] as List<dynamic>? ?? const [];
    final paths = <PathInfo>[];
    final stopsByPath = <int, List<StopInfo>>{};

    for (final rawPath in rawPaths) {
      if (rawPath is! Map) {
        continue;
      }
      final pathId = _toInt(rawPath['pathid']);
      final pathName = rawPath['name']?.toString() ?? '';
      paths.add(PathInfo(routeKey: routeKey, pathId: pathId, name: pathName));
      final stops = (rawPath['stops'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (stop) => StopInfo(
              routeKey: routeKey,
              pathId: pathId,
              stopId: _parseStopId(stop['stopid']),
              stopName: stop['name']?.toString() ?? '',
              sequence: _toInt(stop['seq']),
              lon: _toDouble(stop['lon']),
              lat: _toDouble(stop['lat']),
            ),
          )
          .toList();
      stopsByPath[pathId] = stops;
    }

    var hasLiveData = true;
    Map<String, _LiveStopPayload> liveMap;
    try {
      liveMap = await _getLiveStopMap(routeId);
    } catch (_) {
      hasLiveData = false;
      liveMap = const <String, _LiveStopPayload>{};
    }

    if (hasLiveData) {
      for (final entry in stopsByPath.entries) {
        entry.value.replaceRange(
          0,
          entry.value.length,
          entry.value.map((stop) {
            final payload =
                liveMap[_stopCompositeKey(stop.pathId, stop.stopId)];
            return stop.copyWith(
              sec: payload?.sec,
              msg: payload?.msg,
              t: payload?.t,
              buses: payload?.buses ?? const [],
            );
          }),
        );
      }
    }

    final firstPath = paths.firstOrNull;
    final route = _routeSummaryFromPathRow(
      provider: provider,
      routeId: routeId,
      routeName: routeNameHint?.trim().isNotEmpty == true
          ? routeNameHint!.trim()
          : decoded['name']?.toString() ?? routeId,
      routeNameEn: '',
      pathId: firstPath?.pathId ?? 0,
      pathName: firstPath?.name ?? '',
    );

    return RouteDetailData(
      route: route,
      paths: paths,
      stopsByPath: stopsByPath,
      hasLiveData: hasLiveData,
    );
  }

  RouteSummary _routeSummaryFromPathRow({
    required BusProvider provider,
    required String routeId,
    required String routeName,
    required String routeNameEn,
    required int pathId,
    required String pathName,
  }) {
    final displayRouteName = routeName.trim().isEmpty
        ? routeId
        : routeName.trim();
    final displayPathName = pathName.trim();

    return RouteSummary(
      sourceProvider: provider.name,
      hashMd5: '',
      routeKey: _routeKeyForRouteId(routeId),
      routeId: routeId,
      routeName: displayRouteName,
      officialRouteName: routeNameEn,
      description: displayPathName,
      category: provider.label,
      sequence: pathId,
      rtrip: pathId,
    );
  }

  List<RouteSummary> _dedupeRouteSummaries(List<RouteSummary> items) {
    final deduped = <String, RouteSummary>{};
    for (final item in items) {
      deduped.putIfAbsent(item.routeId, () => item);
    }
    return deduped.values.toList();
  }

  Future<int> _fetchRemoteDatabaseVersion(BusProvider provider) async {
    final name = _providerDatabaseName(provider);
    final response = await _client.get(
      Uri.parse(
        '$_apiBaseUrl/api/v1/database/${Uri.encodeComponent(name)}/version',
      ),
      headers: const {'Accept': 'application/json', 'User-Agent': _userAgent},
    );

    if (response.statusCode != 200) {
      throw HttpException(
        '無法檢查 ${provider.label} 遠端資料庫版本 (${response.statusCode})。',
      );
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final version = decoded['version'];
    if (version is num) {
      return version.toInt();
    }
    final parsed = int.tryParse(version?.toString() ?? '');
    if (parsed == null) {
      throw const FormatException('資料庫版本格式錯誤。');
    }
    return parsed;
  }

  Future<void> _downloadCityDatabase(
    BusProvider provider,
    File targetFile,
  ) async {
    final cityName = _providerDatabaseName(provider);
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/downloads/${Uri.encodeComponent(cityName)}.db'),
      headers: const {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException(
        '無法下載 ${provider.label} 資料庫 (${response.statusCode})。',
      );
    }

    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(response.bodyBytes, flush: true);
  }

  Future<Map<String, _LiveStopPayload>> _getLiveStopMap(String routeId) async {
    final response = await _client.get(
      Uri.parse(
        '$_apiBaseUrl/api/v1/routes/${Uri.encodeComponent(routeId)}/realtime',
      ),
      headers: const {'Accept': 'application/json', 'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException('即時資料暫時無法取得：$routeId (${response.statusCode})。');
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

  Future<String?> _resolveRouteIdByRouteKey(
    BusProvider provider,
    int routeKey,
  ) async {
    final database = await _openDatabase(provider);
    try {
      final rows = await database.query('routes', columns: ['routeid']);
      for (final row in rows) {
        final routeId = row['routeid']?.toString() ?? '';
        if (routeId.isNotEmpty && _routeKeyForRouteId(routeId) == routeKey) {
          return routeId;
        }
      }
      return null;
    } finally {
      await database.close();
    }
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

  T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
    for (final item in items) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }

  String _providerDatabaseName(BusProvider provider) {
    return switch (provider) {
      BusProvider.kee => 'Keelung',
      BusProvider.tpe => 'Taipei',
      BusProvider.nwt => 'NewTaipei',
      BusProvider.tao => 'Taoyuan',
      BusProvider.hsz => 'Hsinchu',
      BusProvider.hsq => 'HsinchuCounty',
      BusProvider.mia => 'MiaoliCounty',
      BusProvider.txg => 'Taichung',
      BusProvider.cha => 'ChanghuaCounty',
      BusProvider.nan => 'NantouCounty',
      BusProvider.yun => 'YunlinCounty',
      BusProvider.cyi => 'Chiayi',
      BusProvider.cyq => 'ChiayiCounty',
      BusProvider.tnn => 'Tainan',
      BusProvider.khh => 'Kaohsiung',
      BusProvider.pif => 'PingtungCounty',
      BusProvider.ila => 'YilanCounty',
      BusProvider.hua => 'HualienCounty',
      BusProvider.ttt => 'TaitungCounty',
      BusProvider.pen => 'PenghuCounty',
      BusProvider.kin => 'KinmenCounty',
      BusProvider.lie => 'LienchiangCounty',
    };
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
