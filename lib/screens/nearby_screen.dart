import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/bus_repository.dart';
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

      if (!mounted) return;
      setState(() {
        _results = results;
      });

      // Phase 2: load ETAs in background without blocking the list render
      unawaited(_loadEtas(results));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
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
    if (results.isEmpty || !mounted) return;

    final controller = AppControllerScope.read(context);
    setState(() => _loadingEtas = true);

    final routeIds =
        results.map((r) => r.route.routeId).toSet().toList(growable: false);

    Map<String, LiveStopMap> liveMaps = const {};
    try {
      liveMaps = await controller.repository.getBatchLiveStopMaps(routeIds);
    } catch (_) {}

    final missingIds =
        routeIds.where((id) => !liveMaps.containsKey(id.trim())).toSet();
    if (missingIds.isNotEmpty) {
      final fallbacks = await Future.wait(
        missingIds.map((routeId) async {
          try {
            final liveMap =
                await controller.repository.getLiveStopMap(routeId);
            return MapEntry(routeId.trim(), liveMap);
          } catch (_) {
            return null;
          }
        }),
      );
      final merged = Map<String, LiveStopMap>.from(liveMaps);
      for (final entry in fallbacks) {
        if (entry != null) merged[entry.key] = entry.value;
      }
      liveMaps = merged;
    }

    if (!mounted) return;
    setState(() {
      _liveMaps = liveMaps;
      _loadingEtas = false;
    });
  }

  StopInfo _liveStop(NearbyStopResult item) {
    final liveMap = _liveMaps[item.route.routeId.trim()];
    final payload = liveMap?['${item.stop.pathId}:${item.stop.stopId}'];
    if (payload == null) return item.stop;
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
    if (message == null || message.isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(message);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  // Bucket 0: sec ETA  1: HH:MM message  2: other message  3: no data
  int _etaBucket(StopInfo stop) {
    if (stop.sec != null) return 0;
    if (_messageEtaMinutes(stop) != null) return 1;
    if (stop.msg?.trim().isNotEmpty ?? false) return 2;
    return 3;
  }

  int _compareByEta(NearbyStopResult a, NearbyStopResult b) {
    final aStop = _liveStop(a);
    final bStop = _liveStop(b);
    final aBucket = _etaBucket(aStop);
    final bBucket = _etaBucket(bStop);
    if (aBucket != bBucket) return aBucket.compareTo(bBucket);
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

  /// Groups flat results (one per route) into stops, preserving distance order.
  /// Routes within each group are sorted by ETA once live data is available.
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

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final hasNearbyBackgroundImage = hasBackgroundImageForPage(
      controller.settings,
      pageKey: 'nearby',
    );

    return BackgroundImageWrapper(
      pageKey: 'nearby',
      child: Scaffold(
        backgroundColor: hasNearbyBackgroundImage ? Colors.transparent : null,
        appBar: AppBar(
          title: const Text('附近站牌'),
          actions: [
            IconButton(
              onPressed: _loadNearbyStops,
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
                            onPressed: () => openAdaptiveSettingsScreen(context),
                            child: const Text('前往設定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : _results.isEmpty
            ? const Center(child: Text('附近沒有找到站牌。'))
            : Column(
                children: [
                  SizedBox(
                    height: 2,
                    child: _loadingEtas
                        ? const LinearProgressIndicator(minHeight: 2)
                        : null,
                  ),
                  Expanded(
                    child: _NearbyStopList(
                      groups: _buildGroups(),
                      alwaysShowSeconds:
                          controller.settings.alwaysShowSeconds,
                      liveStop: _liveStop,
                      onRouteTap: (item) async {
                        final routeProvider = busProviderFromString(
                          item.route.sourceProvider,
                        );
                        await controller.recordRouteSelection(
                          provider: routeProvider,
                          routeKey: item.route.routeKey,
                          routeName: item.route.routeName,
                          source: 'nearby',
                        );
                        if (!context.mounted) return;
                        await openRouteDetailPage(
                          context,
                          routeKey: item.route.routeKey,
                          provider: routeProvider,
                          routeIdHint: item.route.routeId,
                          routeNameHint: item.route.routeName,
                          initialPathId: item.stop.pathId,
                          initialStopId: item.stop.stopId,
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
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

class _NearbyStopList extends StatelessWidget {
  const _NearbyStopList({
    required this.groups,
    required this.alwaysShowSeconds,
    required this.liveStop,
    required this.onRouteTap,
  });

  final List<_NearbyStopGroup> groups;
  final bool alwaysShowSeconds;
  final StopInfo Function(NearbyStopResult) liveStop;
  final ValueChanged<NearbyStopResult> onRouteTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _NearbyStopCard(
        group: groups[index],
        alwaysShowSeconds: alwaysShowSeconds,
        liveStop: liveStop,
        onRouteTap: onRouteTap,
      ),
    );
  }
}

class _NearbyStopCard extends StatelessWidget {
  const _NearbyStopCard({
    required this.group,
    required this.alwaysShowSeconds,
    required this.liveStop,
    required this.onRouteTap,
  });

  final _NearbyStopGroup group;
  final bool alwaysShowSeconds;
  final StopInfo Function(NearbyStopResult) liveStop;
  final ValueChanged<NearbyStopResult> onRouteTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    formatDistance(group.distanceMeters),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    group.stopName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...group.routes.map(
            (item) => _RouteRow(
              item: item,
              liveStop: liveStop(item),
              alwaysShowSeconds: alwaysShowSeconds,
              onTap: () => onRouteTap(item),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.item,
    required this.liveStop,
    required this.alwaysShowSeconds,
    required this.onTap,
  });

  final NearbyStopResult item;
  final StopInfo liveStop;
  final bool alwaysShowSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = item.route;
    final description = route.description.trim();
    final subtitle = [
      busProviderFromString(route.sourceProvider).label,
      if (description.isNotEmpty)
        description.startsWith('往') ? description : '往 $description',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            EtaBadge(
              stop: liveStop,
              alwaysShowSeconds: alwaysShowSeconds,
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.routeName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
