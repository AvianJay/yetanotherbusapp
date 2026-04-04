import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/twbusforum.dart';
import 'route_detail_screen.dart';

class TrackedBusesScreen extends StatefulWidget {
  const TrackedBusesScreen({super.key});

  @override
  State<TrackedBusesScreen> createState() => _TrackedBusesScreenState();
}

class _TrackedBusesScreenState extends State<TrackedBusesScreen>
    with TickerProviderStateMixin {
  Timer? _countdownTimer;
  late final AnimationController _countdownProgressController;
  List<TrackedBusSnapshot> _items = const [];
  bool _isLoading = false;
  String? _error;
  String? _statusMessage;
  String _loadedSignature = '';
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
    super.dispose();
  }

  String _trackedBusesSignature(List<TrackedBus> trackedBuses) {
    return trackedBuses
        .map((entry) => '${entry.provider.name}:${entry.vehicleId}')
        .join('|');
  }

  void _scheduleRefresh() {
    if (_refreshScheduled) {
      return;
    }
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      unawaited(_refreshTrackedBuses());
    });
  }

  void _scheduleRefreshIfNeeded(AppController controller) {
    if (controller.trackedBuses.isEmpty) {
      return;
    }
    if (_isLoading) {
      return;
    }
    final signature = _trackedBusesSignature(controller.trackedBuses);
    if (_loadedSignature != signature) {
      _scheduleRefresh();
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
        unawaited(_refreshTrackedBuses());
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
              key: ValueKey('tracked-buses-loading-progress'),
              minHeight: 4,
            )
          : AnimatedBuilder(
              key: const ValueKey('tracked-buses-countdown-progress'),
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

  Future<void> _refreshTrackedBuses() async {
    final controller = AppControllerScope.read(context);
    final trackedBuses = controller.trackedBuses;
    final signature = _trackedBusesSignature(trackedBuses);
    if (_isLoading && _refreshingSignature == signature) {
      return;
    }
    final requestId = ++_refreshRequestId;

    if (trackedBuses.isEmpty) {
      setState(() {
        _items = const [];
        _isLoading = false;
        _error = null;
        _statusMessage = null;
        _loadedSignature = '';
        _refreshingSignature = '';
      });
      _countdownTimer?.cancel();
      _countdownProgressController
        ..stop()
        ..value = 0;
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _refreshingSignature = signature;
      _statusMessage = '正在更新';
    });

    try {
      final snapshots = await controller.getTrackedBusSnapshots();
      if (!mounted || requestId != _refreshRequestId) {
        return;
      }

      final onlineCount = snapshots.where((item) => item.isOnline).length;
      final offlineCount = snapshots
          .where((item) => item.state == TrackedBusState.offline)
          .length;
      final errorCount = snapshots
          .where((item) => item.state == TrackedBusState.error)
          .length;

      final nextStatusMessage = errorCount == snapshots.length
          ? '追蹤公車更新失敗'
          : onlineCount == 0 && offlineCount > 0
          ? '目前沒有在線上的公車'
          : errorCount > 0
          ? '部分公車更新失敗'
          : null;

      setState(() {
        _items = snapshots;
        _isLoading = false;
        _error = null;
        _statusMessage = nextStatusMessage;
        _loadedSignature = signature;
        _refreshingSignature = '';
      });

      _startCountdown(
        onlineCount > 0
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
        _refreshingSignature = '';
        _loadedSignature = signature;
        _statusMessage = _items.isEmpty ? '追蹤公車更新失敗' : '更新失敗，先保留上一筆資料';
      });
      _startCountdown(controller.settings.busErrorUpdateTime);
    }
  }

  Future<void> _openTwBusForum(String vehicleId) async {
    final didLaunch = await openTwBusForumSearch(vehicleId);
    if (!mounted || didLaunch) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('無法開啟 TWBusforum。')));
  }

  Future<void> _removeTrackedBus(TrackedBus trackedBus) async {
    await AppControllerScope.read(
      context,
    ).removeTrackedBus(trackedBus.vehicleId);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已移除 ${trackedBus.vehicleId}')));
    _scheduleRefresh();
  }

  Future<void> _openRouteDetail(TrackedBusSnapshot item) async {
    final routeKey = item.effectiveRouteKey;
    if (routeKey == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('這台車目前沒有可開啟的路線資訊。')));
      return;
    }

    await AppControllerScope.read(context).recordRouteSelection(
      provider: item.trackedBus.provider,
      routeKey: routeKey,
      routeName: item.displayRouteName,
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailScreen(
          routeKey: routeKey,
          provider: item.trackedBus.provider,
          initialPathId: item.currentPathId,
          initialStopId: item.currentStopId,
        ),
      ),
    );
  }

  String _subtitleForItem(TrackedBusSnapshot item) {
    final routeName = item.displayRouteName;
    final stopName = item.currentStopName?.trim();
    final pathName = item.currentPathName?.trim();
    return switch (item.state) {
      TrackedBusState.online =>
        stopName != null && stopName.isNotEmpty
            ? '$routeName · ${pathName?.isNotEmpty == true ? "$pathName · " : ""}$stopName'
            : routeName,
      TrackedBusState.offline => '$routeName · 目前離線',
      TrackedBusState.error =>
        item.message?.trim().isNotEmpty == true
            ? item.message!.trim()
            : '$routeName · 更新失敗',
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    _scheduleRefreshIfNeeded(controller);

    return Scaffold(
      appBar: AppBar(
        title: const Text('追蹤公車'),
        actions: [
          IconButton(
            onPressed: _refreshTrackedBuses,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: controller.trackedBuses.isEmpty
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
      body: controller.trackedBuses.isEmpty
          ? const _EmptyTrackedBusesState()
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('追蹤公車載入失敗：$_error'),
        ),
      );
    }

    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return const _EmptyTrackedBusesState(message: '目前沒有可顯示的追蹤資料。');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _items[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            onTap: () => unawaited(_openRouteDetail(item)),
            leading: _TrackedBusStateChip(state: item.state),
            title: Text(
              item.trackedBus.vehicleId,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_subtitleForItem(item)),
            ),
            trailing: PopupMenuButton<_TrackedBusMenuAction>(
              onSelected: (action) {
                switch (action) {
                  case _TrackedBusMenuAction.twBusForum:
                    unawaited(_openTwBusForum(item.trackedBus.vehicleId));
                  case _TrackedBusMenuAction.remove:
                    unawaited(_removeTrackedBus(item.trackedBus));
                }
              },
              itemBuilder: (context) {
                return const [
                  PopupMenuItem<_TrackedBusMenuAction>(
                    value: _TrackedBusMenuAction.twBusForum,
                    child: Text('搜尋 TWBusforum'),
                  ),
                  PopupMenuItem<_TrackedBusMenuAction>(
                    value: _TrackedBusMenuAction.remove,
                    child: Text('移除追蹤'),
                  ),
                ];
              },
            ),
          ),
        );
      },
    );
  }
}

class _TrackedBusStateChip extends StatelessWidget {
  const _TrackedBusStateChip({required this.state});

  final TrackedBusState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (backgroundColor, foregroundColor, icon) = switch (state) {
      TrackedBusState.online => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        Icons.directions_bus_filled_rounded,
      ),
      TrackedBusState.offline => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        Icons.cloud_off_rounded,
      ),
      TrackedBusState.error => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
    };

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: foregroundColor),
    );
  }
}

class _EmptyTrackedBusesState extends StatelessWidget {
  const _EmptyTrackedBusesState({this.message = '還沒有追蹤公車，去路線頁點車牌就能加入。'});

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

enum _TrackedBusMenuAction { twBusForum, remove }
