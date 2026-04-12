import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/bus_app.dart';
import '../core/android_home_integration.dart';
import '../core/android_trip_monitor.dart';
import '../core/app_launch_service.dart';
import '../core/live_activity_service.dart';
import '../core/models.dart';
import '../core/route_detail_launch_bridge.dart';
import '../core/trip_monitor_notifications.dart';
import '../core/twbusforum.dart';
import '../widgets/eta_badge.dart';

class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({
    required this.routeKey,
    required this.provider,
    this.routeIdHint,
    this.routeNameHint,
    this.initialPathId,
    this.initialStopId,
    super.key,
  });

  final int routeKey;
  final BusProvider provider;
  final String? routeIdHint;
  final String? routeNameHint;
  final int? initialPathId;
  final int? initialStopId;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final RouteDetailLaunchHandler _launchHandler;
  bool _isLoading = true;
  String? _error;
  String? _statusMessage;
  RouteDetailData? _detail;
  Timer? _countdownTimer;
  late final AnimationController _countdownProgressController;
  TabController? _tabController;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  int _remainingSeconds = 0;
  bool _didScrollToInitialStop = false;
  bool _isScrollingToInitialStop = false;
  bool _didAutoScrollToCurrentLocation = false;
  bool _didAttemptLocationTracking = false;
  bool _didRecordRouteVisit = false;
  bool? _wakelockEnabled;
  bool _backgroundTripMonitorReady = false;
  bool _backgroundTripMonitorPromptInProgress = false;
  bool _backgroundTripMonitorPaused = false;
  bool _backgroundDataRefreshInFlight = false;
  bool _awaitingBackgroundLocationPermission = false;
  bool _destinationPromptShown = false;
  bool _liveActivityActive = false;
  int? _liveActivityStopId;
  int? _liveActivityPathId;
  bool _liveActivityBoardingWindowOpen = false;
  bool _liveActivityRideConfirmed = false;
  DateTime? _liveActivityBoardingWindowOpenedAt;
  bool _iosBoardingCheckPromptSent = false;
  bool _locationTrackingConfiguredForBackground = false;
  bool _backgroundLocationAlwaysGranted = false;
  int? _liveActivityLastNearestStopIndex;
  DateTime? _lastBackgroundDataRefreshAt;
  int? _requestedPathId;
  int? _requestedStopId;
  int? _targetInitialPathId;
  int? _boardingStopId;
  String? _boardingStopName;
  int? _destinationStopId;
  String? _destinationStopName;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Map<int, int> _nearestStopByPath = const <int, int>{};
  final Map<int, GlobalKey> _stopKeys = <int, GlobalKey>{};
  final Map<int, ScrollController> _scrollControllers =
      <int, ScrollController>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _launchHandler = _handleLaunchAction;
    RouteDetailLaunchBridge.instance.attach(_launchHandler);
    _countdownProgressController = AnimationController(vsync: this);
    _requestedPathId = widget.initialPathId;
    _requestedStopId = widget.initialStopId;
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
    unawaited(_configureBackgroundTripMonitorIfNeeded());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RouteDetailLaunchBridge.instance.detach(_launchHandler);
    _countdownTimer?.cancel();
    _countdownProgressController.dispose();
    _positionSubscription?.cancel();
    _tabController?.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    if (_wakelockEnabled == true) {
      unawaited(_setWakelock(false));
    }
    unawaited(TripMonitorNotifications.cancelBoardingCheckPrompt());
    unawaited(AndroidTripMonitor.stop());
    unawaited(LiveActivityService.endLiveActivity());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _appIsForeground;
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed &&
        _awaitingBackgroundLocationPermission) {
      _awaitingBackgroundLocationPermission = false;
      unawaited(
        _configureBackgroundTripMonitorIfNeeded(forcePermissionCheck: true),
      );
    }
    if (state == AppLifecycleState.resumed && _isAndroid) {
      unawaited(_syncBackgroundTripMonitorPausedState());
    }
    if (state == AppLifecycleState.resumed && _isIOS) {
      unawaited(TripMonitorNotifications.cancelBoardingCheckPrompt());
    }
    if (!_isAndroid) {
      return;
    }
    final controller = AppControllerScope.read(context);
    if (!controller.settings.enableRouteBackgroundMonitor ||
        !_backgroundTripMonitorReady) {
      return;
    }
    final isForeground = switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive => true,
      AppLifecycleState.hidden => false,
      AppLifecycleState.paused => false,
      AppLifecycleState.detached => false,
    };
    if (isForeground == wasForeground) {
      if (!isForeground) {
        _pauseForegroundRefreshLoop();
      }
      return;
    }
    if (isForeground) {
      unawaited(AndroidTripMonitor.setAppInForeground(true));
      if (!wasForeground && _detail != null) {
        unawaited(_refresh());
      }
    } else {
      _pauseForegroundRefreshLoop();
      unawaited(AndroidTripMonitor.setAppInForeground(false));
    }
    unawaited(_configureBackgroundTripMonitorIfNeeded());
  }

  Future<void> _refresh() async {
    if (_shouldSuspendForegroundRefreshes) {
      return;
    }
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
        routeIdHint: widget.routeIdHint,
        routeNameHint: widget.routeNameHint,
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
      if (!_didRecordRouteVisit) {
        _didRecordRouteVisit = true;
        unawaited(
          controller.recordRouteVisit(
            displayDetail.route,
            provider: widget.provider,
          ),
        );
      }
      _startCountdown(
        fetchedDetail.hasLiveData
            ? controller.settings.busUpdateTime
            : controller.settings.busErrorUpdateTime,
      );
      _scrollToInitialStopIfNeeded();
      _recalculateNearestStops();
      unawaited(_ensureLocationTracking());
      unawaited(_maybePromptForBackgroundTripMonitor());
      unawaited(_configureBackgroundTripMonitorIfNeeded());
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
      if (_destinationStopId != null &&
          _currentPathStops.every(
            (stop) => stop.stopId != _destinationStopId,
          )) {
        _boardingStopId = null;
        _boardingStopName = null;
        _destinationStopId = null;
        _destinationStopName = null;
        _resetLiveActivityRideState();
      }
      if (_isIOS && _backgroundTripMonitorPaused) {
        _backgroundTripMonitorPaused = false;
      }
      setState(() {});
      _scrollToInitialStopIfNeeded();
      _maybeScrollToCurrentLocation();
      unawaited(_configureBackgroundTripMonitorIfNeeded());
    });
  }

  int _resolveInitialPathIndex(List<PathInfo> paths) {
    if (paths.isEmpty) {
      return 0;
    }

    final requestedPathId = _requestedPathId;
    if (requestedPathId == null) {
      return _resolvePathIndexFromStopId(paths, _requestedStopId) ?? 0;
    }

    final exactMatch = paths.indexWhere(
      (path) => path.pathId == requestedPathId,
    );
    if (exactMatch != -1) {
      return exactMatch;
    }

    final legacyIndex = requestedPathId;
    if (legacyIndex >= 0 && legacyIndex < paths.length) {
      return legacyIndex;
    }
    return _resolvePathIndexFromStopId(paths, _requestedStopId) ?? 0;
  }

  int? _resolvePathIndexFromStopId(List<PathInfo> paths, int? stopId) {
    final detail = _detail;
    if (detail == null || stopId == null) {
      return null;
    }

    for (var index = 0; index < paths.length; index++) {
      final path = paths[index];
      final stops = detail.stopsByPath[path.pathId] ?? const <StopInfo>[];
      if (stops.any((stop) => stop.stopId == stopId)) {
        return index;
      }
    }
    return null;
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
      if (_shouldSuspendForegroundRefreshes) {
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

  Future<bool> _handleLaunchAction(AppLaunchAction action) async {
    if (!mounted ||
        action.target != AppLaunchTarget.routeDetail ||
        action.provider != widget.provider ||
        action.routeKey != widget.routeKey) {
      return false;
    }

    final route = ModalRoute.of(context);
    if (route == null) {
      return false;
    }

    Navigator.of(context).popUntil((candidate) => identical(candidate, route));
    await _applyLaunchFocus(
      requestedPathId: action.pathId,
      requestedStopId: action.stopId,
    );
    return true;
  }

  Future<void> _applyLaunchFocus({
    required int? requestedPathId,
    required int? requestedStopId,
  }) async {
    final detail = _detail;
    final resolvedPathId = _resolveRequestedPathId(
      requestedPathId: requestedPathId,
      requestedStopId: requestedStopId,
    );

    setState(() {
      _requestedPathId = resolvedPathId;
      _requestedStopId = requestedStopId;
      _targetInitialPathId = resolvedPathId;
      _didScrollToInitialStop = requestedStopId == null;
      _didAutoScrollToCurrentLocation = false;
    });

    if (detail != null && _tabController != null && resolvedPathId != null) {
      final targetIndex = detail.paths.indexWhere(
        (path) => path.pathId == resolvedPathId,
      );
      if (targetIndex != -1 && _tabController!.index != targetIndex) {
        _tabController!.animateTo(
          targetIndex,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        for (var attempt = 0; attempt < 12; attempt++) {
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              _tabController == null ||
              !_tabController!.indexIsChanging) {
            break;
          }
        }
      }
    }

    _scrollToInitialStopIfNeeded();
    unawaited(_configureBackgroundTripMonitorIfNeeded());
    unawaited(_refresh());
  }

  int? _resolveRequestedPathId({
    required int? requestedPathId,
    required int? requestedStopId,
  }) {
    final detail = _detail;
    if (detail == null) {
      return requestedPathId;
    }

    if (requestedPathId != null) {
      for (final path in detail.paths) {
        if (path.pathId == requestedPathId) {
          return path.pathId;
        }
      }
      if (requestedPathId >= 0 && requestedPathId < detail.paths.length) {
        return detail.paths[requestedPathId].pathId;
      }
    }

    if (requestedStopId != null) {
      for (final path in detail.paths) {
        final stops = detail.stopsByPath[path.pathId] ?? const <StopInfo>[];
        if (stops.any((stop) => stop.stopId == requestedStopId)) {
          return path.pathId;
        }
      }
    }

    return _currentPathId;
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
      child: _remainingSeconds <= 0 || _isLoading
          ? const LinearProgressIndicator(
              key: ValueKey('loading-progress'),
              minHeight: 4,
            )
          : AnimatedBuilder(
              key: const ValueKey('countdown-progress'),
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

  void _scrollToInitialStopIfNeeded() {
    final requestedStopId = _requestedStopId;
    if (_didScrollToInitialStop ||
        _isScrollingToInitialStop ||
        requestedStopId == null ||
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

    unawaited(_attemptScrollToInitialStop(pathId, requestedStopId));
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
    var hasPrimedLazyList = false;
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
        if (!hasPrimedLazyList) {
          hasPrimedLazyList = await _scrollNearStop(
            pathId,
            stopId,
            alignment: alignment,
            duration: duration,
          );
        }
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

  Future<bool> _scrollNearStop(
    int pathId,
    int stopId, {
    required double alignment,
    required Duration duration,
  }) async {
    final detail = _detail;
    final scrollController = _scrollControllers[pathId];
    if (detail == null ||
        scrollController == null ||
        !scrollController.hasClients) {
      return false;
    }

    final pathStops = detail.stopsByPath[pathId] ?? const <StopInfo>[];
    final targetIndex = pathStops.indexWhere((stop) => stop.stopId == stopId);
    if (targetIndex == -1) {
      return false;
    }

    final maxScrollExtent = scrollController.position.maxScrollExtent;
    if (maxScrollExtent <= 0) {
      return false;
    }

    final stopRatio = pathStops.length <= 1
        ? 0.0
        : targetIndex / (pathStops.length - 1);
    final viewport = scrollController.position.viewportDimension;
    final targetOffset = (maxScrollExtent * stopRatio) - (viewport * alignment);
    await scrollController.animateTo(
      targetOffset.clamp(0.0, maxScrollExtent),
      duration: duration,
      curve: Curves.easeOutCubic,
    );
    return true;
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

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _appIsForeground =>
      _appLifecycleState == AppLifecycleState.resumed ||
      _appLifecycleState == AppLifecycleState.inactive;

  bool get _shouldSuspendForegroundRefreshes =>
      _isAndroid &&
      !_appIsForeground &&
      _backgroundTripMonitorReady &&
      AppControllerScope.read(context).settings.enableRouteBackgroundMonitor;

  void _pauseForegroundRefreshLoop() {
    _countdownTimer?.cancel();
    _countdownProgressController.stop();
  }

  PathInfo? get _currentPathInfo {
    final detail = _detail;
    final pathId = _currentPathId;
    if (detail == null || pathId == null) {
      return null;
    }
    for (final path in detail.paths) {
      if (path.pathId == pathId) {
        return path;
      }
    }
    return null;
  }

  List<StopInfo> get _currentPathStops {
    final detail = _detail;
    final pathId = _currentPathId;
    if (detail == null || pathId == null) {
      return const <StopInfo>[];
    }
    return detail.stopsByPath[pathId] ?? const <StopInfo>[];
  }

  bool _isDestinationStop(StopInfo stop) {
    return stop.pathId == _currentPathId && stop.stopId == _destinationStopId;
  }

  Future<void> _maybePromptForBackgroundTripMonitor() async {
    if (_detail == null || _backgroundTripMonitorPromptInProgress) {
      return;
    }
    final controller = AppControllerScope.read(context);
    if (controller.settings.hasSeenRouteBackgroundMonitorPrompt) {
      return;
    }

    _backgroundTripMonitorPromptInProgress = true;
    try {
      final enable = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('啟用背景乘車提醒？'),
            content: const Text('YABus 可以在你把 app 丟到背景後繼續追蹤這條路線，並在接近目的地下車前提醒你。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('暫時不要'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('啟用'),
              ),
            ],
          );
        },
      );
      if (!mounted || enable == null) {
        return;
      }

      await controller.updateEnableRouteBackgroundMonitor(
        enable,
        markPromptSeen: true,
      );
      if (enable) {
        final notificationGranted =
            await TripMonitorNotifications.requestPermission();
        if (mounted && !notificationGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('背景乘車提醒需要通知權限，否則提醒可能不會跳出。')),
          );
        }
        await _configureBackgroundTripMonitorIfNeeded(
          forcePermissionCheck: true,
        );
        await _maybePromptForDestinationSelection();
      }
    } finally {
      _backgroundTripMonitorPromptInProgress = false;
    }
  }

  TripMonitorSession? _buildTripMonitorSession({
    RouteDetailData? detail,
    PathInfo? pathInfo,
    List<StopInfo>? pathStops,
  }) {
    final resolvedDetail = detail ?? _detail;
    final resolvedPathInfo = pathInfo ?? _currentPathInfo;
    if (resolvedDetail == null || resolvedPathInfo == null) {
      return null;
    }
    final resolvedStops =
        pathStops ??
        resolvedDetail.stopsByPath[resolvedPathInfo.pathId] ??
        const <StopInfo>[];
    if (resolvedStops.isEmpty) {
      return null;
    }
    final fallbackBoardingStop = _boardingStopId == null
        ? _currentBoardingCandidateStop()
        : null;
    return TripMonitorSession(
      providerName: widget.provider.name,
      routeKey: widget.routeKey,
      routeId: resolvedDetail.route.routeId,
      routeName: resolvedDetail.route.routeName,
      pathId: resolvedPathInfo.pathId,
      pathName: resolvedPathInfo.name,
      appInForeground: _appIsForeground,
      backgroundLocationAlwaysGranted: _backgroundLocationAlwaysGranted,
      boardingStopId: _boardingStopId ?? fallbackBoardingStop?.stopId,
      boardingStopName: _boardingStopName ?? fallbackBoardingStop?.stopName,
      destinationStopId: _destinationStopId,
      destinationStopName: _destinationStopName,
      initialLatitude: _lastPosition?.latitude,
      initialLongitude: _lastPosition?.longitude,
      stops: resolvedStops
          .map(
            (stop) => TripMonitorStop(
              stopId: stop.stopId,
              stopName: stop.stopName,
              sequence: stop.sequence,
              lat: stop.lat,
              lon: stop.lon,
            ),
          )
          .toList(),
    );
  }

  Future<void> _syncBackgroundTripMonitorPausedState({
    TripMonitorSession? session,
  }) async {
    if (!_isAndroid) {
      return;
    }
    final resolvedSession = session ?? _buildTripMonitorSession();
    if (resolvedSession == null) {
      if (_backgroundTripMonitorPaused) {
        setState(() {
          _backgroundTripMonitorPaused = false;
        });
      }
      return;
    }
    final paused = await AndroidTripMonitor.isPausedFor(resolvedSession);
    if (!mounted) {
      return;
    }
    if (_backgroundTripMonitorPaused != paused) {
      setState(() {
        _backgroundTripMonitorPaused = paused;
      });
    }
  }

  Future<void> _setBackgroundTripMonitorPaused(
    bool paused, {
    String reason = 'user',
    bool showFeedback = true,
  }) async {
    if (!AppControllerScope.read(
      context,
    ).settings.enableRouteBackgroundMonitor) {
      return;
    }

    final session = _buildTripMonitorSession();
    if (paused) {
      if (_isAndroid && session != null) {
        await AndroidTripMonitor.pause(session, reason: reason);
      }
      if (_isIOS) {
        await _stopLiveActivity();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _backgroundTripMonitorPaused = true;
      });
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已暫時停止背景乘車提醒')));
      }
      return;
    }

    if (_isAndroid) {
      await AndroidTripMonitor.resume();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _backgroundTripMonitorPaused = false;
    });
    await _configureBackgroundTripMonitorIfNeeded();
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已恢復背景乘車提醒')));
    }
  }

  Future<void> _configureBackgroundTripMonitorIfNeeded({
    bool forcePermissionCheck = false,
  }) async {
    if (!mounted) {
      return;
    }

    final controller = AppControllerScope.read(context);
    if (!controller.settings.enableRouteBackgroundMonitor) {
      _backgroundTripMonitorReady = false;
      if (_isAndroid) {
        await AndroidTripMonitor.stop();
      }
      if (_isIOS) {
        await _stopLiveActivity();
        await _ensureLocationTracking(requestPermissionIfNeeded: false);
      }
      return;
    }

    final detail = _detail;
    final pathInfo = _currentPathInfo;
    if (detail == null || pathInfo == null) {
      if (_isIOS) {
        await _stopLiveActivity();
      }
      return;
    }

    if (_backgroundTripMonitorPaused && _isIOS) {
      await _stopLiveActivity();
      return;
    }

    if (_isIOS) {
      if (!_backgroundTripMonitorReady || forcePermissionCheck) {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          _backgroundTripMonitorReady = false;
          await _stopLiveActivity();
          if (forcePermissionCheck && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('要使用背景乘車提醒，請先開啟定位服務。')),
            );
          }
          return;
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied && forcePermissionCheck) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          _backgroundTripMonitorReady = false;
          await _stopLiveActivity();
          if (!forcePermissionCheck) {
            return;
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('要使用背景乘車提醒，必須先允許定位權限。')),
            );
          }
          return;
        }
        if (permission != LocationPermission.always) {
          _backgroundTripMonitorReady = false;
          await _stopLiveActivity();
          if (!forcePermissionCheck) {
            return;
          }
          final openSettings = await _showBackgroundLocationExplainer();
          if (!mounted || openSettings != true) {
            return;
          }
          _awaitingBackgroundLocationPermission = true;
          await Geolocator.openAppSettings();
          return;
        }
        _backgroundTripMonitorReady = true;
      }

      await _ensureLocationTracking(requestPermissionIfNeeded: false);
      await _syncLiveActivityForBackgroundMonitor(detail, pathInfo);
      return;
    }
    if (!_isAndroid) {
      return;
    }

    if (!_backgroundTripMonitorReady || forcePermissionCheck) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && forcePermissionCheck) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!forcePermissionCheck) {
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('要使用背景乘車提醒，必須先允許定位權限。')));
        }
        return;
      }
      final hasAlwaysPermission = permission == LocationPermission.always;
      if (_backgroundLocationAlwaysGranted != hasAlwaysPermission) {
        _backgroundLocationAlwaysGranted = hasAlwaysPermission;
      }
      if (forcePermissionCheck && !hasAlwaysPermission && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未啟用「一律允許」定位，背景乘車提醒會改用最後一次定位與公車到站資訊繼續運作。'),
          ),
        );
      }
      await TripMonitorNotifications.requestPermission();
      _backgroundTripMonitorReady = true;
    }

    final pathStops = detail.stopsByPath[pathInfo.pathId] ?? const <StopInfo>[];
    if (pathStops.isEmpty) {
      return;
    }
    if (_boardingStopId == null) {
      final boardingStop = _currentBoardingCandidateStop();
      if (boardingStop != null) {
        _boardingStopId = boardingStop.stopId;
        _boardingStopName = boardingStop.stopName;
      }
    }
    if (_destinationStopId != null &&
        pathStops.every((stop) => stop.stopId != _destinationStopId)) {
      setState(() {
        _boardingStopId = null;
        _boardingStopName = null;
        _destinationStopId = null;
        _destinationStopName = null;
        _resetLiveActivityRideState();
      });
    }

    final session = _buildTripMonitorSession(
      detail: detail,
      pathInfo: pathInfo,
      pathStops: pathStops,
    );
    if (session == null) {
      return;
    }
    await _syncBackgroundTripMonitorPausedState(session: session);
    if (_backgroundTripMonitorPaused) {
      return;
    }

    await AndroidTripMonitor.setAppInForeground(_appIsForeground);
    await AndroidTripMonitor.startOrUpdate(session);
  }

  Future<bool?> _showBackgroundLocationExplainer() {
    final contentText = _isIOS
        ? '要在把 app 丟到背景後持續更新下車提醒和靈動島，iPhone 需要將定位權限設為「永遠」。'
        : '要在把 app 丟到背景後繼續提醒，Android 需要將定位權限設為「永遠允許」。';
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('允許背景定位'),
          content: Text(contentText),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍後再說'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('前往設定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _maybePromptForDestinationSelection() async {
    if (_destinationPromptShown ||
        _destinationStopId != null ||
        _currentPathStops.isEmpty ||
        !AppControllerScope.read(
          context,
        ).settings.enableRouteBackgroundMonitor) {
      return;
    }
    _destinationPromptShown = true;

    final shouldPick = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('要設定下車提醒嗎？'),
          content: const Text('選一個你要下車的站牌，YABus 會在快到站時提醒你。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍後再說'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('選擇站牌'),
            ),
          ],
        );
      },
    );

    if (shouldPick == true) {
      await _pickDestinationStop();
    }
  }

  Future<void> _pickDestinationStop() async {
    final pathStops = _currentPathStops;
    if (pathStops.isEmpty) {
      return;
    }

    final pickedStop = await showModalBottomSheet<StopInfo>(
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
                  trailing: stop.stopId == _destinationStopId
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
    if (!mounted || pickedStop == null) {
      return;
    }

    await _setDestinationStop(pickedStop);
  }

  Future<void> _setDestinationStop(StopInfo stop) async {
    final boardingStop = _currentBoardingCandidateStop();
    setState(() {
      _resetLiveActivityRideState();
      if (_isIOS) {
        _backgroundTripMonitorPaused = false;
      }
      _boardingStopId = boardingStop?.stopId;
      _boardingStopName = boardingStop?.stopName;
      _destinationStopId = stop.stopId;
      _destinationStopName = stop.stopName;
    });
    await _configureBackgroundTripMonitorIfNeeded();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已將 ${stop.stopName} 設為下車提醒。')));
  }

  Future<void> _clearDestinationStop() async {
    if (_destinationStopId == null) {
      return;
    }
    setState(() {
      _resetLiveActivityRideState();
      if (_isIOS) {
        _backgroundTripMonitorPaused = false;
      }
      _boardingStopId = null;
      _boardingStopName = null;
      _destinationStopId = null;
      _destinationStopName = null;
    });
    await _configureBackgroundTripMonitorIfNeeded();
  }

  ScrollController _scrollControllerForPath(int pathId) {
    return _scrollControllers.putIfAbsent(pathId, ScrollController.new);
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

  Future<void> _ensureLocationTracking({
    bool requestPermissionIfNeeded = true,
  }) async {
    final controller = AppControllerScope.read(context);
    final enableBackgroundLocationStream =
        _isIOS &&
        controller.settings.enableRouteBackgroundMonitor &&
        _backgroundTripMonitorReady;
    if (_didAttemptLocationTracking &&
        _locationTrackingConfiguredForBackground ==
            enableBackgroundLocationStream) {
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (!requestPermissionIfNeeded) {
        return;
      }
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

    final locationSettings = enableBackgroundLocationStream
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            pauseLocationUpdatesAutomatically: false,
            activityType: ActivityType.automotiveNavigation,
            showBackgroundLocationIndicator: false,
            allowBackgroundLocationUpdates: true,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          );

    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_updateNearestStops);
    _didAttemptLocationTracking = true;
    _locationTrackingConfiguredForBackground = enableBackgroundLocationStream;
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
      if (_destinationStopId != null && _boardingStopId == null) {
        final boardingStop = _currentBoardingCandidateStop();
        if (boardingStop != null) {
          setState(() {
            _boardingStopId = boardingStop.stopId;
            _boardingStopName = boardingStop.stopName;
          });
          unawaited(_configureBackgroundTripMonitorIfNeeded());
        }
      }
    }
    _maybeScrollToCurrentLocation();
    unawaited(_maybeRefreshBackgroundTripMonitor());
  }

  StopInfo? _currentBoardingCandidateStop() {
    final pathId = _currentPathId;
    if (pathId == null) {
      return null;
    }
    final nearestStopId = _nearestStopByPath[pathId];
    if (nearestStopId == null) {
      return null;
    }
    for (final stop in _currentPathStops) {
      if (stop.stopId == nearestStopId) {
        return stop;
      }
    }
    return null;
  }

  void _maybeScrollToCurrentLocation() {
    if (_didAutoScrollToCurrentLocation || _requestedStopId != null) {
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
    if (_requestedStopId != stop.stopId) {
      return false;
    }
    return _targetInitialPathId == null || _targetInitialPathId == stop.pathId;
  }

  bool _isNearestStop(StopInfo stop) {
    return _nearestStopByPath[stop.pathId] == stop.stopId;
  }

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void _resetLiveActivityRideState() {
    _liveActivityBoardingWindowOpen = false;
    _liveActivityRideConfirmed = false;
    _liveActivityBoardingWindowOpenedAt = null;
    _iosBoardingCheckPromptSent = false;
    _liveActivityLastNearestStopIndex = null;
  }

  Future<void> _startLiveActivity(
    PathInfo pathInfo,
    LiveActivityDisplayState displayState,
  ) async {
    final didStart = await LiveActivityService.startLiveActivity(
      routeName: _detail?.route.routeName ?? '',
      pathName: pathInfo.name,
      routeKey: widget.routeKey,
      provider: widget.provider.name,
      pathId: pathInfo.pathId,
      state: displayState,
    );

    if (!mounted) {
      return;
    }

    if (didStart) {
      setState(() {
        _liveActivityActive = true;
        _liveActivityStopId = displayState.stopId;
        _liveActivityPathId = pathInfo.pathId;
      });
    } else {
      setState(() {
        _liveActivityActive = false;
        _liveActivityStopId = null;
        _liveActivityPathId = null;
      });
    }
  }

  Future<void> _stopLiveActivity() async {
    await TripMonitorNotifications.cancelBoardingCheckPrompt();
    await LiveActivityService.endLiveActivity();
    if (!mounted) {
      return;
    }
    setState(() {
      _resetLiveActivityRideState();
      _liveActivityActive = false;
      _liveActivityStopId = null;
      _liveActivityPathId = null;
    });
  }

  int? _resolveNearestStopIndex(List<StopInfo> pathStops) {
    if (pathStops.isEmpty) {
      return null;
    }

    final nearestStopId = _nearestStopByPath[_currentPathId];
    if (nearestStopId != null) {
      final index = pathStops.indexWhere(
        (stop) => stop.stopId == nearestStopId,
      );
      if (index != -1) {
        return index;
      }
    }

    final position = _lastPosition;
    if (position == null) {
      return null;
    }

    var nearestIndex = -1;
    double? nearestDistance;
    for (var index = 0; index < pathStops.length; index++) {
      final stop = pathStops[index];
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
        nearestIndex = index;
      }
    }

    return nearestIndex == -1 ? null : nearestIndex;
  }

  String _displayEtaText(StopInfo stop) {
    final message = stop.msg?.trim() ?? '';
    if (message.isNotEmpty) {
      if (message.contains('進站') || message.contains('到站')) {
        return '進站中';
      }
      if (message.contains('即將')) {
        return '即將進站';
      }
      if (message.contains('未發車')) {
        return '未發車';
      }
      if (message.contains('末班')) {
        return '末班已過';
      }
      return message;
    }

    final seconds = stop.sec;
    if (seconds == null) {
      return '--';
    }
    if (seconds <= 0) {
      return '進站中';
    }
    if (seconds < 60) {
      return '$seconds 秒';
    }
    return '${seconds ~/ 60} 分';
  }

  bool _isImmediateEtaText(String? etaText) {
    final value = etaText?.trim() ?? '';
    return value.contains('進站') || value.contains('即將');
  }

  bool _isBusApproachingStop(StopInfo stop) {
    final message = stop.msg?.trim() ?? '';
    return stop.buses.isNotEmpty ||
        (stop.sec != null && stop.sec! <= 0) ||
        message.contains('進站') ||
        message.contains('到站');
  }

  int? _findClosestBusIndex(List<StopInfo> stops, int nearestIndex) {
    final busIndexes = <int>[];
    for (var index = 0; index < stops.length; index++) {
      if (_isBusApproachingStop(stops[index])) {
        busIndexes.add(index);
      }
    }
    if (busIndexes.isEmpty) {
      return null;
    }

    final behindOrAtUser = busIndexes.where((index) => index <= nearestIndex);
    if (behindOrAtUser.isNotEmpty) {
      return behindOrAtUser.reduce(math.max);
    }
    return busIndexes.reduce(math.min);
  }

  int _resolveBoardingIndex(
    List<StopInfo> pathStops,
    int nearestIndex,
    int destinationIndex,
  ) {
    final explicitBoardingIndex = _boardingStopId == null
        ? -1
        : pathStops.indexWhere((stop) => stop.stopId == _boardingStopId);
    final fallbackIndex = explicitBoardingIndex == -1
        ? nearestIndex
        : explicitBoardingIndex;
    return math.min(fallbackIndex, destinationIndex);
  }

  double? _distanceToStop(StopInfo stop) {
    final position = _lastPosition;
    if (position == null || (stop.lat == 0 && stop.lon == 0)) {
      return null;
    }

    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      stop.lat,
      stop.lon,
    );
  }

  bool _updateLiveActivityRideState({
    required int nearestIndex,
    required int boardingIndex,
    required int? busStopsUntilBoarding,
    required String boardingEtaText,
    required double? boardingDistanceMeters,
    required int? busIndex,
  }) {
    final userNearBoardingStop =
        (boardingDistanceMeters != null && boardingDistanceMeters <= 180.0) ||
        nearestIndex == boardingIndex;
    final busNearBoardingStop =
        (busStopsUntilBoarding != null && busStopsUntilBoarding <= 1) ||
        _isImmediateEtaText(boardingEtaText);
    if (userNearBoardingStop && busNearBoardingStop) {
      _liveActivityBoardingWindowOpenedAt ??= DateTime.now();
      _liveActivityBoardingWindowOpen = true;
    }

    final previousNearest = _liveActivityLastNearestStopIndex;
    _liveActivityLastNearestStopIndex = nearestIndex;
    final movedForward =
        previousNearest != null && nearestIndex > previousNearest;
    final busNearUser =
        busIndex != null && (nearestIndex - busIndex).abs() <= 1;

    if (!_liveActivityRideConfirmed &&
        _liveActivityBoardingWindowOpen &&
        movedForward &&
        nearestIndex >= boardingIndex &&
        busNearUser) {
      _liveActivityRideConfirmed = true;
      unawaited(TripMonitorNotifications.cancelBoardingCheckPrompt());
    }

    return _liveActivityRideConfirmed;
  }

  String _pathStatusPrefix(String pathName) {
    final trimmed = pathName.trim();
    return trimmed.isEmpty ? '背景乘車提醒進行中' : trimmed;
  }

  String? _buildBusDistanceSummary(int? stopsAway) {
    if (stopsAway == null) {
      return null;
    }
    if (stopsAway == 0) {
      return '公車即將進站';
    }
    return '公車還有 $stopsAway 站';
  }

  String _buildNearestStatusText({
    required String pathName,
    required StopInfo nearestStop,
    required String nearestEtaText,
    required int? busStopsAway,
  }) {
    final parts = <String>[
      _pathStatusPrefix(pathName),
      '最近站牌 ${nearestStop.stopName}',
    ];
    if (nearestEtaText != '--') {
      parts.add(nearestEtaText);
    }
    final busDistanceSummary = _buildBusDistanceSummary(busStopsAway);
    if (busDistanceSummary != null) {
      parts.add(busDistanceSummary);
    }
    return parts.join(' · ');
  }

  String _buildWaitingBoardingText({
    required String pathName,
    required StopInfo boardingStop,
    required StopInfo destinationStop,
    required int? busStopsUntilBoarding,
  }) {
    final parts = <String>[
      _pathStatusPrefix(pathName),
      '尚未上車',
      '上車站 ${boardingStop.stopName}',
      '目的地 ${destinationStop.stopName}',
    ];
    final busDistanceSummary = _buildBusDistanceSummary(busStopsUntilBoarding);
    if (busDistanceSummary != null) {
      parts.add(busDistanceSummary);
    }
    return parts.join(' · ');
  }

  String? _vehicleIdForStop(StopInfo stop) {
    if (stop.buses.isEmpty) {
      return null;
    }
    return stop.buses.first.id;
  }

  ({String? previousStopName, String? nextStopName}) _adjacentStopNames(
    List<StopInfo> pathStops,
    int stopId,
  ) {
    final stopIndex = pathStops.indexWhere((stop) => stop.stopId == stopId);
    if (stopIndex == -1) {
      return (previousStopName: null, nextStopName: null);
    }

    return (
      previousStopName: stopIndex > 0
          ? pathStops[stopIndex - 1].stopName
          : null,
      nextStopName: stopIndex + 1 < pathStops.length
          ? pathStops[stopIndex + 1].stopName
          : null,
    );
  }

  ({List<String> stopNames, int currentStopIndex, int? highlightedStopIndex})
  _buildLiveActivityStopLine(
    List<StopInfo> pathStops, {
    required int anchorIndex,
    int? highlightedIndex,
  }) {
    final clampedAnchorIndex = anchorIndex.clamp(0, pathStops.length - 1);
    var startIndex = math.max(0, clampedAnchorIndex - 2);
    var endIndex = math.min(pathStops.length, startIndex + 5);
    startIndex = math.max(0, endIndex - 5);

    final stopNames = <String>[
      for (var index = startIndex; index < endIndex; index++)
        pathStops[index].stopName,
    ];
    final resolvedHighlightedIndex =
        highlightedIndex != null &&
            highlightedIndex >= startIndex &&
            highlightedIndex < endIndex
        ? highlightedIndex - startIndex
        : null;

    return (
      stopNames: stopNames,
      currentStopIndex: clampedAnchorIndex - startIndex,
      highlightedStopIndex: resolvedHighlightedIndex,
    );
  }

  LiveActivityDisplayState? _buildLiveActivityDisplayState(
    RouteDetailData detail,
    PathInfo pathInfo,
  ) {
    final pathStops = detail.stopsByPath[pathInfo.pathId] ?? const <StopInfo>[];
    if (pathStops.isEmpty) {
      _resetLiveActivityRideState();
      return null;
    }

    final nearestIndex = _resolveNearestStopIndex(pathStops);
    if (nearestIndex == null) {
      _resetLiveActivityRideState();
      final stopLine = _buildLiveActivityStopLine(
        pathStops,
        anchorIndex: _findClosestBusIndex(pathStops, pathStops.length - 1) ?? 0,
      );
      return LiveActivityDisplayState(
        stopId: pathStops.first.stopId,
        stopName: '等待目前位置',
        lineStopNames: stopLine.stopNames,
        lineCurrentStopIndex: stopLine.currentStopIndex,
        lineHighlightedStopIndex: stopLine.highlightedStopIndex,
        modeLabel: '定位中',
        statusText: _pathStatusPrefix(pathInfo.name),
      );
    }

    final nearestStop = pathStops[nearestIndex];
    final nearestEtaText = _displayEtaText(nearestStop);
    final busIndex = _findClosestBusIndex(pathStops, nearestIndex);
    final destinationIndex = _destinationStopId == null
        ? null
        : pathStops.indexWhere((stop) => stop.stopId == _destinationStopId);
    if (destinationIndex == null || destinationIndex == -1) {
      _resetLiveActivityRideState();
      final busStopsAway = busIndex == null
          ? null
          : math.max(nearestIndex - busIndex, 0);
      final stopLine = _buildLiveActivityStopLine(
        pathStops,
        anchorIndex: busIndex ?? nearestIndex,
        highlightedIndex: nearestIndex,
      );
      final adjacentStops = _adjacentStopNames(pathStops, nearestStop.stopId);
      return LiveActivityDisplayState(
        stopId: nearestStop.stopId,
        stopName: nearestStop.stopName,
        previousStopName: adjacentStops.previousStopName,
        nextStopName: adjacentStops.nextStopName,
        lineStopNames: stopLine.stopNames,
        lineCurrentStopIndex: stopLine.currentStopIndex,
        lineHighlightedStopIndex: stopLine.highlightedStopIndex,
        modeLabel: '最近站牌',
        statusText: _buildNearestStatusText(
          pathName: pathInfo.name,
          nearestStop: nearestStop,
          nearestEtaText: nearestEtaText,
          busStopsAway: busStopsAway,
        ),
        etaSeconds: nearestStop.sec,
        etaMessage: nearestStop.msg,
        vehicleId: _vehicleIdForStop(nearestStop),
      );
    }

    final destinationStop = pathStops[destinationIndex];
    final boardingIndex = _resolveBoardingIndex(
      pathStops,
      nearestIndex,
      destinationIndex,
    );
    final boardingStop = pathStops[boardingIndex];
    final boardingEtaText = _displayEtaText(boardingStop);
    final busStopsUntilBoarding = busIndex == null
        ? null
        : math.max(boardingIndex - busIndex, 0);
    final hasBoarded = _updateLiveActivityRideState(
      nearestIndex: nearestIndex,
      boardingIndex: boardingIndex,
      busStopsUntilBoarding: busStopsUntilBoarding,
      boardingEtaText: boardingEtaText,
      boardingDistanceMeters: _distanceToStop(boardingStop),
      busIndex: busIndex,
    );

    if (!hasBoarded) {
      final boardingProgressValue = busIndex == null
          ? 0
          : math.min(busIndex + 1, boardingIndex + 1);
      final stopLine = _buildLiveActivityStopLine(
        pathStops,
        anchorIndex: busIndex ?? boardingIndex,
        highlightedIndex: boardingIndex,
      );
      final adjacentStops = _adjacentStopNames(pathStops, boardingStop.stopId);
      return LiveActivityDisplayState(
        stopId: boardingStop.stopId,
        stopName: boardingStop.stopName,
        previousStopName: adjacentStops.previousStopName,
        nextStopName: adjacentStops.nextStopName,
        lineStopNames: stopLine.stopNames,
        lineCurrentStopIndex: stopLine.currentStopIndex,
        lineHighlightedStopIndex: stopLine.highlightedStopIndex,
        modeLabel: '尚未上車',
        statusText: _buildWaitingBoardingText(
          pathName: pathInfo.name,
          boardingStop: boardingStop,
          destinationStop: destinationStop,
          busStopsUntilBoarding: busStopsUntilBoarding,
        ),
        etaSeconds: boardingStop.sec,
        etaMessage: boardingStop.msg,
        vehicleId: _vehicleIdForStop(boardingStop),
        progressValue: boardingProgressValue,
        progressTotal: boardingIndex + 1,
      );
    }

    final currentProgress = math.min(nearestIndex + 1, destinationIndex + 1);
    final onboardStatusParts = <String>['已上車', '最近站牌 ${nearestStop.stopName}'];
    if (nearestEtaText != '--') {
      onboardStatusParts.add(nearestEtaText);
    }
    final stopLine = _buildLiveActivityStopLine(
      pathStops,
      anchorIndex: busIndex ?? nearestIndex,
      highlightedIndex: destinationIndex,
    );
    final adjacentStops = _adjacentStopNames(pathStops, destinationStop.stopId);

    return LiveActivityDisplayState(
      stopId: destinationStop.stopId,
      stopName: destinationStop.stopName,
      previousStopName: adjacentStops.previousStopName,
      nextStopName: adjacentStops.nextStopName,
      lineStopNames: stopLine.stopNames,
      lineCurrentStopIndex: stopLine.currentStopIndex,
      lineHighlightedStopIndex: stopLine.highlightedStopIndex,
      modeLabel: '已上車',
      statusText: onboardStatusParts.join(' · '),
      etaSeconds: destinationStop.sec,
      etaMessage: destinationStop.msg,
      vehicleId: _vehicleIdForStop(destinationStop),
      progressValue: currentProgress,
      progressTotal: destinationIndex + 1,
    );
  }

  Future<void> _syncLiveActivityForBackgroundMonitor(
    RouteDetailData detail,
    PathInfo pathInfo,
  ) async {
    final displayState = _buildLiveActivityDisplayState(detail, pathInfo);
    if (displayState == null) {
      await _stopLiveActivity();
      return;
    }

    final needsRestart =
        !_liveActivityActive || _liveActivityPathId != pathInfo.pathId;
    if (needsRestart) {
      await _startLiveActivity(pathInfo, displayState);
      return;
    }

    await LiveActivityService.updateLiveActivity(displayState);
    if (!mounted) {
      return;
    }
    if (_liveActivityStopId != displayState.stopId) {
      setState(() {
        _liveActivityStopId = displayState.stopId;
      });
    }
    await _maybeSendIOSBoardingCheckPrompt();
  }

  Future<void> _maybeSendIOSBoardingCheckPrompt() async {
    if (!_isIOS || _appIsForeground || !_backgroundTripMonitorReady) {
      await TripMonitorNotifications.cancelBoardingCheckPrompt();
      return;
    }
    if (_liveActivityRideConfirmed) {
      await TripMonitorNotifications.cancelBoardingCheckPrompt();
      return;
    }
    if (!_liveActivityBoardingWindowOpen || _iosBoardingCheckPromptSent) {
      return;
    }
    final openedAt = _liveActivityBoardingWindowOpenedAt;
    if (openedAt == null ||
        DateTime.now().difference(openedAt) <
            const Duration(seconds: 45)) {
      return;
    }
    final boardingStopName =
        _boardingStopName ?? _currentBoardingCandidateStop()?.stopName;
    if (boardingStopName == null || boardingStopName.trim().isEmpty) {
      return;
    }
    await TripMonitorNotifications.showBoardingCheckPrompt(
      routeName: _detail?.route.routeName ?? widget.routeNameHint ?? 'YABus',
      boardingStopName: boardingStopName,
      destinationStopName: _destinationStopName,
    );
    _iosBoardingCheckPromptSent = true;
  }

  Future<void> _maybeRefreshBackgroundTripMonitor() async {
    if (!_isIOS || _appIsForeground || _backgroundDataRefreshInFlight) {
      return;
    }

    final controller = AppControllerScope.read(context);
    if (!controller.settings.enableRouteBackgroundMonitor ||
        !_backgroundTripMonitorReady) {
      return;
    }

    final detail = _detail;
    final pathInfo = _currentPathInfo;
    if (detail == null || pathInfo == null) {
      return;
    }

    final refreshIntervalSeconds = math.max(
      controller.settings.busUpdateTime,
      10,
    );
    final now = DateTime.now();
    final lastRefreshAt = _lastBackgroundDataRefreshAt;
    if (lastRefreshAt != null &&
        now.difference(lastRefreshAt) <
            Duration(seconds: refreshIntervalSeconds)) {
      return;
    }

    _backgroundDataRefreshInFlight = true;
    _lastBackgroundDataRefreshAt = now;
    final previousDetail = _detail;
    try {
      final fetchedDetail = await controller.getRouteDetail(
        widget.routeKey,
        provider: widget.provider,
        routeIdHint: widget.routeIdHint,
        routeNameHint: widget.routeNameHint,
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
        _error = null;
        _statusMessage = fetchedDetail.hasLiveData ? null : '即時資訊暫時無法取得';
      });
      _recalculateNearestStops();
      await _syncLiveActivityForBackgroundMonitor(
        displayDetail,
        _currentPathInfo ?? pathInfo,
      );
    } catch (_) {
      // Keep the existing detail and retry on the next throttled location update.
    } finally {
      _backgroundDataRefreshInFlight = false;
    }
  }

  // ignore: unused_element
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
        routeId: _detail?.route.routeId,
        routeName: _detail?.route.routeName,
        stopName: stop.stopName,
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

  Future<void> _handlePinnedShortcut(StopInfo stop) async {
    final didPin = await AndroidHomeIntegration.pinStopShortcut(
      favorite: FavoriteStop(
        provider: widget.provider,
        routeKey: widget.routeKey,
        pathId: stop.pathId,
        stopId: stop.stopId,
        routeId: _detail?.route.routeId,
        routeName: _detail?.route.routeName,
        stopName: stop.stopName,
      ),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(didPin ? '已送出主畫面捷徑要求。' : '這台裝置不支援主畫面捷徑。')),
    );
  }

  Future<void> _handleDestinationAction(StopInfo stop) async {
    if (_isDestinationStop(stop)) {
      await _clearDestinationStop();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已清除下車提醒。')));
      return;
    }

    await _setDestinationStop(stop);
  }

  Future<void> _openStopActionsWithShortcut(StopInfo stop) async {
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
              onPressed: () =>
                  Navigator.of(context).pop(_StopAction.destination),
              child: Text(_isDestinationStop(stop) ? '清除下車提醒' : '設為下車提醒'),
            ),
            if (defaultTargetPlatform == TargetPlatform.android)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop(_StopAction.shortcut),
                child: const Text('新增到主畫面'),
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
    } else if (action == _StopAction.destination) {
      await _handleDestinationAction(stop);
    } else if (action == _StopAction.shortcut) {
      await _handlePinnedShortcut(stop);
    }
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

  Future<void> _openVehicleForum(String vehicleId) async {
    final didLaunch = await openTwBusForumSearch(vehicleId);
    if (!mounted || didLaunch) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('無法開啟 TWBusforum。')));
  }

  Future<void> _handleVehicleAction(
    BusVehicle vehicle,
    _VehicleAction action,
  ) async {
    switch (action) {
      case _VehicleAction.twBusForum:
        await _openVehicleForum(vehicle.id);
    }
  }

  Widget? _buildTrailingStatus(
    BuildContext context,
    ThemeData theme,
    StopInfo stop, {
    required bool isNearest,
    required bool isDestination,
  }) {
    if (isDestination) {
      return _RouteStatusPill(
        icon: Icons.flag_rounded,
        label: '下車站',
        backgroundColor: theme.colorScheme.tertiaryContainer,
        foregroundColor: theme.colorScheme.onTertiaryContainer,
      );
    }

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

      return PopupMenuButton<_VehicleAction>(
        padding: EdgeInsets.zero,
        tooltip: vehicle.id,
        onSelected: (action) =>
            unawaited(_handleVehicleAction(vehicle, action)),
        itemBuilder: (context) {
          return [
            const PopupMenuItem<_VehicleAction>(
              value: _VehicleAction.twBusForum,
              child: Text('搜尋 TWBusforum'),
            ),
          ];
        },
        child: _RouteStatusPill(
          icon: isNearest
              ? Icons.gps_fixed_rounded
              : vehicle.type == '1'
              ? Icons.accessible_rounded
              : Icons.directions_bus_rounded,
          label: vehicle.id,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
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
    BuildContext context,
    ThemeData theme,
    StopInfo stop, {
    required bool alwaysShowSeconds,
    required bool isHighlighted,
    required bool isNearest,
    required bool isDestination,
  }) {
    final trailingStatus = _buildTrailingStatus(
      context,
      theme,
      stop,
      isNearest: isNearest,
      isDestination: isDestination,
    );

    return Material(
      color: isHighlighted
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
          : isDestination
          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.22)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => unawaited(_openStopActionsWithShortcut(stop)),
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
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                    const SizedBox(width: 8),
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
          if (controller.settings.enableRouteBackgroundMonitor &&
              _currentPathStops.isNotEmpty)
            IconButton(
              onPressed: () => unawaited(
                _setBackgroundTripMonitorPaused(
                  !_backgroundTripMonitorPaused,
                  reason: 'user',
                ),
              ),
              tooltip: _backgroundTripMonitorPaused ? '恢復背景乘車提醒' : '暫時停止背景乘車提醒',
              icon: Icon(
                _backgroundTripMonitorPaused
                    ? Icons.play_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
              ),
            ),
          if (_currentPathStops.isNotEmpty)
            IconButton(
              onPressed: () => _destinationStopId == null
                  ? unawaited(_pickDestinationStop())
                  : unawaited(_clearDestinationStop()),
              icon: Icon(
                _destinationStopId == null
                    ? Icons.flag_outlined
                    : Icons.flag_rounded,
              ),
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
                                ? '路線 ID: ${detail.route.routeKey}'
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
      bottomNavigationBar: Material(
        color: theme.bottomAppBarTheme.color ?? theme.colorScheme.surface,
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
                    style: theme.textTheme.bodySmall,
                  ),
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
                    tabAlignment: TabAlignment.center,
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
                              controller: _scrollControllerForPath(path.pathId),
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
                                    context,
                                    theme,
                                    stop,
                                    alwaysShowSeconds:
                                        controller.settings.alwaysShowSeconds,
                                    isHighlighted: _isInitialStop(stop),
                                    isNearest: _isNearestStop(stop),
                                    isDestination: _isDestinationStop(stop),
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

enum _StopAction { favorite, destination, shortcut }

enum _VehicleAction { twBusForum }
