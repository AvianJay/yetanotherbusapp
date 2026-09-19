import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/app_routes.dart';
import '../core/app_controller.dart';
import '../core/friendly_error.dart';
import '../core/models.dart';
import '../core/pwa_install_service.dart';
import '../core/route_direction_label.dart';
import '../core/smart_route_service.dart';
import '../widgets/eta_badge.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/transit_station_map.dart';
import 'adaptive_settings_presenter.dart';
import 'bus_map_screen.dart';
import 'database_settings_screen.dart';
import 'favorites_screen.dart';
import 'nearby_screen.dart';
import 'route_detail_navigation.dart';
import 'search_screen.dart';
import '../widgets/ad_banner_widget.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _desktopSidebarBreakpoint = 1100.0;
  static const _desktopSidebarWidth = 450.0;

  Future<void> _openDatabaseSettings(
    BuildContext context,
    AppController controller,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.databaseSettings),
        builder: (_) => const DatabaseSettingsScreen(),
      ),
    );
  }

  Widget _buildFeatureList(
    BuildContext context,
    AppController controller, {
    required bool compactMode,
  }) {
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          if (controller.settings.enableSmartRecommendations) ...[
            _SmartRecommendationCard(
              controller: controller,
              compactMode: compactMode,
            ),
            const SizedBox(height: 8),
          ],
          _buildSearchFeatureCard(context, compactMode: compactMode),
          const SizedBox(height: 8),
          _buildFavoritesFeatureCard(context, compactMode: compactMode),
          const SizedBox(height: 8),
          _buildNearbyFeatureCard(context, compactMode: compactMode),
          const SizedBox(height: 8),
          _buildBusMapFeatureCard(context, compactMode: compactMode),
        ],
      ),
    );
  }

  Widget _buildDesktopMainPanel(
    BuildContext context,
    AppController controller, {
    required bool compactMode,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 12, 32),
      children: [
        SizedBox(
          height: 196,
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
              const SizedBox(width: 16),
              Expanded(
                child: _buildFavoritesFeatureCard(
                  context,
                  bigIcon: true,
                  compactMode: compactMode,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildNearbyFeatureCard(
                  context,
                  bigIcon: true,
                  compactMode: compactMode,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildBusMapFeatureCard(
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
            maxSuggestions: 3,
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
            settings: const RouteSettings(name: AppRoutes.search),
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
            settings: const RouteSettings(name: AppRoutes.favorites),
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
            settings: const RouteSettings(name: AppRoutes.nearby),
            builder: (_) => const NearbyScreen(),
          ),
        );
      },
    );
  }

  Widget _buildBusMapFeatureCard(
    BuildContext context, {
    bool bigIcon = false,
    bool compactMode = false,
  }) {
    return _FeatureCard(
      icon: Icons.map_outlined,
      title: '全公車地圖',
      subtitle: '看整個縣市的公車現在開到哪，點一輛就能看它的路線與站牌。',
      bigIcon: bigIcon,
      compact: compactMode,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'bus_map'),
            builder: (_) => const BusMapScreen(),
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
                const SizedBox(height: 20),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => openAdaptiveSettingsScreen(context),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('開啓設定'),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _desktopSidebarBreakpoint;
    final hasBusBackgroundImage = hasBackgroundImageForPage(
      controller.settings,
      pageKey: 'bus',
    );
    return Scaffold(
      backgroundColor: hasBusBackgroundImage ? Colors.transparent : null,
      appBar: AppBar(
        title: Transform.translate(
          offset: Offset(0, isDesktop ? 4 : 0),
          child: SvgPicture.asset(
            'assets/branding/YABus-black.svg',
            width: isDesktop ? 164 : 96,
            height: isDesktop ? 36 : 21,
            semanticsLabel: 'YABus',
            colorFilter: ColorFilter.mode(
              colorScheme.onSurface,
              BlendMode.srcIn,
            ),
          ),
        ),
        titleSpacing: 24,
        automaticallyImplyLeading: false,
        actionsPadding: const EdgeInsets.only(right: 16),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideLayout =
              constraints.maxWidth >= _desktopSidebarBreakpoint;
          final compactMode = _useCompactHomeMode(
            controller.settings,
            constraints.maxWidth,
          );
          return Container(
            decoration: BoxDecoration(
              color: _shouldShowHomeBackground(controller)
                  ? colorScheme.primaryContainer.withValues(
                      alpha: controller.settings.homeBackgroundOpacity,
                    )
                  : null,
            ),
            child: isWideLayout
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _buildDesktopMainPanel(
                          context,
                          controller,
                          compactMode: compactMode,
                        ),
                      ),
                      SizedBox(
                        width: _desktopSidebarWidth,
                        child: _buildDesktopSidebar(context, controller),
                      ),
                    ],
                  )
                : _buildFeatureList(
                    context,
                    controller,
                    compactMode: compactMode,
                  ),
          );
        },
      ),
    );
  }

  /// AMOLED mode keeps the home page pure black.
  bool _shouldShowHomeBackground(AppController controller) {
    final settings = controller.settings;
    if (settings.useAmoledDark && settings.themeMode != ThemeMode.light) {
      return false;
    }
    return settings.homeBackgroundOpacity > 0;
  }
}

bool _useCompactHomeMode(AppSettings settings, double availableWidth) {
  final isDesktopApp =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
  return isDesktopApp ||
      settings.enableCompactMode ||
      availableWidth >= HomeScreen._desktopSidebarBreakpoint;
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
              Text('把 YABus 安裝成應用程式，之後就能像一般應用程式一樣開啓。'),
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
    this.maxSuggestions = 1,
  });

  final AppController controller;
  final bool compactMode;
  final int maxSuggestions;

  @override
  State<_SmartRecommendationCard> createState() =>
      _SmartRecommendationCardState();
}

class _SmartCardData {
  const _SmartCardData.recommended(this.suggestions) : nearbyList = const [];

  const _SmartCardData.nearby(this.nearbyList) : suggestions = const [];

  final List<SmartRouteSuggestion> suggestions;
  final List<_NearbyFallbackData> nearbyList;
}

class _NearbyFallbackData {
  const _NearbyFallbackData({
    required this.result,
    required this.detail,
    required this.liveStop,
    this.path,
  });

  final NearbyStopResult result;
  final RouteDetailData detail;
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
        if (lastKnown != null) {
          return lastKnown;
        }
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 3),
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
    final positionFuture = _resolvePosition();
    Position? position;

    // Smart route suggestions require local database for usage profiles.
    // On web (or when DB not ready), skip to nearby fallback if location is available.
    if (controller.databaseReady && controller.routeUsageProfiles.isNotEmpty) {
      final baseSuggestions = await controller.getSmartRouteSuggestions(
        limit: widget.maxSuggestions,
      );
      if (baseSuggestions.isNotEmpty) {
        final allHaveFavoriteStops = baseSuggestions.every(
          (suggestion) => suggestion.favoriteStop != null,
        );
        if (!allHaveFavoriteStops) {
          position = await positionFuture.timeout(
            const Duration(milliseconds: 800),
            onTimeout: () => null,
          );
        }
        final suggestions = position == null
            ? baseSuggestions
            : baseSuggestions
                  .map((suggestion) {
                    final detail = suggestion.detail;
                    if (detail == null) {
                      return suggestion;
                    }
                    return SmartRouteService.buildSuggestion(
                      profile: suggestion.profile,
                      score: suggestion.score,
                      reason: suggestion.reason,
                      detail: detail,
                      favorite: suggestion.favorite,
                      position: position,
                    );
                  })
                  .toList(growable: false);
        return _SmartCardData.recommended(suggestions);
      }
    }

    // Nearby fallback via API — works on both native and web.
    position ??= await positionFuture;
    if (position == null) {
      return null;
    }

    try {
      final nearbyStops = await controller.getNearbyStops(
        latitude: position.latitude,
        longitude: position.longitude,
        limit: widget.maxSuggestions,
      );
      if (nearbyStops.isEmpty) {
        return null;
      }

      final nearbyList = await Future.wait(
        nearbyStops.take(widget.maxSuggestions).map((nearest) async {
          final routeProvider = busProviderFromString(
            nearest.route.sourceProvider,
          );
          final detail = await controller.getPrimaryRouteDetail(
            nearest.route.routeKey,
            provider: routeProvider,
            routeIdHint: nearest.route.routeId,
            routeNameHint: nearest.route.routeName,
          );
          final liveStop = _findStopInDetail(
            detail,
            pathId: nearest.stop.pathId,
            stopId: nearest.stop.stopId,
          );
          return _NearbyFallbackData(
            result: nearest,
            detail: detail,
            liveStop: liveStop,
            path: _findPath(detail, nearest.stop.pathId),
          );
        }),
      );
      return _SmartCardData.nearby(nearbyList);
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
    final detail = suggestion.detail;
    final routeId = detail?.route.routeId.trim() ?? '';
    final routeName = detail?.route.routeName ?? suggestion.profile.routeName;
    final initialAlertsFuture = routeId.isEmpty
        ? null
        : controller
              .getRouteAlerts(routeId)
              .catchError((_) => const <RouteAlert>[]);
    final initialCancelledDeparturesFuture =
        suggestion.profile.provider != BusProvider.txg
        ? null
        : controller.repository
              .fetchTaichungCancelledDepartures(
                routeId: routeId,
                routeName: routeName,
                date: DateTime.now(),
              )
              .catchError((_) => const <CancelledDeparture>[]);
    unawaited(() async {
      final autoFavorited = await controller.recordRouteSelection(
        provider: suggestion.profile.provider,
        routeKey: suggestion.profile.routeKey,
        routeName: suggestion.profile.routeName,
        favorite: favorite,
        source: 'smart_suggestion',
        pathId: pathId,
        stopId: stopId,
        stopName: suggestion.recommendedStop?.stopName,
      );
      if (mounted && autoFavorited != null) {
        showAutoFavoritedSnackBar(context, autoFavorited);
      }
    }());
    await openRouteDetailPage(
      context,
      routeKey: suggestion.profile.routeKey,
      provider: suggestion.profile.provider,
      routeIdHint: routeId.isEmpty ? suggestion.favorite?.routeId : routeId,
      routeNameHint: routeName,
      initialPathId: pathId,
      initialStopId: stopId,
      initialDestinationPathId: favorite?.destinationPathId,
      initialDestinationStopId: favorite?.destinationStopId,
      initialTopologyFuture: Future<RouteDetailData?>.value(detail),
      initialAlertsFuture: initialAlertsFuture,
      initialCancelledDeparturesFuture: initialCancelledDeparturesFuture,
    );
  }

  Future<void> _openNearbyFallback(_NearbyFallbackData nearby) async {
    final controller = widget.controller;
    final routeProvider = busProviderFromString(
      nearby.result.route.sourceProvider,
    );
    final routeId = nearby.result.route.routeId.trim();
    final initialAlertsFuture = routeId.isEmpty
        ? null
        : controller
              .getRouteAlerts(routeId)
              .catchError((_) => const <RouteAlert>[]);
    final initialCancelledDeparturesFuture = routeProvider != BusProvider.txg
        ? null
        : controller.repository
              .fetchTaichungCancelledDepartures(
                routeId: routeId,
                routeName: nearby.result.route.routeName,
                date: DateTime.now(),
              )
              .catchError((_) => const <CancelledDeparture>[]);
    unawaited(() async {
      final autoFavorited = await controller.recordRouteSelection(
        provider: routeProvider,
        routeKey: nearby.result.route.routeKey,
        routeName: nearby.result.route.routeName,
        source: 'nearby_fallback',
        pathId: nearby.result.stop.pathId,
        stopId: nearby.result.stop.stopId,
        stopName: nearby.result.stop.stopName,
      );
      if (mounted && autoFavorited != null) {
        showAutoFavoritedSnackBar(context, autoFavorited);
      }
    }());
    await openRouteDetailPage(
      context,
      routeKey: nearby.result.route.routeKey,
      provider: routeProvider,
      routeIdHint: nearby.result.route.routeId,
      routeNameHint: nearby.result.route.routeName,
      initialPathId: nearby.result.stop.pathId,
      initialStopId: nearby.result.stop.stopId,
      initialTopologyFuture: Future<RouteDetailData?>.value(nearby.detail),
      initialAlertsFuture: initialAlertsFuture,
      initialCancelledDeparturesFuture: initialCancelledDeparturesFuture,
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
      trailing: IconButton(
        tooltip: '設定',
        onPressed: _openSettings,
        icon: const Icon(Icons.tune_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '這個功能目前已關閉。開啓後，YABus 會學習你在不同時段最常點開的路線，並在首頁直接推薦。',
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
      child: Text('請先下載本地資料庫。下載完成後，這張卡片才會開始學習你的使用習慣並顯示附近站牌到站時間。'),
    );
  }

  // ignore: unused_element
  Widget _buildEmptyState(BuildContext context) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      trailing: IconButton(
        tooltip: '重新整理',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '再多打開幾次常用路線，尤其是在你平常會查車的時段。至少累積幾次實際開啓後，這裡才會開始穩定推薦；如果有定位資料，也會優先嘗試帶你看最近站點。',
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
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: child,
        ),
      ),
    );
  }

  /// ETA is the leading element when available. Route, stop and secondary
  /// details stay in one vertical text block so narrow phones do not overflow.
  Widget _buildSmartTileRow({
    required BuildContext context,
    required IconData leadingIcon,
    required String title,
    String? stopName,
    List<String> metadata = const [],
    Widget? etaBadge,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        etaBadge ??
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(leadingIcon, color: colorScheme.onPrimaryContainer),
            ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (stopName != null) ...[
                const SizedBox(height: 4),
                Text(
                  stopName,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final line in metadata)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionTile(
    BuildContext context,
    SmartRouteSuggestion suggestion,
  ) {
    final controller = widget.controller;
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
    final leadingIcon = favorite == null
        ? Icons.gps_fixed_rounded
        : Icons.favorite_rounded;
    final metadata = [
      if (destinationLabel != null) '目的地：$destinationLabel',
      if (showDistance) '距離你約 ${formatDistance(suggestion.distanceMeters!)}',
    ];
    final etaBadge = recommendedStop != null
        ? EtaBadge(
            stop: recommendedStop,
            alwaysShowSeconds: controller.settings.alwaysShowSeconds,
            size: 64,
          )
        : null;

    return _buildRouteTile(
      context: context,
      onTap: () => _openSuggestion(suggestion),
      child: _buildSmartTileRow(
        context: context,
        leadingIcon: leadingIcon,
        title: suggestion.profile.routeName,
        stopName: recommendedStop?.stopName,
        metadata: metadata,
        etaBadge: etaBadge,
      ),
    );
  }

  Widget _buildResponsiveTileList(List<Widget> tiles) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const minimumTileWidth = 320.0;
        final horizontal =
            tiles.length > 1 &&
            constraints.maxWidth >=
                (tiles.length * minimumTileWidth) +
                    ((tiles.length - 1) * spacing);

        if (horizontal) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: spacing),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: spacing),
              tiles[i],
            ],
          ],
        );
      },
    );
  }

  Widget _buildSuggestionListState(
    BuildContext context,
    List<SmartRouteSuggestion> suggestions,
  ) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      trailing: IconButton(
        tooltip: '重新整理',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: _buildResponsiveTileList([
        for (final suggestion in suggestions)
          _buildSuggestionTile(context, suggestion),
      ]),
    );
  }

  Widget _buildNearbyFallbackTile(
    BuildContext context,
    _NearbyFallbackData nearby,
  ) {
    final controller = widget.controller;
    final stop = nearby.liveStop ?? nearby.result.stop;
    final route = nearby.result.route;
    // Prefer the PathInfo when it carries a real destination, but fall back to
    // route.description — both nearby fetch paths populate it, so the direction
    // no longer vanishes when getRouteDetail could not match the pathId.
    final pathName =
        isMeaningfulPathName(nearby.path?.name, routeName: route.routeName)
        ? nearby.path!.name
        : route.description;
    final direction = routeDirectionLabel(
      pathName: pathName,
      pathId: nearby.result.stop.pathId,
      routeName: route.routeName,
    );
    final metadata = [
      '距離你約 ${formatDistance(nearby.result.distanceMeters)}',
      if (direction.isNotEmpty) '方向：$direction',
    ];
    const badgeSize = 64.0;
    final etaBadge = EtaBadge(
      stop: stop,
      alwaysShowSeconds: controller.settings.alwaysShowSeconds,
      size: badgeSize,
    );

    return _buildRouteTile(
      context: context,
      onTap: () => _openNearbyFallback(nearby),
      child: _buildSmartTileRow(
        context: context,
        leadingIcon: Icons.directions_bus_filled_rounded,
        title: route.routeName,
        stopName: nearby.result.stop.stopName,
        metadata: metadata,
        etaBadge: etaBadge,
      ),
    );
  }

  Widget _buildNearbyFallbackListState(
    BuildContext context,
    List<_NearbyFallbackData> nearbyList,
  ) {
    return _SmartRecommendationShell(
      title: '智慧推薦',
      trailing: IconButton(
        tooltip: '重新整理',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: _buildResponsiveTileList([
        for (final nearby in nearbyList)
          _buildNearbyFallbackTile(context, nearby),
      ]),
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
        if (cardData.suggestions.isNotEmpty) {
          return _buildSuggestionListState(context, cardData.suggestions);
        }
        if (cardData.nearbyList.isNotEmpty) {
          return _buildNearbyFallbackListState(context, cardData.nearbyList);
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
        final direction = routeDirectionLabel(
          pathName: result.route.description,
          pathId: result.stop.pathId,
          routeName: result.route.routeName,
        );
        return TransitMapPoint(
          id: _pointIdForResult(result),
          label: result.stop.stopName,
          subtitle: <String>[
            provider.label,
            result.route.routeName,
            if (direction.isNotEmpty) direction,
          ].join(' · '),
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
        throw StateError('定位服務尚未開啓。');
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
    unawaited(() async {
      final autoFavorited = await widget.controller.recordRouteSelection(
        provider: routeProvider,
        routeKey: selected.route.routeKey,
        routeName: selected.route.routeName,
        source: 'home_nearby_map',
        pathId: selected.stop.pathId,
        stopId: selected.stop.stopId,
        stopName: selected.stop.stopName,
      );
      if (mounted && autoFavorited != null) {
        showAutoFavoritedSnackBar(context, autoFavorited);
      }
    }());
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
        settings: const RouteSettings(name: AppRoutes.nearby),
        builder: (_) => const NearbyScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedResult;
    final selectedDirection = selected == null
        ? ''
        : routeDirectionLabel(
            pathName: selected.route.description,
            pathId: selected.stop.pathId,
            routeName: selected.route.routeName,
          );
    final compactMode = _useCompactHomeMode(
      widget.controller.settings,
      HomeScreen._desktopSidebarWidth,
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
                                // Own line, own ellipsis budget: two stops of
                                // the same name sit across the street from each
                                // other and the direction is all that tells the
                                // selected one apart.
                                if (selectedDirection.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    selectedDirection,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
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
    required this.child,
    this.trailing,
  });

  final String title;
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
                  child: Text(title, style: theme.textTheme.headlineSmall),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 1),
            Text(
              '根據你的使用習慣推薦路線',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
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
                    Row(
                      children: [
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
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
