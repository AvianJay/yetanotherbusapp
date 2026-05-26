import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/route_search_ranking.dart';
import '../widgets/background_image_wrapper.dart';
import 'route_detail_navigation.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  Timer? _debounce;
  bool _isLoading = false;
  bool _isResolvingStopDistances = false;
  String? _error;
  List<_SearchDisplayItem> _results = const <_SearchDisplayItem>[];
  BusProvider? _webPreferredProvider;
  int _activeSearchToken = 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_resolveWebPreferredProvider());
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {});
    if (value.trim().isEmpty) {
      _activeSearchToken += 1;
      setState(() {
        _results = const <_SearchDisplayItem>[];
        _isLoading = false;
        _isResolvingStopDistances = false;
        _error = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_search(value));
    });
  }

  int _providerPriority(AppController busController, BusProvider provider) {
    if (kIsWeb) {
      final webPreferredProvider = _webPreferredProvider;
      if (webPreferredProvider == null) {
        return 0;
      }
      if (provider == webPreferredProvider) {
        return 0;
      }
      return provider == BusProvider.inter ? 2 : 1;
    }
    final currentProvider = busController.settings.provider;
    if (provider == currentProvider) {
      return 0;
    }
    if (provider == BusProvider.inter) {
      return 1;
    }
    return 2;
  }

  List<RouteSummary> _sortRouteResults(
    Iterable<RouteSummary> routes,
    String query,
    AppController busController,
  ) {
    return sortRouteSummariesForQuery(
      routes,
      query: query,
      providerPriority: (provider) =>
          _providerPriority(busController, provider),
    );
  }

  List<StopRouteSearchResult> _sortStopResults(
    Iterable<StopRouteSearchResult> results,
    String query,
    AppController busController, {
    Map<String, int>? baseOrder,
  }) {
    final sorted = results.toList();
    sorted.sort(
      (left, right) => _compareStopResults(
        left,
        right,
        query: query,
        busController: busController,
        baseOrder: baseOrder,
      ),
    );
    return sorted;
  }

  int _compareStopResults(
    StopRouteSearchResult left,
    StopRouteSearchResult right, {
    required String query,
    required AppController busController,
    Map<String, int>? baseOrder,
  }) {
    final leftDistance = left.nearestDistanceMeters;
    final rightDistance = right.nearestDistanceMeters;
    if (leftDistance != null && rightDistance != null) {
      final distanceCompare = leftDistance.compareTo(rightDistance);
      if (distanceCompare != 0) {
        return distanceCompare;
      }
    } else if (leftDistance != null) {
      return -1;
    } else if (rightDistance != null) {
      return 1;
    }

    final leftMatchTier = _stopSearchMatchTier(
      left.matchedStop.stopName,
      query,
    );
    final rightMatchTier = _stopSearchMatchTier(
      right.matchedStop.stopName,
      query,
    );
    if (leftMatchTier != rightMatchTier) {
      return leftMatchTier.compareTo(rightMatchTier);
    }

    final leftGap = _stopSearchLengthGap(left.matchedStop.stopName, query);
    final rightGap = _stopSearchLengthGap(right.matchedStop.stopName, query);
    if (leftGap != rightGap) {
      return leftGap.compareTo(rightGap);
    }

    final leftProviderPriority = _providerPriority(
      busController,
      busProviderFromString(left.route.sourceProvider),
    );
    final rightProviderPriority = _providerPriority(
      busController,
      busProviderFromString(right.route.sourceProvider),
    );
    if (leftProviderPriority != rightProviderPriority) {
      return leftProviderPriority.compareTo(rightProviderPriority);
    }

    final routeNameCompare = left.route.routeName.compareTo(
      right.route.routeName,
    );
    if (routeNameCompare != 0) {
      return routeNameCompare;
    }

    final descriptionCompare = left.route.description.compareTo(
      right.route.description,
    );
    if (descriptionCompare != 0) {
      return descriptionCompare;
    }

    final leftIndex = baseOrder?[_stopResultKey(left)];
    final rightIndex = baseOrder?[_stopResultKey(right)];
    if (leftIndex != null && rightIndex != null && leftIndex != rightIndex) {
      return leftIndex.compareTo(rightIndex);
    }

    return left.route.routeId.compareTo(right.route.routeId);
  }

  int _stopSearchMatchTier(String stopName, String query) {
    final normalizedStopName = _normalizeSearchText(stopName);
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) {
      return 0;
    }
    if (normalizedStopName == normalizedQuery) {
      return 0;
    }
    if (normalizedStopName.startsWith(normalizedQuery)) {
      return 1;
    }
    if (normalizedStopName.contains(normalizedQuery)) {
      return 2;
    }
    return 3;
  }

  int _stopSearchLengthGap(String stopName, String query) {
    final normalizedStopName = _normalizeSearchText(stopName);
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) {
      return 0;
    }
    return (normalizedStopName.length - normalizedQuery.length).abs();
  }

  Future<void> _resolveWebPreferredProvider() async {
    final position = await _resolveSearchPosition();
    if (!mounted || position == null) {
      return;
    }

    final nextProvider = nearestBusProvider(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (nextProvider == _webPreferredProvider) {
      return;
    }

    final busController = AppControllerScope.read(context);
    setState(() {
      _webPreferredProvider = nextProvider;
      if (_results.isNotEmpty && _controller.text.trim().isNotEmpty) {
        final query = _controller.text.trim();
        final routeResults = _results
            .where((item) => !item.isStopSearchResult)
            .map((item) => item.route)
            .toList();
        if (routeResults.length == _results.length) {
          _results = _sortRouteResults(
            routeResults,
            query,
            busController,
          ).map(_SearchDisplayItem.route).toList();
        }
      }
    });
  }

  Future<Position?> _resolveSearchPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }

      final permission = await Geolocator.checkPermission();
      Position? lastKnown;
      try {
        lastKnown = await Geolocator.getLastKnownPosition();
      } catch (_) {
        lastKnown = null;
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return lastKnown;
      }

      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (_) {
        return lastKnown;
      }
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeRouteQuery(String query) {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) {
      return false;
    }

    if (RegExp(
          r'^[a-z0-9][a-z0-9\-/]*$',
          caseSensitive: false,
        ).hasMatch(normalized) &&
        normalized.length <= 10) {
      return true;
    }

    if (RegExp(r'\d').hasMatch(normalized) && normalized.length <= 12) {
      return true;
    }

    const prefixes = <String>[
      '紅',
      '藍',
      '綠',
      '棕',
      '橘',
      '黃',
      '紫',
      '小',
      '副',
      '幹',
      '跳蛙',
      '市民',
      '內科',
      '南軟',
      '通勤',
      '快捷',
      '快線',
      '先導',
    ];
    if (prefixes.any(normalized.startsWith) && normalized.length <= 12) {
      return true;
    }

    if (normalized.endsWith('幹線') ||
        normalized.contains('快線') ||
        normalized.contains('跳蛙')) {
      return true;
    }

    return false;
  }

  bool _hasStrongRouteMatch(String query, List<RouteSummary> routes) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) {
      return false;
    }

    for (final route in routes.take(6)) {
      final normalizedRouteName = _normalizeSearchText(
        _displayRouteName(route),
      );
      final normalizedRouteId = _normalizeSearchText(route.routeId);
      if (normalizedRouteName == normalizedQuery ||
          normalizedRouteId == normalizedQuery) {
        return true;
      }
      if (normalizedQuery.length >= 3 &&
          normalizedRouteName.startsWith(normalizedQuery) &&
          normalizedRouteName.length <= normalizedQuery.length + 2) {
        return true;
      }
    }

    return false;
  }

  String _displayRouteName(RouteSummary route) {
    final routeName = route.routeName.trim();
    if (routeName.isNotEmpty) {
      return routeName;
    }
    final officialRouteName = route.officialRouteName.trim();
    if (officialRouteName.isNotEmpty) {
      return officialRouteName;
    }
    return route.routeId.trim();
  }

  String _normalizeSearchText(String value) {
    return value.trim().toLowerCase();
  }

  Future<void> _search(String query) async {
    final busController = AppControllerScope.read(context);
    final trimmedQuery = query.trim();
    final token = ++_activeSearchToken;
    final providerCount = busController.searchProviders.length;
    final localProviderCount = busController.searchProviders
        .where(
          (provider) =>
              provider.supportsLocalDatabase &&
              busController.isDatabaseReady(provider),
        )
        .length;
    final remoteProviderCount = providerCount - localProviderCount;
    final likelyStopSearch =
        localProviderCount > 0 && !_looksLikeRouteQuery(trimmedQuery);

    setState(() {
      _isLoading = true;
      _isResolvingStopDistances = likelyStopSearch;
      _error = null;
    });

    try {
      final routeResults = _sortRouteResults(
        await busController.searchRoutesAcrossSelected(trimmedQuery),
        trimmedQuery,
        busController,
      );

      if (!mounted || token != _activeSearchToken) {
        return;
      }

      final shouldTryStopSearch =
          localProviderCount > 0 &&
          !_looksLikeRouteQuery(trimmedQuery) &&
          !_hasStrongRouteMatch(trimmedQuery, routeResults);

      if (shouldTryStopSearch) {
        final stopResults = await _runProgressiveStopSearchFallback(
          trimmedQuery,
          token: token,
          busController: busController,
        );

        if (!mounted || token != _activeSearchToken) {
          return;
        }

        if (stopResults.isNotEmpty) {
          // `_runProgressiveStopSearchFallback` owns the staged UI updates for
          // stop results, including nearest-stop resolution, so we must not
          // overwrite `_results` here with the older unresolved snapshot.
          unawaited(
            busController.analytics.logSearchExecuted(
              queryLength: trimmedQuery.length,
              resultsCount: stopResults.length,
              providerCount: providerCount,
              localProviderCount: localProviderCount,
              remoteProviderCount: remoteProviderCount,
            ),
          );
          return;
        }
      }

      setState(() {
        _results = routeResults.map(_SearchDisplayItem.route).toList();
        _isLoading = false;
        _isResolvingStopDistances = false;
      });

      unawaited(
        busController.analytics.logSearchExecuted(
          queryLength: trimmedQuery.length,
          resultsCount: routeResults.length,
          providerCount: providerCount,
          localProviderCount: localProviderCount,
          remoteProviderCount: remoteProviderCount,
        ),
      );
    } catch (error) {
      if (!mounted || token != _activeSearchToken) {
        return;
      }
      setState(() {
        _error = '$error';
        _isResolvingStopDistances = false;
      });
      unawaited(
        busController.analytics.logSearchFailed(
          queryLength: trimmedQuery.length,
          providerCount: providerCount,
        ),
      );
    } finally {
      if (mounted && token == _activeSearchToken && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<StopRouteSearchResult>> _runProgressiveStopSearchFallback(
    String query, {
    required int token,
    required AppController busController,
  }) async {
    final providers = busController.searchProviders
        .where(busController.isDatabaseReady)
        .toList();
    if (providers.isEmpty) {
      if (mounted && token == _activeSearchToken) {
        setState(() {
          _isResolvingStopDistances = false;
        });
      }
      return const <StopRouteSearchResult>[];
    }

    final positionFuture = _resolveSearchPosition();
    final collectedResults = <StopRouteSearchResult>[];
    final baseOrder = <String, int>{};
    var nextBaseOrder = 0;

    if (mounted && token == _activeSearchToken) {
      setState(() {
        _isLoading = false;
        _isResolvingStopDistances = true;
        _results = const <_SearchDisplayItem>[];
      });
    }

    final pendingBatches = <int, Future<_StopSearchBatch>>{
      for (var index = 0; index < providers.length; index += 1)
        index: busController
            .searchRoutesByStop(query, provider: providers[index])
            .then(
              (results) =>
                  _StopSearchBatch(providerIndex: index, results: results),
            ),
    };

    while (pendingBatches.isNotEmpty) {
      final batch = await Future.any(pendingBatches.values);
      pendingBatches.remove(batch.providerIndex);
      if (!mounted || token != _activeSearchToken) {
        return const <StopRouteSearchResult>[];
      }

      final sortedProviderResults = _sortStopResults(
        batch.results,
        query,
        busController,
      );
      var didAppend = false;
      for (final result in sortedProviderResults) {
        final resultKey = _stopResultKey(result);
        if (baseOrder.containsKey(resultKey)) {
          continue;
        }
        baseOrder[resultKey] = nextBaseOrder;
        nextBaseOrder += 1;
        collectedResults.add(result);
        didAppend = true;

        setState(() {
          _results = _sortStopResults(
            collectedResults,
            query,
            busController,
            baseOrder: baseOrder,
          ).map(_SearchDisplayItem.stop).toList();
        });
      }

      if (!didAppend) {
        continue;
      }
    }

    if (collectedResults.isEmpty) {
      if (mounted && token == _activeSearchToken) {
        setState(() {
          _isResolvingStopDistances = false;
        });
      }
      return const <StopRouteSearchResult>[];
    }

    final position = await positionFuture;
    if (!mounted || token != _activeSearchToken) {
      return collectedResults;
    }

    if (position == null) {
      setState(() {
        _isResolvingStopDistances = false;
      });
      return _sortStopResults(
        collectedResults,
        query,
        busController,
        baseOrder: baseOrder,
      );
    }

    return _progressivelyResolveStopSearchResults(
      collectedResults,
      query: query,
      position: position,
      token: token,
      busController: busController,
    );
  }

  Future<List<StopRouteSearchResult>> _progressivelyResolveStopSearchResults(
    List<StopRouteSearchResult> initialResults, {
    required String query,
    required Position position,
    required int token,
    required AppController busController,
  }) async {
    final workingResults = List<StopRouteSearchResult>.of(initialResults);
    final baseOrder = <String, int>{
      for (var index = 0; index < initialResults.length; index += 1)
        _stopResultKey(initialResults[index]): index,
    };
    final routeStopsCache = <String, Future<List<StopInfo>>>{};

    try {
      for (final result in initialResults) {
        if (!mounted || token != _activeSearchToken) {
          return workingResults;
        }

        final resolvedResult = await _resolveNearestStopSearchResult(
          result,
          position: position,
          busController: busController,
          routeStopsCache: routeStopsCache,
        );
        if (!mounted || token != _activeSearchToken) {
          return workingResults;
        }

        final resultKey = _stopResultKey(result);
        final workingIndex = workingResults.indexWhere(
          (item) => _stopResultKey(item) == resultKey,
        );
        if (workingIndex < 0) {
          continue;
        }

        workingResults[workingIndex] = resolvedResult;
        final sortedResults = _sortStopResults(
          workingResults,
          query,
          busController,
          baseOrder: baseOrder,
        );
        setState(() {
          _results = sortedResults.map(_SearchDisplayItem.stop).toList();
        });
      }
    } finally {
      if (mounted && token == _activeSearchToken) {
        setState(() {
          _isResolvingStopDistances = false;
        });
      }
    }

    return _sortStopResults(
      workingResults,
      query,
      busController,
      baseOrder: baseOrder,
    );
  }

  Future<StopRouteSearchResult> _resolveNearestStopSearchResult(
    StopRouteSearchResult result, {
    required Position position,
    required AppController busController,
    required Map<String, Future<List<StopInfo>>> routeStopsCache,
  }) async {
    final route = result.route;
    final provider = busProviderFromString(route.sourceProvider);
    final cacheKey = '${provider.name}:${route.routeId}';

    try {
      final routeStopsFuture = routeStopsCache.putIfAbsent(cacheKey, () {
        return busController.getStopsByRoute(
          route.routeKey,
          provider: provider,
          routeIdHint: route.routeId,
        );
      });

      final pathStops = (await routeStopsFuture)
          .where((stop) => stop.pathId == result.matchedStop.pathId)
          .toList();
      if (pathStops.isEmpty) {
        return result;
      }

      StopInfo? nearestStop;
      double? nearestDistanceMeters;
      for (final stop in pathStops) {
        final distanceMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          stop.lat,
          stop.lon,
        );
        if (nearestDistanceMeters == null ||
            distanceMeters < nearestDistanceMeters) {
          nearestStop = stop;
          nearestDistanceMeters = distanceMeters;
        }
      }

      if (nearestStop == null || nearestDistanceMeters == null) {
        return result;
      }

      return result.copyWith(
        nearestStop: nearestStop,
        nearestDistanceMeters: nearestDistanceMeters,
      );
    } catch (_) {
      return result;
    }
  }

  String _stopResultKey(StopRouteSearchResult result) {
    return [
      result.route.sourceProvider,
      result.route.routeId,
      result.matchedStop.pathId,
      result.matchedStop.stopId,
    ].join(':');
  }

  String _subtitleForResult(_SearchDisplayItem item) {
    final route = item.route;
    final providerLabel = busProviderFromString(route.sourceProvider).label;
    final routeMeta = route.description.trim().isEmpty
        ? providerLabel
        : '$providerLabel | ${route.description.trim()}';
    final stopSearch = item.stopSearch;
    if (stopSearch == null) {
      return routeMeta;
    }

    final details = <String>['符合站牌：${stopSearch.matchedStop.stopName}'];
    final nearestStop = stopSearch.nearestStop;
    final nearestDistanceMeters = stopSearch.nearestDistanceMeters;
    if (nearestStop != null && nearestDistanceMeters != null) {
      details.add(
        '離你最近：${nearestStop.stopName} (${formatDistance(nearestDistanceMeters)})',
      );
    }

    return '$routeMeta\n${details.join('\n')}';
  }

  Future<void> _openRoute({
    required BusProvider provider,
    required int routeKey,
    required String routeName,
    String? routeIdHint,
    int? initialPathId,
    int? initialStopId,
    RouteSummary? route,
    bool saveHistory = false,
    String source = 'search_result',
  }) async {
    final busController = AppControllerScope.read(context);
    if (saveHistory && route != null) {
      await busController.addHistoryEntry(route, provider: provider);
    }
    await busController.recordRouteSelection(
      provider: provider,
      routeKey: routeKey,
      routeName: routeName,
      source: source,
    );
    if (!mounted) {
      return;
    }
    await openRouteDetailPage(
      context,
      routeKey: routeKey,
      provider: provider,
      routeIdHint: routeIdHint,
      routeNameHint: routeName,
      initialPathId: initialPathId,
      initialStopId: initialStopId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final busController = AppControllerScope.of(context);
    final selectedProviders = busController.selectedProviders;
    final hasSearchBackgroundImage = hasBackgroundImageForPage(
      busController.settings,
      pageKey: 'search',
    );
    final missingProviders = selectedProviders
        .where((provider) => !busController.isDatabaseReady(provider))
        .toList();

    return BackgroundImageWrapper(
      pageKey: 'search',
      child: Scaffold(
        backgroundColor: hasSearchBackgroundImage ? Colors.transparent : null,
        appBar: AppBar(title: const Text('搜尋路線或站牌')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: '搜尋公車路線或站牌名稱',
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isResolvingStopDistances) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            if (_controller.text.trim().isEmpty)
              _HistorySection(
                history: busController.history,
                onClear: busController.clearHistory,
                onSelect: (entry) {
                  unawaited(
                    _openRoute(
                      provider: entry.provider,
                      routeKey: entry.routeKey,
                      routeName: entry.routeName,
                      routeIdHint: entry.routeId,
                      source: 'search_history',
                    ),
                  );
                },
              )
            else if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('搜尋失敗：$_error'),
                ),
              )
            else if (_isResolvingStopDistances && _results.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('正在搜尋站牌，結果會陸續出現…'),
                ),
              )
            else if (_results.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    missingProviders.isEmpty
                        ? '找不到符合的路線或站牌。'
                        : '找不到符合的路線或站牌。部分站牌搜尋需要本機資料庫。',
                  ),
                ),
              )
            else
              ..._results.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          item.route.routeName.trim().isEmpty
                              ? '?'
                              : item.route.routeName.characters.first,
                        ),
                      ),
                      title: Text(item.route.routeName),
                      subtitle: Text(
                        _subtitleForResult(item),
                        maxLines: item.isStopSearchResult ? 3 : 1,
                      ),
                      onTap: () async {
                        final route = item.route;
                        final stopSearch = item.stopSearch;
                        final routeProvider = busProviderFromString(
                          route.sourceProvider,
                        );
                        await _openRoute(
                          provider: routeProvider,
                          routeKey: route.routeKey,
                          routeName: route.routeName,
                          routeIdHint: route.routeId,
                          initialPathId:
                              stopSearch?.matchedStop.pathId ?? route.rtrip,
                          initialStopId:
                              stopSearch?.nearestStop?.stopId ??
                              stopSearch?.matchedStop.stopId,
                          route: route,
                          saveHistory: true,
                          source: stopSearch == null
                              ? 'search_result'
                              : 'search_stop_result',
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchDisplayItem {
  const _SearchDisplayItem.route(this.route) : stopSearch = null;

  _SearchDisplayItem.stop(StopRouteSearchResult result)
    : route = result.route,
      stopSearch = result;

  final RouteSummary route;
  final StopRouteSearchResult? stopSearch;

  bool get isStopSearchResult => stopSearch != null;
}

class _StopSearchBatch {
  const _StopSearchBatch({required this.providerIndex, required this.results});

  final int providerIndex;
  final List<StopRouteSearchResult> results;
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.history,
    required this.onClear,
    required this.onSelect,
  });

  final List<SearchHistoryEntry> history;
  final Future<void> Function() onClear;
  final ValueChanged<SearchHistoryEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(16), child: Text('還沒有搜尋紀錄。')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('最近搜尋', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await onClear();
              },
              child: const Text('清除'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...history.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(entry.routeName),
                subtitle: Text(
                  entry.pathName != null && entry.pathName!.isNotEmpty
                      ? '${entry.provider.label} | ${entry.pathName}'
                      : entry.provider.label,
                ),
                onTap: () => onSelect(entry),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
