import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/eta_badge.dart';
import 'favorites_screen.dart';
import 'nearby_screen.dart';
import 'route_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'tracked_buses_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _showDatabaseSheet(
    BuildContext context,
    AppController controller,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '資料庫',
                  style: Theme.of(sheetContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('目前資料來源：${controller.settings.provider.label}'),
                const SizedBox(height: 4),
                FutureBuilder<int?>(
                  future: controller.currentProviderLocalVersion(),
                  builder: (context, snapshot) {
                    final version = snapshot.data;
                    final text = version == null || version == 0
                        ? '本機尚未下載資料庫'
                        : '本機資料庫版本：$version';
                    return Text(text);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  controller.databaseReady
                      ? '本機資料庫已可用。你可以在這裡重新下載，或先檢查是否有更新版本。'
                      : '第一次使用需要先下載 ${controller.settings.provider.label} 的 sqlite 資料庫，之後搜尋、路線詳情與智慧推薦才會完整可用。',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: controller.downloadingDatabase
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.of(sheetContext).pop();
                              try {
                                await controller.downloadCurrentProviderDatabase();
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('資料庫下載完成。'),
                                  ),
                                );
                              } catch (error) {
                                if (!context.mounted) {
                                  return;
                                }
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '資料庫下載失敗：$error',
                                    ),
                                  ),
                                );
                              }
                            },
                        icon: controller.downloadingDatabase
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              controller.databaseReady
                                  ? Icons.download_for_offline_outlined
                                  : Icons.cloud_download_outlined,
                            ),
                      label: Text(
                        controller.downloadingDatabase
                            ? '下載中...'
                            : (controller.databaseReady
                                  ? '重新下載'
                                  : '下載資料庫'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.of(sheetContext).pop();
                        try {
                          final updates = await controller.checkDatabaseUpdates();
                          if (!context.mounted) {
                            return;
                          }
                          final lines = updates.entries
                              .map(
                                (entry) => entry.value == null
                                    ? '${entry.key.label}：已是最新版本'
                                    : '${entry.key.label}：可更新到 ${entry.value}',
                              )
                              .join('\n');
                          messenger.showSnackBar(
                            SnackBar(content: Text(lines)),
                          );
                        } catch (error) {
                          if (!context.mounted) {
                            return;
                          }
                          messenger.showSnackBar(
                            SnackBar(content: Text('檢查資料庫更新失敗：$error')),
                          );
                        }
                      },
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('檢查更新'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('YABus'),
        actions: [
          IconButton(
            tooltip: '資料庫',
            onPressed: () => _showDatabaseSheet(context, controller),
            icon: controller.downloadingDatabase
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    controller.databaseReady
                        ? Icons.storage_rounded
                        : Icons.cloud_download_outlined,
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
            _SmartRecommendationCard(controller: controller),
            const SizedBox(height: 16),
            _FeatureCard(
              icon: Icons.search_rounded,
              title: '搜尋路線',
              subtitle: '輸入公車號碼或名稱，直接看即時到站資訊。',
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
              icon: Icons.directions_bus_filled_outlined,
              title: '追蹤公車',
              subtitle: controller.trackedBuses.isEmpty
                  ? '在路線頁點車牌後，可以把公車加入追蹤清單。'
                  : '目前追蹤 ${controller.trackedBuses.length} 輛公車，查看最新位置與離線狀態。',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TrackedBusesScreen(),
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

class _SmartRecommendationCardState extends State<_SmartRecommendationCard> {
  Future<SmartRouteSuggestion?>? _future;
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

  Future<SmartRouteSuggestion?> _loadSuggestion() async {
    final controller = widget.controller;
    if (!controller.settings.enableSmartRecommendations ||
        !controller.databaseReady ||
        controller.routeUsageProfiles.isEmpty) {
      return null;
    }

    final position = await _resolvePosition();
    return controller.getSmartRouteSuggestion(position: position);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _openSuggestion(SmartRouteSuggestion suggestion) async {
    final pathId = suggestion.nearestPath?.pathId;
    final stopId = suggestion.nearestStop?.stopId;
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

  Widget _buildDisabledState(BuildContext context) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: '根據你在不同時段最常打開的路線，主動推薦現在最可能要查的那一條。',
      trailing: IconButton(
        tooltip: '設定',
        onPressed: _openSettings,
        icon: const Icon(Icons.tune_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '這個功能目前已關閉。開啟後，YABus 會學習你在不同時段最常查看的路線，並在首頁直接推薦。',
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
      subtitle: '根據你平常打開路線的時間點，推薦你現在最可能要看的路線。',
      child: Text(
        '請先下載本地資料庫。下載完成後，這張卡片才會開始學習你的使用習慣並顯示附近站牌到站時間。',
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: '根據你平常打開路線的時間點，推薦你現在最可能要看的路線。',
      trailing: IconButton(
        tooltip: '重新整理',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '再多打開幾次常用路線，尤其是在你平常會查車的時段，這裡就會慢慢學到你的習慣。',
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
                    Text(
                      suggestion.profile.routeName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '你最常在 $preferredHourLabel:00 左右打開這條路線，累計 ${suggestion.profile.totalOpens} 次。',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (suggestion.nearestPath != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '方向：${suggestion.nearestPath!.name}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (nearestStop != null)
                EtaBadge(
                  stop: nearestStop,
                  alwaysShowSeconds: controller.settings.alwaysShowSeconds,
                  size: 64,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (nearestStop != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed_rounded),
                  const SizedBox(width: 12),
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
                              ? '目前沒有位置資料，先只用習慣推薦這條路線。'
                              : '距離你約 ${formatDistance(suggestion.distanceMeters!)}。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              '目前沒有位置資料，先只根據你的使用習慣推薦這條路線。',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openSuggestion(suggestion),
            icon: const Icon(Icons.directions_bus_rounded),
            label: const Text('查看這條路線'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.settings.enableSmartRecommendations) {
      return _buildDisabledState(context);
    }
    if (!controller.databaseReady) {
      return _buildNeedDatabaseState(context);
    }
    if (controller.routeUsageProfiles.isEmpty) {
      return _buildEmptyState(context);
    }

    return FutureBuilder<SmartRouteSuggestion?>(
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

        final suggestion = snapshot.data;
        if (suggestion == null) {
          return _buildEmptyState(context);
        }
        return _buildSuggestionState(context, suggestion);
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
