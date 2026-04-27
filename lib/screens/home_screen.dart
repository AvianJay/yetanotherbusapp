import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/eta_badge.dart';
import '../widgets/transit_drawer.dart';
import 'database_settings_screen.dart';
import 'favorites_screen.dart';
import 'nearby_screen.dart';
import 'route_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onModeChanged, super.key});

  final ValueChanged<TransitMode> onModeChanged;

  Future<void> _openDatabaseSettings(
    BuildContext context,
    AppController controller,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const DatabaseSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('YABus'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '資料庫與下載',
            onPressed: () => _openDatabaseSettings(context, controller),
            icon: controller.downloadingDatabase
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: controller.hasPendingDatabaseUpdates,
                    child: Icon(
                      controller.databaseReady
                          ? Icons.storage_rounded
                          : Icons.cloud_download_outlined,
                    ),
                  ),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      drawer: TransitDrawer(
        currentMode: TransitMode.bus,
        onModeChanged: onModeChanged,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withValues(alpha: 0.65),
              Theme.of(context).scaffoldBackgroundColor,
              colorScheme.secondaryContainer.withValues(alpha: 0.25),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            if (controller.settings.enableSmartRecommendations) ...[
              _SmartRecommendationCard(controller: controller),
              const SizedBox(height: 16),
            ],
            _FeatureCard(
              icon: Icons.search_rounded,
              title: '搜尋路線',
              subtitle: '輸入公車號碼、路線名稱或客運路線，直接看即時到站資訊。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.favorite_outline_rounded,
              title: '我的最愛',
              subtitle: '整理常用站牌與群組，快速跳回指定站點。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FavoritesScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _FeatureCard(
              icon: Icons.near_me_outlined,
              title: '附近站牌',
              subtitle: '依照你目前位置找附近的公車站牌。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NearbyScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartRecommendationCard extends StatefulWidget {
  const _SmartRecommendationCard({required this.controller});

  final AppController controller;

  @override
  State<_SmartRecommendationCard> createState() =>
      _SmartRecommendationCardState();
}

class _SmartCardData {
  const _SmartCardData.recommended(this.suggestion) : nearby = null;

  const _SmartCardData.nearby(this.nearby) : suggestion = null;

  final SmartRouteSuggestion? suggestion;
  final _NearbyFallbackData? nearby;
}

class _NearbyFallbackData {
  const _NearbyFallbackData({
    required this.result,
    required this.liveStop,
    this.path,
  });

  final NearbyStopResult result;
  final StopInfo? liveStop;
  final PathInfo? path;
}

class _SmartRecommendationCardState extends State<_SmartRecommendationCard> {
  Future<_SmartCardData?>? _future;
  String _reloadKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _SmartRecommendationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reloadIfNeeded();
  }

  void _reloadIfNeeded() {
    final nextKey = [
      widget.controller.settings.provider.name,
      widget.controller.settings.enableSmartRecommendations,
      widget.controller.databaseReady,
      widget.controller.smartRouteSignature,
    ].join('|');
    if (_reloadKey == nextKey) {
      return;
    }
    _reloadKey = nextKey;
    _future = _loadSuggestion();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadSuggestion();
    });
  }

  Future<Position?> _resolvePosition() async {
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

  Future<_SmartCardData?> _loadSuggestion() async {
    final controller = widget.controller;
    if (!controller.settings.enableSmartRecommendations ||
        !controller.databaseReady) {
      return null;
    }

    final position = await _resolvePosition();
    if (controller.routeUsageProfiles.isNotEmpty) {
      final suggestion = await controller.getSmartRouteSuggestion(
        position: position,
      );
      if (suggestion != null) {
        return _SmartCardData.recommended(suggestion);
      }
    }

    if (position == null) {
      return null;
    }

    try {
      final nearbyStops = await controller.getNearbyStops(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (nearbyStops.isEmpty) {
        return null;
      }

      final nearest = nearbyStops.first;
      final detail = await controller.getRouteDetail(
        nearest.route.routeKey,
        provider: controller.settings.provider,
      );
      final liveStop = _findStopInDetail(
        detail,
        pathId: nearest.stop.pathId,
        stopId: nearest.stop.stopId,
      );
      final path = _findPath(detail, nearest.stop.pathId);
      return _SmartCardData.nearby(
        _NearbyFallbackData(result: nearest, liveStop: liveStop, path: path),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  Future<void> _openSuggestion(SmartRouteSuggestion suggestion) async {
    final controller = widget.controller;
    final pathId = suggestion.nearestPath?.pathId;
    final stopId = suggestion.nearestStop?.stopId;
    await controller.recordRouteSelection(
      provider: suggestion.profile.provider,
      routeKey: suggestion.profile.routeKey,
      routeName: suggestion.profile.routeName,
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(
          routeKey: suggestion.profile.routeKey,
          provider: suggestion.profile.provider,
          initialPathId: pathId,
          initialStopId: stopId,
        ),
      ),
    );
  }

  Future<void> _openNearbyFallback(_NearbyFallbackData nearby) async {
    final controller = widget.controller;
    await controller.recordRouteSelection(
      provider: controller.settings.provider,
      routeKey: nearby.result.route.routeKey,
      routeName: nearby.result.route.routeName,
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(
          routeKey: nearby.result.route.routeKey,
          provider: controller.settings.provider,
          initialPathId: nearby.result.stop.pathId,
          initialStopId: nearby.result.stop.stopId,
        ),
      ),
    );
  }

  StopInfo? _findStopInDetail(
    RouteDetailData detail, {
    required int pathId,
    required int stopId,
  }) {
    final stops = detail.stopsByPath[pathId] ?? const <StopInfo>[];
    for (final stop in stops) {
      if (stop.stopId == stopId) {
        return stop;
      }
    }
    return null;
  }

  PathInfo? _findPath(RouteDetailData detail, int pathId) {
    for (final path in detail.paths) {
      if (path.pathId == pathId) {
        return path;
      }
    }
    return null;
  }

  // ignore: unused_element
  Widget _buildDisabledState(BuildContext context) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: '根據你在不同時段最常點開的路線，主動推薦現在最可能要查的那一條。',
      trailing: IconButton(
        tooltip: '設定',
        onPressed: _openSettings,
        icon: const Icon(Icons.tune_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '這個功能目前已關閉。開啟後，YABus 會學習你在不同時段最常點開的路線，並在首頁直接推薦。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_suggest_rounded),
            label: const Text('前往設定'),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedDatabaseState(BuildContext context) {
    return const _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: '根據你平常點開路線的時間點，推薦你現在最可能要看的路線。',
      child: Text('請先下載本地資料庫。下載完成後，這張卡片才會開始學習你的使用習慣並顯示附近站牌到站時間。'),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: '根據你平常點開路線的時間點，推薦你現在最可能要看的路線。',
      trailing: IconButton(
        tooltip: '重新整理',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '再多打開幾次常用路線，尤其是在你平常會查車的時段。至少累積幾次實際開啟後，這裡才會開始穩定推薦；如果有定位資料，也會優先嘗試帶你看最近站點。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Chip(
                avatar: const Icon(Icons.schedule_rounded),
                label: Text(
                  '已學習 ${widget.controller.routeUsageProfiles.length} 條路線',
                ),
              ),
              Chip(
                avatar: const Icon(Icons.storage_rounded),
                label: Text(widget.controller.settings.provider.label),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTile({
    required BuildContext context,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSuggestionState(
    BuildContext context,
    SmartRouteSuggestion suggestion,
  ) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final nearestStop = suggestion.nearestStop;
    final preferredHourLabel = suggestion.profile.preferredHour
        .toString()
        .padLeft(2, '0');

    return _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: suggestion.reason,
      trailing: IconButton(
        tooltip: '重新整理',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: _buildRouteTile(
        context: context,
        onTap: () => _openSuggestion(suggestion),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.profile.routeName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '你最常在 $preferredHourLabel:00 左右點開這條路線，累計 ${suggestion.profile.totalInteractions} 次。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (suggestion.nearestPath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '方向：${suggestion.nearestPath!.name}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (nearestStop != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.gps_fixed_rounded, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nearestStop.stopName,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                suggestion.distanceMeters == null
                                    ? '目前沒有位置資料，先用你的習慣推薦這條路線。'
                                    : '距離你約 ${formatDistance(suggestion.distanceMeters!)}。',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '目前沒有位置資料，先只根據你的使用習慣推薦這條路線。',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (nearestStop != null)
                  EtaBadge(
                    stop: nearestStop,
                    alwaysShowSeconds: controller.settings.alwaysShowSeconds,
                    size: 64,
                  ),
                const SizedBox(height: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyFallbackState(
    BuildContext context,
    _NearbyFallbackData nearby,
  ) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final stop = nearby.liveStop ?? nearby.result.stop;

    return _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: '這個時段還沒有學到明確偏好，先帶你看最近的站點。',
      trailing: IconButton(
        tooltip: '重新整理',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: _buildRouteTile(
        context: context,
        onTap: () => _openNearbyFallback(nearby),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nearby.result.route.routeName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '最近站點：${nearby.result.stop.stopName}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '距離你約 ${formatDistance(nearby.result.distanceMeters)}。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (nearby.path != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '方向：${nearby.path!.name}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                EtaBadge(
                  stop: stop,
                  alwaysShowSeconds: controller.settings.alwaysShowSeconds,
                  size: 64,
                ),
                const SizedBox(height: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.settings.enableSmartRecommendations) {
      return const SizedBox.shrink();
    }
    if (!controller.databaseReady) {
      return _buildNeedDatabaseState(context);
    }

    return FutureBuilder<_SmartCardData?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _SmartRecommendationShell(
            title: '智慧推薦',
            subtitle: '正在整理你這個時段最常看的路線...',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          return _SmartRecommendationShell(
            title: '智慧推薦',
            subtitle: '這個時段原本有學到偏好，但這次整理失敗了。',
            trailing: IconButton(
              tooltip: '重試',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            child: Text('推薦整理失敗：${snapshot.error}'),
          );
        }

        final cardData = snapshot.data;
        if (cardData == null) {
          return _buildEmptyState(context);
        }
        if (cardData.suggestion case final suggestion?) {
          return _buildSuggestionState(context, suggestion);
        }
        if (cardData.nearby case final nearby?) {
          return _buildNearbyFallbackState(context, nearby);
        }
        return _buildEmptyState(context);
      },
    );
  }
}

class _SmartRecommendationShell extends StatelessWidget {
  const _SmartRecommendationShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(subtitle, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
