import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app/bus_app.dart';
import '../core/models.dart';

class RouteBusMapSheet extends StatefulWidget {
  const RouteBusMapSheet({
    required this.routeId,
    required this.routeName,
    required this.paths,
    required this.selectedPathIdListenable,
    required this.refreshIntervalSeconds,
    this.dragScrollController,
    this.onSelectedPathChanged,
    super.key,
  });

  final String routeId;
  final String routeName;
  final List<PathInfo> paths;
  final ValueListenable<int?> selectedPathIdListenable;
  final int refreshIntervalSeconds;
  final ScrollController? dragScrollController;
  final ValueChanged<int>? onSelectedPathChanged;

  @override
  State<RouteBusMapSheet> createState() => _RouteBusMapSheetState();
}

class _RouteBusMapSheetState extends State<RouteBusMapSheet>
    with SingleTickerProviderStateMixin {
  static const _simulationTick = Duration(milliseconds: 250);
  static const _snapToRouteThresholdMeters = 180.0;
  static const _offRouteThresholdMeters = 320.0;
  static const _cameraPadding = EdgeInsets.fromLTRB(20, 20, 20, 140);

  final MapController _mapController = MapController();
  late final AnimationController _refreshProgressController;

  Timer? _refreshTimer;
  Timer? _simulationTimer;
  _RouteGeometry? _geometry;
  Map<String, _AnimatedBusState> _busStates = <String, _AnimatedBusState>{};
  int _refreshRequestSerial = 0;
  bool _isRefreshing = false;
  String? _error;
  String? _selectedBusId;
  late int _activePathId;

  @override
  void initState() {
    super.initState();
    _activePathId =
        widget.selectedPathIdListenable.value ?? widget.paths.first.pathId;
    _refreshProgressController = AnimationController(vsync: this);
    widget.selectedPathIdListenable.addListener(_handleExternalPathSelection);
    _simulationTimer = Timer.periodic(_simulationTick, (_) {
      if (!mounted || _busStates.isEmpty) {
        return;
      }
      setState(() {});
    });
    unawaited(_loadMapData(fitCamera: true));
  }

  @override
  void dispose() {
    widget.selectedPathIdListenable.removeListener(_handleExternalPathSelection);
    _refreshTimer?.cancel();
    _simulationTimer?.cancel();
    _refreshProgressController.dispose();
    super.dispose();
  }

  int get _refreshSeconds => math.max(3, widget.refreshIntervalSeconds);

  _AnimatedBusState? get _selectedBusState {
    final selectedBusId = _selectedBusId;
    if (selectedBusId == null) {
      return null;
    }
    return _busStates[selectedBusId];
  }

  void _handleExternalPathSelection() {
    final nextPathId = widget.selectedPathIdListenable.value;
    if (nextPathId == null || nextPathId == _activePathId) {
      return;
    }
    _switchPath(nextPathId, notifyParent: false);
  }

  void _switchPath(int pathId, {required bool notifyParent}) {
    if (_activePathId == pathId) {
      return;
    }
    if (!widget.paths.any((path) => path.pathId == pathId)) {
      return;
    }

    _refreshTimer?.cancel();
    _refreshProgressController
      ..stop()
      ..value = 0;
    setState(() {
      _activePathId = pathId;
      _selectedBusId = null;
      _error = null;
      _geometry = null;
      _busStates = <String, _AnimatedBusState>{};
    });

    if (notifyParent) {
      widget.onSelectedPathChanged?.call(pathId);
    }
    unawaited(_loadMapData(fitCamera: true));
  }

  Future<void> _loadMapData({bool fitCamera = false}) async {
    final controller = AppControllerScope.read(context);
    final pathId = _activePathId;
    final previousStates = _busStates;
    final requestId = ++_refreshRequestSerial;
    setState(() {
      _isRefreshing = true;
      _error = null;
    });

    try {
      final pathPoints = await controller.repository.getRoutePathPoints(
        widget.routeId,
        pathId: pathId,
      );
      final buses = await controller.repository.getRouteRealtimeBuses(
        widget.routeId,
        pathId: pathId,
      );
      if (!mounted ||
          pathId != _activePathId ||
          requestId != _refreshRequestSerial) {
        return;
      }

      final geometry = _RouteGeometry.fromPoints(pathPoints);
      final nextStates = _buildAnimatedBusStates(
        geometry,
        buses,
        previousStates,
      );
      final nextSelectedBusId =
          _selectedBusId != null && nextStates.containsKey(_selectedBusId)
          ? _selectedBusId
          : null;
      setState(() {
        _geometry = geometry;
        _busStates = nextStates;
        _selectedBusId = nextSelectedBusId;
        _isRefreshing = false;
      });
      _scheduleNextRefresh();
      if (fitCamera) {
        _fitCameraToGeometry(geometry);
      }
    } catch (error) {
      if (!mounted ||
          pathId != _activePathId ||
          requestId != _refreshRequestSerial) {
        return;
      }
      setState(() {
        _isRefreshing = false;
        _error = '$error';
      });
      _scheduleNextRefresh();
    }
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    _refreshProgressController
      ..stop()
      ..duration = Duration(seconds: _refreshSeconds)
      ..value = 0;
    if (!mounted) {
      return;
    }
    unawaited(_refreshProgressController.forward(from: 0));
    _refreshTimer = Timer(Duration(seconds: _refreshSeconds), () {
      if (!mounted) {
        return;
      }
      unawaited(_loadMapData());
    });
  }

  void _fitCameraToGeometry(_RouteGeometry geometry) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || geometry.points.isEmpty) {
        return;
      }
      try {
        if (geometry.points.length == 1) {
          _mapController.move(geometry.points.first, 16);
          return;
        }
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(geometry.points),
            padding: _cameraPadding,
          ),
        );
      } catch (_) {
        // Ignore fit errors from early controller lifecycle and wait for next refresh.
      }
    });
  }

  Map<String, _AnimatedBusState> _buildAnimatedBusStates(
    _RouteGeometry geometry,
    List<RouteRealtimeBus> buses,
    Map<String, _AnimatedBusState> previousStates,
  ) {
    final now = DateTime.now();
    final nextStates = <String, _AnimatedBusState>{};

    for (final bus in buses) {
      final rawPoint = LatLng(bus.lat, bus.lon);
      final projection = geometry.project(rawPoint);
      final previous = previousStates[bus.id];
      final speedMps = (((bus.speedKph ?? 0) / 3.6).clamp(0, 36)).toDouble();
      final status = describeBusStatus(bus.statusCode);
      final sampleTime = _effectiveSampleTime(bus.updatedAt, now);

      if (projection.distanceToRouteMeters <= _offRouteThresholdMeters) {
        var baseDistance = projection.distanceAlongRouteMeters;
        final predictedPrevious = previous?.distanceAlongRouteAt(
          sampleTime,
          geometry: geometry,
        );
        if (predictedPrevious != null) {
          final delta = baseDistance - predictedPrevious;
          if (delta.abs() <= 180) {
            final blendFactor = delta < 0 ? 0.18 : 0.35;
            baseDistance = predictedPrevious + delta * blendFactor;
          }
        }
        nextStates[bus.id] = _AnimatedBusState(
          bus: bus,
          status: status,
          mode: _BusMotionMode.snappedToRoute,
          routeDistanceAtSampleMeters: baseDistance
              .clamp(0.0, geometry.totalLengthMeters)
              .toDouble(),
          sampledAt: sampleTime,
          rawPoint: rawPoint,
          speedMps: speedMps,
          azimuth: bus.azimuth,
          distanceToRouteMeters: projection.distanceToRouteMeters,
        );
        continue;
      }

      var basePoint = rawPoint;
      if (previous != null) {
        final predicted = previous.positionAt(sampleTime, geometry: geometry);
        final gap = _distanceMetersBetween(predicted, rawPoint);
        if (gap <= _snapToRouteThresholdMeters) {
          basePoint = _lerpLatLng(predicted, rawPoint, 0.35);
        }
      }

      nextStates[bus.id] = _AnimatedBusState(
        bus: bus,
        status: status,
        mode: _BusMotionMode.freeFloating,
        routeDistanceAtSampleMeters: null,
        sampledAt: sampleTime,
        rawPoint: basePoint,
        speedMps: speedMps,
        azimuth: bus.azimuth,
        distanceToRouteMeters: projection.distanceToRouteMeters,
      );
    }

    return nextStates;
  }

  DateTime _effectiveSampleTime(DateTime? updatedAt, DateTime now) {
    if (updatedAt == null) {
      return now;
    }
    if (updatedAt.isAfter(now)) {
      return now;
    }
    final oldestAllowed = now.subtract(
      Duration(seconds: math.max(_refreshSeconds, 12)),
    );
    if (updatedAt.isBefore(oldestAllowed)) {
      return oldestAllowed;
    }
    return updatedAt;
  }

  String _refreshLabel() {
    if (_isRefreshing) {
      return '更新中';
    }
    final secondsRemaining = math.max(
      0,
      ((_refreshSeconds * (1 - _refreshProgressController.value))).ceil(),
    );
    return '$secondsRemaining 秒後更新';
  }

  Alignment _selectedPopupAlignment(LatLng point) {
    try {
      final offset = _mapController.camera.latLngToScreenOffset(point);
      if (offset.dy < 168) {
        return Alignment.bottomCenter;
      }
    } catch (_) {
      // Ignore camera state errors before the map is fully ready.
    }
    return Alignment.topCenter;
  }

  Widget _buildTopProgressBar() {
    return SizedBox(
      height: 3,
      child: _isRefreshing
          ? const LinearProgressIndicator(minHeight: 3)
          : AnimatedBuilder(
              animation: _refreshProgressController,
              builder: (context, child) {
                return LinearProgressIndicator(
                  value: _refreshProgressController.value,
                  minHeight: 3,
                );
              },
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '公車地圖',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.routeName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedBuilder(
                animation: _refreshProgressController,
                builder: (context, child) {
                  return Text(
                    _refreshLabel(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _isRefreshing
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ),
          if (widget.paths.length > 1) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _activePathId,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(16),
                    items: widget.paths
                        .map(
                          (path) => DropdownMenuItem<int>(
                            value: path.pathId,
                            child: Text(path.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      _switchPath(value, notifyParent: true);
                    },
                  ),
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapArea(ThemeData theme) {
    final geometry = _geometry;
    if (geometry == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (geometry.points.isEmpty) {
      return Center(
        child: Text(
          '目前沒有可顯示的路線地圖資料',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final now = DateTime.now();
    final displayBuses = _busStates.values
        .map(
          (busState) => _DisplayedBus(
            state: busState,
            point: busState.positionAt(now, geometry: geometry),
          ),
        )
        .toList();
    final selectedBus = _selectedBusState;
    _DisplayedBus? selectedDisplayBus;
    if (selectedBus != null) {
      for (final bus in displayBuses) {
        if (bus.state.bus.id == selectedBus.bus.id) {
          selectedDisplayBus = bus;
          break;
        }
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: geometry.points.first,
              initialZoom: 13.5,
              onTap: (_, point) {
                if (_selectedBusId == null) {
                  return;
                }
                setState(() {
                  _selectedBusId = null;
                });
              },
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'tw.avianjay.taiwanbus.flutter',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: geometry.points,
                    strokeWidth: 5,
                    color: theme.colorScheme.primary.withValues(alpha: 0.88),
                    borderColor: theme.colorScheme.surface,
                    borderStrokeWidth: 1.2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: displayBuses.map((bus) {
                  final selected = _selectedBusId == bus.state.bus.id;
                  return Marker(
                    point: bus.point,
                    width: selected ? 48 : 40,
                    height: selected ? 48 : 40,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBusId =
                              _selectedBusId == bus.state.bus.id
                              ? null
                              : bus.state.bus.id;
                        });
                      },
                      child: _BusMarker(
                        color: bus.state.status.color,
                        selected: selected,
                        label: bus.state.bus.id,
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (selectedDisplayBus != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selectedDisplayBus.point,
                      width: 244,
                      height: 156,
                      alignment: _selectedPopupAlignment(
                        selectedDisplayBus.point,
                      ),
                      child: IgnorePointer(
                        child: _BusInfoPopup(
                          busState: selectedDisplayBus.state,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(child: _buildTopProgressBar()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: true,
        bottom: false,
        child: CustomScrollView(
          controller: widget.dragScrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(theme)),
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildMapArea(theme),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusMarker extends StatelessWidget {
  const _BusMarker({
    required this.color,
    required this.selected,
    required this.label,
  });

  final Color color;
  final bool selected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final foreground = color.computeLuminance() > 0.45
        ? Colors.black87
        : Colors.white;
    return AnimatedScale(
      scale: selected ? 1.08 : 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: selected ? 3 : 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Tooltip(
          message: label,
          child: Icon(
            Icons.directions_bus_rounded,
            color: foreground,
            size: selected ? 24 : 20,
          ),
        ),
      ),
    );
  }
}

class _BusInfoPopup extends StatelessWidget {
  const _BusInfoPopup({
    required this.busState,
  });

  final _AnimatedBusState busState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = busState.status;
    final statusForeground = status.color.computeLuminance() > 0.45
        ? Colors.black87
        : Colors.white;

    return Material(
      elevation: 10,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    busState.bus.id,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: status.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusForeground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _InfoChip(
                  label: '速度',
                  value: busState.bus.speedKph == null
                      ? '--'
                      : '${busState.bus.speedKph!.round()} km/h',
                ),
                _InfoChip(
                  label: '方位',
                  value: busState.bus.azimuth == null
                      ? '--'
                      : '${busState.bus.azimuth!.round()}°',
                ),
                _InfoChip(
                  label: '更新',
                  value: _formatTime(busState.bus.updatedAt),
                ),
                _InfoChip(
                  label: '位置',
                  value: busState.mode == _BusMotionMode.snappedToRoute
                      ? '沿路線'
                      : '離線路 ${busState.distanceToRouteMeters.round()}m',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime? dateTime) {
    if (dateTime == null) {
      return '--';
    }
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textWidthBasis: TextWidthBasis.parent,
        textScaler: MediaQuery.textScalerOf(context),
      ),
    );
  }
}

class _DisplayedBus {
  const _DisplayedBus({
    required this.state,
    required this.point,
  });

  final _AnimatedBusState state;
  final LatLng point;
}

enum _BusMotionMode { snappedToRoute, freeFloating }

class _AnimatedBusState {
  const _AnimatedBusState({
    required this.bus,
    required this.status,
    required this.mode,
    required this.routeDistanceAtSampleMeters,
    required this.sampledAt,
    required this.rawPoint,
    required this.speedMps,
    required this.azimuth,
    required this.distanceToRouteMeters,
  });

  final RouteRealtimeBus bus;
  final BusStatusDescriptor status;
  final _BusMotionMode mode;
  final double? routeDistanceAtSampleMeters;
  final DateTime sampledAt;
  final LatLng rawPoint;
  final double speedMps;
  final double? azimuth;
  final double distanceToRouteMeters;

  LatLng positionAt(
    DateTime now, {
    required _RouteGeometry geometry,
  }) {
    if (mode == _BusMotionMode.snappedToRoute &&
        routeDistanceAtSampleMeters != null) {
      return geometry.pointAtDistance(
        distanceAlongRouteAt(now, geometry: geometry) ??
            routeDistanceAtSampleMeters!,
      );
    }
    return _advanceOffRoutePoint(
      start: rawPoint,
      speedMps: speedMps,
      azimuth: azimuth,
      elapsedSeconds: _elapsedSeconds(now),
    );
  }

  double? distanceAlongRouteAt(
    DateTime now, {
    required _RouteGeometry geometry,
  }) {
    final baseDistance = routeDistanceAtSampleMeters;
    if (mode != _BusMotionMode.snappedToRoute || baseDistance == null) {
      return null;
    }
    final advanceMeters = math.min(speedMps * _elapsedSeconds(now), 280.0);
    return (baseDistance + advanceMeters).clamp(0.0, geometry.totalLengthMeters);
  }

  double _elapsedSeconds(DateTime now) {
    return math.max(
      0,
      now.difference(sampledAt).inMilliseconds / 1000.0,
    );
  }
}

class _RouteGeometry {
  _RouteGeometry._({
    required this.points,
    required this.cumulativeDistances,
    required this.segmentBearings,
    required this.totalLengthMeters,
  });

  factory _RouteGeometry.fromPoints(List<RoutePathPoint> points) {
    final latLngs = points.map((point) => LatLng(point.lat, point.lon)).toList();
    if (latLngs.length <= 1) {
      return _RouteGeometry._(
        points: latLngs,
        cumulativeDistances: const <double>[0],
        segmentBearings: const <double>[0],
        totalLengthMeters: 0,
      );
    }

    final cumulative = <double>[0];
    final bearings = <double>[];
    var total = 0.0;
    for (var index = 0; index < latLngs.length - 1; index++) {
      final start = latLngs[index];
      final end = latLngs[index + 1];
      total += _distanceMetersBetween(start, end);
      cumulative.add(total);
      bearings.add(_bearingBetween(start, end));
    }
    bearings.add(bearings.isEmpty ? 0 : bearings.last);

    return _RouteGeometry._(
      points: latLngs,
      cumulativeDistances: cumulative,
      segmentBearings: bearings,
      totalLengthMeters: total,
    );
  }

  final List<LatLng> points;
  final List<double> cumulativeDistances;
  final List<double> segmentBearings;
  final double totalLengthMeters;

  _RouteProjection project(LatLng point) {
    if (points.length <= 1) {
      return _RouteProjection(
        snappedPoint: points.isEmpty ? point : points.first,
        distanceToRouteMeters: points.isEmpty
            ? double.infinity
            : _distanceMetersBetween(point, points.first),
        distanceAlongRouteMeters: 0,
      );
    }

    var bestDistance = double.infinity;
    LatLng? bestPoint;
    var bestAlongDistance = 0.0;

    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      final projected = _projectOntoSegment(point, start, end);
      final distance = _distanceMetersBetween(point, projected.projectedPoint);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = projected.projectedPoint;
        final segmentLength = _distanceMetersBetween(start, end);
        bestAlongDistance =
            cumulativeDistances[index] + segmentLength * projected.segmentT;
      }
    }

    return _RouteProjection(
      snappedPoint: bestPoint ?? points.first,
      distanceToRouteMeters: bestDistance,
      distanceAlongRouteMeters: bestAlongDistance,
    );
  }

  LatLng pointAtDistance(double distanceMeters) {
    if (points.isEmpty) {
      return const LatLng(0, 0);
    }
    if (points.length == 1 || distanceMeters <= 0) {
      return points.first;
    }
    if (distanceMeters >= totalLengthMeters) {
      return points.last;
    }

    for (var index = 0; index < cumulativeDistances.length - 1; index++) {
      final segmentStartDistance = cumulativeDistances[index];
      final segmentEndDistance = cumulativeDistances[index + 1];
      if (distanceMeters > segmentEndDistance) {
        continue;
      }
      final segmentLength = segmentEndDistance - segmentStartDistance;
      final t = segmentLength == 0
          ? 0.0
          : (distanceMeters - segmentStartDistance) / segmentLength;
      return _lerpLatLng(points[index], points[index + 1], t);
    }
    return points.last;
  }
}

class _RouteProjection {
  const _RouteProjection({
    required this.snappedPoint,
    required this.distanceToRouteMeters,
    required this.distanceAlongRouteMeters,
  });

  final LatLng snappedPoint;
  final double distanceToRouteMeters;
  final double distanceAlongRouteMeters;
}

class _ProjectedSegmentPoint {
  const _ProjectedSegmentPoint({
    required this.projectedPoint,
    required this.segmentT,
  });

  final LatLng projectedPoint;
  final double segmentT;
}

_ProjectedSegmentPoint _projectOntoSegment(
  LatLng point,
  LatLng start,
  LatLng end,
) {
  final referenceLat = (start.latitude + end.latitude + point.latitude) / 3;
  final pointXy = _toMeters(point, referenceLat: referenceLat);
  final startXy = _toMeters(start, referenceLat: referenceLat);
  final endXy = _toMeters(end, referenceLat: referenceLat);
  final segmentDx = endXy.dx - startXy.dx;
  final segmentDy = endXy.dy - startXy.dy;
  final segmentLengthSquared = segmentDx * segmentDx + segmentDy * segmentDy;
  if (segmentLengthSquared == 0) {
    return _ProjectedSegmentPoint(projectedPoint: start, segmentT: 0);
  }

  final rawT =
      ((pointXy.dx - startXy.dx) * segmentDx +
          (pointXy.dy - startXy.dy) * segmentDy) /
      segmentLengthSquared;
  final t = rawT.clamp(0.0, 1.0);
  return _ProjectedSegmentPoint(
    projectedPoint: _lerpLatLng(start, end, t),
    segmentT: t,
  );
}

LatLng _advanceOffRoutePoint({
  required LatLng start,
  required double speedMps,
  required double? azimuth,
  required double elapsedSeconds,
}) {
  if (speedMps <= 0 || azimuth == null) {
    return start;
  }
  final distanceMeters = math.min(speedMps * elapsedSeconds, 240.0);
  final angularDistance = distanceMeters / 6378137.0;
  final bearing = azimuth * math.pi / 180;
  final lat1 = start.latitude * math.pi / 180;
  final lon1 = start.longitude * math.pi / 180;

  final sinLat1 = math.sin(lat1);
  final cosLat1 = math.cos(lat1);
  final sinAngular = math.sin(angularDistance);
  final cosAngular = math.cos(angularDistance);

  final lat2 = math.asin(
    sinLat1 * cosAngular + cosLat1 * sinAngular * math.cos(bearing),
  );
  final lon2 =
      lon1 +
      math.atan2(
        math.sin(bearing) * sinAngular * cosLat1,
        cosAngular - sinLat1 * math.sin(lat2),
      );

  return LatLng(
    lat2 * 180 / math.pi,
    lon2 * 180 / math.pi,
  );
}

double _distanceMetersBetween(LatLng left, LatLng right) {
  const earthRadius = 6378137.0;
  final dLat = _degreesToRadians(right.latitude - left.latitude);
  final dLon = _degreesToRadians(right.longitude - left.longitude);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(left.latitude)) *
          math.cos(_degreesToRadians(right.latitude)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _bearingBetween(LatLng start, LatLng end) {
  final lat1 = _degreesToRadians(start.latitude);
  final lat2 = _degreesToRadians(end.latitude);
  final dLon = _degreesToRadians(end.longitude - start.longitude);
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

({double dx, double dy}) _toMeters(
  LatLng point, {
  required double referenceLat,
}) {
  final radians = _degreesToRadians(referenceLat);
  return (
    dx: point.longitude * 111320.0 * math.cos(radians),
    dy: point.latitude * 110540.0,
  );
}

LatLng _lerpLatLng(LatLng start, LatLng end, double t) {
  final clampedT = t.clamp(0.0, 1.0);
  return LatLng(
    start.latitude + (end.latitude - start.latitude) * clampedT,
    start.longitude + (end.longitude - start.longitude) * clampedT,
  );
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;
