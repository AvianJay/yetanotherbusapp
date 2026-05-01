import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../widgets/eta_badge.dart';
import 'favorite_groups_screen.dart';
import 'route_detail_screen.dart';
import '../widgets/background_image_wrapper.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({this.initialGroupName, super.key});

  final String? initialGroupName;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  Timer? _countdownTimer;
  late final AnimationController _countdownProgressController;
  List<FavoriteResolvedItem> _items = const [];
  bool _isLoading = false;
  String? _error;
  String? _statusMessage;
  String? _loadedGroupName;
  String _loadedSignature = '';
  String? _refreshingGroupName;
  String _refreshingSignature = '';
  bool _refreshScheduled = false;
  int _refreshRequestId = 0;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _countdownProgressController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _countdownProgressController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  void _syncTabController(List<String> groups) {
    if (groups.isEmpty) {
      _tabController?.dispose();
      _tabController = null;
      _countdownTimer?.cancel();
      _countdownProgressController
        ..stop()
        ..value = 0;
      _items = const [];
      _isLoading = false;
      _error = null;
      _statusMessage = null;
      _loadedGroupName = null;
      _loadedSignature = '';
      _refreshingGroupName = null;
      _refreshingSignature = '';
      return;
    }

    final initialIndex = _tabController == null
        ? _resolveInitialGroupIndex(groups)
        : _tabController!.index.clamp(0, groups.length - 1);
    if (_tabController?.length == groups.length) {
      if (_tabController!.index != initialIndex) {
        _tabController!.index = initialIndex;
      }
      return;
    }

    _tabController?.dispose();
    _tabController = TabController(
      length: groups.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        return;
      }
      setState(() {});
      _scheduleRefresh(forceResolveStatic: true);
    });
  }

  int _resolveInitialGroupIndex(List<String> groups) {
    final initialGroupName = widget.initialGroupName;
    if (initialGroupName == null) {
      return 0;
    }
    final index = groups.indexOf(initialGroupName);
    return index == -1 ? 0 : index;
  }

  String? _currentGroupName(List<String> groups) {
    if (groups.isEmpty) {
      return null;
    }
    final index = (_tabController?.index ?? 0).clamp(0, groups.length - 1);
    return groups[index];
  }

  String _favoritesSignature(List<FavoriteStop> favorites) {
    return favorites
        .map(
          (favorite) =>
              '${favorite.provider.name}:'
              '${favorite.routeKey}:'
              '${favorite.pathId}:'
              '${favorite.stopId}:'
              '${favorite.destinationPathId ?? 0}:'
              '${favorite.destinationStopId ?? 0}',
        )
        .join('|');
  }

  String _favoriteItemKey(FavoriteStop favorite) {
    return '${favorite.provider.name}:${favorite.routeKey}:${favorite.pathId}:${favorite.stopId}';
  }

  String _routeRequestKey(FavoriteStop favorite) {
    return '${favorite.provider.name}:${favorite.routeKey}';
  }

  void _scheduleRefresh({bool forceResolveStatic = false}) {
    if (_refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      unawaited(_refreshCurrentGroup(forceResolveStatic: forceResolveStatic));
    });
  }

  void _scheduleRefreshIfNeeded(AppController controller, List<String> groups) {
    final groupName = _currentGroupName(groups);
    if (groupName == null) {
      return;
    }

    final signature = _favoritesSignature(
      controller.favoritesInGroup(groupName),
    );
    if (_isLoading &&
        groupName == _refreshingGroupName &&
        signature == _refreshingSignature) {
      return;
    }
    if (groupName != _loadedGroupName || signature != _loadedSignature) {
      _scheduleRefresh(forceResolveStatic: true);
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _remainingSeconds = seconds;
    _countdownProgressController
      ..stop()
      ..duration = Duration(seconds: seconds <= 0 ? 1 : seconds)
      ..value = 0;
    if (seconds > 0) {
      unawaited(_countdownProgressController.forward(from: 0));
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 0) {
        timer.cancel();
        unawaited(_refreshCurrentGroup());
        return;
      }
      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  Widget _buildBottomProgressIndicator() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axis: Axis.horizontal,
          axisAlignment: -1,
          child: child,
        );
      },
      child: _isLoading
          ? const LinearProgressIndicator(
              key: ValueKey('favorites-loading-progress'),
              minHeight: 4,
            )
          : AnimatedBuilder(
              key: const ValueKey('favorites-countdown-progress'),
              animation: _countdownProgressController,
              builder: (context, child) {
                return LinearProgressIndicator(
                  value: _countdownProgressController.value,
                  minHeight: 4,
                );
              },
            ),
    );
  }

  Future<void> _refreshCurrentGroup({bool forceResolveStatic = false}) async {
    final controller = AppControllerScope.read(context);
    final groups = controller.favoriteGroupNames;
    final groupName = _currentGroupName(groups);
    if (groupName == null) {
      return;
    }

    final references = controller.favoritesInGroup(groupName);
    final signature = _favoritesSignature(references);
    final shouldResolveStatic =
        forceResolveStatic ||
        groupName != _loadedGroupName ||
        signature != _loadedSignature;
    final previousItemsByKey = <String, FavoriteResolvedItem>{
      for (final item in _items) _favoriteItemKey(item.reference): item,
    };
    final requestId = ++_refreshRequestId;

    setState(() {
      _isLoading = true;
      _error = null;
      _refreshingGroupName = groupName;
      _refreshingSignature = signature;
      _statusMessage = '正在更新';
    });

    try {
      final baseItems = shouldResolveStatic
          ? await controller.resolveFavoriteGroup(groupName)
          : _items;

      if (!mounted || requestId != _refreshRequestId) {
        return;
      }

      final uniqueRoutes = <String, FavoriteStop>{};
      for (final item in baseItems) {
        uniqueRoutes.putIfAbsent(
          _routeRequestKey(item.reference),
          () => item.reference,
        );
      }

      final detailEntries = await Future.wait(
        uniqueRoutes.entries.map((entry) async {
          try {
            final detail = await controller.getRouteDetail(
              entry.value.routeKey,
              provider: entry.value.provider,
            );
            return MapEntry(entry.key, detail);
          } catch (_) {
            return MapEntry<String, RouteDetailData?>(entry.key, null);
          }
        }),
      );

      if (!mounted || requestId != _refreshRequestId) {
        return;
      }

      final detailsByRoute = <String, RouteDetailData?>{
        for (final entry in detailEntries) entry.key: entry.value,
      };
      var liveRouteCount = 0;
      var failedRouteCount = 0;
      for (final detail in detailsByRoute.values) {
        if (detail == null) {
          failedRouteCount += 1;
        } else if (detail.hasLiveData) {
          liveRouteCount += 1;
        }
      }

      final enrichedItems = baseItems.map((item) {
        final routeKey = _routeRequestKey(item.reference);
        final detail = detailsByRoute[routeKey];
        if (detail != null) {
          final liveStop = _findStopInDetail(detail, item.reference);
          if (liveStop != null) {
            return FavoriteResolvedItem(
              reference: item.reference,
              route: item.route,
              stop: liveStop,
            );
          }
        }

        final previousItem =
            previousItemsByKey[_favoriteItemKey(item.reference)];
        if (previousItem != null && hasRealtimeStopData(previousItem.stop)) {
          return FavoriteResolvedItem(
            reference: item.reference,
            route: item.route,
            stop: previousItem.stop,
          );
        }

        return item;
      }).toList();

      final allRoutesFailed =
          uniqueRoutes.isNotEmpty && failedRouteCount == uniqueRoutes.length;
      final hasAnyLiveData = liveRouteCount > 0;
      final nextStatusMessage = allRoutesFailed
          ? '即時資訊更新失敗'
          : !hasAnyLiveData
          ? '目前沒有可用的即時資訊'
          : failedRouteCount > 0
          ? '部分路線更新失敗'
          : null;

      setState(() {
        _loadedGroupName = groupName;
        _loadedSignature = signature;
        _items = enrichedItems;
        _isLoading = false;
        _error = null;
        _statusMessage = nextStatusMessage;
        _refreshingGroupName = null;
        _refreshingSignature = '';
      });

      _startCountdown(
        hasAnyLiveData
            ? controller.settings.busUpdateTime
            : controller.settings.busErrorUpdateTime,
      );
    } catch (error) {
      if (!mounted || requestId != _refreshRequestId) {
        return;
      }

      setState(() {
        _isLoading = false;
        _error = '$error';
        _refreshingGroupName = null;
        _refreshingSignature = '';
        _statusMessage = _items.isEmpty ? '載入失敗' : '更新失敗，保留上一筆資料';
      });
      _startCountdown(controller.settings.busErrorUpdateTime);
    }
  }

  StopInfo? _findStopInDetail(RouteDetailData detail, FavoriteStop favorite) {
    final pathStops = detail.stopsByPath[favorite.pathId] ?? const <StopInfo>[];
    for (final stop in pathStops) {
      if (stop.stopId == favorite.stopId) {
        return stop;
      }
    }
    return null;
  }

  Future<void> _removeFavorite(
    AppController controller,
    String groupName,
    FavoriteResolvedItem item,
  ) async {
    setState(() {
      _items = _items
          .where((entry) => !entry.reference.sameAs(item.reference))
          .toList();
    });

    await controller.removeFavoriteStop(groupName, item.reference);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已從 $groupName 移除 ${item.stop.stopName}')),
    );
    _scheduleRefresh(forceResolveStatic: true);
  }

  Future<void> _handleFavoriteDestinationAction(
    AppController controller,
    String groupName,
    FavoriteResolvedItem item,
    _FavoriteDestinationAction action,
  ) async {
    if (action == _FavoriteDestinationAction.setDestination) {
      final detail = await controller.getRouteDetail(
        item.reference.routeKey,
        provider: item.reference.provider,
        routeIdHint: item.reference.routeId,
        routeNameHint: item.route.routeName,
      );
      if (!mounted) {
        return;
      }
      final pathStops =
          detail.stopsByPath[item.reference.pathId] ?? const <StopInfo>[];
      if (pathStops.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('這條路線目前沒有可選的站牌。')));
        return;
      }

      final destination = await showModalBottomSheet<StopInfo>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: ListView.separated(
                itemCount: pathStops.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final stop = pathStops[index];
                  return ListTile(
                    title: Text(stop.stopName),
                    subtitle: Text('第 ${index + 1} 站'),
                    trailing: stop.stopId == item.reference.destinationStopId
                        ? const Icon(Icons.flag_rounded)
                        : null,
                    onTap: () => Navigator.of(context).pop(stop),
                  );
                },
              ),
            ),
          );
        },
      );

      if (!mounted || destination == null) {
        return;
      }

      final didChange = await controller.updateFavoriteDestination(
        groupName,
        item.reference,
        destinationPathId: destination.pathId,
        destinationStopId: destination.stopId,
        destinationStopName: destination.stopName,
      );
      if (!mounted) {
        return;
      }
      if (didChange) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已將目的地設為 ${destination.stopName}')),
        );
        _scheduleRefresh(forceResolveStatic: true);
      }
      return;
    }

    final didChange = await controller.updateFavoriteDestination(
      groupName,
      item.reference,
      destinationPathId: null,
      destinationStopId: null,
      destinationStopName: null,
    );
    if (!mounted) {
      return;
    }
    if (didChange) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清除這個最愛的目的地設定')));
      _scheduleRefresh(forceResolveStatic: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final groups = controller.favoriteGroupNames;
    _syncTabController(groups);
    _scheduleRefreshIfNeeded(controller, groups);

    final currentGroupName = _currentGroupName(groups);
    final displayItems = currentGroupName == _loadedGroupName
        ? _items
        : const <FavoriteResolvedItem>[];
    final hasFavoritesBackgroundImage = hasBackgroundImageForPage(
      controller.settings,
      pageKey: 'favorites',
    );

    return BackgroundImageWrapper(
      pageKey: 'favorites',
      child: Scaffold(
        backgroundColor: hasFavoritesBackgroundImage
            ? Colors.transparent
            : null,
        appBar: AppBar(
          title: const Text('我的最愛'),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'favorite_groups'),
                    builder: (_) => const FavoriteGroupsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.folder_outlined),
            ),
          ],
          bottom: groups.isEmpty
              ? null
              : TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: groups.map((group) => Tab(text: group)).toList(),
                ),
        ),
        bottomNavigationBar: groups.isEmpty
            ? null
            : Material(
                color:
                    Theme.of(context).bottomAppBarTheme.color ??
                    Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBottomProgressIndicator(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _statusMessage ??
                                (_remainingSeconds > 0
                                    ? '$_remainingSeconds 秒後更新'
                                    : '正在更新'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: groups.isEmpty
            ? const _EmptyFavoritesState()
            : _buildBody(
                context,
                controller,
                currentGroupName: currentGroupName!,
                items: displayItems,
              ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppController controller, {
    required String currentGroupName,
    required List<FavoriteResolvedItem> items,
  }) {
    if (_error != null && items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('載入最愛失敗：$_error'),
        ),
      );
    }

    if (_isLoading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return const _EmptyFavoritesState(message: '這個群組目前沒有站牌。');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final destinationSummary =
            item.reference.destinationStopName?.trim().isNotEmpty == true
            ? item.reference.destinationStopName!.trim()
            : (item.reference.destinationStopId == null
                  ? null
                  : '站牌 ${item.reference.destinationStopId}');
        return Dismissible(
          key: ValueKey(_favoriteItemKey(item.reference)),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          onDismissed: (_) =>
              unawaited(_removeFavorite(controller, currentGroupName, item)),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              leading: EtaBadge(
                stop: item.stop,
                alwaysShowSeconds: controller.settings.alwaysShowSeconds,
                size: 52,
              ),
              title: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.titleMedium,
                  children: [
                    TextSpan(
                      text: '${item.route.routeName} ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: item.stop.stopName),
                  ],
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${item.reference.provider.label} · '
                  '${item.route.description.isEmpty ? "routeKey ${item.route.routeKey}" : item.route.description}'
                  '${destinationSummary == null ? "" : "\n目的地：$destinationSummary"}',
                ),
              ),
              trailing: controller.settings.enableRouteBackgroundMonitor
                  ? PopupMenuButton<_FavoriteDestinationAction>(
                      tooltip: '目的地設定',
                      icon: Icon(
                        item.reference.destinationStopId == null
                            ? Icons.flag_outlined
                            : Icons.flag_rounded,
                      ),
                      onSelected: (action) {
                        unawaited(
                          _handleFavoriteDestinationAction(
                            controller,
                            currentGroupName,
                            item,
                            action,
                          ),
                        );
                      },
                      itemBuilder: (context) {
                        return [
                          const PopupMenuItem(
                            value: _FavoriteDestinationAction.setDestination,
                            child: Text('設定目的地'),
                          ),
                          if (item.reference.destinationStopId != null)
                            const PopupMenuItem(
                              value:
                                  _FavoriteDestinationAction.clearDestination,
                              child: Text('清除目的地'),
                            ),
                        ];
                      },
                    )
                  : null,
              onTap: () async {
                await controller.recordRouteSelection(
                  provider: item.reference.provider,
                  routeKey: item.reference.routeKey,
                  routeName: item.route.routeName,
                  source: 'favorite',
                );
                if (!context.mounted) {
                  return;
                }
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'route_detail'),
                    builder: (_) => RouteDetailScreen(
                      routeKey: item.reference.routeKey,
                      provider: item.reference.provider,
                      initialPathId: item.reference.pathId,
                      initialStopId: item.reference.stopId,
                      initialDestinationPathId:
                          item.reference.destinationPathId,
                      initialDestinationStopId:
                          item.reference.destinationStopId,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

enum _FavoriteDestinationAction { setDestination, clearDestination }

class _EmptyFavoritesState extends StatelessWidget {
  const _EmptyFavoritesState({this.message = '還沒有任何已收藏的站牌。'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
