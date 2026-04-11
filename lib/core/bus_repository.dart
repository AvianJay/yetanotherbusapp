import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'native_sqlite_bridge.dart';

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
  static const _databaseDirectoryName = '.yabus_backend';
  static const _legacyDatabaseDirectoryNames = <String>['.taiwanbus'];
  static const _routeMetadataDatabaseFileName = 'routes_metadata_v1.sqlite';
  static const _webLocalDatabaseUnsupportedMessage =
      'Web 版目前不支援本 app 使用的本機 SQLite 資料庫。';

  final http.Client _client;
  static const _routeDetailCacheTtl = Duration(seconds: 2);
  static const _searchApiCacheTtl = Duration(seconds: 2);
  static const _realtimeCacheTtl = Duration(seconds: 2);
  final Map<String, _TimedValue<RouteDetailData>> _routeDetailCache =
      <String, _TimedValue<RouteDetailData>>{};
  final Map<String, Future<RouteDetailData>> _routeDetailInFlight =
      <String, Future<RouteDetailData>>{};
  final Map<String, _TimedValue<List<RouteSummary>>> _searchRoutesApiCache =
      <String, _TimedValue<List<RouteSummary>>>{};
  final Map<String, Future<List<RouteSummary>>> _searchRoutesApiInFlight =
      <String, Future<List<RouteSummary>>>{};
  final Map<String, _TimedValue<Map<String, _LiveStopPayload>>> _realtimeCache =
      <String, _TimedValue<Map<String, _LiveStopPayload>>>{};
  final Map<String, Future<Map<String, _LiveStopPayload>>> _realtimeInFlight =
      <String, Future<Map<String, _LiveStopPayload>>>{};

  Future<bool> databaseExists(BusProvider provider) async {
    if (!_supportsLocalDatabase) {
      return false;
    }
    final metadataFile = await _routeMetadataDatabaseFile();
    final cityFile = await _cityDatabaseFile(provider);
    if (!await metadataFile.exists() || !await cityFile.exists()) {
      return false;
    }
    if (!await _looksLikeSqliteFile(metadataFile)) {
      await _deleteDatabaseArtifacts(metadataFile);
      return false;
    }
    if (!await _looksLikeSqliteFile(cityFile)) {
      await _markDatabaseInvalid(provider, cityFile);
      return false;
    }

    if (Platform.isIOS) {
      try {
        await _validateMetadataDatabaseFileWithSqlite3(metadataFile);
      } catch (_) {
        await _deleteDatabaseArtifacts(metadataFile);
        return false;
      }

      try {
        await _validateCityDatabaseFileWithSqlite3(cityFile);
        return true;
      } catch (_) {
        await _markDatabaseInvalid(provider, cityFile);
        return false;
      }
    }

    try {
      final metadataDatabase = await openDatabase(
        metadataFile.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        await _validateMetadataDatabaseSchema(metadataDatabase);
      } finally {
        await metadataDatabase.close();
      }
    } catch (_) {
      await _deleteDatabaseArtifacts(metadataFile);
      return false;
    }

    try {
      final cityDatabase = await openDatabase(
        cityFile.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        await _validateCityDatabaseSchema(cityDatabase);
      } finally {
        await cityDatabase.close();
      }
      return true;
    } catch (_) {
      await _markDatabaseInvalid(provider, cityFile);
      return false;
    }
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
    final file = await _cityDatabaseFile(provider);
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
    final metadataFile = await _routeMetadataDatabaseFile();
    final cityFile = await _cityDatabaseFile(provider);
    final tempMetadataFile = File('${metadataFile.path}.download');
    final tempCityFile = File('${cityFile.path}.download');

    await metadataFile.parent.create(recursive: true);
    try {
      await _deleteDatabaseArtifacts(tempMetadataFile);
      await _deleteDatabaseArtifacts(tempCityFile);
      await _downloadRouteMetadataDatabase(tempMetadataFile);
      await _ensureDownloadedMetadataDatabaseUsable(tempMetadataFile);
      await _downloadCityDatabase(provider, tempCityFile);
      await _ensureDownloadedCityDatabaseUsable(provider, tempCityFile);
      await _deleteDatabaseArtifacts(metadataFile);
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      await tempMetadataFile.rename(metadataFile.path);
      await _deleteDatabaseArtifacts(cityFile);
      if (await cityFile.exists()) {
        await cityFile.delete();
      }
      await tempCityFile.rename(cityFile.path);
    } finally {
      await _deleteDatabaseArtifacts(tempMetadataFile);
      await _deleteDatabaseArtifacts(tempCityFile);
    }

    final versions = await _readVersionMap();
    versions[provider.name] = remoteVersion;
    await _writeVersionMap(versions);
  }

  Future<List<_MetadataPathRow>> _loadMetadataPathRows({
    required BusProvider provider,
    String? routeId,
    Set<String>? routeIds,
    String? searchQuery,
    int? limit,
  }) async {
    if (Platform.isIOS) {
      final file = await _routeMetadataDatabaseFile();
      if (!await file.exists()) {
        throw DatabaseNotReadyException('尚未下載路線資料庫。');
      }
      if (!await _looksLikeSqliteFile(file)) {
        await _deleteDatabaseArtifacts(file);
        throw DatabaseNotReadyException('路線資料庫已損壞，請重新下載。');
      }

      try {
        return _withSqlite3Database(
          file,
          (database) {
            _validateMetadataDatabaseSchemaSqlite(database);
            return _queryMetadataPathRowsSqlite(
              database,
              provider: provider,
              routeId: routeId,
              routeIds: routeIds,
              searchQuery: searchQuery,
              limit: limit,
            );
          },
        );
      } catch (_) {
        throw DatabaseNotReadyException('路線資料庫無法開啟，請重新下載。');
      }
    }

    final database = await _openMetadataDatabase();
    try {
      return _queryMetadataPathRows(
        database,
        provider: provider,
        routeId: routeId,
        routeIds: routeIds,
        searchQuery: searchQuery,
        limit: limit,
      );
    } finally {
      await database.close();
    }
  }

  Future<List<_CityStopRow>> _loadCityStopRows({
    required BusProvider provider,
    String? routeId,
    double? latitude,
    double? longitude,
    double? latDelta,
    double? lonDelta,
    int? limit,
  }) async {
    if (Platform.isIOS) {
      final file = await _cityDatabaseFile(provider);
      if (!await file.exists()) {
        throw DatabaseNotReadyException('尚未下載 ${provider.label} 資料庫。');
      }
      if (!await _looksLikeSqliteFile(file)) {
        await _markDatabaseInvalid(provider, file);
        throw DatabaseNotReadyException('${provider.label} 資料庫已損壞，請重新下載。');
      }

      try {
        return _withSqlite3Database(
          file,
          (database) {
            _validateCityDatabaseSchemaSqlite(database);
            return _queryCityStopRowsSqlite(
              database,
              routeId: routeId,
              latitude: latitude,
              longitude: longitude,
              latDelta: latDelta,
              lonDelta: lonDelta,
              limit: limit,
            );
          },
        );
      } catch (_) {
        throw DatabaseNotReadyException('${provider.label} 資料庫無法開啟，請重新下載。');
      }
    }

    final database = await _openCityDatabase(provider);
    try {
      return await _queryCityStopRows(
        database,
        routeId: routeId,
        latitude: latitude,
        longitude: longitude,
        latDelta: latDelta,
        lonDelta: lonDelta,
        limit: limit,
      );
    } finally {
      await database.close();
    }
  }

  Future<List<RouteSummary>> searchRoutes(
    String query, {
    required BusProvider provider,
    int limit = 80,
  }) async {
    final rows = await _loadMetadataPathRows(
      provider: provider,
      searchQuery: query,
      limit: limit,
    );

    final summaries = rows
        .map(
          (row) => _routeSummaryFromPathRow(
            provider: provider,
            routeId: row.routeId,
            routeName: row.routeName,
            routeNameEn: row.routeNameEn,
            pathId: row.pathId,
            pathName: row.pathName,
          ),
        )
        .where((summary) => summary.routeId.isNotEmpty)
        .toList();
    return _collapseRouteSummariesByRouteId(summaries);
  }

  Future<List<RouteSummary>> searchRoutesFromApi(
    String query, {
    required BusProvider provider,
    int limit = 80,
  }) async {
    final normalizedQuery = query.trim();
    final cacheKey = '${provider.name}:${normalizedQuery.toLowerCase()}:$limit';
    final cached = _readFreshCache(
      _searchRoutesApiCache,
      cacheKey,
      _searchApiCacheTtl,
    );
    if (cached != null) {
      return cached;
    }

    final inFlight = _searchRoutesApiInFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadSearchRoutesFromApi(
      normalizedQuery,
      provider: provider,
      limit: limit,
    );
    _searchRoutesApiInFlight[cacheKey] = future;
    try {
      final summaries = await future;
      _searchRoutesApiCache[cacheKey] = _TimedValue<List<RouteSummary>>(
        summaries,
      );
      return summaries;
    } finally {
      if (identical(_searchRoutesApiInFlight[cacheKey], future)) {
        _searchRoutesApiInFlight.remove(cacheKey);
      }
    }
  }

  Future<List<RouteSummary>> _loadSearchRoutesFromApi(
    String query, {
    required BusProvider provider,
    required int limit,
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
    return _collapseRouteSummariesByRouteId(summaries);
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

    final routeRows = await _loadMetadataPathRows(
      provider: provider,
      routeId: routeId,
    );
    if (routeRows.isEmpty) {
      return null;
    }

    final pickedPath = preferredPathId == null
        ? routeRows.firstOrNull
        : routeRows.firstWhere(
            (row) => row.pathId == preferredPathId,
            orElse: () =>
                routeRows.firstOrNull ??
                const _MetadataPathRow(
                  routeId: '',
                  routeName: '',
                  routeNameEn: '',
                  pathId: 0,
                  pathName: '',
                  pathNameEn: '',
                ),
          );
    final routeRow = pickedPath ?? routeRows.first;

    return _routeSummaryFromPathRow(
      provider: provider,
      routeId: routeRow.routeId,
      routeName: routeRow.routeName,
      routeNameEn: routeRow.routeNameEn,
      pathId: routeRow.pathId,
      pathName: routeRow.pathName,
    );
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

    final rows = await _loadMetadataPathRows(
      provider: provider,
      routeId: routeId,
    );
    return rows
        .map(
          (row) => PathInfo(
            routeKey: routeKey,
            pathId: row.pathId,
            name: row.pathName,
          ),
        )
        .toList();
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

    final rows = await _loadCityStopRows(provider: provider, routeId: routeId);
    return rows
        .map(
          (row) => StopInfo(
            routeKey: routeKey,
            pathId: row.pathId,
            stopId: _parseStopId(row.stopId),
            stopName: row.stopName,
            sequence: row.sequence,
            lon: row.lon,
            lat: row.lat,
          ),
        )
        .toList();
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

    final cacheKey = '${provider.name}:$routeId';
    final cached = _readFreshCache(
      _routeDetailCache,
      cacheKey,
      _routeDetailCacheTtl,
    );
    if (cached != null) {
      return _applyRouteNameHint(cached, routeNameHint);
    }

    final inFlight = _routeDetailInFlight[cacheKey];
    if (inFlight != null) {
      final detail = await inFlight;
      return _applyRouteNameHint(detail, routeNameHint);
    }

    final future = _loadCompleteBusInfo(
      provider: provider,
      routeId: routeId,
      routeNameHint: routeNameHint,
    );
    _routeDetailInFlight[cacheKey] = future;
    try {
      final detail = await future;
      _routeDetailCache[cacheKey] = _TimedValue<RouteDetailData>(detail);
      return detail;
    } finally {
      if (identical(_routeDetailInFlight[cacheKey], future)) {
        _routeDetailInFlight.remove(cacheKey);
      }
    }
  }

  Future<RouteDetailData> _loadCompleteBusInfo({
    required BusProvider provider,
    required String routeId,
    String? routeNameHint,
  }) async {
    try {
      final routeRows = await _loadMetadataPathRows(
        provider: provider,
        routeId: routeId,
      );
      final stopRows = await _loadCityStopRows(
        provider: provider,
        routeId: routeId,
      );

      var hasLiveData = true;
      Map<String, _LiveStopPayload> liveMap;
      try {
        liveMap = await _getLiveStopMap(routeId);
      } catch (_) {
        hasLiveData = false;
        liveMap = const <String, _LiveStopPayload>{};
      }

      return _buildRouteDetailFromLocalRows(
        provider: provider,
        routeId: routeId,
        routeRows: routeRows,
        stopRows: stopRows,
        routeNameHint: routeNameHint,
        hasLiveData: hasLiveData,
        liveMap: liveMap,
      );
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
    final rows = await _loadCityStopRows(
      provider: provider,
      latitude: latitude,
      longitude: longitude,
      latDelta: latDelta,
      lonDelta: lonDelta,
      limit: 500,
    );

    final results = <NearbyStopResult>[];
    final seen = <String>{};
    final routeMetadata = await _loadRouteMetadataMapFromLocalStore(
      provider: provider,
      routeIds: rows.map((row) => row.routeId).where((id) => id.isNotEmpty).toSet(),
    );

    for (final row in rows) {
      final routeId = row.routeId;
      final pathId = row.pathId;
      final stopId = _parseStopId(row.stopId);
      final stop = StopInfo(
        routeKey: _routeKeyForRouteId(routeId),
        pathId: pathId,
        stopId: stopId,
        stopName: row.stopName,
        sequence: row.sequence,
        lon: row.lon,
        lat: row.lat,
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

      final routeMetadataEntry = routeMetadata['$routeId:$pathId'];
      if (routeMetadataEntry == null) {
        continue;
      }
      final route = _routeSummaryFromPathRow(
        provider: provider,
        routeId: routeId,
        routeName: routeMetadataEntry.routeName,
        routeNameEn: routeMetadataEntry.routeNameEn,
        pathId: pathId,
        pathName: routeMetadataEntry.pathName,
      );

      results.add(
        NearbyStopResult(route: route, stop: stop, distanceMeters: distance),
      );
    }

    results.sort(
      (left, right) => left.distanceMeters.compareTo(right.distanceMeters),
    );
    return results.take(limit).toList();
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

  RouteDetailData _buildRouteDetailFromLocalRows({
    required BusProvider provider,
    required String routeId,
    required List<_MetadataPathRow> routeRows,
    required List<_CityStopRow> stopRows,
    required bool hasLiveData,
    required Map<String, _LiveStopPayload> liveMap,
    String? routeNameHint,
  }) {
    if (routeRows.isEmpty) {
      throw StateError('?曆??啗楝蝺?$routeId');
    }
    final routeRow = routeRows.first;
    final routeKey = _routeKeyForRouteId(routeId);
    final paths = routeRows
        .map(
          (row) => PathInfo(
            routeKey: routeKey,
            pathId: row.pathId,
            name: row.pathName,
          ),
        )
        .toList();

    final stopsByPath = <int, List<StopInfo>>{
      for (final path in paths) path.pathId: <StopInfo>[],
    };

    for (final row in stopRows) {
      final livePayload = liveMap[_stopCompositeKey(row.pathId, _parseStopId(row.stopId))];
      final stop = StopInfo(
        routeKey: routeKey,
        pathId: row.pathId,
        stopId: _parseStopId(row.stopId),
        stopName: row.stopName,
        sequence: row.sequence,
        lon: row.lon,
        lat: row.lat,
        sec: livePayload?.sec,
        msg: livePayload?.msg,
        t: livePayload?.t,
        buses: livePayload?.buses ?? const [],
      );
      stopsByPath.putIfAbsent(row.pathId, () => <StopInfo>[]).add(stop);
    }

    final firstPath = routeRows.firstOrNull;
    final route = _routeSummaryFromPathRow(
      provider: provider,
      routeId: routeId,
      routeName: routeNameHint?.trim().isNotEmpty == true
          ? routeNameHint!.trim()
          : routeRow.routeName,
      routeNameEn: routeRow.routeNameEn,
      pathId: firstPath?.pathId ?? 0,
      pathName: firstPath?.pathName ?? '',
    );

    return RouteDetailData(
      route: route,
      paths: paths,
      stopsByPath: stopsByPath,
      hasLiveData: hasLiveData,
    );
  }

  Future<Map<String, _RouteMetadataRow>> _loadRouteMetadataMapFromLocalStore({
    required BusProvider provider,
    required Set<String> routeIds,
  }) async {
    final rows = await _loadMetadataPathRows(
      provider: provider,
      routeIds: routeIds,
    );
    final metadata = <String, _RouteMetadataRow>{};
    for (final row in rows) {
      metadata['${row.routeId}:${row.pathId}'] = _RouteMetadataRow(
        routeName: row.routeName,
        routeNameEn: row.routeNameEn,
        pathName: row.pathName,
      );
    }
    return metadata;
  }

  // ignore: unused_element
  Future<RouteDetailData> _buildRouteDetailFromLocalDatabase({
    required Database metadataDatabase,
    required Database cityDatabase,
    required BusProvider provider,
    required String routeId,
    String? routeNameHint,
  }) async {
    final routeRows = await _queryMetadataPathRows(
      metadataDatabase,
      provider: provider,
      routeId: routeId,
    );
    if (routeRows.isEmpty) {
      throw StateError('找不到路線 $routeId');
    }
    final routeRow = routeRows.first;

    final stopRows = await cityDatabase.query(
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
    final paths = routeRows
        .map(
          (row) => PathInfo(
            routeKey: routeKey,
            pathId: row.pathId,
            name: row.pathName,
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

    final firstPath = routeRows.firstOrNull;
    final route = _routeSummaryFromPathRow(
      provider: provider,
      routeId: routeId,
      routeName: routeNameHint?.trim().isNotEmpty == true
          ? routeNameHint!.trim()
          : routeRow.routeName,
      routeNameEn: routeRow.routeNameEn,
      pathId: firstPath?.pathId ?? 0,
      pathName: firstPath?.pathName ?? '',
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

  List<RouteSummary> _collapseRouteSummariesByRouteId(List<RouteSummary> items) {
    final grouped = <String, List<RouteSummary>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.routeId, () => <RouteSummary>[]).add(item);
    }

    return grouped.values.map((group) {
      final first = group.first;
      final descriptions = group
          .map((item) => item.description.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      descriptions.sort();
      final mergedDescription = descriptions.join(' / ');

      return RouteSummary(
        sourceProvider: first.sourceProvider,
        hashMd5: first.hashMd5,
        routeKey: first.routeKey,
        routeId: first.routeId,
        routeName: first.routeName,
        officialRouteName: first.officialRouteName,
        description: mergedDescription,
        category: first.category,
        sequence: first.sequence,
        rtrip: first.rtrip,
      );
    }).toList();
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

  Future<void> _downloadRouteMetadataDatabase(File targetFile) async {
    final response = await _client.get(
      Uri.parse('$_apiBaseUrl/downloads/bus.db'),
      headers: const {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw HttpException('Download failed (/downloads/bus.db, ${response.statusCode})');
    }

    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsBytes(response.bodyBytes, flush: true);
  }

  // ignore: unused_element
  Future<Map<String, _RouteMetadataRow>> _loadRouteMetadataMap(
    Database database, {
    required BusProvider provider,
    required Set<String> routeIds,
  }) async {
    if (routeIds.isEmpty) {
      return const <String, _RouteMetadataRow>{};
    }

    final rows = await _queryMetadataPathRows(
      database,
      provider: provider,
      routeIds: routeIds,
    );

    final metadata = <String, _RouteMetadataRow>{};
    for (final row in rows) {
      if (row.routeId.isEmpty) {
        continue;
      }
      metadata['${row.routeId}:${row.pathId}'] = _RouteMetadataRow(
        routeName: row.routeName,
        routeNameEn: row.routeNameEn,
        pathName: row.pathName,
      );
    }
    return metadata;
  }

  Future<Map<String, _LiveStopPayload>> _getLiveStopMap(String routeId) async {
    final cached = _readFreshCache(
      _realtimeCache,
      routeId,
      _realtimeCacheTtl,
    );
    if (cached != null) {
      return cached;
    }

    final inFlight = _realtimeInFlight[routeId];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadLiveStopMap(routeId);
    _realtimeInFlight[routeId] = future;
    try {
      final result = await future;
      _realtimeCache[routeId] =
          _TimedValue<Map<String, _LiveStopPayload>>(result);
      return result;
    } finally {
      if (identical(_realtimeInFlight[routeId], future)) {
        _realtimeInFlight.remove(routeId);
      }
    }
  }

  Future<Map<String, _LiveStopPayload>> _loadLiveStopMap(String routeId) async {
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

  RouteDetailData _applyRouteNameHint(
    RouteDetailData detail,
    String? routeNameHint,
  ) {
    final normalizedHint = routeNameHint?.trim() ?? '';
    if (normalizedHint.isEmpty || normalizedHint == detail.route.routeName) {
      return detail;
    }

    return RouteDetailData(
      route: RouteSummary(
        sourceProvider: detail.route.sourceProvider,
        hashMd5: detail.route.hashMd5,
        routeKey: detail.route.routeKey,
        routeId: detail.route.routeId,
        routeName: normalizedHint,
        officialRouteName: detail.route.officialRouteName,
        description: detail.route.description,
        category: detail.route.category,
        sequence: detail.route.sequence,
        rtrip: detail.route.rtrip,
      ),
      paths: detail.paths,
      stopsByPath: detail.stopsByPath,
      hasLiveData: detail.hasLiveData,
    );
  }

  T? _readFreshCache<T>(
    Map<String, _TimedValue<T>> cache,
    String key,
    Duration ttl,
  ) {
    final cached = cache[key];
    if (cached == null) {
      return null;
    }
    if (DateTime.now().difference(cached.createdAt) > ttl) {
      cache.remove(key);
      return null;
    }
    return cached.value;
  }

  Future<Database> _openCityDatabase(BusProvider provider) async {
    _ensureLocalDatabaseSupported();
    final file = await _cityDatabaseFile(provider);
    if (!await file.exists()) {
      throw DatabaseNotReadyException('尚未下載 ${provider.label} 資料庫。');
    }

    if (!await _looksLikeSqliteFile(file)) {
      await _markDatabaseInvalid(provider, file);
      throw DatabaseNotReadyException('${provider.label} 資料庫已損壞，請重新下載。');
    }

    try {
      final database = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );
      await _validateCityDatabaseSchema(database);
      return database;
    } catch (_) {
      await _markDatabaseInvalid(provider, file);
      throw DatabaseNotReadyException('${provider.label} 資料庫無法開啟，請重新下載。');
    }
  }

  Future<Database> _openMetadataDatabase() async {
    _ensureLocalDatabaseSupported();
    final file = await _routeMetadataDatabaseFile();
    if (!await file.exists()) {
      throw DatabaseNotReadyException('尚未下載路線資料庫。');
    }

    if (!await _looksLikeSqliteFile(file)) {
      await _deleteDatabaseArtifacts(file);
      throw DatabaseNotReadyException('路線資料庫已損壞，請重新下載。');
    }

    try {
      final database = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );
      await _validateMetadataDatabaseSchema(database);
      return database;
    } catch (_) {
      await _deleteDatabaseArtifacts(file);
      throw DatabaseNotReadyException('路線資料庫無法開啟，請重新下載。');
    }
  }

  Future<File> _cityDatabaseFile(BusProvider provider) async {
    final directory = await _databaseDirectory();
    final file = File(p.join(directory.path, provider.databaseFileName));
    await _migrateLegacyDatabaseFileIfNeeded(file);
    return file;
  }

  Future<File> _routeMetadataDatabaseFile() async {
    final directory = await _databaseDirectory();
    return File(p.join(directory.path, _routeMetadataDatabaseFileName));
  }

  Future<Directory> _databaseDirectory() async {
    final rootPath = await getDatabasesPath();
    final directory = Platform.isIOS
        ? Directory(rootPath)
        : Directory(p.join(rootPath, _databaseDirectoryName));
    await _migrateLegacyDatabaseDirectoryIfNeeded(directory);
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _migrateLegacyDatabaseDirectoryIfNeeded(
    Directory targetDirectory,
  ) async {
    if (await targetDirectory.exists()) {
      return;
    }

    for (final legacyDirectory in await _legacyDatabaseDirectories()) {
      if (!await legacyDirectory.exists()) {
        continue;
      }

      await targetDirectory.create(recursive: true);
      await _copyDirectoryContents(legacyDirectory, targetDirectory);
      return;
    }
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory destination,
  ) async {
    await for (final entity in source.list(recursive: false)) {
      final name = p.basename(entity.path);
      final targetPath = p.join(destination.path, name);
      if (entity is File) {
        final targetFile = File(targetPath);
        if (!await targetFile.exists()) {
          await entity.copy(targetPath);
        }
        continue;
      }

      if (entity is Directory) {
        final targetDirectory = Directory(targetPath);
        await targetDirectory.create(recursive: true);
        await _copyDirectoryContents(entity, targetDirectory);
      }
    }
  }

  Future<List<Directory>> _legacyDatabaseDirectories() async {
    final directories = <Directory>[];

    final documentsRoot = await getApplicationDocumentsDirectory();
    directories.add(Directory(p.join(documentsRoot.path, _databaseDirectoryName)));
    for (final legacyName in _legacyDatabaseDirectoryNames) {
      directories.add(Directory(p.join(documentsRoot.path, legacyName)));
    }

    final supportRoot = await getApplicationSupportDirectory();
    directories.add(Directory(p.join(supportRoot.path, _databaseDirectoryName)));
    for (final legacyName in _legacyDatabaseDirectoryNames) {
      directories.add(Directory(p.join(supportRoot.path, legacyName)));
    }

    final databaseRoot = Directory(await getDatabasesPath());
    directories.add(Directory(p.join(databaseRoot.path, _databaseDirectoryName)));
    for (final legacyName in _legacyDatabaseDirectoryNames) {
      directories.add(Directory(p.join(databaseRoot.path, legacyName)));
    }

    final deduped = <String, Directory>{};
    for (final directory in directories) {
      deduped.putIfAbsent(directory.path, () => directory);
    }
    return deduped.values.toList();
  }

  Future<void> _migrateLegacyDatabaseFileIfNeeded(File targetFile) async {
    if (await targetFile.exists()) {
      return;
    }

    for (final legacyDirectory in await _legacyDatabaseDirectories()) {
      final legacyFile = File(
        p.join(legacyDirectory.path, p.basename(targetFile.path)),
      );
      if (!await legacyFile.exists()) {
        continue;
      }

      await targetFile.parent.create(recursive: true);
      await legacyFile.copy(targetFile.path);

      final targetVersionFile = File(p.join(targetFile.parent.path, 'version.json'));
      if (!await targetVersionFile.exists()) {
        final legacyVersionFile = File(p.join(legacyDirectory.path, 'version.json'));
        if (await legacyVersionFile.exists()) {
          await legacyVersionFile.copy(targetVersionFile.path);
        }
      }
      return;
    }
  }

  Future<bool> _looksLikeSqliteFile(File file) async {
    try {
      final length = await file.length();
      if (length < 16) {
        return false;
      }
      final bytes = await file.openRead(0, 16).first;
      return ascii.decode(bytes, allowInvalid: true) == 'SQLite format 3\u0000';
    } catch (_) {
      return false;
    }
  }

  Future<void> _validateDatabaseSchema(Database database) async {
    final rows = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name IN ('routes', 'paths', 'stops')
      ''',
    );
    final tableNames = rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    if (!tableNames.containsAll(const {'routes', 'paths', 'stops'})) {
      throw const FormatException('Invalid city database schema.');
    }
  }

  Future<void> _markDatabaseInvalid(BusProvider provider, File file) async {
    for (final candidatePath in <String>[
      file.path,
      '${file.path}-wal',
      '${file.path}-shm',
      '${file.path}-journal',
    ]) {
      final candidate = File(candidatePath);
      if (await candidate.exists()) {
        await candidate.delete();
      }
    }

    final versions = await _readVersionMap();
    if (versions[provider.name] != null && versions[provider.name] != 0) {
      versions[provider.name] = 0;
      await _writeVersionMap(versions);
    }
  }

  // ignore: unused_element
  Future<void> _ensureDownloadedDatabaseUsable(
    BusProvider provider,
    File file,
  ) async {
    if (!await _looksLikeSqliteFile(file)) {
      await _markDatabaseInvalid(provider, file);
      throw DatabaseNotReadyException('${provider.label} 資料庫下載失敗，請稍後再試。');
    }

    try {
      final database = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        await _validateDatabaseSchema(database);
      } finally {
        await database.close();
      }
    } catch (_) {
      await _markDatabaseInvalid(provider, file);
      throw DatabaseNotReadyException('${provider.label} 資料庫下載失敗，請稍後再試。');
    }
  }

  Future<void> _validateMetadataDatabaseSchema(Database database) async {
    await _detectMetadataLayout(database);
  }

  Future<void> _validateCityDatabaseSchema(Database database) async {
    final tableNames = await _loadTableNames(database);
    if (!tableNames.contains('stops')) {
      throw const FormatException('Invalid city database schema.');
    }

    final stopColumns = await _loadColumnNames(database, 'stops');
    if (!stopColumns.containsAll(
      const {'routeid', 'pathid', 'seq', 'stopid', 'name', 'lat', 'lon'},
    )) {
      throw const FormatException('Invalid city database schema.');
    }
  }

  Future<_MetadataLayout> _detectMetadataLayout(Database database) async {
    final tableNames = await _loadTableNames(database);
    if (!tableNames.contains('routes')) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    final routeColumns = await _loadColumnNames(database, 'routes');
    if (!routeColumns.containsAll(const {'routeid', 'name'})) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    if (routeColumns.containsAll(const {'pathid', 'path_name'})) {
      return _MetadataLayout.flattenedRoutes;
    }

    if (!tableNames.contains('paths')) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    final pathColumns = await _loadColumnNames(database, 'paths');
    if (!pathColumns.containsAll(const {'routeid', 'pathid', 'name'})) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    return _MetadataLayout.routesAndPaths;
  }

  Future<Set<String>> _loadTableNames(Database database) async {
    final rows = await database.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
      ''',
    );
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> _loadColumnNames(
    Database database,
    String tableName,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($tableName)');
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<List<_MetadataPathRow>> _queryMetadataPathRows(
    Database database, {
    required BusProvider provider,
    String? routeId,
    Set<String>? routeIds,
    String? searchQuery,
    int? limit,
  }) async {
    final layout = await _detectMetadataLayout(database);
    final parameters = <Object?>['${provider.prefix}%'];
    final whereClauses = <String>['routes.routeid LIKE ?'];
    final pathIdColumn = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'routes.pathid',
      _MetadataLayout.routesAndPaths => 'paths.pathid',
    };
    final pathNameColumn = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'routes.path_name',
      _MetadataLayout.routesAndPaths => 'paths.name',
    };
    final pathNameEnColumn = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'routes.path_name_en',
      _MetadataLayout.routesAndPaths => 'paths.name_en',
    };
    final fromClause = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'FROM routes',
      _MetadataLayout.routesAndPaths =>
        'FROM routes JOIN paths ON paths.routeid = routes.routeid',
    };

    if (routeId != null && routeId.isNotEmpty) {
      whereClauses.add('routes.routeid = ?');
      parameters.add(routeId);
    }

    if (routeIds != null && routeIds.isNotEmpty) {
      final placeholders = List.filled(routeIds.length, '?').join(', ');
      whereClauses.add('routes.routeid IN ($placeholders)');
      parameters.addAll(routeIds);
    }

    final normalizedQuery = searchQuery?.trim() ?? '';
    if (normalizedQuery.isNotEmpty) {
      whereClauses.add(
        '(routes.name LIKE ? OR routes.routeid LIKE ? OR $pathNameColumn LIKE ?)',
      );
      parameters.addAll(
        <Object?>[
          '%$normalizedQuery%',
          '%$normalizedQuery%',
          '%$normalizedQuery%',
        ],
      );
    }

    final limitClause = limit == null ? '' : 'LIMIT ?';
    if (limit != null) {
      parameters.add(limit);
    }

    final rows = await database.rawQuery(
      '''
      SELECT
        routes.routeid AS route_id,
        routes.name AS route_name,
        routes.name_en AS route_name_en,
        $pathIdColumn AS path_id,
        $pathNameColumn AS path_name,
        $pathNameEnColumn AS path_name_en
      $fromClause
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY routes.routeid ASC, path_id ASC
      $limitClause
      ''',
      parameters,
    );

    return rows
        .map(
          (row) => _MetadataPathRow(
            routeId: row['route_id']?.toString() ?? '',
            routeName: row['route_name']?.toString() ?? '',
            routeNameEn: row['route_name_en']?.toString() ?? '',
            pathId: (row['path_id'] as num?)?.toInt() ?? 0,
            pathName: row['path_name']?.toString() ?? '',
            pathNameEn: row['path_name_en']?.toString() ?? '',
          ),
        )
        .where((row) => row.routeId.isNotEmpty)
        .toList();
  }

  List<_MetadataPathRow> _queryMetadataPathRowsSqlite(
    NativeSqliteDatabase database, {
    required BusProvider provider,
    String? routeId,
    Set<String>? routeIds,
    String? searchQuery,
    int? limit,
  }) {
    final layout = _detectMetadataLayoutSqlite(database);
    final parameters = <Object?>['${provider.prefix}%'];
    final whereClauses = <String>['routes.routeid LIKE ?'];
    final pathIdColumn = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'routes.pathid',
      _MetadataLayout.routesAndPaths => 'paths.pathid',
    };
    final pathNameColumn = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'routes.path_name',
      _MetadataLayout.routesAndPaths => 'paths.name',
    };
    final pathNameEnColumn = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'routes.path_name_en',
      _MetadataLayout.routesAndPaths => 'paths.name_en',
    };
    final fromClause = switch (layout) {
      _MetadataLayout.flattenedRoutes => 'FROM routes',
      _MetadataLayout.routesAndPaths =>
        'FROM routes JOIN paths ON paths.routeid = routes.routeid',
    };

    if (routeId != null && routeId.isNotEmpty) {
      whereClauses.add('routes.routeid = ?');
      parameters.add(routeId);
    }

    if (routeIds != null && routeIds.isNotEmpty) {
      final placeholders = List.filled(routeIds.length, '?').join(', ');
      whereClauses.add('routes.routeid IN ($placeholders)');
      parameters.addAll(routeIds);
    }

    final normalizedQuery = searchQuery?.trim() ?? '';
    if (normalizedQuery.isNotEmpty) {
      whereClauses.add(
        '(routes.name LIKE ? OR routes.routeid LIKE ? OR $pathNameColumn LIKE ?)',
      );
      parameters.addAll(
        <Object?>[
          '%$normalizedQuery%',
          '%$normalizedQuery%',
          '%$normalizedQuery%',
        ],
      );
    }

    final limitClause = limit == null ? '' : 'LIMIT ?';
    if (limit != null) {
      parameters.add(limit);
    }

    final rows = database.select(
      '''
      SELECT
        routes.routeid AS route_id,
        routes.name AS route_name,
        routes.name_en AS route_name_en,
        $pathIdColumn AS path_id,
        $pathNameColumn AS path_name,
        $pathNameEnColumn AS path_name_en
      $fromClause
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY routes.routeid ASC, path_id ASC
      $limitClause
      ''',
      parameters,
    );

    return rows
        .map(
          (row) => _MetadataPathRow(
            routeId: row['route_id']?.toString() ?? '',
            routeName: row['route_name']?.toString() ?? '',
            routeNameEn: row['route_name_en']?.toString() ?? '',
            pathId: (row['path_id'] as num?)?.toInt() ?? 0,
            pathName: row['path_name']?.toString() ?? '',
            pathNameEn: row['path_name_en']?.toString() ?? '',
          ),
        )
        .where((row) => row.routeId.isNotEmpty)
        .toList();
  }

  Future<List<_CityStopRow>> _queryCityStopRows(
    Database database, {
    String? routeId,
    double? latitude,
    double? longitude,
    double? latDelta,
    double? lonDelta,
    int? limit,
  }) async {
    final parameters = <Object?>[];
    final whereClauses = <String>[];
    if (routeId != null && routeId.isNotEmpty) {
      whereClauses.add('stops.routeid = ?');
      parameters.add(routeId);
    }
    if (latitude != null &&
        longitude != null &&
        latDelta != null &&
        lonDelta != null) {
      whereClauses.add('ABS(stops.lat - ?) <= ?');
      whereClauses.add('ABS(stops.lon - ?) <= ?');
      parameters.addAll(<Object?>[latitude, latDelta, longitude, lonDelta]);
    }
    final whereClause = whereClauses.isEmpty
        ? ''
        : 'WHERE ${whereClauses.join(' AND ')}';
    final limitClause = limit == null ? '' : 'LIMIT ?';
    if (limit != null) {
      parameters.add(limit);
    }

    final rows = await database.rawQuery(
      '''
      SELECT
        stops.routeid,
        stops.pathid,
        stops.stopid,
        stops.name AS stop_name,
        stops.seq,
        stops.lon,
        stops.lat
      FROM stops
      $whereClause
      ORDER BY stops.routeid ASC, stops.pathid ASC, stops.seq ASC
      $limitClause
      ''',
      parameters,
    );

    return rows
        .map(
          (row) => _CityStopRow(
            routeId: row['routeid']?.toString() ?? '',
            pathId: (row['pathid'] as num?)?.toInt() ?? 0,
            stopId: row['stopid'],
            stopName: row['stop_name']?.toString() ?? '',
            sequence: (row['seq'] as num?)?.toInt() ?? 0,
            lon: (row['lon'] as num?)?.toDouble() ?? 0,
            lat: (row['lat'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  List<_CityStopRow> _queryCityStopRowsSqlite(
    NativeSqliteDatabase database, {
    String? routeId,
    double? latitude,
    double? longitude,
    double? latDelta,
    double? lonDelta,
    int? limit,
  }) {
    final parameters = <Object?>[];
    final whereClauses = <String>[];
    if (routeId != null && routeId.isNotEmpty) {
      whereClauses.add('stops.routeid = ?');
      parameters.add(routeId);
    }
    if (latitude != null &&
        longitude != null &&
        latDelta != null &&
        lonDelta != null) {
      whereClauses.add('ABS(stops.lat - ?) <= ?');
      whereClauses.add('ABS(stops.lon - ?) <= ?');
      parameters.addAll(<Object?>[latitude, latDelta, longitude, lonDelta]);
    }
    final whereClause = whereClauses.isEmpty
        ? ''
        : 'WHERE ${whereClauses.join(' AND ')}';
    final limitClause = limit == null ? '' : 'LIMIT ?';
    if (limit != null) {
      parameters.add(limit);
    }

    final rows = database.select(
      '''
      SELECT
        stops.routeid,
        stops.pathid,
        stops.stopid,
        stops.name AS stop_name,
        stops.seq,
        stops.lon,
        stops.lat
      FROM stops
      $whereClause
      ORDER BY stops.routeid ASC, stops.pathid ASC, stops.seq ASC
      $limitClause
      ''',
      parameters,
    );

    return rows
        .map(
          (row) => _CityStopRow(
            routeId: row['routeid']?.toString() ?? '',
            pathId: (row['pathid'] as num?)?.toInt() ?? 0,
            stopId: row['stopid'],
            stopName: row['stop_name']?.toString() ?? '',
            sequence: (row['seq'] as num?)?.toInt() ?? 0,
            lon: (row['lon'] as num?)?.toDouble() ?? 0,
            lat: (row['lat'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  void _validateMetadataDatabaseSchemaSqlite(
    NativeSqliteDatabase database,
  ) {
    _detectMetadataLayoutSqlite(database);
  }

  void _validateCityDatabaseSchemaSqlite(NativeSqliteDatabase database) {
    final tableNames = _loadTableNamesSqlite(database);
    if (!tableNames.contains('stops')) {
      throw const FormatException('Invalid city database schema.');
    }

    final stopColumns = _loadColumnNamesSqlite(database, 'stops');
    if (!stopColumns.containsAll(
      const {'routeid', 'pathid', 'seq', 'stopid', 'name', 'lat', 'lon'},
    )) {
      throw const FormatException('Invalid city database schema.');
    }
  }

  _MetadataLayout _detectMetadataLayoutSqlite(
    NativeSqliteDatabase database,
  ) {
    final tableNames = _loadTableNamesSqlite(database);
    if (!tableNames.contains('routes')) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    final routeColumns = _loadColumnNamesSqlite(database, 'routes');
    if (!routeColumns.containsAll(const {'routeid', 'name'})) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    if (routeColumns.containsAll(const {'pathid', 'path_name'})) {
      return _MetadataLayout.flattenedRoutes;
    }

    if (!tableNames.contains('paths')) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    final pathColumns = _loadColumnNamesSqlite(database, 'paths');
    if (!pathColumns.containsAll(const {'routeid', 'pathid', 'name'})) {
      throw const FormatException('Invalid route metadata database schema.');
    }

    return _MetadataLayout.routesAndPaths;
  }

  Set<String> _loadTableNamesSqlite(NativeSqliteDatabase database) {
    final rows = database.select(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
      ''',
    );
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Set<String> _loadColumnNamesSqlite(
    NativeSqliteDatabase database,
    String tableName,
  ) {
    final rows = database.select('PRAGMA table_info($tableName)');
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  T _withSqlite3Database<T>(
    File file,
    T Function(NativeSqliteDatabase database) action,
  ) {
    final database = openReadOnlySqliteDatabase(
      file.path);
    try {
      return action(database);
    } finally {
      database.close();
    }
  }

  Future<void> _validateMetadataDatabaseFileWithSqlite3(File file) async {
    _withSqlite3Database(file, (database) {
      _validateMetadataDatabaseSchemaSqlite(database);
      return null;
    });
  }

  Future<void> _validateCityDatabaseFileWithSqlite3(File file) async {
    _withSqlite3Database(file, (database) {
      _validateCityDatabaseSchemaSqlite(database);
      return null;
    });
  }

  Future<void> _deleteDatabaseArtifacts(File file) async {
    for (final candidatePath in <String>[
      file.path,
      '${file.path}-wal',
      '${file.path}-shm',
      '${file.path}-journal',
    ]) {
      final candidate = File(candidatePath);
      if (await candidate.exists()) {
        await candidate.delete();
      }
    }
  }

  Future<void> _ensureDownloadedMetadataDatabaseUsable(File file) async {
    if (!await _looksLikeSqliteFile(file)) {
      await _deleteDatabaseArtifacts(file);
      throw DatabaseNotReadyException('Route metadata database is invalid.');
    }

    if (Platform.isIOS) {
      try {
        await _validateMetadataDatabaseFileWithSqlite3(file);
      } catch (_) {
        await _deleteDatabaseArtifacts(file);
        throw DatabaseNotReadyException('Route metadata database is invalid.');
      }
      return;
    }

    try {
      final database = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        await _validateMetadataDatabaseSchema(database);
      } finally {
        await database.close();
      }
    } catch (_) {
      await _deleteDatabaseArtifacts(file);
      throw DatabaseNotReadyException('Route metadata database is invalid.');
    }
  }

  Future<void> _ensureDownloadedCityDatabaseUsable(
    BusProvider provider,
    File file,
  ) async {
    if (!await _looksLikeSqliteFile(file)) {
      await _markDatabaseInvalid(provider, file);
      throw DatabaseNotReadyException('${provider.label} city database is invalid.');
    }

    if (Platform.isIOS) {
      try {
        await _validateCityDatabaseFileWithSqlite3(file);
      } catch (_) {
        await _markDatabaseInvalid(provider, file);
        throw DatabaseNotReadyException('${provider.label} city database is invalid.');
      }
      return;
    }

    try {
      final database = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        await _validateCityDatabaseSchema(database);
      } finally {
        await database.close();
      }
    } catch (_) {
      await _markDatabaseInvalid(provider, file);
      throw DatabaseNotReadyException('${provider.label} city database is invalid.');
    }
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
    final rows = await _loadMetadataPathRows(provider: provider);
    for (final row in rows) {
      if (row.routeId.isNotEmpty && _routeKeyForRouteId(row.routeId) == routeKey) {
        return row.routeId;
      }
    }
    return null;
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

enum _MetadataLayout { flattenedRoutes, routesAndPaths }

class _MetadataPathRow {
  const _MetadataPathRow({
    required this.routeId,
    required this.routeName,
    required this.routeNameEn,
    required this.pathId,
    required this.pathName,
    required this.pathNameEn,
  });

  final String routeId;
  final String routeName;
  final String routeNameEn;
  final int pathId;
  final String pathName;
  final String pathNameEn;
}

class _RouteMetadataRow {
  const _RouteMetadataRow({
    required this.routeName,
    required this.routeNameEn,
    required this.pathName,
  });

  final String routeName;
  final String routeNameEn;
  final String pathName;
}

class _CityStopRow {
  const _CityStopRow({
    required this.routeId,
    required this.pathId,
    required this.stopId,
    required this.stopName,
    required this.sequence,
    required this.lon,
    required this.lat,
  });

  final String routeId;
  final int pathId;
  final Object? stopId;
  final String stopName;
  final int sequence;
  final double lon;
  final double lat;
}

class _TimedValue<T> {
  _TimedValue(this.value) : createdAt = DateTime.now();

  final T value;
  final DateTime createdAt;
}
