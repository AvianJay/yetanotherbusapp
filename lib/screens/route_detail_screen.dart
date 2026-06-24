import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/bus_app.dart';
import '../core/android_home_integration.dart';
import '../core/android_trip_monitor.dart';
import '../core/app_controller.dart';
import '../core/haptic_feedback_service.dart';
import '../core/app_launch_service.dart';
import '../core/app_route_observer.dart';
import '../core/app_routes.dart';
import '../core/bus_repository.dart';
import '../core/desktop_discord_presence_service.dart';
import '../core/live_activity_service.dart';
import '../core/models.dart';
import '../core/route_detail_launch_bridge.dart';
import '../core/trip_monitor_notifications.dart';
import '../core/twbusforum.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/cat_state_card.dart';
import '../widgets/eta_badge.dart';
import '../widgets/route_bus_map_sheet.dart';
import '../widgets/ad_banner_widget.dart';

class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({
    required this.routeKey,
    required this.provider,
    this.routeIdHint,
    this.routeNameHint,
    this.initialPathId,
    this.initialStopId,
    this.initialDestinationPathId,
    this.initialDestinationStopId,
    this.suppressAutoDestinationSelection = false,
    super.key,
  });

  final int routeKey;
  final BusProvider provider;
  final String? routeIdHint;
  final String? routeNameHint;
  final int? initialPathId;
  final int? initialStopId;
  final int? initialDestinationPathId;
  final int? initialDestinationStopId;
  final bool suppressAutoDestinationSelection;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  static const double _wideLayoutBreakpoint = 1080;
  static const Duration _maxMergedPreviousLiveAge = Duration(seconds: 90);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final RouteDetailLaunchHandler _launchHandler;
  late final ValueNotifier<int?> _selectedMapPathId;
  late final ValueNotifier<Map<int, List<StopInfo>>> _liveMapStopsByPath;
  ModalRoute<dynamic>? _route;
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
  Timer? _routeVisitTimer;
  bool? _wakelockEnabled;
  bool _backgroundTripMonitorReady = false;
  bool _backgroundTripMonitorPromptInProgress = false;
  bool _backgroundTripMonitorPaused = false;
  bool _backgroundDataRefreshInFlight = false;
  bool _awaitingBackgroundLocationPermission = false;
  bool _destinationPromptShown = false;
  bool _liveActivityActive = false;
  bool _showWideMapPanel = true;
  bool _pendingAutoDestinationSelection = true;
  bool _autoDestinationSelectionInProgress = false;
  bool _isRouteVisible = true;
  int? _liveActivityStopId;
  int? _liveActivityPathId;
  int? _liveActivityRouteKey;
  String? _liveActivityProviderName;
  String? _liveActivityId;
  String? _liveActivityRidingVehicleId;
  bool _liveActivityBoardingWindowOpen = false;
  bool _liveActivityRideConfirmed = false;
  DateTime? _liveActivityBoardingWindowOpenedAt;
  bool _liveActivityBoardingArrivalAlertSent = false;
  bool _liveActivityDestinationSetupAlertSent = false;
  int _liveActivityDestinationAlertStage = 0;
  bool _iosBoardingCheckPromptSent = false;
  bool _locationTrackingConfiguredForBackground = false;
  bool _backgroundLocationAlwaysGranted = false;
  int? _liveActivityLastNearestStopIndex;
  DateTime? _lastBackgroundDataRefreshAt;
  int? _requestedPathId;
  int? _requestedStopId;
  int? _targetInitialPathId;
  int? _requestedDestinationPathId;
  int? _requestedDestinationStopId;
  int? _boardingStopId;
  String? _boardingStopName;
  int? _destinationStopId;
  String? _destinationStopName;
  List<RouteAlert> _alerts = const <RouteAlert>[];
  bool _alertsFetched = false;
  bool _alertsRead = false;
  int _refreshRequestId = 0;
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
    _selectedMapPathId = ValueNotifier<int?>(widget.initialPathId);
    _liveMapStopsByPath = ValueNotifier<Map<int, List<StopInfo>>>(
      const <int, List<StopInfo>>{},
    );
    _countdownProgressController = AnimationController(vsync: this);
    _requestedPathId = widget.initialPathId;
    _requestedStopId = widget.initialStopId;
    _requestedDestinationPathId = widget.initialDestinationPathId;
    _requestedDestinationStopId = widget.initialDestinationStopId;
    _pendingAutoDestinationSelection =
        !widget.suppressAutoDestinationSelection &&
        widget.initialDestinationStopId == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      if (_route != null) {
        appRouteObserver.unsubscribe(this);
      }
      _route = route;
      if (route != null) {
        appRouteObserver.subscribe(this, route);
        _isRouteVisible = route.isCurrent;
      } else {
        _isRouteVisible = true;
      }
    }
    _syncWakelock(
      AppControllerScope.of(context).settings.keepScreenAwakeOnRouteDetail,
    );
    unawaited(_configureBackgroundTripMonitorIfNeeded());
  }

  @override
  void dispose() {
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    RouteDetailLaunchBridge.instance.detach(_launchHandler);
    _countdownTimer?.cancel();
    _routeVisitTimer?.cancel();
    _countdownProgressController.dispose();
    _selectedMapPathId.dispose();
    _liveMapStopsByPath.dispose();
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
    if (_liveActivityId != null) {
      unawaited(
        LiveActivityService.endLiveActivity(ownerActivityId: _liveActivityId),
      );
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _appIsForeground;
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed &&
        _awaitingBackgroundLocationPermission) {
      _awaitingBackgroundLocationPermission = false;
      if (_isAndroid) {
        unawaited(_handleReturnedFromAndroidBackgroundLocationSettings());
      } else {
        unawaited(
          _configureBackgroundTripMonitorIfNeeded(forcePermissionCheck: true),
        );
      }
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
    unawaited(AndroidTripMonitor.setAppInForeground(isForeground));
    if (isForeground == wasForeground) {
      if (!isForeground) {
        _pauseForegroundRefreshLoop();
      }
      return;
    }
    if (isForeground) {
      if (!wasForeground && _detail != null) {
        unawaited(_refresh());
      }
    } else {
      _pauseForegroundRefreshLoop();
    }
  }

  Future<void> _refresh() async {
    if (_shouldSuspendForegroundRefreshes) {
      return;
    }
    final requestId = ++_refreshRequestId;
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
      if (!mounted ||
          requestId != _refreshRequestId ||
          _shouldSuspendForegroundRefreshes) {
        return;
      }

      final displayDetail = !fetchedDetail.hasLiveData && previousDetail != null
          ? _mergeDetailWithPreviousLiveData(fetchedDetail, previousDetail)
          : fetchedDetail;

      _syncLiveMapStopsByPath(displayDetail.stopsByPath);
      _syncTabController(displayDetail);
      setState(() {
        _detail = displayDetail;
        _isLoading = false;
        _error = null;
        _statusMessage = fetchedDetail.hasLiveData ? null : '即時資訊暫時無法取得';
      });
      if (!_didRecordRouteVisit) {
        _didRecordRouteVisit = true;
        _routeVisitTimer = Timer(const Duration(seconds: 10), () {
          if (!mounted) return;
          final detail = _detail;
          if (detail == null) return;
          unawaited(
            AppControllerScope.read(
              context,
            ).recordRouteVisit(detail.route, provider: widget.provider),
          );
        });
      }
      if (!_alertsFetched) {
        _alertsFetched = true;
        unawaited(_fetchAndShowAlerts(displayDetail.route.routeId));
      }
      _startCountdown(
        fetchedDetail.hasLiveData
            ? controller.settings.busUpdateTime
            : controller.settings.busErrorUpdateTime,
      );
      _scrollToInitialStopIfNeeded();
      _recalculateNearestStops();
      await _applyRequestedDestinationIfPossible();
      await _maybeAutoSelectDestinationForBackgroundMonitor();
      unawaited(_ensureLocationTracking());
      unawaited(_maybePromptForBackgroundTripMonitor());
      unawaited(_configureBackgroundTripMonitorIfNeeded());
    } catch (error) {
      if (!mounted || requestId != _refreshRequestId) {
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

  void _syncLiveMapStopsByPath(Map<int, List<StopInfo>> stopsByPath) {
    _liveMapStopsByPath.value = stopsByPath.map(
      (pathId, stops) => MapEntry(pathId, List<StopInfo>.of(stops)),
    );
  }

  Future<void> _fetchAndShowAlerts(String routeId) async {
    try {
      final controller = AppControllerScope.read(context);
      final alerts = await controller.getRouteAlerts(routeId);
      if (!mounted) return;
      final activeAlertIds = alerts
          .map((alert) => alert.alertId.trim())
          .where((alertId) => alertId.isNotEmpty)
          .toSet();
      await controller.syncReadRouteAlertsForRoute(
        routeId,
        activeAlertIds: activeAlertIds,
      );
      final readAlertIds = controller.readRouteAlertIdsForRoute(routeId);
      final unseenAlerts = alerts
          .where((alert) => !readAlertIds.contains(alert.alertId.trim()))
          .toList();
      setState(() {
        _alerts = alerts;
        _alertsRead = alerts.isEmpty || unseenAlerts.isEmpty;
      });
      if (unseenAlerts.isNotEmpty) {
        await controller.syncReadRouteAlertsForRoute(
          routeId,
          activeAlertIds: activeAlertIds,
          markAsReadAlertIds: unseenAlerts.map((alert) => alert.alertId),
        );
        if (!mounted) return;
        setState(() {
          _alertsRead = true;
        });
        _showAlertsDialog();
      }
    } catch (_) {
      // Silently ignore alert fetch errors.
    }
  }

  void _playSelectionHaptic() {
    unawaited(AppHaptics.selectionClick());
  }

  void _playSuccessHaptic() {
    unawaited(AppHaptics.lightImpact());
  }

  Future<void> _markCurrentRouteAlertsAsRead() async {
    final routeId = _detail?.route.routeId.trim();
    if (routeId == null || routeId.isEmpty || _alerts.isEmpty) {
      return;
    }
    final controller = AppControllerScope.read(context);
    await controller.syncReadRouteAlertsForRoute(
      routeId,
      activeAlertIds: _alerts.map((alert) => alert.alertId),
      markAsReadAlertIds: _alerts.map((alert) => alert.alertId),
    );
  }

  void _showRouteInfoDialog(RouteDetailData detail) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _RouteInfoDialog(
          detail: detail,
          alerts: _alerts,
          repository: AppControllerScope.read(context).repository,
          provider: widget.provider,
          routeKey: widget.routeKey,
        );
      },
    );
  }

  void _showAlertsDialog() {
    if (_alerts.isEmpty || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.error,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('營運通知')),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final alert = _alerts[index];
                return _buildAlertTile(alert, theme);
              },
            ),
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
  }

  Widget _buildAlertTile(RouteAlert alert, ThemeData theme) {
    final effectLabel = alert.effectText;
    final causeLabel = alert.causeText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: alert.statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(alert.title, style: theme.textTheme.titleSmall),
            ),
          ],
        ),
        if (effectLabel.isNotEmpty || causeLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 16),
            child: Wrap(
              spacing: 6,
              children: [
                if (effectLabel.isNotEmpty)
                  Chip(
                    label: Text(effectLabel),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: theme.textTheme.labelSmall,
                    padding: EdgeInsets.zero,
                  ),
                if (causeLabel.isNotEmpty)
                  Chip(
                    label: Text(causeLabel),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: theme.textTheme.labelSmall,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        if (alert.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 16),
            child: Text(alert.description, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  RouteDetailData _mergeDetailWithPreviousLiveData(
    RouteDetailData next,
    RouteDetailData previous,
  ) {
    final now = DateTime.now();
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

        final previousUpdatedAt = _parseStopRealtimeUpdatedAt(
          previousStop.t,
          now,
        );
        if (previousUpdatedAt == null ||
            now.difference(previousUpdatedAt) > _maxMergedPreviousLiveAge) {
          return stop;
        }

        return stop.copyWith(
          sec: previousStop.sec,
          msg: previousStop.msg,
          t: previousStop.t,
          buses: previousStop.buses,
          etas: previousStop.etas,
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

  DateTime? _parseStopRealtimeUpdatedAt(String? value, DateTime now) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    final numericValue = int.tryParse(text);
    if (numericValue != null) {
      if (numericValue > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(
          numericValue,
          isUtc: true,
        ).toLocal();
      }
      if (numericValue > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(
          numericValue * 1000,
          isUtc: true,
        ).toLocal();
      }
    }

    final parsed = DateTime.tryParse(text)?.toLocal();
    if (parsed == null || parsed.isAfter(now.add(const Duration(seconds: 15)))) {
      return null;
    }
    return parsed;
  }

  void _syncTabController(RouteDetailData detail) {
    final pathIds = detail.paths.map((path) => path.pathId).toList();
    if (pathIds.isEmpty) {
      _tabController?.dispose();
      _tabController = null;
      _targetInitialPathId = null;
      _syncSelectedMapPathId(null);
      return;
    }

    final initialIndex = _resolveInitialPathIndex(detail.paths);
    _targetInitialPathId = detail.paths[initialIndex].pathId;
    // Preserve the selection by pathId rather than raw tab index, so a
    // refresh that reorders (or adds/removes) paths cannot silently switch
    // the screen, and the Live Activity, to a different direction.
    final previousSelectedPathId = _currentPathId;
    final preservedIndex = previousSelectedPathId == null
        ? -1
        : pathIds.indexOf(previousSelectedPathId);
    final selectedIndex = _tabController == null
        ? initialIndex
        : (preservedIndex != -1
              ? preservedIndex
              : _tabController!.index.clamp(0, pathIds.length - 1));

    if (_tabController?.length == pathIds.length) {
      _tabController!.index = selectedIndex;
      _syncSelectedMapPathId(detail.paths[selectedIndex].pathId);
      return;
    }

    _tabController?.dispose();
    _tabController = TabController(
      length: pathIds.length,
      vsync: this,
      initialIndex: selectedIndex,
    );
    _syncSelectedMapPathId(detail.paths[selectedIndex].pathId);
    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        return;
      }
      if (_destinationStopId != null &&
          _currentPathStops.every(
            (stop) => stop.stopId != _destinationStopId,
          )) {
        final boardingStop = _findStopById(_currentPathStops, _boardingStopId);
        _boardingStopId = boardingStop?.stopId;
        _boardingStopName = boardingStop?.stopName;
        _destinationStopId = null;
        _destinationStopName = null;
        _resetLiveActivityRideState();
      }
      if (_isIOS && _backgroundTripMonitorPaused) {
        _backgroundTripMonitorPaused = false;
      }
      _syncSelectedMapPathId();
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

    final navigator = route.navigator;
    if (navigator == null || !route.isActive) {
      return false;
    }

    if (!route.isCurrent) {
      navigator.popUntil((candidate) => identical(candidate, route));
      if (!mounted || !route.isCurrent) {
        return false;
      }
    }

    await _applyLaunchFocus(
      requestedPathId: action.pathId,
      requestedStopId: action.stopId,
      requestedDestinationPathId: action.destinationPathId,
      requestedDestinationStopId: action.destinationStopId,
    );
    return true;
  }

  Future<void> _applyLaunchFocus({
    required int? requestedPathId,
    required int? requestedStopId,
    required int? requestedDestinationPathId,
    required int? requestedDestinationStopId,
  }) async {
    final detail = _detail;
    final resolvedPathId = _resolveRequestedPathId(
      requestedPathId: requestedPathId,
      requestedStopId: requestedStopId,
    );

    setState(() {
      _requestedPathId = resolvedPathId;
      _requestedStopId = requestedStopId;
      _requestedDestinationPathId = requestedDestinationPathId;
      _requestedDestinationStopId = requestedDestinationStopId;
      _pendingAutoDestinationSelection = requestedDestinationStopId == null;
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

    await _applyRequestedDestinationIfPossible();
    await _maybeAutoSelectDestinationForBackgroundMonitor();
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

  Future<void> _applyRequestedDestinationIfPossible() async {
    final requestedDestinationStopId = _requestedDestinationStopId;
    final detail = _detail;
    if (requestedDestinationStopId == null || detail == null) {
      return;
    }

    final resolvedPathId = _resolveRequestedPathId(
      requestedPathId: _requestedDestinationPathId,
      requestedStopId: requestedDestinationStopId,
    );
    if (resolvedPathId == null) {
      return;
    }

    if (_tabController != null) {
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

    final pathStops = detail.stopsByPath[resolvedPathId] ?? const <StopInfo>[];
    final destinationStop = _findStopById(
      pathStops,
      requestedDestinationStopId,
    );
    if (destinationStop == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _requestedDestinationPathId = null;
        _requestedDestinationStopId = null;
      });
      return;
    }

    final boardingStop = _findStopById(
      pathStops,
      _nearestStopByPath[resolvedPathId],
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _pendingAutoDestinationSelection = false;
      _resetLiveActivityRideState();
      if (_isIOS) {
        _backgroundTripMonitorPaused = false;
      }
      _requestedDestinationPathId = null;
      _requestedDestinationStopId = null;
      _destinationStopId = destinationStop.stopId;
      _destinationStopName = destinationStop.stopName;
      _boardingStopId = boardingStop?.stopId;
      _boardingStopName = boardingStop?.stopName;
    });

    await _configureBackgroundTripMonitorIfNeeded();
  }

  Future<void> _maybeAutoSelectDestinationForBackgroundMonitor() async {
    if (_autoDestinationSelectionInProgress ||
        !_pendingAutoDestinationSelection ||
        _destinationStopId != null ||
        _requestedDestinationStopId != null ||
        !mounted) {
      return;
    }

    final controller = AppControllerScope.read(context);
    if (!controller.settings.enableRouteBackgroundMonitor) {
      return;
    }

    final pathStops = _currentPathStops;
    if (pathStops.isEmpty) {
      return;
    }

    final boardingStop = _autoDestinationBoardingReferenceStop();
    if (boardingStop == null) {
      return;
    }

    final boardingIndex = pathStops.indexWhere(
      (stop) => stop.stopId == boardingStop.stopId,
    );
    if (boardingIndex == -1 || boardingIndex >= pathStops.length - 1) {
      _pendingAutoDestinationSelection = false;
      return;
    }

    final destinationStop = pathStops.last;
    if (destinationStop.stopId == boardingStop.stopId) {
      _pendingAutoDestinationSelection = false;
      return;
    }

    _autoDestinationSelectionInProgress = true;
    try {
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingAutoDestinationSelection = false;
        _resetLiveActivityRideState();
        if (_isIOS) {
          _backgroundTripMonitorPaused = false;
        }
        _boardingStopId = boardingStop.stopId;
        _boardingStopName = boardingStop.stopName;
        _destinationStopId = destinationStop.stopId;
        _destinationStopName = destinationStop.stopName;
      });
      await _configureBackgroundTripMonitorIfNeeded();
    } finally {
      _autoDestinationSelectionInProgress = false;
    }
  }

  StopInfo? _autoDestinationBoardingReferenceStop() {
    return _findStopById(_currentPathStops, _boardingStopId) ??
        _findStopById(_currentPathStops, _requestedStopId) ??
        _currentBoardingCandidateStop();
  }

  StopInfo? _findStopById(List<StopInfo> stops, int? stopId) {
    if (stopId == null) {
      return null;
    }
    for (final stop in stops) {
      if (stop.stopId == stopId) {
        return stop;
      }
    }
    return null;
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
    double alignment = 0.5,
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
    scrollController.jumpTo(
      targetOffset.clamp(0.0, maxScrollExtent).toDouble(),
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

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _appIsForeground =>
      _appLifecycleState == AppLifecycleState.resumed ||
      _appLifecycleState == AppLifecycleState.inactive;

  bool get _shouldSuspendForegroundRefreshes =>
      !_isRouteVisible ||
      (_isAndroid &&
          !_appIsForeground &&
          _backgroundTripMonitorReady &&
          AppControllerScope.read(
            context,
          ).settings.enableRouteBackgroundMonitor);

  void _pauseForegroundRefreshLoop({bool invalidateRequest = false}) {
    _countdownTimer?.cancel();
    _countdownProgressController.stop();
    if (invalidateRequest) {
      _refreshRequestId += 1;
    }
  }

  @override
  void didPush() {
    _isRouteVisible = true;
  }

  @override
  void didPopNext() {
    _isRouteVisible = true;
    unawaited(_refresh());
  }

  @override
  void didPushNext() {
    _isRouteVisible = false;
    _pauseForegroundRefreshLoop(invalidateRequest: true);
  }

  @override
  void didPop() {
    _isRouteVisible = false;
    _pauseForegroundRefreshLoop(invalidateRequest: true);
  }

  void _syncSelectedMapPathId([int? pathId]) {
    final nextPathId = pathId ?? _currentPathId;
    if (_selectedMapPathId.value == nextPathId) {
      return;
    }
    _selectedMapPathId.value = nextPathId;
  }

  void _handleMapPathSelection(int pathId) {
    _syncSelectedMapPathId(pathId);
    final detail = _detail;
    final tabController = _tabController;
    if (detail == null || tabController == null) {
      return;
    }
    final targetIndex = detail.paths.indexWhere(
      (path) => path.pathId == pathId,
    );
    if (targetIndex == -1 || tabController.index == targetIndex) {
      return;
    }
    tabController.animateTo(
      targetIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openBusMapSheet() async {
    final detail = _detail;
    final routeId = detail?.route.routeId.trim() ?? '';
    final currentPathId = _currentPathId;
    if (detail == null ||
        detail.paths.isEmpty ||
        routeId.isEmpty ||
        currentPathId == null) {
      return;
    }

    _syncSelectedMapPathId(currentPathId);
    final controller = AppControllerScope.read(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 1,
          snap: true,
          snapSizes: const [0.82, 1],
          builder: (context, scrollController) {
            return RouteBusMapSheet(
              routeKey: widget.routeKey,
              provider: widget.provider,
              routeId: routeId,
              routeIdHint: widget.routeIdHint,
              routeName: detail.route.routeName,
              paths: detail.paths,
              stopsByPath: detail.stopsByPath,
              liveStopsByPathListenable: _liveMapStopsByPath,
              alwaysShowSeconds: controller.settings.alwaysShowSeconds,
              selectedPathIdListenable: _selectedMapPathId,
              refreshIntervalSeconds: controller.settings.busUpdateTime,
              dragScrollController: scrollController,
              onSelectedPathChanged: _handleMapPathSelection,
            );
          },
        );
      },
    );
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

  bool _stopHasAlert(StopInfo stop) {
    if (_alerts.isEmpty) return false;
    final stopIdStr = stop.stopId.toString();
    for (final alert in _alerts) {
      if (alert.stopIds.isNotEmpty && alert.stopIds.contains(stopIdStr)) {
        return true;
      }
    }
    return false;
  }

  Color _alertColorForStop(StopInfo stop) {
    final stopIdStr = stop.stopId.toString();
    Color color = const Color(0xFFF57C00); // default orange
    for (final alert in _alerts) {
      if (alert.stopIds.isNotEmpty && alert.stopIds.contains(stopIdStr)) {
        if (alert.status == 0) return const Color(0xFFD32F2F);
        if (alert.status == 2) color = const Color(0xFFF57C00);
      }
    }
    return color;
  }

  static Future<bool> isOppoOrRealmeAndAndroid16Plus() async {
    if (!_isAndroidPlatform) return false;

    try {
      final androidInfo = await AndroidTripMonitor.getAndroidDeviceInfo();
      if (androidInfo == null) return false;

      final manufacturer = androidInfo.manufacturer.toLowerCase();
      final brand = androidInfo.brand.toLowerCase();

      final isTargetBrand =
          manufacturer.contains('oppo') ||
          brand.contains('oppo') ||
          manufacturer.contains('realme') ||
          brand.contains('realme') ||
          manufacturer.contains('oneplus') ||
          brand.contains('oneplus');

      final isAndroid16Plus = androidInfo.sdkVersion >= 36;

      return isTargetBrand && isAndroid16Plus;
    } catch (e) {
      return false;
    }
  }

  static bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
        final isOppoOrRealme = await isOppoOrRealmeAndAndroid16Plus();
        if (isOppoOrRealme && mounted) {
          // show note blahblah
          await showDialog<void>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('提示'),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('你的系統可能支援流體雲功能，但你需要在 YABus 的通知設定裡啟用他。'),
                    SizedBox(height: 8),
                    Image(
                      image: AssetImage('assets/oppo_enable_live_alert.jpg'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      AndroidTripMonitor.openNotificationChannelSettings();
                    },
                    child: const Text('前往設定'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('好的'),
                  ),
                ],
              );
            },
          );
        }
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

    // Desktop / Web — basic notification support (no background location tracking).
    if (_isDesktop || kIsWeb) {
      if (!_backgroundTripMonitorReady || forcePermissionCheck) {
        final granted = await TripMonitorNotifications.requestPermission();
        if (granted) {
          _backgroundTripMonitorReady = true;
        } else {
          _backgroundTripMonitorReady = false;
          if (forcePermissionCheck && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('要使用乘車到站提醒，必須先允許通知權限。')),
            );
          }
          return;
        }
      }
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
      if (forcePermissionCheck && !hasAlwaysPermission) {
        final shouldUpgrade =
            await _showAndroidBackgroundLocationUpgradePrompt() ?? false;
        if (shouldUpgrade) {
          final requestStatus =
              await AndroidTripMonitor.requestBackgroundLocationPermission();
          if (!mounted) {
            return;
          }
          if (requestStatus ==
              AndroidBackgroundLocationPermissionRequestStatus.openedSettings) {
            _awaitingBackgroundLocationPermission = true;
            return;
          }
        }
        permission = await Geolocator.checkPermission();
        final updatedHasAlwaysPermission =
            permission == LocationPermission.always;
        if (_backgroundLocationAlwaysGranted != updatedHasAlwaysPermission) {
          _backgroundLocationAlwaysGranted = updatedHasAlwaysPermission;
        }
        if (!updatedHasAlwaysPermission && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未啟用「一律允許」定位，背景乘車提醒會改用最後一次定位與公車到站資訊繼續運作。'),
            ),
          );
        }
      }
      await TripMonitorNotifications.requestPermission();
      _backgroundTripMonitorReady = true;
    }

    await _ensureLocationTracking(requestPermissionIfNeeded: false);

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
      final boardingStop = _findStopById(pathStops, _boardingStopId);
      setState(() {
        _boardingStopId = boardingStop?.stopId;
        _boardingStopName = boardingStop?.stopName;
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
    if (_backgroundTripMonitorPaused) {
      return;
    }

    // Prime the service as soon as we have a valid route session so the
    // foreground/background transition is not the first cold start.
    await AndroidTripMonitor.startOrUpdate(session);
    await _syncBackgroundTripMonitorPausedState(session: session);
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

  Future<bool?> _showAndroidBackgroundLocationUpgradePrompt() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('要把定位權限改為一律允許嗎？'),
          content: const Text('YABus 需要一律允許才可以在背景偵測你是否上車或到站。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('先不用'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('去開啟'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleReturnedFromAndroidBackgroundLocationSettings() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final hasAlwaysPermission = permission == LocationPermission.always;
    if (_backgroundLocationAlwaysGranted != hasAlwaysPermission) {
      _backgroundLocationAlwaysGranted = hasAlwaysPermission;
    }
    if (!hasAlwaysPermission && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未啟用「一律允許」定位，背景乘車提醒會改用最後一次定位與公車到站資訊繼續運作。'),
        ),
      );
    }
    await _configureBackgroundTripMonitorIfNeeded();
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

  Future<StopInfo?> _pickTripMonitorStop({
    required String title,
    required int? selectedStopId,
    required IconData selectedIcon,
    int? blockedStopId,
    String? blockedReason,
  }) async {
    final pathStops = _currentPathStops;
    if (pathStops.isEmpty) {
      return null;
    }

    return showModalBottomSheet<StopInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: pathStops.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final stop = pathStops[index];
                      final isBlocked =
                          blockedStopId != null && stop.stopId == blockedStopId;
                      final subtitleParts = <String>['第 ${index + 1} 站'];
                      if (isBlocked && blockedReason != null) {
                        subtitleParts.add(blockedReason);
                      }
                      return ListTile(
                        enabled: !isBlocked,
                        title: Text(stop.stopName),
                        subtitle: Text(subtitleParts.join(' · ')),
                        trailing: isBlocked
                            ? const Icon(Icons.block_rounded)
                            : stop.stopId == selectedStopId
                            ? Icon(selectedIcon)
                            : null,
                        onTap: isBlocked
                            ? null
                            : () => Navigator.of(context).pop(stop),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickBoardingStop() async {
    final pickedStop = await _pickTripMonitorStop(
      title: '設定上車站',
      selectedStopId: _boardingStopId,
      selectedIcon: Icons.directions_bus_rounded,
      blockedStopId: _destinationStopId,
      blockedReason: '這個站已設為下車站',
    );
    if (!mounted || pickedStop == null) {
      return;
    }

    await _setBoardingStop(pickedStop);
  }

  Future<void> _pickDestinationStop() async {
    final pickedStop = await _pickTripMonitorStop(
      title: '設定下車提醒',
      selectedStopId: _destinationStopId,
      selectedIcon: Icons.flag_rounded,
      blockedStopId: _resolvedBoardingStop()?.stopId,
      blockedReason: '這個站已設為上車站',
    );
    if (!mounted || pickedStop == null) {
      return;
    }

    if (pickedStop.stopId == _resolvedBoardingStop()?.stopId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('上車站不能同時設為下車站。')));
      return;
    }
    await _setDestinationStop(pickedStop);
  }

  Future<void> _setBoardingStop(StopInfo stop) async {
    setState(() {
      _pendingAutoDestinationSelection = _destinationStopId == null;
      _resetLiveActivityRideState();
      if (_isIOS) {
        _backgroundTripMonitorPaused = false;
      }
      _boardingStopId = stop.stopId;
      _boardingStopName = stop.stopName;
    });
    await _configureBackgroundTripMonitorIfNeeded();
    await _maybeAutoSelectDestinationForBackgroundMonitor();
    if (!mounted) {
      return;
    }
    _playSuccessHaptic();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已將 ${stop.stopName} 設為上車站。')));
  }

  Future<void> _setDestinationStop(StopInfo stop) async {
    final boardingStop = _resolvedBoardingStop();
    setState(() {
      _pendingAutoDestinationSelection = false;
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
    _playSuccessHaptic();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已將 ${stop.stopName} 設為下車提醒。')));
  }

  Future<void> _clearBoardingStop() async {
    if (_boardingStopId == null) {
      return;
    }
    final fallbackBoardingStop = _currentBoardingCandidateStop();
    setState(() {
      _resetLiveActivityRideState();
      if (_isIOS) {
        _backgroundTripMonitorPaused = false;
      }
      _boardingStopId = null;
      _boardingStopName = null;
    });
    await _configureBackgroundTripMonitorIfNeeded();
    if (!mounted) {
      return;
    }
    _playSelectionHaptic();
    final message = fallbackBoardingStop == null
        ? '已清除手動上車站，之後拿到定位會再自動判斷。'
        : '已改回使用目前位置判斷上車站。';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearDestinationStop() async {
    if (_destinationStopId == null) {
      return;
    }
    setState(() {
      _pendingAutoDestinationSelection = false;
      _resetLiveActivityRideState();
      if (_isIOS) {
        _backgroundTripMonitorPaused = false;
      }
      _destinationStopId = null;
      _destinationStopName = null;
    });
    await _configureBackgroundTripMonitorIfNeeded();
    _playSelectionHaptic();
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

    Position? current;
    try {
      current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      current = null;
    }
    if (!mounted) {
      return;
    }
    if (current != null) {
      _updateNearestStops(current);
    }

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
    final previousPosition = _lastPosition;
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
      if (_destinationStopId == null) {
        unawaited(_maybeAutoSelectDestinationForBackgroundMonitor());
      }
    }
    _maybeScrollToCurrentLocation();
    if (_isAndroid &&
        previousPosition == null &&
        !_backgroundLocationAlwaysGranted &&
        _backgroundTripMonitorReady &&
        AppControllerScope.read(
          context,
        ).settings.enableRouteBackgroundMonitor) {
      unawaited(_configureBackgroundTripMonitorIfNeeded());
    }
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

  StopInfo? _resolvedBoardingStop() {
    return _findStopById(_currentPathStops, _boardingStopId) ??
        _currentBoardingCandidateStop();
  }

  String? _buildDesktopDiscordArrivalStatus(AppSettings settings) {
    if (!settings.desktopDiscordShowScreen) {
      return null;
    }

    final stop = _currentBoardingCandidateStop();
    if (stop == null) {
      return null;
    }

    final message = stop.msg?.trim() ?? '';
    if (message.isNotEmpty) {
      return switch (message) {
        '即將進站' => '公車即將到站',
        '進站中' => '公車進站中',
        '末班駛離' => '公車末班已駛離',
        '今日未營運' => '今日未營運',
        _ => '公車$message',
      };
    }

    final seconds = effectiveStopEtaSeconds(stop);
    if (seconds == null) {
      return null;
    }
    if (seconds <= 0) {
      return '公車進站中';
    }
    if (seconds < 60) {
      return '公車即將到站';
    }

    return '公車還有 ${seconds ~/ 60} 分到站';
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

  void _resetLiveActivityRideState() {
    _liveActivityBoardingWindowOpen = false;
    _liveActivityRideConfirmed = false;
    _liveActivityBoardingWindowOpenedAt = null;
    _liveActivityBoardingArrivalAlertSent = false;
    _liveActivityDestinationSetupAlertSent = false;
    _liveActivityDestinationAlertStage = 0;
    _iosBoardingCheckPromptSent = false;
    _liveActivityLastNearestStopIndex = null;
    _liveActivityRidingVehicleId = null;
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
        _liveActivityId = LiveActivityService.activeActivityId;
        _liveActivityStopId = displayState.stopId;
        _liveActivityPathId = pathInfo.pathId;
        _liveActivityRouteKey = widget.routeKey;
        _liveActivityProviderName = widget.provider.name;
      });
    } else {
      setState(() {
        _liveActivityActive = false;
        _liveActivityId = null;
        _liveActivityStopId = null;
        _liveActivityPathId = null;
        _liveActivityRouteKey = null;
        _liveActivityProviderName = null;
      });
    }
  }

  Future<void> _stopLiveActivity() async {
    await TripMonitorNotifications.cancelBoardingCheckPrompt();
    // Only end the activity this screen started; another route screen may
    // own the currently visible Live Activity.
    if (_liveActivityId != null) {
      await LiveActivityService.endLiveActivity(
        ownerActivityId: _liveActivityId,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _resetLiveActivityRideState();
      _liveActivityActive = false;
      _liveActivityId = null;
      _liveActivityStopId = null;
      _liveActivityPathId = null;
      _liveActivityRouteKey = null;
      _liveActivityProviderName = null;
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

  String _displayEtaText(StopInfo stop, {String? vehicleId}) {
    final message =
        effectiveStopEtaMessageForVehicle(stop, vehicleId)?.trim() ?? '';
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

    final seconds = effectiveStopEtaSecondsForVehicle(stop, vehicleId);
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
    final seconds = effectiveStopEtaSeconds(stop);
    return stop.buses.isNotEmpty ||
        stop.etas.any((eta) => normalizeBusVehicleId(eta.vehicleId) != null) ||
        (seconds != null && seconds <= 0) ||
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
    required String? busVehicleId,
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
      _liveActivityRidingVehicleId = normalizeBusVehicleId(busVehicleId);
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

  // ignore: unused_element
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
    StopInfo? destinationStop,
    required int? busStopsUntilBoarding,
  }) {
    final parts = <String>[
      _pathStatusPrefix(pathName),
      '尚未上車',
      '上車站 ${boardingStop.stopName}',
    ];
    if (destinationStop != null &&
        destinationStop.stopId != boardingStop.stopId) {
      parts.add('目的地 ${destinationStop.stopName}');
    }
    final busDistanceSummary = _buildBusDistanceSummary(busStopsUntilBoarding);
    if (busDistanceSummary != null) {
      parts.add(busDistanceSummary);
    }
    return parts.join(' · ');
  }

  String? _vehicleIdForStop(StopInfo stop, {String? preferredVehicleId}) {
    final preferred = normalizeBusVehicleId(preferredVehicleId);
    if (preferred != null &&
        (stop.buses.any(
              (vehicle) => normalizeBusVehicleId(vehicle.id) == preferred,
            ) ||
            stop.etas.any(
              (eta) => normalizeBusVehicleId(eta.vehicleId) == preferred,
            ))) {
      return preferred;
    }

    for (final vehicle in stop.buses) {
      final vehicleId = normalizeBusVehicleId(vehicle.id);
      if (vehicleId != null) {
        return vehicleId;
      }
    }
    for (final eta in stop.etas) {
      final vehicleId = normalizeBusVehicleId(eta.vehicleId);
      if (vehicleId != null) {
        return vehicleId;
      }
    }
    return null;
  }

  int? _findStopIndexForVehicleId(List<StopInfo> stops, String? vehicleId) {
    final normalizedVehicleId = normalizeBusVehicleId(vehicleId);
    if (normalizedVehicleId == null) {
      return null;
    }
    for (var index = 0; index < stops.length; index++) {
      final stop = stops[index];
      final vehicleSeenAtStop =
          stop.buses.any(
            (vehicle) =>
                normalizeBusVehicleId(vehicle.id) == normalizedVehicleId,
          ) ||
          stop.etas.any(
            (eta) =>
                normalizeBusVehicleId(eta.vehicleId) == normalizedVehicleId,
          );
      if (vehicleSeenAtStop) {
        return index;
      }
    }
    return null;
  }

  String? _vehicleIdAtStop(StopInfo stop, String? preferredVehicleId) {
    return _vehicleIdForStop(stop, preferredVehicleId: preferredVehicleId);
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

  String? _maybeIssueLiveActivityBoardingAlert({
    required int? busStopsUntilBoarding,
    required String boardingEtaText,
  }) {
    if (_appIsForeground || _liveActivityBoardingArrivalAlertSent) {
      return null;
    }
    final shouldAlert =
        (busStopsUntilBoarding != null && busStopsUntilBoarding <= 1) ||
        _isImmediateEtaText(boardingEtaText);
    if (!shouldAlert) {
      return null;
    }
    _liveActivityBoardingArrivalAlertSent = true;
    return 'boarding_imminent';
  }

  String? _maybeIssueLiveActivityDestinationSetupAlert() {
    if (_appIsForeground || _liveActivityDestinationSetupAlertSent) {
      return null;
    }
    _liveActivityDestinationSetupAlertSent = true;
    return 'boarded_no_destination';
  }

  String? _maybeIssueLiveActivityDestinationArrivalAlert({
    required int remainingStops,
    required double? destinationDistanceMeters,
  }) {
    if (_appIsForeground) {
      return null;
    }
    if (remainingStops <= 1 ||
        (destinationDistanceMeters != null &&
            destinationDistanceMeters <= 120)) {
      if (_liveActivityDestinationAlertStage < 2) {
        _liveActivityDestinationAlertStage = 2;
        return 'destination_arriving';
      }
      return null;
    }
    if (remainingStops <= 2 && _liveActivityDestinationAlertStage < 1) {
      _liveActivityDestinationAlertStage = 1;
      return 'destination_imminent';
    }
    return null;
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
      final explicitBoardingIndex = _boardingStopId == null
          ? null
          : pathStops.indexWhere((stop) => stop.stopId == _boardingStopId);
      final boardingIndex =
          explicitBoardingIndex != null && explicitBoardingIndex != -1
          ? explicitBoardingIndex
          : nearestIndex;
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
        busVehicleId: busIndex == null
            ? null
            : _vehicleIdForStop(pathStops[busIndex]),
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
        final adjacentStops = _adjacentStopNames(
          pathStops,
          boardingStop.stopId,
        );
        return LiveActivityDisplayState(
          stopId: boardingStop.stopId,
          stopName: boardingStop.stopName,
          previousStopName: adjacentStops.previousStopName,
          nextStopName: adjacentStops.nextStopName,
          lineStopNames: stopLine.stopNames,
          lineCurrentStopIndex: stopLine.currentStopIndex,
          lineHighlightedStopIndex: stopLine.highlightedStopIndex,
          modeLabel: '等待上車',
          statusText: _buildWaitingBoardingText(
            pathName: pathInfo.name,
            boardingStop: boardingStop,
            busStopsUntilBoarding: busStopsUntilBoarding,
          ),
          etaSeconds: effectiveStopEtaSeconds(boardingStop),
          etaMessage: boardingStop.msg,
          vehicleId: _vehicleIdForStop(boardingStop),
          progressValue: boardingProgressValue,
          progressTotal: boardingIndex + 1,
          alertKind: _maybeIssueLiveActivityBoardingAlert(
            busStopsUntilBoarding: busStopsUntilBoarding,
            boardingEtaText: boardingEtaText,
          ),
        );
      }

      final currentProgress = math.min(
        (busIndex ?? nearestIndex) + 1,
        pathStops.length,
      );
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
        statusText: '尚未設定下車站',
        etaSeconds: effectiveStopEtaSeconds(nearestStop),
        etaMessage: nearestStop.msg,
        vehicleId: _vehicleIdForStop(nearestStop),
        progressValue: currentProgress,
        progressTotal: pathStops.length,
        alertKind: _maybeIssueLiveActivityDestinationSetupAlert(),
      );
    }

    final destinationStop = pathStops[destinationIndex];
    final boardingIndex = _resolveBoardingIndex(
      pathStops,
      nearestIndex,
      destinationIndex,
    );
    final boardingStop = pathStops[boardingIndex];
    final boardingVehicleId = busIndex == null
        ? _vehicleIdForStop(boardingStop)
        : _vehicleIdForStop(pathStops[busIndex]);
    final boardingEtaText = _displayEtaText(
      boardingStop,
      vehicleId: boardingVehicleId,
    );
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
      busVehicleId: boardingVehicleId,
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
        etaSeconds: effectiveStopEtaSecondsForVehicle(
          boardingStop,
          boardingVehicleId,
        ),
        etaMessage: effectiveStopEtaMessageForVehicle(
          boardingStop,
          boardingVehicleId,
        ),
        vehicleId: boardingVehicleId,
        progressValue: boardingProgressValue,
        progressTotal: boardingIndex + 1,
      );
    }

    final currentProgress = math.min(nearestIndex + 1, destinationIndex + 1);
    final preferredRidingVehicleId = normalizeBusVehicleId(
      _liveActivityRidingVehicleId,
    );
    final hasPreferredRidingVehicleId = preferredRidingVehicleId != null;
    final ridingVehicleIndex = _findStopIndexForVehicleId(
      pathStops,
      preferredRidingVehicleId,
    );
    final displayIndex =
        ridingVehicleIndex ??
        (hasPreferredRidingVehicleId ? nearestIndex : busIndex ?? nearestIndex);
    final displayStop = pathStops[displayIndex];
    final displayVehicleId =
        ridingVehicleIndex != null || !hasPreferredRidingVehicleId
        ? _vehicleIdAtStop(displayStop, preferredRidingVehicleId)
        : null;
    if (displayVehicleId != null) {
      _liveActivityRidingVehicleId = displayVehicleId;
    }
    final stopLine = _buildLiveActivityStopLine(
      pathStops,
      anchorIndex: displayIndex,
      highlightedIndex: destinationIndex,
    );
    final adjacentStops = _adjacentStopNames(pathStops, destinationStop.stopId);
    final etaVehicleId = displayVehicleId ?? preferredRidingVehicleId;
    final destinationEtaText = _displayEtaText(
      destinationStop,
      vehicleId: etaVehicleId,
    );
    final onboardStatusParts = <String>[
      '已上車',
      '目的地 ${destinationStop.stopName}',
    ];
    if (destinationEtaText != '--') {
      onboardStatusParts.add(destinationEtaText);
    }
    onboardStatusParts.add('最近站牌 ${nearestStop.stopName}');
    if (nearestEtaText != '--') {
      onboardStatusParts.add(nearestEtaText);
    }

    return LiveActivityDisplayState(
      stopId: destinationStop.stopId,
      stopName: destinationStop.stopName,
      alertStopName: destinationStop.stopName,
      previousStopName: adjacentStops.previousStopName,
      nextStopName: adjacentStops.nextStopName,
      lineStopNames: stopLine.stopNames,
      lineCurrentStopIndex: stopLine.currentStopIndex,
      lineHighlightedStopIndex: stopLine.highlightedStopIndex,
      modeLabel: '已上車',
      statusText: onboardStatusParts.join(' · '),
      etaSeconds: effectiveStopEtaSecondsForVehicle(
        destinationStop,
        etaVehicleId,
      ),
      etaMessage: effectiveStopEtaMessageForVehicle(
        destinationStop,
        etaVehicleId,
      ),
      vehicleId: displayVehicleId,
      progressValue: currentProgress,
      progressTotal: destinationIndex + 1,
      alertKind: _maybeIssueLiveActivityDestinationArrivalAlert(
        remainingStops: destinationIndex - nearestIndex,
        destinationDistanceMeters: _distanceToStop(destinationStop),
      ),
    );
  }

  Future<void> _syncLiveActivityForBackgroundMonitor(
    RouteDetailData detail,
    PathInfo pathInfo,
  ) async {
    // Only the route screen the user is actually looking at (top of the
    // navigation stack) may drive the Live Activity. Without this guard a
    // screen lower in the stack could keep pushing its own route data into
    // an activity started by another screen, making the Dynamic Island show
    // the wrong bus/route.
    if (!_isRouteVisible) {
      return;
    }

    final displayState = _buildLiveActivityDisplayState(detail, pathInfo);
    if (displayState == null) {
      await _stopLiveActivity();
      return;
    }

    final needsRestart =
        !_liveActivityActive ||
        !LiveActivityService.ownsActivity(_liveActivityId) ||
        _liveActivityPathId != pathInfo.pathId ||
        _liveActivityRouteKey != widget.routeKey ||
        _liveActivityProviderName != widget.provider.name;
    if (needsRestart) {
      await _startLiveActivity(pathInfo, displayState);
      return;
    }

    final updated = await LiveActivityService.updateLiveActivity(
      displayState,
      ownerActivityId: _liveActivityId,
    );
    if (!mounted) {
      return;
    }
    if (!updated) {
      // The activity was dismissed or replaced natively; restart it so the
      // user keeps getting updates for the bus they are riding.
      await _startLiveActivity(pathInfo, displayState);
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
    // On desktop / web, send a notification when the bus arrives at the
    // boarding stop (foreground only — no background location tracking).
    if (_isDesktop || kIsWeb) {
      if (_appIsForeground || !_backgroundTripMonitorReady) {
        await TripMonitorNotifications.cancelBoardingCheckPrompt();
        return;
      }
      if (_iosBoardingCheckPromptSent) {
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
      return;
    }

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
        DateTime.now().difference(openedAt) < const Duration(seconds: 45)) {
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
    if (!_isIOS ||
        !_isRouteVisible ||
        _appIsForeground ||
        _backgroundDataRefreshInFlight) {
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
      _syncLiveMapStopsByPath(displayDetail.stopsByPath);
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

    final favorite = FavoriteStop(
      provider: widget.provider,
      routeKey: widget.routeKey,
      pathId: stop.pathId,
      stopId: stop.stopId,
      routeId: _detail?.route.routeId,
      routeName: _detail?.route.routeName,
      stopName: stop.stopName,
    );
    String selectedGroup;
    try {
      selectedGroup = await controller.addFavoriteStop(
        favorite,
        groupName: groupName,
      );
    } on FavoriteGroupFullException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('我的最愛已達上限 ${e.maxStops} 站，無法再加入')));
      return;
    }
    if (!mounted) {
      return;
    }

    String? assignedDestinationName;
    if (await _shouldAssignFavoriteDestination()) {
      final destination = await _pickFavoriteDestinationStop(
        pathId: stop.pathId,
      );
      if (!mounted) {
        return;
      }
      if (destination != null) {
        final didAssign = await controller.updateFavoriteDestination(
          selectedGroup,
          favorite,
          destinationPathId: destination.pathId,
          destinationStopId: destination.stopId,
          destinationStopName: destination.stopName,
        );
        if (!mounted) {
          return;
        }
        if (didAssign) {
          assignedDestinationName = destination.stopName;
        }
      }
    }

    if (!mounted) {
      return;
    }
    final message = assignedDestinationName == null
        ? '已加入 $selectedGroup'
        : '已加入 $selectedGroup，目的地：$assignedDestinationName';
    _playSuccessHaptic();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _shouldAssignFavoriteDestination() async {
    final detail = _detail;
    if (detail == null || _currentPathStops.isEmpty) {
      return false;
    }

    final shouldAssign = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('設定最愛目的地？'),
          content: const Text('下次從最愛或小工具開啟時，會自動幫你套用下車提醒。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('先不用'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('設定目的地'),
            ),
          ],
        );
      },
    );

    return shouldAssign == true;
  }

  Future<StopInfo?> _pickFavoriteDestinationStop({required int pathId}) async {
    final detail = _detail;
    if (detail == null) {
      return null;
    }
    final pathStops = detail.stopsByPath[pathId] ?? const <StopInfo>[];
    if (pathStops.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('這個方向目前沒有可選擇的站牌。')));
      return null;
    }

    return showModalBottomSheet<StopInfo>(
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
                final destinationStop = pathStops[index];
                return ListTile(
                  title: Text(destinationStop.stopName),
                  subtitle: Text('第 ${index + 1} 站'),
                  onTap: () => Navigator.of(context).pop(destinationStop),
                );
              },
            ),
          ),
        );
      },
    );
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

  bool _canOpenStopInGoogleMaps(StopInfo stop) {
    return !(stop.lat == 0 && stop.lon == 0);
  }

  Uri _buildGoogleMapsStopUri(StopInfo stop) {
    return Uri.https('www.google.com', '/maps/search/', <String, String>{
      'api': '1',
      'query': '${stop.lat},${stop.lon}',
    });
  }

  Future<void> _openStopInGoogleMaps(StopInfo stop) async {
    if (!_canOpenStopInGoogleMaps(stop)) {
      return;
    }

    final didLaunch = await launchUrl(
      _buildGoogleMapsStopUri(stop),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || didLaunch) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('無法開啟 Google Maps。')));
  }

  bool _canShowRelatedStopRoutesAction(StopInfo stop) {
    final stopName = stop.stopName.trim();
    if (stopName.isEmpty || !widget.provider.supportsLocalDatabase) {
      return false;
    }
    return AppControllerScope.read(context).isDatabaseReady(widget.provider);
  }

  String _normalizeStopRouteLookupName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  Future<List<StopRouteSearchResult>> _loadRelatedStopRoutes(
    StopInfo stop,
  ) async {
    if (!_canShowRelatedStopRoutesAction(stop)) {
      return const <StopRouteSearchResult>[];
    }

    final controller = AppControllerScope.read(context);
    final normalizedStopName = _normalizeStopRouteLookupName(stop.stopName);
    final currentRouteId =
        _detail?.route.routeId.trim() ?? widget.routeIdHint?.trim() ?? '';
    final results = await controller.searchRoutesByStop(
      stop.stopName,
      provider: widget.provider,
    );

    return results
        .where((result) {
          if (_normalizeStopRouteLookupName(result.matchedStop.stopName) !=
              normalizedStopName) {
            return false;
          }
          if (result.route.routeKey == widget.routeKey) {
            return false;
          }
          if (currentRouteId.isNotEmpty &&
              result.route.routeId.trim() == currentRouteId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  Future<List<_RelatedStopRouteEta>> _loadRelatedStopRouteEtas(
    StopInfo stop,
  ) async {
    final controller = AppControllerScope.read(context);
    final routes = await _loadRelatedStopRoutes(stop);
    if (routes.isEmpty) {
      return const <_RelatedStopRouteEta>[];
    }

    BatchLiveStopMap liveMaps = const <String, LiveStopMap>{};
    try {
      liveMaps = await controller.repository.getBatchLiveStopMaps(
        routes.map((result) => result.route.routeId).toList(growable: false),
      );
    } catch (error) {
      debugPrint('Related stop route ETA load error: $error');
    }

    final items = routes.map((result) {
      final liveMap = liveMaps[result.route.routeId.trim()];
      final livePayload = liveMap?[_relatedStopRealtimeKey(result.matchedStop)];
      final liveStop = livePayload == null
          ? result.matchedStop
          : result.matchedStop.copyWith(
              sec: livePayload.sec,
              msg: livePayload.msg,
              t: livePayload.t,
              buses: livePayload.buses,
            );
      return _RelatedStopRouteEta(result: result, liveStop: liveStop);
    }).toList();

    items.sort(_compareRelatedStopRouteEtas);
    return items;
  }

  String _relatedStopRealtimeKey(StopInfo stop) {
    return '${stop.pathId}:${stop.stopId}';
  }

  String _relatedRouteDirectionText(RouteSummary route) {
    final description = route.description.trim();
    if (description.isEmpty) {
      return '';
    }
    return description.startsWith('往') ? description : '往 $description';
  }

  int _compareRelatedStopRouteEtas(
    _RelatedStopRouteEta left,
    _RelatedStopRouteEta right,
  ) {
    final leftBucket = _relatedStopEtaSortBucket(left.liveStop);
    final rightBucket = _relatedStopEtaSortBucket(right.liveStop);
    if (leftBucket != rightBucket) {
      return leftBucket.compareTo(rightBucket);
    }

    final leftSec = left.liveStop.sec;
    final rightSec = right.liveStop.sec;
    if (leftSec != null && rightSec != null && leftSec != rightSec) {
      return leftSec.compareTo(rightSec);
    }

    final leftMessageEta = _relatedStopMessageEta(left.liveStop);
    final rightMessageEta = _relatedStopMessageEta(right.liveStop);
    if (leftMessageEta != null &&
        rightMessageEta != null &&
        leftMessageEta != rightMessageEta) {
      return leftMessageEta.compareTo(rightMessageEta);
    }
    if (leftMessageEta != null) {
      return -1;
    }
    if (rightMessageEta != null) {
      return 1;
    }

    return left.result.route.routeKey.compareTo(right.result.route.routeKey);
  }

  int _relatedStopEtaSortBucket(StopInfo stop) {
    if (stop.sec != null) {
      return 0;
    }
    if (_relatedStopMessageEta(stop) != null) {
      return 1;
    }
    if (stop.msg?.trim().isNotEmpty ?? false) {
      return 2;
    }
    return 3;
  }

  int? _relatedStopMessageEta(StopInfo stop) {
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

  String _relatedStopStatusText(StopInfo stop) {
    final message = stop.msg?.trim() ?? '';
    if (message.isNotEmpty) {
      return message;
    }

    final seconds = stop.sec;
    if (seconds == null) {
      return '無即時資料';
    }
    if (seconds <= 0) {
      return '進站中';
    }
    if (seconds < 60) {
      return '$seconds 秒';
    }

    final minutes = seconds ~/ 60;
    final leftoverSeconds = seconds % 60;
    if (AppControllerScope.read(context).settings.alwaysShowSeconds &&
        leftoverSeconds > 0) {
      return '約 $minutes 分 $leftoverSeconds 秒';
    }
    return '約 $minutes 分鐘';
  }

  Future<void> _openRelatedRouteDetail(StopRouteSearchResult result) async {
    final controller = AppControllerScope.read(context);
    final provider = busProviderFromString(result.route.sourceProvider);
    await controller.recordRouteSelection(
      provider: provider,
      routeKey: result.route.routeKey,
      routeName: result.route.routeName,
      source: 'route_detail_related_stop_routes',
    );
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(
          routeKey: result.route.routeKey,
          provider: provider,
          routeIdHint: result.route.routeId,
          routeNameHint: result.route.routeName,
          initialPathId: result.matchedStop.pathId,
          initialStopId: result.matchedStop.stopId,
          suppressAutoDestinationSelection: true,
        ),
      ),
    );
  }

  Future<void> _openRelatedStopRoutes(StopInfo stop) async {
    if (!_canShowRelatedStopRoutesAction(stop)) {
      return;
    }

    final stopName = stop.stopName.trim();
    final relatedRoutesFuture = _loadRelatedStopRouteEtas(stop);
    final selectedRoute = await showModalBottomSheet<StopRouteSearchResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: FutureBuilder<List<_RelatedStopRouteEta>>(
              future: relatedRoutesFuture,
              builder: (context, snapshot) {
                Widget content;
                if (snapshot.connectionState != ConnectionState.done) {
                  content = const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  content = Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        '載入站牌經過路線時發生錯誤',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                } else {
                  final routes =
                      snapshot.data ?? const <_RelatedStopRouteEta>[];
                  if (routes.isEmpty) {
                    content = Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          '找不到「$stopName」的其他路線',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    );
                  } else {
                    content = ListView.separated(
                      itemCount: routes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = routes[index];
                        final result = item.result;
                        final route = result.route;
                        final direction = _relatedRouteDirectionText(route);
                        final subtitleParts = <String>[
                          _relatedStopStatusText(item.liveStop),
                          if (direction.isNotEmpty) direction,
                        ];
                        return ListTile(
                          leading: EtaBadge(
                            stop: item.liveStop,
                            alwaysShowSeconds: AppControllerScope.read(
                              context,
                            ).settings.alwaysShowSeconds,
                            size: 52,
                          ),
                          title: Text(route.routeName),
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(subtitleParts.join(' · ')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(result),
                        );
                      },
                    );
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Text(
                        '站牌經過路線',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        stopName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (!mounted || selectedRoute == null) {
      return;
    }
    await _openRelatedRouteDetail(selectedRoute);
  }

  Future<void> _openStopActionsWithShortcut(StopInfo stop) async {
    final controller = AppControllerScope.read(context);
    final showDestinationAction =
        controller.settings.enableRouteBackgroundMonitor &&
        _currentPathStops.isNotEmpty;
    final showShortcutAction = _isAndroid;
    final showGoogleMapsAction = _canOpenStopInGoogleMaps(stop);
    final showRelatedRoutesAction = _canShowRelatedStopRoutesAction(stop);
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
            if (showDestinationAction)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop(_StopAction.destination),
                child: Text(_isDestinationStop(stop) ? '清除下車提醒' : '設為下車提醒'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(_StopAction.schedule),
              child: const Text('本站發車/到站時刻'),
            ),
            if (showRelatedRoutesAction)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop(_StopAction.relatedRoutes),
                child: const Text('站牌經過路線'),
              ),
            if (showGoogleMapsAction)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(context).pop(_StopAction.googleMaps),
                child: const Text('在 Google Maps 開啟'),
              ),
            if (showShortcutAction)
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
    } else if (action == _StopAction.schedule) {
      await _openStopScheduleDrawer(stop);
    } else if (action == _StopAction.relatedRoutes) {
      await _openRelatedStopRoutes(stop);
    } else if (action == _StopAction.googleMaps) {
      await _openStopInGoogleMaps(stop);
    } else if (action == _StopAction.shortcut) {
      await _handlePinnedShortcut(stop);
    }
  }

  Future<void> _openStopScheduleDrawer(StopInfo stop) async {
    final detail = _detail;
    if (detail == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _StopScheduleSheet(
          routeId: detail.route.routeId,
          routeName: detail.route.routeName,
          stop: stop,
          repository: AppControllerScope.read(context).repository,
        );
      },
    );
  }

  Widget _buildBackgroundTripMonitorDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedBoardingStop = _resolvedBoardingStop();
    final hasManualBoardingStop = _boardingStopId != null;
    final boardingName = resolvedBoardingStop?.stopName.trim();
    final boardingSubtitle = boardingName != null && boardingName.isNotEmpty
        ? '目前站點：$boardingName'
        : '沒定位時也可以手動選一個站牌當上車站。';
    final destinationName = _destinationStopName?.trim();
    final destinationSubtitle =
        destinationName != null && destinationName.isNotEmpty
        ? '目前站點：$destinationName'
        : '選擇一個站牌作為下車提醒。';

    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * 0.88, 360),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '背景乘車提醒',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '關閉',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '把背景追蹤與下車提醒控制集中在這裡。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                _backgroundTripMonitorPaused
                    ? Icons.play_circle_outline_rounded
                    : Icons.pause_circle_outline_rounded,
              ),
              title: Text(
                _backgroundTripMonitorPaused ? '恢復背景乘車提醒' : '暫時停止背景乘車提醒',
              ),
              subtitle: Text(
                _backgroundTripMonitorPaused
                    ? '重新開始背景追蹤與提醒。'
                    : '保留設定，但先停止背景追蹤與提醒。',
              ),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(
                  _setBackgroundTripMonitorPaused(
                    !_backgroundTripMonitorPaused,
                    reason: 'user',
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                resolvedBoardingStop == null
                    ? Icons.directions_bus_outlined
                    : Icons.directions_bus_rounded,
              ),
              title: Text(resolvedBoardingStop == null ? '設定上車站' : '變更上車站'),
              subtitle: Text(boardingSubtitle),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_pickBoardingStop());
              },
            ),
            if (hasManualBoardingStop)
              ListTile(
                leading: const Icon(Icons.my_location_rounded),
                title: Text(
                  _currentBoardingCandidateStop() == null
                      ? '清除手動上車站'
                      : '改回目前位置',
                ),
                subtitle: Text(
                  _currentBoardingCandidateStop() == null
                      ? '先保留背景提醒，之後拿到定位再自動判斷上車站。'
                      : '重新跟著目前最近的站牌自動判斷上車站。',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_clearBoardingStop());
                },
              ),
            ListTile(
              leading: Icon(
                _destinationStopId == null
                    ? Icons.flag_outlined
                    : Icons.flag_rounded,
              ),
              title: Text(_destinationStopId == null ? '設定下車提醒' : '清除下車提醒'),
              subtitle: Text(destinationSubtitle),
              onTap: () {
                Navigator.of(context).pop();
                if (_destinationStopId == null) {
                  unawaited(_pickDestinationStop());
                } else {
                  unawaited(_clearDestinationStop());
                }
              },
            ),
          ],
        ),
      ),
    );
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

  String _vehicleSourceLabel(BusVehicle vehicle) {
    return isBackfillBusSource(vehicle.source) ? '回灌補點' : '即時定位';
  }

  String _vehicleOfflineLabel(BusVehicle vehicle) {
    final offlineState = _vehicleOfflineState(vehicle);
    final updatedAt = offlineState.updatedAt;
    if (updatedAt == null) {
      return isBackfillBusSource(vehicle.source) ? '補點資料' : '未提供時間';
    }
    final ageSeconds = math.max(
      0,
      DateTime.now().difference(updatedAt).inSeconds,
    );
    if (ageSeconds < 20) {
      return '剛更新';
    }
    if (ageSeconds < 60) {
      return '$ageSeconds 秒前';
    }
    final minutes = ageSeconds ~/ 60;
    if (minutes < 60) {
      return '$minutes 分鐘前';
    }
    final hours = minutes ~/ 60;
    return '$hours 小時前';
  }

  Future<void> _showVehicleDetails(
    StopInfo stop,
    BusVehicle vehicle, {
    required bool isNearest,
  }) async {
    final theme = Theme.of(context);
    final statusStyle = _vehicleStatusStyleForVehicle(
      theme,
      stop,
      vehicle,
      isNearest: isNearest,
    );
    final etaSeconds = effectiveStopEtaSecondsForVehicle(stop, vehicle.id);
    final etaMessage = effectiveStopEtaMessageForVehicle(stop, vehicle.id);
    final detailRows = <({String label, String value})>[
      (label: '來源', value: _vehicleSourceLabel(vehicle)),
      (label: '離線', value: _vehicleOfflineLabel(vehicle)),
      (
        label: '本站 ETA',
        value: etaMessage?.trim().isNotEmpty == true
            ? etaMessage!.trim()
            : etaSeconds == null
            ? '--'
            : etaSeconds <= 0
            ? '進站中'
            : etaSeconds < 60
            ? '$etaSeconds 秒'
            : '${etaSeconds ~/ 60} 分',
      ),
      if (vehicle.note.trim().isNotEmpty)
        (label: '備註', value: vehicle.note.trim()),
      if (vehicle.full) (label: '車況', value: '客滿'),
      if (vehicle.carOnStop) (label: '到站', value: '目前在站'),
      if (_isElectricVehicle(vehicle)) (label: '車型', value: '電動公車'),
      if (vehicle.type == '1') (label: '設備', value: '低地板 / 無障礙'),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final bottomTheme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _RouteStatusPill(
                      icon: statusStyle.icon,
                      label: null,
                      backgroundColor: statusStyle.backgroundColor,
                      foregroundColor: statusStyle.foregroundColor,
                      borderColor: statusStyle.borderColor,
                      glowColor: statusStyle.glowColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.id,
                            style: bottomTheme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stop.stopName,
                            style: bottomTheme.textTheme.bodyMedium?.copyWith(
                              color: bottomTheme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final row in detailRows) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          row.label,
                          style: bottomTheme.textTheme.labelLarge?.copyWith(
                            color: bottomTheme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          row.value,
                          style: bottomTheme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _playSelectionHaptic();
                      unawaited(
                        _handleVehicleAction(
                          vehicle,
                          _VehicleAction.twBusForum,
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('搜尋 TWBusforum'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _displayStopName(StopInfo stop) {
    return stop.stopName;
  }

  bool _isElectricVehicle(BusVehicle vehicle) {
    final vehicleId = vehicle.id.trim().toUpperCase();
    final note = vehicle.note.toLowerCase();
    final type = vehicle.type.toLowerCase();
    return vehicle.electric ||
        vehicleId.startsWith('E') ||
        vehicleId.endsWith('FV') ||
        vehicle.note.contains('電動') ||
        vehicle.note.contains('純電') ||
        vehicle.note.contains('電巴') ||
        note.contains('electric') ||
        note.contains('e-bus') ||
        note.contains('e_bus') ||
        type.contains('electric') ||
        type.contains('e-bus') ||
        type.contains('e_bus');
  }

  Color _blendColor(Color start, Color end, double amount) {
    return Color.lerp(start, end, amount.clamp(0.0, 1.0)) ?? end;
  }

  ({double severity, DateTime? updatedAt}) _vehicleOfflineState(
    BusVehicle vehicle,
  ) {
    return (
      severity: busOfflineSeverity(source: vehicle.source),
      updatedAt: null,
    );
  }

  String _vehicleStatusTooltip(StopInfo stop) {
    final ids = stop.buses.map((vehicle) => vehicle.id).join('、');
    final flags = <String>[
      if (stop.buses.any((vehicle) => vehicle.carOnStop)) '進站中',
      if (stop.buses.any((vehicle) => vehicle.full)) '客滿',
      if (stop.buses.any(_isElectricVehicle)) '電動車',
      if (stop.buses.any((vehicle) => vehicle.type == '1')) '無障礙',
    ];
    if (flags.isEmpty) {
      return ids;
    }
    return '$ids · ${flags.join(' · ')}';
  }

  _VehicleStatusStyle _vehicleStatusStyleForVehicle(
    ThemeData theme,
    StopInfo stop,
    BusVehicle vehicle, {
    required bool isNearest,
  }) {
    final seconds = effectiveStopEtaSecondsForVehicle(stop, vehicle.id);
    final hasArrivingBus =
        vehicle.carOnStop || (seconds != null && seconds <= 0);
    final isLessThanOneMinute = seconds != null && seconds > 0 && seconds < 60;
    final isUrgentEta = seconds != null && seconds >= 60 && seconds < 180;
    final hasFullBus = vehicle.full;
    final hasElectricBus = _isElectricVehicle(vehicle);
    final hasAccessibleBus = vehicle.type == '1';
    final vehicleIcon = hasElectricBus
        ? Icons.electric_bolt_rounded
        : Icons.directions_bus_filled_rounded;

    _VehicleStatusStyle style;
    if (hasArrivingBus) {
      style = _VehicleStatusStyle(
        icon: vehicleIcon,
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        borderColor: Colors.red.shade200.withValues(alpha: 0.85),
        glowColor: Colors.red.shade500.withValues(alpha: 0.38),
      );
    } else if (isLessThanOneMinute) {
      style = _VehicleStatusStyle(
        icon: hasElectricBus
            ? Icons.electric_bolt_rounded
            : Icons.timer_rounded,
        backgroundColor: Colors.deepOrange.shade600,
        foregroundColor: Colors.white,
        borderColor: Colors.orange.shade200.withValues(alpha: 0.8),
        glowColor: Colors.deepOrange.shade400.withValues(alpha: 0.32),
      );
    } else if (isUrgentEta) {
      style = _VehicleStatusStyle(
        icon: hasElectricBus
            ? Icons.electric_bolt_rounded
            : Icons.timer_rounded,
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        borderColor: Colors.orange.shade200.withValues(alpha: 0.78),
        glowColor: Colors.orange.shade400.withValues(alpha: 0.28),
      );
    } else if (hasFullBus) {
      style = _VehicleStatusStyle(
        icon: hasElectricBus
            ? Icons.electric_bolt_rounded
            : Icons.groups_rounded,
        backgroundColor: Colors.brown.shade600,
        foregroundColor: Colors.white,
        borderColor: Colors.orange.shade200.withValues(alpha: 0.75),
        glowColor: Colors.brown.shade400.withValues(alpha: 0.28),
      );
    } else if (hasElectricBus) {
      style = _VehicleStatusStyle(
        icon: Icons.electric_bolt_rounded,
        backgroundColor: Colors.amber.shade500,
        foregroundColor: Colors.black87,
        borderColor: Colors.amber.shade100.withValues(alpha: 0.9),
        glowColor: Colors.amber.shade400.withValues(alpha: 0.3),
      );
    } else if (isNearest) {
      style = _VehicleStatusStyle(
        icon: Icons.gps_fixed_rounded,
        backgroundColor: Colors.cyan.shade400,
        foregroundColor: Colors.black87,
        borderColor: Colors.cyan.shade100.withValues(alpha: 0.8),
        glowColor: Colors.cyan.shade300.withValues(alpha: 0.32),
      );
    } else if (hasAccessibleBus) {
      style = _VehicleStatusStyle(
        icon: Icons.accessible_rounded,
        backgroundColor: Colors.indigo.shade500,
        foregroundColor: Colors.white,
        borderColor: Colors.indigo.shade100.withValues(alpha: 0.7),
        glowColor: Colors.indigo.shade300.withValues(alpha: 0.2),
      );
    } else {
      style = _VehicleStatusStyle(
        icon: Icons.directions_bus_rounded,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        borderColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        glowColor: theme.colorScheme.primary.withValues(alpha: 0.16),
      );
    }

    final offlineState = _vehicleOfflineState(vehicle);
    if (offlineState.severity <= 0) {
      return style;
    }

    return _VehicleStatusStyle(
      icon: offlineState.severity >= 0.65 ? Icons.wifi_off_rounded : style.icon,
      backgroundColor: _blendColor(
        style.backgroundColor,
        Colors.red.shade800,
        offlineState.severity * 0.88,
      ),
      foregroundColor: style.foregroundColor,
      borderColor: _blendColor(
        style.borderColor,
        Colors.red.shade200,
        offlineState.severity * 0.72,
      ),
      glowColor: _blendColor(
        style.glowColor,
        Colors.red.shade400.withValues(alpha: 0.34),
        offlineState.severity * 0.82,
      ),
    );
  }

  _VehicleStatusStyle _vehicleStatusStyle(
    ThemeData theme,
    StopInfo stop, {
    required bool isNearest,
  }) {
    if (stop.buses.length == 1) {
      return _vehicleStatusStyleForVehicle(
        theme,
        stop,
        stop.buses.first,
        isNearest: isNearest,
      );
    }

    final seconds = effectiveStopEtaSeconds(stop);
    final hasMultipleBuses = stop.buses.length > 1;
    final hasArrivingBus =
        stop.buses.any((vehicle) => vehicle.carOnStop) ||
        (seconds != null && seconds <= 0);
    final isLessThanOneMinute = seconds != null && seconds > 0 && seconds < 60;
    final isUrgentEta = seconds != null && seconds >= 60 && seconds < 180;
    final hasFullBus = stop.buses.any((vehicle) => vehicle.full);
    final hasElectricBus = stop.buses.any(_isElectricVehicle);
    final hasAccessibleBus = stop.buses.any((vehicle) => vehicle.type == '1');
    final maxOfflineSeverity = stop.buses
        .map((vehicle) => _vehicleOfflineState(vehicle).severity)
        .fold<double>(0.0, math.max);
    final vehicleIcon = hasElectricBus
        ? Icons.electric_bolt_rounded
        : Icons.directions_bus_filled_rounded;

    _VehicleStatusStyle style;
    if (hasArrivingBus) {
      style = _VehicleStatusStyle(
        icon: vehicleIcon,
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        borderColor: Colors.red.shade200.withValues(alpha: 0.85),
        glowColor: Colors.red.shade500.withValues(alpha: 0.38),
        showStackedBuses: hasMultipleBuses,
      );
    } else if (isLessThanOneMinute) {
      style = _VehicleStatusStyle(
        icon: hasElectricBus
            ? Icons.electric_bolt_rounded
            : Icons.timer_rounded,
        backgroundColor: Colors.deepOrange.shade600,
        foregroundColor: Colors.white,
        borderColor: Colors.orange.shade200.withValues(alpha: 0.8),
        glowColor: Colors.deepOrange.shade400.withValues(alpha: 0.32),
        showStackedBuses: hasMultipleBuses,
      );
    } else if (isUrgentEta) {
      style = _VehicleStatusStyle(
        icon: hasElectricBus
            ? Icons.electric_bolt_rounded
            : Icons.timer_rounded,
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        borderColor: Colors.orange.shade200.withValues(alpha: 0.78),
        glowColor: Colors.orange.shade400.withValues(alpha: 0.28),
        showStackedBuses: hasMultipleBuses,
      );
    } else if (hasFullBus) {
      style = _VehicleStatusStyle(
        icon: hasElectricBus
            ? Icons.electric_bolt_rounded
            : Icons.groups_rounded,
        backgroundColor: Colors.brown.shade600,
        foregroundColor: Colors.white,
        borderColor: Colors.orange.shade200.withValues(alpha: 0.75),
        glowColor: Colors.brown.shade400.withValues(alpha: 0.28),
        showStackedBuses: hasMultipleBuses,
      );
    } else if (hasElectricBus) {
      style = _VehicleStatusStyle(
        icon: Icons.electric_bolt_rounded,
        backgroundColor: Colors.amber.shade500,
        foregroundColor: Colors.black87,
        borderColor: Colors.amber.shade100.withValues(alpha: 0.9),
        glowColor: Colors.amber.shade400.withValues(alpha: 0.3),
        showStackedBuses: hasMultipleBuses,
      );
    } else if (isNearest) {
      style = _VehicleStatusStyle(
        icon: Icons.gps_fixed_rounded,
        backgroundColor: Colors.cyan.shade400,
        foregroundColor: Colors.black87,
        borderColor: Colors.cyan.shade100.withValues(alpha: 0.8),
        glowColor: Colors.cyan.shade300.withValues(alpha: 0.32),
        showStackedBuses: hasMultipleBuses,
      );
    } else if (hasMultipleBuses) {
      style = _VehicleStatusStyle(
        icon: Icons.directions_bus_rounded,
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        borderColor: theme.colorScheme.secondary.withValues(alpha: 0.45),
        glowColor: theme.colorScheme.secondary.withValues(alpha: 0.2),
        showStackedBuses: true,
      );
    } else if (hasAccessibleBus) {
      style = _VehicleStatusStyle(
        icon: Icons.accessible_rounded,
        backgroundColor: Colors.indigo.shade500,
        foregroundColor: Colors.white,
        borderColor: Colors.indigo.shade100.withValues(alpha: 0.7),
        glowColor: Colors.indigo.shade300.withValues(alpha: 0.2),
      );
    } else {
      style = _VehicleStatusStyle(
        icon: Icons.directions_bus_rounded,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        borderColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        glowColor: theme.colorScheme.primary.withValues(alpha: 0.16),
      );
    }

    if (maxOfflineSeverity <= 0) {
      return style;
    }

    return _VehicleStatusStyle(
      icon: maxOfflineSeverity >= 0.65 ? Icons.wifi_off_rounded : style.icon,
      backgroundColor: _blendColor(
        style.backgroundColor,
        Colors.red.shade800,
        maxOfflineSeverity * 0.82,
      ),
      foregroundColor: style.foregroundColor,
      borderColor: _blendColor(
        style.borderColor,
        Colors.red.shade200,
        maxOfflineSeverity * 0.7,
      ),
      glowColor: _blendColor(
        style.glowColor,
        Colors.red.shade400.withValues(alpha: 0.32),
        maxOfflineSeverity * 0.8,
      ),
      showStackedBuses: style.showStackedBuses,
    );
  }

  double _measureMaxLineWidth(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final textDirection = Directionality.of(context);
    var maxWidth = 0.0;
    for (final line in text.split('\n')) {
      final painter = TextPainter(
        text: TextSpan(text: line, style: style),
        maxLines: 1,
        textDirection: textDirection,
      )..layout();
      maxWidth = math.max(maxWidth, painter.width);
    }
    return maxWidth;
  }

  double _estimateRouteStatusPillWidth(
    BuildContext context, {
    required IconData icon,
    String? label,
    bool showStackedBuses = false,
  }) {
    final hasLabel = label != null && label.trim().isNotEmpty;
    final labelWidth = hasLabel
        ? _measureMaxLineWidth(
            context,
            label,
            const TextStyle(fontWeight: FontWeight.w700),
          )
        : 0.0;
    final horizontalPadding = hasLabel ? 28.0 : 20.0;
    final gap = hasLabel ? 8.0 : 0.0;
    final iconWidth = showStackedBuses ? 28.0 : 18.0;
    return horizontalPadding + iconWidth + gap + labelWidth;
  }

  bool _shouldUseCompactVehicleStatus(
    BuildContext context,
    ThemeData theme,
    StopInfo stop, {
    required bool isNearest,
    required double availableWidth,
  }) {
    if (stop.buses.isEmpty) {
      return false;
    }

    final stopNameWidth = _measureMaxLineWidth(
      context,
      _displayStopName(stop),
      theme.textTheme.headlineSmall?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
        height: 1.2,
      ),
    );
    final statusStyle = _vehicleStatusStyle(theme, stop, isNearest: isNearest);
    final fullPillWidth = _estimateRouteStatusPillWidth(
      context,
      icon: statusStyle.icon,
      label: null,
      showStackedBuses: statusStyle.showStackedBuses,
    );
    final hasAlert = _stopHasAlert(stop);
    final alertWidth = hasAlert ? 16.0 : 0.0;
    final alertSpacing = hasAlert ? 6.0 : 0.0;
    const dividerSpacing = 8.0;
    const dividerMinWidth = 96.0;
    const trailingSpacing = 8.0;

    final requiredWidth =
        stopNameWidth +
        alertSpacing +
        alertWidth +
        dividerSpacing +
        dividerMinWidth +
        trailingSpacing +
        fullPillWidth;
    return requiredWidth > availableWidth;
  }

  Widget _buildVehicleMenuItem(BuildContext context, BusVehicle vehicle) {
    final theme = Theme.of(context);
    final details = <String>[
      if (vehicle.note.trim().isNotEmpty) vehicle.note.trim(),
      if (vehicle.full) '滿載',
      if (vehicle.carOnStop) '進站中',
      '搜尋 TWBusforum',
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          vehicle.type == '1'
              ? Icons.accessible_rounded
              : Icons.directions_bus_rounded,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vehicle.id,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(details.join(' · '), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _buildTrailingStatus(
    BuildContext context,
    ThemeData theme,
    StopInfo stop, {
    required bool isNearest,
    required bool isDestination,
  }) {
    if (isNearest) {
      return const _RouteStatusPill(
        icon: Icons.gps_fixed_rounded,
        label: '你的位置',
        backgroundColor: Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      );
    }

    if (isDestination) {
      return _RouteStatusPill(
        icon: Icons.flag_rounded,
        label: '下車站',
        backgroundColor: theme.colorScheme.tertiaryContainer,
        foregroundColor: theme.colorScheme.onTertiaryContainer,
      );
    }

    if (stop.buses.isNotEmpty) {
      final statusStyle = _vehicleStatusStyle(
        theme,
        stop,
        isNearest: isNearest,
      );
      final primaryVehicle = stop.buses.first;
      final pill = _RouteStatusPill(
        icon: statusStyle.icon,
        label: null,
        backgroundColor: statusStyle.backgroundColor,
        foregroundColor: statusStyle.foregroundColor,
        borderColor: statusStyle.borderColor,
        glowColor: statusStyle.glowColor,
        showStackedBuses: statusStyle.showStackedBuses,
      );

      if (stop.buses.length == 1) {
        return Tooltip(
          message: _vehicleStatusTooltip(stop),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              _playSelectionHaptic();
              unawaited(
                _showVehicleDetails(stop, primaryVehicle, isNearest: isNearest),
              );
            },
            child: pill,
          ),
        );
      }

      return PopupMenuButton<BusVehicle>(
        padding: EdgeInsets.zero,
        tooltip: _vehicleStatusTooltip(stop),
        onSelected: (vehicle) {
          _playSelectionHaptic();
          unawaited(_showVehicleDetails(stop, vehicle, isNearest: isNearest));
        },
        itemBuilder: (context) {
          return [
            for (final vehicle in stop.buses)
              PopupMenuItem<BusVehicle>(
                value: vehicle,
                child: _buildVehicleMenuItem(context, vehicle),
              ),
          ];
        },
        child: pill,
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
    final stopNameStyle = theme.textTheme.headlineSmall?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.primary,
      height: 1.2,
    );
    final stopName = _displayStopName(stop);
    final hasAlert = _stopHasAlert(stop);

    return Material(
      color: isHighlighted
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
          : isDestination
          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.22)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          _playSelectionHaptic();
          unawaited(_openStopActionsWithShortcut(stop));
        },
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useCompactVehicleStatus =
                        stop.buses.isNotEmpty &&
                        _shouldUseCompactVehicleStatus(
                          context,
                          theme,
                          stop,
                          isNearest: isNearest,
                          availableWidth: constraints.maxWidth,
                        );
                    final trailingStatus = _buildTrailingStatus(
                      context,
                      theme,
                      stop,
                      isNearest: isNearest,
                      isDestination: isDestination,
                    );
                    final vehicleStatusStyle = stop.buses.isEmpty
                        ? null
                        : _vehicleStatusStyle(
                            theme,
                            stop,
                            isNearest: isNearest,
                          );
                    final trailingStatusWidth = switch ((
                      isNearest,
                      isDestination,
                      stop.buses.isNotEmpty,
                    )) {
                      (true, _, _) => _estimateRouteStatusPillWidth(
                        context,
                        icon: Icons.gps_fixed_rounded,
                        label: '你的位置',
                      ),
                      (false, true, _) => _estimateRouteStatusPillWidth(
                        context,
                        icon: Icons.flag_rounded,
                        label: '下車站',
                      ),
                      (false, false, true) => _estimateRouteStatusPillWidth(
                        context,
                        icon: vehicleStatusStyle!.icon,
                        label: null,
                        showStackedBuses: vehicleStatusStyle.showStackedBuses,
                      ),
                      _ => 0.0,
                    };
                    final minimumDividerWidth = trailingStatus == null
                        ? 48.0
                        : useCompactVehicleStatus
                        ? 36.0
                        : 28.0;
                    final stopNameMaxWidth = math.max(
                      96.0,
                      constraints.maxWidth -
                          minimumDividerWidth -
                          trailingStatusWidth -
                          (trailingStatus == null ? 0.0 : 8.0) -
                          (hasAlert ? 16.0 : 0.0) -
                          (hasAlert ? 6.0 : 0.0) -
                          6.0,
                    );
                    final stopNameWidth = math.min(
                      _measureMaxLineWidth(context, stopName, stopNameStyle),
                      math.min(stopNameMaxWidth, constraints.maxWidth),
                    );
                    final dividerLeftOffset =
                        stopNameWidth + 6.0 + (hasAlert ? 16.0 + 6.0 : 0.0);
                    final dividerRightOffset = trailingStatus == null
                        ? 0.0
                        : trailingStatusWidth + 8.0;
                    final showDivider =
                        constraints.maxWidth -
                            dividerLeftOffset -
                            dividerRightOffset >=
                        24.0;

                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        if (showDivider)
                          Positioned(
                            left: dividerLeftOffset,
                            right: dividerRightOffset,
                            child: Container(
                              height: 1,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: stopNameWidth,
                              child: Text(
                                stopName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: stopNameStyle,
                              ),
                            ),
                            if (hasAlert) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: _showAlertsDialog,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: _alertColorForStop(stop),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (trailingStatus != null) ...[
                              const SizedBox(width: 8),
                              trailingStatus,
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopsPane(
    BuildContext context,
    ThemeData theme,
    AppController controller,
    RouteDetailData detail,
  ) {
    return Column(
      children: [
        if (_tabController != null)
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: detail.paths.map((path) => Tab(text: path.name)).toList(),
          ),
        Expanded(
          child: _tabController == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CatStateCard(
                      mood: CatStateMood.sad,
                      title: '這條路線還沒有方向資料',
                      message: '貓貓翻不到去程或返程，稍後再試試看。',
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: detail.paths.map((path) {
                    final pathStops =
                        detail.stopsByPath[path.pathId] ?? const <StopInfo>[];
                    if (pathStops.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CatStateCard(
                            mood: CatStateMood.sad,
                            title: '這個方向沒有站牌',
                            message: '可能是資料還沒同步完成，等一下再更新。',
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: _scrollControllerForPath(path.pathId),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      itemCount: pathStops.length + 2,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        if (index == 0 || index == pathStops.length + 1) {
                          return const AdBannerWidget();
                        }
                        final stop = pathStops[index - 1];
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
    );
  }

  Widget _buildInlineMapPane(
    BuildContext context,
    AppController controller,
    RouteDetailData detail,
  ) {
    final routeId = detail.route.routeId.trim();
    final currentPathId = _currentPathId;
    if (routeId.isEmpty || currentPathId == null) {
      return const ColoredBox(
        color: Colors.transparent,
        child: Center(child: Text('目前沒有可顯示的地圖資料')),
      );
    }

    return RouteBusMapSheet(
      routeKey: widget.routeKey,
      provider: widget.provider,
      routeId: routeId,
      routeIdHint: widget.routeIdHint,
      routeName: detail.route.routeName,
      paths: detail.paths,
      stopsByPath: detail.stopsByPath,
      liveStopsByPathListenable: _liveMapStopsByPath,
      alwaysShowSeconds: controller.settings.alwaysShowSeconds,
      selectedPathIdListenable: _selectedMapPathId,
      refreshIntervalSeconds: controller.settings.busUpdateTime,
      onSelectedPathChanged: _handleMapPathSelection,
      embedded: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final detail = _detail;
    final theme = Theme.of(context);
    final settings = controller.settings;
    final isAmoled =
        settings.useAmoledDark && settings.themeMode != ThemeMode.light;
    final hasRouteDetailBackgroundImage = hasBackgroundImageForPage(
      settings,
      pageKey: 'route_detail',
    );
    final currentPathId = _currentPathId;
    final currentNearestStopId = currentPathId == null
        ? null
        : _nearestStopByPath[currentPathId];
    final canOpenBackgroundTripMonitorDrawer =
        settings.enableRouteBackgroundMonitor && _currentPathStops.isNotEmpty;
    final isWideLayout =
        MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    final canShowInlineMap =
        isWideLayout && detail != null && currentPathId != null;
    final showInlineMap = canShowInlineMap && _showWideMapPanel;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final baseBottomBarColor =
        theme.bottomAppBarTheme.color ??
        (hasRouteDetailBackgroundImage && !isAmoled
            ? theme.colorScheme.surface.withValues(
                alpha: (theme.appBarTheme.backgroundColor?.a ?? 1.0),
              )
            : theme.colorScheme.surface);
    final bottomBarColor = baseBottomBarColor.a < 0.92
        ? baseBottomBarColor.withValues(alpha: 0.92)
        : baseBottomBarColor;

    unawaited(
      desktopDiscordPresenceService.updateScreen(
        settings: settings,
        screenLabel: '查看路線',
        provider: widget.provider,
        routeName: detail?.route.routeName,
        stateLabel: _buildDesktopDiscordArrivalStatus(settings),
      ),
    );

    return BackgroundImageWrapper(
      pageKey: 'route_detail',
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: hasRouteDetailBackgroundImage
            ? Colors.transparent
            : null,
        endDrawer: canOpenBackgroundTripMonitorDrawer
            ? _buildBackgroundTripMonitorDrawer(context)
            : null,
        appBar: AppBar(
          title: Text(detail?.route.routeName ?? '公車資訊'),
          actions: [
            if (detail != null && currentPathId != null)
              IconButton(
                onPressed: () {
                  if (isWideLayout) {
                    setState(() {
                      _showWideMapPanel = !_showWideMapPanel;
                    });
                    return;
                  }
                  unawaited(_openBusMapSheet());
                },
                tooltip: isWideLayout
                    ? (showInlineMap ? '隱藏地圖' : '顯示地圖')
                    : '公車地圖',
                icon: Icon(
                  showInlineMap ? Icons.map_rounded : Icons.map_outlined,
                ),
              ),
            if (currentPathId != null && currentNearestStopId != null)
              IconButton(
                onPressed: () => unawaited(
                  _scrollToStop(currentPathId, currentNearestStopId),
                ),
                icon: const Icon(Icons.gps_fixed_rounded),
              ),
            if (canOpenBackgroundTripMonitorDrawer)
              IconButton(
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                tooltip: '背景乘車提醒',
                icon: Icon(
                  _backgroundTripMonitorPaused
                      ? Icons.notifications_paused_outlined
                      : Icons.notifications_active_outlined,
                ),
              ),
            IconButton(
              onPressed: detail == null
                  ? null
                  : () async {
                      if (_alerts.isNotEmpty) {
                        await _markCurrentRouteAlertsAsRead();
                      }
                      if (!mounted) {
                        return;
                      }
                      if (_alerts.isNotEmpty && !_alertsRead) {
                        setState(() {
                          _alertsRead = true;
                        });
                      }
                      _showRouteInfoDialog(detail);
                    },
              icon: _alerts.isNotEmpty && !_alertsRead
                  ? const Badge(
                      smallSize: 8,
                      child: Icon(Icons.info_outline_rounded),
                    )
                  : const Icon(Icons.info_outline_rounded),
            ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: bottomBarColor,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBottomProgressIndicator(),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _statusMessage ??
                        (_remainingSeconds > 0
                            ? '$_remainingSeconds 秒後更新'
                            : '正在更新'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        body: _isLoading && detail == null
            ? const Center(child: CircularProgressIndicator())
            : detail == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CatStateCard(
                    mood: CatStateMood.cry,
                    title: '公車資訊被貓貓壓住了',
                    message: _error ?? '目前無法載入公車資訊，稍後再更新一次。',
                    actionLabel: '重新載入',
                    onAction: () => unawaited(_refresh()),
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final canUseWideLayout =
                      constraints.maxWidth >= _wideLayoutBreakpoint;
                  final showWideMap =
                      canUseWideLayout &&
                      _showWideMapPanel &&
                      currentPathId != null;
                  final stopsPane = _buildStopsPane(
                    context,
                    theme,
                    controller,
                    detail,
                  );
                  if (!showWideMap) {
                    return stopsPane;
                  }

                  final maxMapPaneWidth = math.max(
                    400.0,
                    constraints.maxWidth - 420.0,
                  );
                  final mapPaneWidth = math
                      .min(
                        math.max(constraints.maxWidth * 0.55, 520),
                        maxMapPaneWidth,
                      )
                      .toDouble();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: stopsPane),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      SizedBox(
                        width: mapPaneWidth,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: _buildInlineMapPane(
                            context,
                            controller,
                            detail,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _VehicleStatusStyle {
  const _VehicleStatusStyle({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.glowColor,
    this.showStackedBuses = false,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final Color glowColor;
  final bool showStackedBuses;
}

class _RouteStatusPill extends StatelessWidget {
  const _RouteStatusPill({
    required this.icon,
    this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    this.glowColor,
    this.showStackedBuses = false,
  });

  final IconData icon;
  final String? label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final Color? glowColor;
  final bool showStackedBuses;

  Widget _buildIcon() {
    if (!showStackedBuses) {
      return Icon(icon, size: 18, color: foregroundColor);
    }

    return SizedBox(
      width: 28,
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 8,
            top: 1,
            child: Icon(
              Icons.directions_bus_rounded,
              size: 16,
              color: foregroundColor.withValues(alpha: 0.58),
            ),
          ),
          Icon(icon, size: 18, color: foregroundColor),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: hasLabel ? 14 : 10,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: glowColor == null
            ? null
            : [BoxShadow(color: glowColor!, blurRadius: 14, spreadRadius: 1)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(),
          if (hasLabel) ...[
            const SizedBox(width: 8),
            Text(
              label!,
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteInfoDialog extends StatefulWidget {
  const _RouteInfoDialog({
    required this.detail,
    required this.alerts,
    required this.repository,
    required this.provider,
    required this.routeKey,
  });

  final RouteDetailData detail;
  final List<RouteAlert> alerts;
  final BusRepository repository;
  final BusProvider provider;
  final int routeKey;

  @override
  State<_RouteInfoDialog> createState() => _RouteInfoDialogState();
}

class _RouteInfoDialogState extends State<_RouteInfoDialog> {
  List<RouteOperator>? _operators;
  List<RouteScheduleEntry>? _schedule;
  bool _loading = true;
  String? _error;
  final Set<String> _expandedAlertIds = <String>{};
  DateTime _selectedDate = DateTime.now();

  /// Cache of `yyyy-MM-dd` -> isHoliday, populated from the API per year.
  /// Empty for a date means: no explicit entry, fall back to the weekend rule.
  final Map<String, bool> _holidayMap = <String, bool>{};
  final Set<int> _loadedHolidayYears = <int>{};

  @override
  void initState() {
    super.initState();
    _loadData();
    _ensureHolidaysLoaded(_selectedDate.year);
  }

  Future<void> _ensureHolidaysLoaded(int year) async {
    if (_loadedHolidayYears.contains(year)) return;
    _loadedHolidayYears.add(year);
    try {
      final map = await widget.repository.fetchHolidaysForYear(year);
      if (!mounted || map.isEmpty) return;
      setState(() => _holidayMap.addAll(map));
    } catch (_) {
      // Ignore: detection falls back to the weekend rule.
    }
  }

  Future<void> _loadData() async {
    final routeId = widget.detail.route.routeId;
    try {
      final results = await Future.wait([
        widget.repository.fetchRouteOperators(routeId),
        widget.repository.fetchRouteSchedule(routeId),
      ]);
      if (!mounted) return;
      setState(() {
        _operators = results[0] as List<RouteOperator>;
        _schedule = results[1] as List<RouteScheduleEntry>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('RouteInfoDialog load error for $routeId: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = widget.detail.route;

    return AlertDialog(
      title: Text(route.routeName),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (route.description.isNotEmpty) ...[
              Text(route.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            if (widget.alerts.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.error,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '營運通知',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final alert in widget.alerts)
                _buildExpandableAlertItem(alert, theme),
              const Divider(height: 20),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else ...[
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '載入失敗：$_error',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (_operators != null && _operators!.isNotEmpty) ...[
                Text('營運業者', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final op in _operators!) _buildOperatorTile(op, theme),
                const Divider(height: 20),
              ],
              if (_schedule != null && _schedule!.isNotEmpty) ...[
                Row(
                  children: [
                    Text('發車時間', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _pickScheduleDate,
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(_formatSelectedDateLabel()),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ..._buildScheduleSection(),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _shareRouteLink,
          icon: const Icon(Icons.share, size: 18),
          label: const Text('分享連結'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    );
  }

  static const String _appBaseUrl = 'https://busapp.avianjay.sbs';

  String _buildShareUrl() {
    final route = widget.detail.route;
    final path = AppRoutes.routeDetailPath(
      provider: widget.provider,
      routeKey: widget.routeKey,
      routeId: route.routeId,
    );
    final base = _appBaseUrl.endsWith('/')
        ? _appBaseUrl.substring(0, _appBaseUrl.length - 1)
        : _appBaseUrl;
    final suffix = path.startsWith('/') ? path : '/$path';
    return '$base$suffix';
  }

  Future<void> _shareRouteLink() async {
    final route = widget.detail.route;
    final url = _buildShareUrl();
    final shareText = '${route.routeName}\n$url';

    var shared = false;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: shareText, subject: route.routeName),
      );
      shared = result.status != ShareResultStatus.unavailable;
    } catch (e) {
      debugPrint('Share route link failed, falling back to clipboard: $e');
      shared = false;
    }

    if (!shared) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已複製連結')));
    }
  }

  Widget _buildExpandableAlertItem(RouteAlert alert, ThemeData theme) {
    final expanded = _expandedAlertIds.contains(alert.alertId);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          if (expanded) {
            _expandedAlertIds.remove(alert.alertId);
          } else {
            _expandedAlertIds.add(alert.alertId);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: alert.statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(alert.title, style: theme.textTheme.bodySmall),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (expanded) ...[
              if (alert.effectText.isNotEmpty || alert.causeText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 16),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      if (alert.effectText.isNotEmpty)
                        Chip(
                          label: Text(alert.effectText),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          labelStyle: theme.textTheme.labelSmall,
                          padding: EdgeInsets.zero,
                        ),
                      if (alert.causeText.isNotEmpty)
                        Chip(
                          label: Text(alert.causeText),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          labelStyle: theme.textTheme.labelSmall,
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              if (alert.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 16),
                  child: Text(
                    alert.description,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOperatorTile(RouteOperator op, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            op.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (op.phone != null && op.phone!.isNotEmpty)
            Text('電話：${op.phone}', style: theme.textTheme.bodySmall),
          if (op.url != null && op.url!.isNotEmpty)
            Text('網站：${op.url}', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  static const List<String> _weekdayLabels = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  String _formatSelectedDateLabel() {
    final d = _selectedDate;
    final weekday = _weekdayLabels[d.weekday - 1];
    final holidaySuffix = _isHoliday(d) ? '・假日' : '';
    return '${d.month}/${d.day}（$weekday$holidaySuffix）';
  }

  /// Determines whether [date] is a holiday (non-working day).
  ///
  /// Prefers the Taiwan holiday calendar fetched from the API (which handles
  /// national holidays and make-up working days). Falls back to the weekend
  /// rule (Sat/Sun = holiday) when there is no explicit entry — this keeps the
  /// behaviour compatible when the API is unavailable.
  bool _isHoliday(DateTime date) {
    final key = _dateKey(date);
    final explicit = _holidayMap[key];
    if (explicit != null) {
      return explicit;
    }
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  String _dateKey(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '選擇日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
    unawaited(_ensureHolidaysLoaded(picked.year));
  }

  /// Determines whether a schedule entry is active on the selected date,
  /// based on its service-day flags (and holiday handling).
  bool _isEntryActiveOnSelectedDate(RouteScheduleEntry entry) {
    final days = entry.serviceDays;
    final date = _selectedDate;

    if (_isHoliday(date) && days['holiday'] == 1) {
      return true;
    }

    const weekdayKeys = <String>[
      'mon',
      'tue',
      'wed',
      'thu',
      'fri',
      'sat',
      'sun',
    ];
    final key = weekdayKeys[date.weekday - 1];
    return days[key] == 1;
  }

  List<Widget> _buildScheduleSection() {
    final theme = Theme.of(context);

    // Filter entries that run on the selected date, then group by direction.
    final activeEntries = _schedule!
        .where(_isEntryActiveOnSelectedDate)
        .toList();

    if (activeEntries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '這天沒有發車資訊',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }

    final byDirection = <int, List<RouteScheduleEntry>>{};
    for (final entry in activeEntries) {
      (byDirection[entry.direction] ??= []).add(entry);
    }

    final directions = byDirection.keys.toList()..sort();
    final widgets = <Widget>[];
    for (final direction in directions) {
      final entries = byDirection[direction]!;
      widgets.add(_buildDirectionRow(direction, entries, theme));
    }
    return widgets;
  }

  Widget _buildDirectionRow(
    int direction,
    List<RouteScheduleEntry> entries,
    ThemeData theme,
  ) {
    final frequencyEntries = entries.where((e) => e.isFrequency).toList();
    final departureTimes = <String>{};
    for (final entry in entries) {
      if (entry.isFrequency) continue;
      final stops = entry.payload['stop_times'] as List<dynamic>? ?? [];
      if (stops.isNotEmpty) {
        final first = stops.first as Map<String, dynamic>;
        final departure = (first['departure'] as String? ?? '').trim();
        if (departure.isNotEmpty) {
          departureTimes.add(_normalizeTime(departure));
        }
      }
    }

    final sortedTimes = departureTimes.toList()..sort();

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _directionLabel(direction),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (frequencyEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in frequencyEntries)
                    Text(entry.displayText, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (sortedTimes.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final time in sortedTimes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(time, style: theme.textTheme.bodySmall),
                  ),
              ],
            )
          else if (frequencyEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '無發車時間資料',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _directionLabel(int direction) {
    switch (direction) {
      case 0:
        return '去程';
      case 1:
        return '返程';
      default:
        return '方向 $direction';
    }
  }

  /// Normalizes a departure time string to HH:MM (drops seconds if present).
  String _normalizeTime(String raw) {
    final parts = raw.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return raw;
  }
}

/// Bottom sheet showing the timetabled arrival/departure times at a single
/// stop, grouped by direction and filtered by a selectable date.
class _StopScheduleSheet extends StatefulWidget {
  const _StopScheduleSheet({
    required this.routeId,
    required this.routeName,
    required this.stop,
    required this.repository,
  });

  final String routeId;
  final String routeName;
  final StopInfo stop;
  final BusRepository repository;

  @override
  State<_StopScheduleSheet> createState() => _StopScheduleSheetState();
}

class _StopScheduleSheetState extends State<_StopScheduleSheet> {
  List<RouteScheduleEntry>? _schedule;
  bool _loading = true;
  String? _error;
  DateTime _selectedDate = DateTime.now();

  final Map<String, bool> _holidayMap = <String, bool>{};
  final Set<int> _loadedHolidayYears = <int>{};

  static const List<String> _weekdayLabels = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _ensureHolidaysLoaded(_selectedDate.year);
  }

  Future<void> _load() async {
    try {
      final schedule = await widget.repository.fetchStopEstimatedTimes(
        widget.routeId,
      );
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loading = false;
      });
    } catch (e) {
      debugPrint('StopScheduleSheet load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _ensureHolidaysLoaded(int year) async {
    if (_loadedHolidayYears.contains(year)) return;
    _loadedHolidayYears.add(year);
    try {
      final map = await widget.repository.fetchHolidaysForYear(year);
      if (!mounted || map.isEmpty) return;
      setState(() => _holidayMap.addAll(map));
    } catch (_) {
      // Falls back to the weekend rule.
    }
  }

  bool _isHoliday(DateTime date) {
    final key = _dateKey(date);
    final explicit = _holidayMap[key];
    if (explicit != null) return explicit;
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  String _dateKey(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$d';
  }

  String _formatSelectedDateLabel() {
    final d = _selectedDate;
    final weekday = _weekdayLabels[d.weekday - 1];
    final holidaySuffix = _isHoliday(d) ? '・假日' : '';
    return '${d.month}/${d.day}（$weekday$holidaySuffix）';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '選擇日期',
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
    unawaited(_ensureHolidaysLoaded(picked.year));
  }

  bool _isEntryActiveOnSelectedDate(RouteScheduleEntry entry) {
    final days = entry.serviceDays;
    final date = _selectedDate;
    if (_isHoliday(date) && days['holiday'] == 1) return true;
    const weekdayKeys = <String>[
      'mon',
      'tue',
      'wed',
      'thu',
      'fri',
      'sat',
      'sun',
    ];
    return days[weekdayKeys[date.weekday - 1]] == 1;
  }

  /// Extracts the stop time (arrival, fallback departure) for [widget.stop]
  /// from a timetable entry. Matches by stop id first, then stop sequence.
  String? _stopTimeForEntry(RouteScheduleEntry entry) {
    final stops = entry.payload['stop_times'] as List<dynamic>? ?? const [];
    final targetId = widget.stop.stopId.toString();
    final targetSeq = widget.stop.sequence;
    Map<String, dynamic>? matched;
    for (final raw in stops) {
      if (raw is! Map<String, dynamic>) continue;
      final sid = (raw['stopid'] ?? '').toString();
      if (sid.isNotEmpty && sid == targetId) {
        matched = raw;
        break;
      }
    }
    matched ??= () {
      for (final raw in stops) {
        if (raw is Map<String, dynamic> && raw['seq'] == targetSeq) {
          return raw;
        }
      }
      return null;
    }();
    if (matched == null) return null;
    final arrival = (matched['arrival'] as String? ?? '').trim();
    final departure = (matched['departure'] as String? ?? '').trim();
    final time = arrival.isNotEmpty ? arrival : departure;
    return time.isEmpty ? null : _normalizeTime(time);
  }

  /// Whether [entry] has estimated (extrapolated) stop times rather than
  /// authoritative timetable data.
  bool _isEntryEstimated(RouteScheduleEntry entry) {
    return entry.isFrequency &&
        (entry.payload['has_estimated_stops'] as bool? ?? false);
  }

  String _normalizeTime(String raw) {
    final parts = raw.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.stop.stopName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${widget.routeName}・預計時刻',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '依時刻表推算，實際以現場為準',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_formatSelectedDateLabel()),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(child: _buildBody(theme, scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ThemeData theme, ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null) {
      return Center(
        child: Text(
          '載入失敗：$_error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }
    final schedule = _schedule ?? const [];
    final timetableEntries = schedule
        .where((e) => !e.isFrequency)
        .where(_isEntryActiveOnSelectedDate)
        .toList();
    final frequencyEntries = schedule
        .where((e) => e.isFrequency)
        .where(_isEntryActiveOnSelectedDate)
        .toList();

    if (timetableEntries.isEmpty && frequencyEntries.isEmpty) {
      return Center(
        child: Text(
          schedule.isEmpty ? '這條路線沒有時刻表資料' : '這天沒有發車資訊',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // The stop was opened from a specific path/direction, so we only show the
    // times for the direction(s) this stop actually belongs to. A timetable
    // entry is relevant only if THIS stop appears in its stop_times — entries
    // for the opposite direction (where this stop doesn't exist) are skipped.
    final stopTimes = <String, bool>{}; // time -> isEstimated
    final relevantDirections = <int>{};
    for (final entry in timetableEntries) {
      final time = _stopTimeForEntry(entry);
      if (time != null) {
        stopTimes[time] = false;
        relevantDirections.add(entry.direction);
      }
    }

    // Frequency entries may now carry estimated per-stop times (from the
    // stop-estimated-times API endpoint).  Extract stop times from those
    // that have them.
    final estimatedFrequencyEntries = <RouteScheduleEntry>[];
    final plainFrequencyEntries = <RouteScheduleEntry>[];
    for (final entry in frequencyEntries) {
      if (relevantDirections.isNotEmpty &&
          !relevantDirections.contains(entry.direction)) {
        continue;
      }
      if (_isEntryEstimated(entry)) {
        estimatedFrequencyEntries.add(entry);
      } else {
        plainFrequencyEntries.add(entry);
      }
    }

    // Collect estimated times from frequency entries with extrapolated stops.
    for (final entry in estimatedFrequencyEntries) {
      final time = _stopTimeForEntry(entry);
      if (time != null) {
        stopTimes[time] = true;
        relevantDirections.add(entry.direction);
      }
    }

    if (stopTimes.isEmpty && plainFrequencyEntries.isEmpty) {
      return Center(
        child: Text(
          '這個站點在當天沒有對應的發車時刻',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final sortedTimes = stopTimes.keys.toList()..sort();

    return ListView(
      controller: scrollController,
      children: [
        if (plainFrequencyEntries.isNotEmpty) ...[
          Text(
            '行駛班距',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          for (final entry in plainFrequencyEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(entry.displayText, style: theme.textTheme.bodyMedium),
            ),
          if (sortedTimes.isNotEmpty) const SizedBox(height: 12),
        ],
        if (sortedTimes.isNotEmpty) ...[
          Row(
            children: [
              Text(
                '預計到站時間',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (stopTimes.values.any((e) => e)) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '含推算',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final time in sortedTimes)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: stopTimes[time] == true
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(time, style: theme.textTheme.bodyMedium),
                ),
            ],
          ),
          if (stopTimes.values.any((e) => e)) ...[
            const SizedBox(height: 8),
            Text(
              '※ 標示「含推算」的時間由班距與行駛時間推算，僅供參考',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _RelatedStopRouteEta {
  const _RelatedStopRouteEta({required this.result, required this.liveStop});

  final StopRouteSearchResult result;
  final StopInfo liveStop;
}

enum _StopAction {
  favorite,
  destination,
  schedule,
  relatedRoutes,
  googleMaps,
  shortcut,
}

enum _VehicleAction { twBusForum }
