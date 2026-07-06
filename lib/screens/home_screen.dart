import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/app_routes.dart';
import '../core/app_controller.dart';
import '../core/friendly_error.dart';
import '../core/models.dart';
import '../core/pwa_install_service.dart';
import '../widgets/eta_badge.dart';
import '../widgets/transit_station_map.dart';
import '../widgets/transit_drawer.dart';
import 'adaptive_settings_presenter.dart';
import 'database_settings_screen.dart';
import 'favorites_screen.dart';
import 'nearby_screen.dart';
import 'route_detail_navigation.dart';
import 'search_screen.dart';
import '../widgets/ad_banner_widget.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onModeChanged, super.key});

  static const _desktopSidebarBreakpoint = 1100.0;
  static const _desktopSidebarWidth = 450.0;

  final ValueChanged<TransitMode> onModeChanged;

  Future<void> _openDatabaseSettings(
    BuildContext context,
    AppController controller,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'database_settings'),
        builder: (_) => const DatabaseSettingsScreen(),
      ),
    );
  }

  Widget _buildFeatureList(BuildContext context, AppController controller) {
    final compactMode = _useCompactHomeMode(context, controller.settings);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (controller.settings.enableSmartRecommendations) ...[
          _SmartRecommendationCard(
            controller: controller,
            compactMode: compactMode,
          ),
          const SizedBox(height: 16),
        ],
        _buildSearchFeatureCard(context, compactMode: compactMode),
        const SizedBox(height: 12),
        _buildFavoritesFeatureCard(context, compactMode: compactMode),
        const SizedBox(height: 12),
        _buildNearbyFeatureCard(context, compactMode: compactMode),
        const SizedBox(height: 16),
        const AdBannerWidget(),
      ],
    );
  }

  Widget _buildDesktopMainPanel(
    BuildContext context,
    AppController controller,
  ) {
    final compactMode = _useCompactHomeMode(context, controller.settings);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 12, 32),
      children: [
        SizedBox(
          height: 212,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildSearchFeatureCard(
                  context,
                  bigIcon: true,
                  compactMode: compactMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFavoritesFeatureCard(
                  context,
                  bigIcon: true,
                  compactMode: compactMode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildNearbyFeatureCard(
                  context,
                  bigIcon: true,
                  compactMode: compactMode,
                ),
              ),
            ],
          ),
        ),
        if (controller.settings.enableSmartRecommendations) ...[
          const SizedBox(height: 16),
          _SmartRecommendationCard(
            controller: controller,
            compactMode: compactMode,
          ),
        ],
        const SizedBox(height: 16),
        const AdBannerWidget(),
      ],
    );
  }

  Widget _buildSearchFeatureCard(
    BuildContext context, {
    bool bigIcon = false,
    bool compactMode = false,
  }) {
    return _FeatureCard(
      icon: Icons.search_rounded,
      title: '搜尋路線',
      subtitle: '輸入公車號碼、路線名稱或客運路線，直接看即時到站資訊。',
      bigIcon: bigIcon,
      compact: compactMode,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'search'),
            builder: (_) => const SearchScreen(),
          ),
        );
      },
    );
  }

  Widget _buildFavoritesFeatureCard(
    BuildContext context, {
    bool bigIcon = false,
    bool compactMode = false,
  }) {
    return _FeatureCard(
      icon: Icons.favorite_outline_rounded,
      title: '我的最愛',
      subtitle: '整理常用站牌與群組，快速跳回指定站點。',
      bigIcon: bigIcon,
      compact: compactMode,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'favorites'),
            builder: (_) => const FavoritesScreen(),
          ),
        );
      },
    );
  }

  Widget _buildNearbyFeatureCard(
    BuildContext context, {
    bool bigIcon = false,
    bool compactMode = false,
  }) {
    return _FeatureCard(
      icon: Icons.near_me_outlined,
      title: '附近站牌',
      subtitle: '依照你目前位置找附近的公車站牌。',
      bigIcon: bigIcon,
      compact: compactMode,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'nearby'),
            builder: (_) => const NearbyScreen(),
          ),
        );
      },
    );
  }

  Widget _buildDesktopSidebar(BuildContext context, AppController controller) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 32, 24, 32),
      children: [
        _DesktopNearbyMapPanel(controller: controller),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '總覽',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // const SizedBox(height: 6),
                // Text(
                //   '左邊保留主要操作，右邊集中顯示推薦、設定與狀態摘要。',
                //   style: theme.textTheme.bodyMedium,
                // ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (kIsWeb)
                      const Chip(
                        avatar: Icon(Icons.public_rounded),
                        label: Text('(*/ω＼*)'),
                      )
                    else
                      Chip(
                        avatar: const Icon(Icons.location_on_outlined),
                        label: Text(controller.settings.provider.label),
                      ),
                    Chip(
                      avatar: const Icon(Icons.layers_outlined),
                      label: Text(
                        '已選 ${controller.selectedProviders.length} 個地區',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => openAdaptiveSettingsScreen(context),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('開啟設定'),
                    style: FilledButton.styleFrom(
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _openDatabaseSettings(context, controller),
                      icon: const Icon(Icons.storage_rounded),
                      label: const Text('資料庫與下載'),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final hasBusBackgroundImage = controller.settings.pageBackgroundImagePaths
        .containsKey('bus');
    final isWideLayout =
        MediaQuery.sizeOf(context).width >= _desktopSidebarBreakpoint;

    return Scaffold(
      backgroundColor: hasBusBackgroundImage ? Colors.transparent : null,
      appBar: AppBar(
        title: const Text('YABus'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          if (kIsWeb) const _WebPwaInstallButton(),
          if (!kIsWeb)
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
            tooltip: '公告',
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoutes.announcements);
            },
            icon:
                controller.announcementsLoading &&
                    controller.announcements.isEmpty
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: controller.hasUnreadAnnouncements,
                    child: const Icon(Icons.campaign_outlined),
                  ),
          ),
          IconButton(
            onPressed: () => openAdaptiveSettingsScreen(context),
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
          gradient: _shouldShowGradient(controller)
              ? LinearGradient(
                  colors: [
                    colorScheme.primaryContainer.withValues(
                      alpha: controller.settings.homeBackgroundOpacity,
                    ),
                    Theme.of(context).scaffoldBackgroundColor,
                    colorScheme.secondaryContainer.withValues(
                      alpha: controller.settings.homeBackgroundOpacity * 0.38,
                    ),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: isWideLayout
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildDesktopMainPanel(context, controller)),
                  SizedBox(
                    width: _desktopSidebarWidth,
                    child: _buildDesktopSidebar(context, controller),
                  ),
                ],
              )
            : _buildFeatureList(context, controller),
      ),
    );
  }

  /// In AMOLED dark mode, skip the gradient so the pure-black background shows.
  /// Also skip gradient when a background image is set for the bus page.
  bool _shouldShowGradient(AppController controller) {
    final settings = controller.settings;
    if (settings.useAmoledDark && settings.themeMode != ThemeMode.light) {
      return false;
    }
    if (settings.pageBackgroundImagePaths.containsKey('bus')) {
      return false;
    }
    return settings.homeBackgroundOpacity > 0;
  }
}

bool _useCompactHomeMode(BuildContext context, AppSettings settings) {
  final isDesktopApp =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
  return isDesktopApp ||
      settings.enableCompactMode ||
      MediaQuery.sizeOf(context).width >= HomeScreen._desktopSidebarBreakpoint;
}

class _WebPwaInstallButton extends StatelessWidget {
  const _WebPwaInstallButton();

  Future<void> _handlePressed(BuildContext context) async {
    final shouldInstall = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('要安裝成應用程式嗎？'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('把 YABus 安裝成應用程式，之後就能像一般應用程式一樣開啟。'),
              SizedBox(height: 12),
              Text(
                '功能會比原版應用程式少就是了',
                style: TextStyle(decoration: TextDecoration.lineThrough),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('先不要'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('當然好啊 ＼(^o^)／'),
            ),
          ],
        );
      },
    );
    if (shouldInstall != true || !context.mounted) {
      return;
    }

    final outcome = await pwaInstallService.promptInstall();
    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (outcome) {
      case PwaInstallPromptOutcome.accepted:
        messenger?.showSnackBar(const SnackBar(content: Text('已送出安裝要求。')));
      case PwaInstallPromptOutcome.dismissed:
        messenger?.showSnackBar(const SnackBar(content: Text('已取消安裝。')));
      case PwaInstallPromptOutcome.unavailable:
        messenger?.showSnackBar(
          const SnackBar(content: Text('這個裝置目前無法顯示安裝提示。')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PwaInstallState>(
      valueListenable: pwaInstallService.stateListenable,
      builder: (context, state, _) {
        if (!state.shouldShowInstallAction) {
          return const SizedBox.shrink();
        }
        return IconButton(
          tooltip: '安裝 App',
          onPressed: () => _handlePressed(context),
          icon: const Icon(Icons.download_rounded),
        );
      },
    );
  }
}

class _SmartRecommendationCard extends StatefulWidget {
  const _SmartRecommendationCard({
    required this.controller,
    required this.compactMode,
  });

  final AppController controller;
  final bool compactMode;

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
    if (!controller.settings.enableSmartRecommendations) {
      return null;
    }

    // Smart route suggestions require local database for usage profiles.
    // On web (or when DB not ready), skip to nearby fallback if location is available.
    if (controller.databaseReady && controller.routeUsageProfiles.isNotEmpty) {
      final position = await _resolvePosition();
      final suggestion = await controller.getSmartRouteSuggestion(
        position: position,
      );
      if (suggestion != null) {
        return _SmartCardData.recommended(suggestion);
      }
    }

    // Nearby fallback via API — works on both native and web.
    final position = await _resolvePosition();
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
      final routeProvider = busProviderFromString(nearest.route.sourceProvider);
      final detail = await controller.getRouteDetail(
        nearest.route.routeKey,
        provider: routeProvider,
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
    await openAdaptiveSettingsScreen(context);
  }

  Future<void> _openSuggestion(SmartRouteSuggestion suggestion) async {
    final controller = widget.controller;
    final favorite = suggestion.favorite;
    final pathId = suggestion.recommendedPath?.pathId;
    final stopId = suggestion.recommendedStop?.stopId;
    await controller.recordRouteSelection(
      provider: suggestion.profile.provider,
      routeKey: suggestion.profile.routeKey,
      routeName: suggestion.profile.routeName,
      favorite: favorite,
      source: 'smart_suggestion',
    );
    if (!mounted) {
      return;
    }
    await openRouteDetailPage(
      context,
      routeKey: suggestion.profile.routeKey,
      provider: suggestion.profile.provider,
      routeIdHint:
          suggestion.detail?.route.routeId ?? suggestion.favorite?.routeId,
      routeNameHint:
          suggestion.detail?.route.routeName ?? suggestion.profile.routeName,
      initialPathId: pathId,
      initialStopId: stopId,
      initialDestinationPathId: favorite?.destinationPathId,
      initialDestinationStopId: favorite?.destinationStopId,
    );
  }

  Future<void> _openNearbyFallback(_NearbyFallbackData nearby) async {
    final controller = widget.controller;
    final routeProvider = busProviderFromString(
      nearby.result.route.sourceProvider,
    );
    await controller.recordRouteSelection(
      provider: routeProvider,
      routeKey: nearby.result.route.routeKey,
      routeName: nearby.result.route.routeName,
      source: 'nearby_fallback',
    );
    if (!mounted) {
      return;
    }
    await openRouteDetailPage(
      context,
      routeKey: nearby.result.route.routeKey,
      provider: routeProvider,
      routeIdHint: nearby.result.route.routeId,
      routeNameHint: nearby.result.route.routeName,
      initialPathId: nearby.result.stop.pathId,
      initialStopId: nearby.result.stop.stopId,
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

  // ignore: unused_element
  Widget _buildNeedDatabaseState(BuildContext context) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      subtitle: '根據你平常點開路線的時間點，推薦你現在最可能要看的路線。',
      child: Text('請先下載本地資料庫。下載完成後，這張卡片才會開始學習你的使用習慣並顯示附近站牌到站時間。'),
    );
  }

  // ignore: unused_element
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
      color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainerHighest,
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
    final recommendedStop = suggestion.recommendedStop;
    final favorite = suggestion.favorite;
    final destinationLabel =
        favorite?.destinationStopName?.trim().isNotEmpty == true
        ? favorite!.destinationStopName!.trim()
        : favorite?.destinationStopId == null
        ? null
        : '目的地站牌 ${favorite!.destinationStopId}';
    final showDistance =
        suggestion.favoriteStop == null && suggestion.distanceMeters != null;
    // ignore: unused_local_variable
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
          crossAxisAlignment: widget.compactMode
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
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
                  // const SizedBox(height: 6),
                  // // Text(
                  // //   '你最常在 $preferredHourLabel:00 左右點開這條路線，累計 ${suggestion.profile.totalInteractions} 次。',
                  // //   style: theme.textTheme.bodyMedium,
                  // // ),
                  // Text(
                  //   '根據使用習慣。',
                  //   style: theme.textTheme.bodyMedium,
                  // ),
                  // if (suggestion.nearestPath != null) ...[
                  //   const SizedBox(height: 8),
                  //   Text(
                  //     '方向：${suggestion.nearestPath!.name}',
                  //     style: theme.textTheme.bodySmall,
                  //   ),
                  // ],
                  if (recommendedStop != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          favorite == null
                              ? Icons.gps_fixed_rounded
                              : Icons.favorite_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recommendedStop.stopName,
                                style: theme.textTheme.titleMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (destinationLabel != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '目的地：$destinationLabel',
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (showDistance) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '距離你約 ${formatDistance(suggestion.distanceMeters!)}。',
                                  style: theme.textTheme.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else if (destinationLabel != null)
                    Text(
                      '目的地：$destinationLabel',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (recommendedStop != null)
                  EtaBadge(
                    stop: recommendedStop,
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
      subtitle: '最近的站點。',
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
                    nearby.result.stop.stopName,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '距離你約 ${formatDistance(nearby.result.distanceMeters)}。',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (nearby.path != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '方向：${nearby.path!.name}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

    return FutureBuilder<_SmartCardData?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _SmartRecommendationShell(
            title: '智慧推薦',
            subtitle: '正在整理你這個時段最常看的路線...',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (snapshot.hasError) {
          // return _SmartRecommendationShell(
          //   title: '智慧推薦',
          //   subtitle: '這個時段原本有學到偏好，但這次整理失敗了。',
          //   trailing: IconButton(
          //     tooltip: '重試',
          //     onPressed: _refresh,
          //     icon: const Icon(Icons.refresh_rounded),
          //   ),
          //   child: Text('推薦整理失敗：${snapshot.error}'),
          // );
          return const SizedBox.shrink();
        }

        final cardData = snapshot.data;
        if (cardData == null) {
          // return _buildEmptyState(context);
          return const SizedBox.shrink();
        }
        if (cardData.suggestion case final suggestion?) {
          return _buildSuggestionState(context, suggestion);
        }
        if (cardData.nearby case final nearby?) {
          return _buildNearbyFallbackState(context, nearby);
        }
        // return _buildEmptyState(context);
        return const SizedBox.shrink();
      },
    );
  }
}

class _DesktopNearbyMapPanel extends StatefulWidget {
  const _DesktopNearbyMapPanel({required this.controller});

  final AppController controller;

  @override
  State<_DesktopNearbyMapPanel> createState() => _DesktopNearbyMapPanelState();
}

class _DesktopNearbyMapPanelState extends State<_DesktopNearbyMapPanel> {
  bool _loading = true;
  String? _error;
  List<NearbyStopResult> _results = const [];
  String? _selectedPointId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadNearby());
    });
  }

  String _pointIdForResult(NearbyStopResult result) {
    return [
      result.route.sourceProvider,
      result.route.routeKey,
      result.stop.pathId,
      result.stop.stopId,
    ].join(':');
  }

  NearbyStopResult? get _selectedResult {
    final selectedPointId = _selectedPointId;
    if (selectedPointId == null) {
      return _results.isEmpty ? null : _results.first;
    }
    for (final result in _results) {
      if (_pointIdForResult(result) == selectedPointId) {
        return result;
      }
    }
    return _results.isEmpty ? null : _results.first;
  }

  List<TransitMapPoint> get _mapPoints => _results
      .map((result) {
        final provider = busProviderFromString(result.route.sourceProvider);
        return TransitMapPoint(
          id: _pointIdForResult(result),
          label: result.stop.stopName,
          subtitle: '${provider.label} · ${result.route.routeName}',
          badge: formatDistance(result.distanceMeters),
          latitude: result.stop.lat,
          longitude: result.stop.lon,
        );
      })
      .toList(growable: false);

  Future<void> _loadNearby() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      final results = await widget.controller.getNearbyStops(
        latitude: position.latitude,
        longitude: position.longitude,
        limit: 12,
      );
      if (!mounted) {
        return;
      }

      String? nextSelectedPointId = _selectedPointId;
      if (results.isEmpty ||
          !results.any(
            (result) => _pointIdForResult(result) == nextSelectedPointId,
          )) {
        nextSelectedPointId = results.isEmpty
            ? null
            : _pointIdForResult(results.first);
      }

      setState(() {
        _results = results;
        _selectedPointId = nextSelectedPointId;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const [];
        _selectedPointId = null;
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

  Future<void> _openSelectedResult() async {
    final selected = _selectedResult;
    if (selected == null) {
      return;
    }

    final routeProvider = busProviderFromString(selected.route.sourceProvider);
    await widget.controller.recordRouteSelection(
      provider: routeProvider,
      routeKey: selected.route.routeKey,
      routeName: selected.route.routeName,
      source: 'home_nearby_map',
    );
    if (!mounted) {
      return;
    }
    await openRouteDetailPage(
      context,
      routeKey: selected.route.routeKey,
      provider: routeProvider,
      routeIdHint: selected.route.routeId,
      routeNameHint: selected.route.routeName,
      initialPathId: selected.stop.pathId,
      initialStopId: selected.stop.stopId,
    );
  }

  Future<void> _openNearbyScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'nearby'),
        builder: (_) => const NearbyScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedResult;
    final compactMode = _useCompactHomeMode(
      context,
      widget.controller.settings,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('附近地圖', style: theme.textTheme.headlineSmall),
                      if (!compactMode) ...[
                        const SizedBox(height: 6),
                        Text('今天想去哪搭公車？', style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '重整附近站牌',
                  onPressed: _loading ? null : _loadNearby,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const SizedBox(
                height: 320,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _DesktopNearbyMessage(
                message: _error!,
                primaryLabel: '重試',
                onPrimaryPressed: _loadNearby,
                secondaryLabel: '附近站牌',
                onSecondaryPressed: _openNearbyScreen,
              )
            else if (_mapPoints.isEmpty)
              _DesktopNearbyMessage(
                message: '附近暫時沒有可顯示的站牌。',
                primaryLabel: '附近站牌',
                onPrimaryPressed: _openNearbyScreen,
              )
            else ...[
              TransitStationMap(
                points: _mapPoints,
                selectedPointId: _selectedPointId,
                onPointSelected: (point) {
                  setState(() {
                    _selectedPointId = point.id;
                  });
                },
                height: 320,
                emptyLabel: '目前沒有可顯示的站點位置。',
              ),
              const SizedBox(height: 12),
              if (selected != null)
                Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openSelectedResult,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
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
                              formatDistance(selected.distanceMeters),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selected.stop.stopName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${busProviderFromString(selected.route.sourceProvider).label} · ${selected.route.routeName}',
                                  style: theme.textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.chevron_right_rounded),
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
  }
}

class _DesktopNearbyMessage extends StatelessWidget {
  const _DesktopNearbyMessage({
    required this.message,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  final String message;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: onPrimaryPressed,
                    child: Text(primaryLabel),
                  ),
                  if (secondaryLabel != null && onSecondaryPressed != null)
                    OutlinedButton(
                      onPressed: onSecondaryPressed,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
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
    final hasSubtitle = subtitle.trim().isNotEmpty;

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
                      if (hasSubtitle) ...[
                        const SizedBox(height: 6),
                        Text(subtitle, style: theme.textTheme.bodyMedium),
                      ],
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
    required this.bigIcon,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool bigIcon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final iconTile = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: colorScheme.onPrimaryContainer),
    );
    final titleText = Text(
      title,
      style: theme.textTheme.titleMedium,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final showSubtitle = !compact && subtitle.trim().isNotEmpty;
    final showBigIconSubtitle = subtitle.trim().isNotEmpty;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            bigIcon ? 16 : 18,
            18,
            bigIcon ? 16 : 18,
          ),
          child: bigIcon
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: 26,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showBigIconSubtitle) ...[
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: showSubtitle
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    iconTile,
                    const SizedBox(width: 16),
                    Expanded(
                      child: showSubtitle
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                titleText,
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: theme.textTheme.bodyMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            )
                          : titleText,
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
        ),
      ),
    );
  }
}
