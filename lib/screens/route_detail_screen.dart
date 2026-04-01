import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/bus_app.dart';
import '../core/models.dart';
import '../widgets/eta_badge.dart';

class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({
    required this.routeKey,
    required this.provider,
    this.initialPathId,
    this.initialStopId,
    super.key,
  });

  final int routeKey;
  final BusProvider provider;
  final int? initialPathId;
  final int? initialStopId;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  String? _statusMessage;
  RouteDetailData? _detail;
  Timer? _countdownTimer;
  TabController? _tabController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  int _remainingSeconds = 0;
  bool _didScrollToInitialStop = false;
  bool _isScrollingToInitialStop = false;
  bool _didAutoScrollToCurrentLocation = false;
  bool _didAttemptLocationTracking = false;
  bool? _wakelockEnabled;
  int? _targetInitialPathId;
  Map<int, int> _nearestStopByPath = const <int, int>{};
  final Map<int, GlobalKey> _stopKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWakelock(
      AppControllerScope.of(context).settings.keepScreenAwakeOnRouteDetail,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _positionSubscription?.cancel();
    _tabController?.dispose();
    if (_wakelockEnabled == true) {
      unawaited(_setWakelock(false));
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    final controller = AppControllerScope.read(context);
    final previousDetail = _detail;

    setState(() {
      _isLoading = true;
      _error = null;
      _statusMessage = '正在更新';
    });

    try {
      final fetchedDetail = await controller.getRouteDetail(
        widget.routeKey,
        provider: widget.provider,
      );
      if (!mounted) {
        return;
      }

      final displayDetail = !fetchedDetail.hasLiveData && previousDetail != null
          ? _mergeDetailWithPreviousLiveData(fetchedDetail, previousDetail)
          : fetchedDetail;

      _syncTabController(displayDetail);
      setState(() {
        _detail = displayDetail;
        _isLoading = false;
        _error = null;
        _statusMessage = fetchedDetail.hasLiveData ? null : '即時資訊暫時無法取得';
      });
      _startCountdown(
        fetchedDetail.hasLiveData
            ? controller.settings.busUpdateTime
            : controller.settings.busErrorUpdateTime,
      );
      _scrollToInitialStopIfNeeded();
      _recalculateNearestStops();
      unawaited(_ensureLocationTracking());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '$error';
        _statusMessage = previousDetail == null ? '讀取失敗' : '更新失敗，保留上一筆資料';
      });
      _startCountdown(controller.settings.busErrorUpdateTime);
    }
  }

  RouteDetailData _mergeDetailWithPreviousLiveData(
    RouteDetailData next,
    RouteDetailData previous,
  ) {
    final previousStops = <int, StopInfo>{};
    for (final entry in previous.stopsByPath.entries) {
      for (final stop in entry.value) {
        previousStops[_keyForStop(stop.pathId, stop.stopId)] = stop;
      }
    }

    final mergedStopsByPath = <int, List<StopInfo>>{};
    for (final entry in next.stopsByPath.entries) {
      mergedStopsByPath[entry.key] = entry.value.map((stop) {
        if (hasRealtimeStopData(stop)) {
          return stop;
        }

        final previousStop =
            previousStops[_keyForStop(stop.pathId, stop.stopId)];
        if (previousStop == null || !hasRealtimeStopData(previousStop)) {
          return stop;
        }

        return stop.copyWith(
          sec: previousStop.sec,
          msg: previousStop.msg,
          t: previousStop.t,
          buses: previousStop.buses,
        );
      }).toList();
    }

    return RouteDetailData(
      route: next.route,
      paths: next.paths,
      stopsByPath: mergedStopsByPath,
      hasLiveData: next.hasLiveData,
    );
  }

  void _syncTabController(RouteDetailData detail) {
    final pathIds = detail.paths.map((path) => path.pathId).toList();
    if (pathIds.isEmpty) {
      _tabController?.dispose();
      _tabController = null;
      _targetInitialPathId = null;
      return;
    }

    final initialIndex = _resolveInitialPathIndex(detail.paths);
    _targetInitialPathId = detail.paths[initialIndex].pathId;
    final selectedIndex = _tabController == null
        ? initialIndex
        : _tabController!.index.clamp(0, pathIds.length - 1);

    if (_tabController?.length == pathIds.length) {
      _tabController!.index = selectedIndex;
      return;
    }

    _tabController?.dispose();
    _tabController = TabController(
      length: pathIds.length,
      vsync: this,
      initialIndex: selectedIndex,
    );
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        return;
      }
      setState(() {});
      _scrollToInitialStopIfNeeded();
      _maybeScrollToCurrentLocation();
    });
  }

  int _resolveInitialPathIndex(List<PathInfo> paths) {
    if (widget.initialPathId == null || paths.isEmpty) {
      return 0;
    }

    final exactMatch = paths.indexWhere(
      (path) => path.pathId == widget.initialPathId,
    );
    if (exactMatch != -1) {
      return exactMatch;
    }

    final legacyIndex = widget.initialPathId!;
    if (legacyIndex >= 0 && legacyIndex < paths.length) {
      return legacyIndex;
    }
    return 0;
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _remainingSeconds = seconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 0) {
        timer.cancel();
        unawaited(_refresh());
        return;
      }
      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  void _scrollToInitialStopIfNeeded() {
    if (_didScrollToInitialStop ||
        _isScrollingToInitialStop ||
        widget.initialStopId == null ||
        _detail == null) {
      return;
    }

    final pathId = _currentPathId;
    if (pathId == null) {
      return;
    }
    if (_targetInitialPathId != null && _targetInitialPathId != pathId) {
      return;
    }

    unawaited(_attemptScrollToInitialStop(pathId, widget.initialStopId!));
  }

  Future<void> _attemptScrollToInitialStop(int pathId, int stopId) async {
    _isScrollingToInitialStop = true;
    try {
      final didScroll = await _scrollToStop(pathId, stopId);
      if (didScroll) {
        _didScrollToInitialStop = true;
      }
    } finally {
      _isScrollingToInitialStop = false;
    }
  }

  Future<bool> _scrollToStop(
    int pathId,
    int stopId, {
    double alignment = 0.28,
    Duration duration = const Duration(milliseconds: 360),
  }) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return false;
      }
      if (_currentPathId != pathId) {
        return false;
      }

      final key = _stopKeys[_keyForStop(pathId, stopId)];
      final targetContext = key?.currentContext;
      if (targetContext == null || !targetContext.mounted) {
        continue;
      }

      await Scrollable.ensureVisible(
        targetContext,
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: alignment,
      );
      return true;
    }

    return false;
  }

  int? get _currentPathId {
    final detail = _detail;
    final tabController = _tabController;
    if (detail == null || detail.paths.isEmpty || tabController == null) {
      return null;
    }

    return detail.paths[tabController.index].pathId;
  }

  int _keyForStop(int pathId, int stopId) {
    return Object.hash(pathId, stopId);
  }

  void _syncWakelock(bool enable) {
    if (_wakelockEnabled == enable) {
      return;
    }
    _wakelockEnabled = enable;
    unawaited(_setWakelock(enable));
  }

  Future<void> _setWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } catch (_) {
      // Ignore unsupported platform or plugin errors.
    }
  }

  Future<void> _ensureLocationTracking() async {
    if (_didAttemptLocationTracking) {
      return;
    }
    _didAttemptLocationTracking = true;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      _updateNearestStops(lastKnown);
    }

    final current = await Geolocator.getCurrentPosition();
    if (!mounted) {
      return;
    }
    _updateNearestStops(current);

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(_updateNearestStops);
  }

  void _recalculateNearestStops() {
    final lastPosition = _lastPosition;
    if (lastPosition != null) {
      _updateNearestStops(lastPosition);
    }
  }

  void _updateNearestStops(Position position) {
    _lastPosition = position;
    final detail = _detail;
    if (detail == null) {
      return;
    }

    final nearestByPath = <int, int>{};
    for (final path in detail.paths) {
      final pathStops = detail.stopsByPath[path.pathId] ?? const <StopInfo>[];
      StopInfo? nearestStop;
      double? nearestDistance;

      for (final stop in pathStops) {
        if (stop.lat == 0 && stop.lon == 0) {
          continue;
        }

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          stop.lat,
          stop.lon,
        );
        if (nearestDistance == null || distance < nearestDistance) {
          nearestDistance = distance;
          nearestStop = stop;
        }
      }

      if (nearestStop != null) {
        nearestByPath[path.pathId] = nearestStop.stopId;
      }
    }

    if (!mapEquals(_nearestStopByPath, nearestByPath)) {
      setState(() {
        _nearestStopByPath = nearestByPath;
      });
    }
    _maybeScrollToCurrentLocation();
  }

  void _maybeScrollToCurrentLocation() {
    if (_didAutoScrollToCurrentLocation || widget.initialStopId != null) {
      return;
    }

    final pathId = _currentPathId;
    if (pathId == null) {
      return;
    }
    final stopId = _nearestStopByPath[pathId];
    if (stopId == null) {
      return;
    }

    _didAutoScrollToCurrentLocation = true;
    unawaited(_scrollToStop(pathId, stopId));
  }

  bool _isInitialStop(StopInfo stop) {
    if (widget.initialStopId != stop.stopId) {
      return false;
    }
    return _targetInitialPathId == null || _targetInitialPathId == stop.pathId;
  }

  bool _isNearestStop(StopInfo stop) {
    return _nearestStopByPath[stop.pathId] == stop.stopId;
  }

  Future<void> _openStopActions(StopInfo stop) async {
    final action = await showDialog<_StopAction>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(stop.stopName),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(_StopAction.favorite),
              child: const Text('加入最愛'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    if (!mounted || action == null) {
      return;
    }

    if (action == _StopAction.favorite) {
      await _handleFavorite(stop);
    }
  }

  Future<void> _handleFavorite(StopInfo stop) async {
    final controller = AppControllerScope.read(context);
    String? groupName;

    if (controller.favoriteGroupNames.length > 1) {
      groupName = await _showGroupPicker(controller.favoriteGroupNames);
      if (!mounted || groupName == null) {
        return;
      }
      if (groupName == '__new__') {
        groupName = await _showAddGroupDialog();
        if (!mounted || groupName == null || groupName.trim().isEmpty) {
          return;
        }
        await controller.addFavoriteGroup(groupName);
      }
    } else if (controller.favoriteGroupNames.length == 1) {
      groupName = controller.favoriteGroupNames.first;
    }

    final selectedGroup = await controller.addFavoriteStop(
      FavoriteStop(
        provider: widget.provider,
        routeKey: widget.routeKey,
        pathId: stop.pathId,
        stopId: stop.stopId,
      ),
      groupName: groupName,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已加入 $selectedGroup')));
  }

  Future<String?> _showGroupPicker(List<String> groups) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('選擇最愛群組'),
          children: [
            ...groups.map(
              (group) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(group),
                child: Text(group),
              ),
            ),
            const Divider(height: 1),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('__new__'),
              child: const Text('新增群組'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showAddGroupDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增最愛群組'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '輸入群組名稱'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('新增'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget? _buildTrailingStatus(
    ThemeData theme,
    StopInfo stop, {
    required bool isNearest,
  }) {
    if (stop.buses.isNotEmpty) {
      final vehicle = stop.buses.first;
      final backgroundColor = isNearest
          ? Colors.cyan.shade400
          : (vehicle.id.startsWith('E') || vehicle.id.endsWith('FV'))
          ? Colors.amber.shade600
          : theme.colorScheme.primary;
      final foregroundColor = backgroundColor.computeLuminance() > 0.6
          ? Colors.black87
          : Colors.white;

      return _RouteStatusPill(
        icon: isNearest
            ? Icons.gps_fixed_rounded
            : vehicle.type == '1'
            ? Icons.accessible_rounded
            : Icons.directions_bus_rounded,
        label: vehicle.id,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      );
    }

    if (isNearest) {
      return const _RouteStatusPill(
        icon: Icons.gps_fixed_rounded,
        label: '目前位置',
        backgroundColor: Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      );
    }

    return null;
  }

  Widget _buildStopTile(
    ThemeData theme,
    StopInfo stop, {
    required bool alwaysShowSeconds,
    required bool isHighlighted,
    required bool isNearest,
  }) {
    final trailingStatus = _buildTrailingStatus(
      theme,
      stop,
      isNearest: isNearest,
    );

    return Material(
      color: isHighlighted
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => unawaited(_openStopActions(stop)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              EtaBadge(
                stop: stop,
                alwaysShowSeconds: alwaysShowSeconds,
                size: 58,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stop.stopName.replaceAll('(', '\n('),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    if (trailingStatus != null) ...[
                      const SizedBox(width: 12),
                      trailingStatus,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final detail = _detail;
    final theme = Theme.of(context);
    final updateSeconds = _error == null
        ? controller.settings.busUpdateTime
        : controller.settings.busErrorUpdateTime;
    final progress = updateSeconds <= 0
        ? null
        : ((updateSeconds - _remainingSeconds) / updateSeconds).clamp(0.0, 1.0);
    final currentPathId = _currentPathId;
    final currentNearestStopId = currentPathId == null
        ? null
        : _nearestStopByPath[currentPathId];

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.route.routeName ?? '公車資訊'),
        actions: [
          if (currentPathId != null && currentNearestStopId != null)
            IconButton(
              onPressed: () =>
                  unawaited(_scrollToStop(currentPathId, currentNearestStopId)),
              icon: const Icon(Icons.gps_fixed_rounded),
            ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: detail == null
                ? null
                : () {
                    showDialog<void>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text(detail.route.routeName),
                          content: Text(
                            detail.route.description.isEmpty
                                ? 'routeKey: ${detail.route.routeKey}'
                                : detail.route.description,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('關閉'),
                            ),
                          ],
                        );
                      },
                    );
                  },
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _statusMessage ??
                      (_remainingSeconds > 0
                          ? '$_remainingSeconds 秒後自動更新'
                          : '準備重新整理'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading && detail == null
          ? const Center(child: CircularProgressIndicator())
          : detail == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? '目前無法載入公車資訊'),
              ),
            )
          : Column(
              children: [
                if (_tabController != null)
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.fill,
                    tabs: detail.paths
                        .map((path) => Tab(text: path.name))
                        .toList(),
                  ),
                Expanded(
                  child: _tabController == null
                      ? const Center(child: Text('目前沒有可顯示的方向'))
                      : TabBarView(
                          controller: _tabController,
                          children: detail.paths.map((path) {
                            final pathStops =
                                detail.stopsByPath[path.pathId] ?? const [];
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                20,
                              ),
                              itemCount: pathStops.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 18),
                              itemBuilder: (context, index) {
                                final stop = pathStops[index];
                                final key = _stopKeys.putIfAbsent(
                                  _keyForStop(path.pathId, stop.stopId),
                                  GlobalKey.new,
                                );
                                return Container(
                                  key: key,
                                  child: _buildStopTile(
                                    theme,
                                    stop,
                                    alwaysShowSeconds:
                                        controller.settings.alwaysShowSeconds,
                                    isHighlighted: _isInitialStop(stop),
                                    isNearest: _isNearestStop(stop),
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
    );
  }
}

class _RouteStatusPill extends StatelessWidget {
  const _RouteStatusPill({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foregroundColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StopAction { favorite }
