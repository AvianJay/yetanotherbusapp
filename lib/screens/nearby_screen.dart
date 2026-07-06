import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/bus_repository.dart';
import '../core/friendly_error.dart';
import '../core/models.dart';
import 'adaptive_settings_presenter.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/eta_badge.dart';
import 'route_detail_navigation.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyStopGroup {
  const _NearbyStopGroup({
    required this.stopName,
    required this.distanceMeters,
    required this.routes,
  });

  final String stopName;
  final double distanceMeters;
  final List<NearbyStopResult> routes;
}

class _NearbyScreenState extends State<NearbyScreen> {
  bool _loading = true;
  String? _error;
  List<NearbyStopResult> _results = const [];
  Map<String, LiveStopMap> _liveMaps = const {};
  bool _loadingEtas = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNearbyStops();
    });
  }

  Future<void> _loadNearbyStops() async {
    final controller = AppControllerScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
      _liveMaps = const {};
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw StateError('定位服務尚未開啟。');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('沒有取得定位權限。');
      }

      final position = await Geolocator.getCurrentPosition();
      final results = await controller.getNearbyStops(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
      });

      // Phase 2: load ETAs in background without blocking the list render.
      unawaited(_loadEtas(results));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const [];
        _error = friendlyErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadEtas(List<NearbyStopResult> results) async {
    if (results.isEmpty || !mounted) {
      return;
    }

    final controller = AppControllerScope.read(context);
    setState(() => _loadingEtas = true);

    final routeIds = results
        .map((result) => result.route.routeId)
        .toSet()
        .toList(growable: false);

    Map<String, LiveStopMap> liveMaps = const {};
    try {
      liveMaps = await controller.repository.getBatchLiveStopMaps(routeIds);
    } catch (_) {}

    final missingRouteIds = routeIds
        .map((routeId) => routeId.trim())
        .where((routeId) => !liveMaps.containsKey(routeId))
        .toSet();
    if (missingRouteIds.isNotEmpty) {
      final fallbackEntries = await Future.wait(
        missingRouteIds.map((routeId) async {
          try {
            final liveMap = await controller.repository.getLiveStopMap(routeId);
            return MapEntry(routeId, liveMap);
          } catch (_) {
            return null;
          }
        }),
      );
      final merged = Map<String, LiveStopMap>.from(liveMaps);
      for (final entry in fallbackEntries) {
        if (entry != null) {
          merged[entry.key] = entry.value;
        }
      }
      liveMaps = merged;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _liveMaps = liveMaps;
      _loadingEtas = false;
    });
  }

  StopInfo _liveStop(NearbyStopResult item) {
    final liveMap = _liveMaps[item.route.routeId.trim()];
    final payload = liveMap?['${item.stop.pathId}:${item.stop.stopId}'];
    if (payload == null) {
      return item.stop;
    }
    return item.stop.copyWith(
      sec: payload.sec,
      msg: payload.msg,
      t: payload.t,
      buses: payload.buses,
    );
  }

  // Returns the minute-of-day if the message starts with HH:MM, else null.
  int? _messageEtaMinutes(StopInfo stop) {
    final message = stop.msg?.trim();
    if (message == null || message.isEmpty) {
      return null;
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(message);
    if (match == null) {
      return null;
    }
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) {
      return null;
    }
    return hour * 60 + minute;
  }

  // Bucket 0: sec ETA  1: HH:MM message  2: other message  3: no data
  int _etaBucket(StopInfo stop) {
    if (stop.sec != null) {
      return 0;
    }
    if (_messageEtaMinutes(stop) != null) {
      return 1;
    }
    if (stop.msg?.trim().isNotEmpty ?? false) {
      return 2;
    }
    return 3;
  }

  int _compareByEta(NearbyStopResult a, NearbyStopResult b) {
    final aStop = _liveStop(a);
    final bStop = _liveStop(b);
    final aBucket = _etaBucket(aStop);
    final bBucket = _etaBucket(bStop);
    if (aBucket != bBucket) {
      return aBucket.compareTo(bBucket);
    }
    final aSec = aStop.sec;
    final bSec = bStop.sec;
    if (aSec != null && bSec != null && aSec != bSec) {
      return aSec.compareTo(bSec);
    }
    final aMin = _messageEtaMinutes(aStop);
    final bMin = _messageEtaMinutes(bStop);
    if (aMin != null && bMin != null && aMin != bMin) {
      return aMin.compareTo(bMin);
    }
    return a.route.routeKey.compareTo(b.route.routeKey);
  }

  /// Groups flat results (one per route) into stops, preserving distance
  /// order. Routes within each group are sorted by ETA once live data is
  /// available.
  List<_NearbyStopGroup> _buildGroups() {
    final groupOrder = <String>[];
    final groupDistances = <String, double>{};
    final groupRoutes = <String, List<NearbyStopResult>>{};

    for (final item in _results) {
      final name = item.stop.stopName;
      if (!groupRoutes.containsKey(name)) {
        groupOrder.add(name);
        groupDistances[name] = item.distanceMeters;
        groupRoutes[name] = [];
      }
      groupRoutes[name]!.add(item);
    }

    return [
      for (final name in groupOrder)
        _NearbyStopGroup(
          stopName: name,
          distanceMeters: groupDistances[name]!,
          routes: groupRoutes[name]!..sort(_compareByEta),
        ),
    ];
  }

  Future<void> _openRoute(NearbyStopResult item) async {
    final controller = AppControllerScope.read(context);
    final routeProvider = busProviderFromString(item.route.sourceProvider);
    final autoFavorited = await controller.recordRouteSelection(
      provider: routeProvider,
      routeKey: item.route.routeKey,
      routeName: item.route.routeName,
      source: 'nearby',
      pathId: item.stop.pathId,
      stopId: item.stop.stopId,
      stopName: item.stop.stopName,
    );
    if (!mounted) {
      return;
    }
    if (autoFavorited != null) {
      showAutoFavoritedSnackBar(context, autoFavorited);
    }
    await openRouteDetailPage(
      context,
      routeKey: item.route.routeKey,
      provider: routeProvider,
      routeIdHint: item.route.routeId,
      routeNameHint: item.route.routeName,
      initialPathId: item.stop.pathId,
      initialStopId: item.stop.stopId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final theme = Theme.of(context);
    final hasNearbyBackgroundImage = hasBackgroundImageForPage(
      controller.settings,
      pageKey: 'nearby',
    );
    final groups = _buildGroups();

    return BackgroundImageWrapper(
      pageKey: 'nearby',
      child: Scaffold(
        backgroundColor: hasNearbyBackgroundImage ? Colors.transparent : null,
        appBar: AppBar(
          title: const Text('附近站牌'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadNearbyStops,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: _loadNearbyStops,
                            child: const Text('重試'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              openAdaptiveSettingsScreen(context);
                            },
                            child: const Text('前往設定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : groups.isEmpty
            ? const Center(child: Text('附近沒有找到站牌。'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  formatDistance(group.distanceMeters),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelMedium,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  group.stopName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (_loadingEtas) ...[
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(minHeight: 2),
                          ],
                          const SizedBox(height: 8),
                          for (final item in group.routes) ...[
                            if (item != group.routes.first)
                              const Divider(height: 1),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _openRoute(item),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      EtaBadge(
                                        stop: _liveStop(item),
                                        alwaysShowSeconds: controller
                                            .settings
                                            .alwaysShowSeconds,
                                        size: 44,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '${busProviderFromString(item.route.sourceProvider).label} · ${item.route.routeName}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 20,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
