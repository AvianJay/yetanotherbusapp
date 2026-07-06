import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../app/bus_app.dart';
import '../core/friendly_error.dart';
import '../core/models.dart';
import 'eta_badge.dart';
import 'platform_map_provider.dart';

class RouteBusMapSheet extends StatefulWidget {
  const RouteBusMapSheet({
    required this.routeKey,
    required this.provider,
    required this.routeId,
    required this.routeName,
    required this.paths,
    required this.stopsByPath,
    this.liveStopsByPathListenable,
    required this.alwaysShowSeconds,
    this.routeIdHint,
    required this.selectedPathIdListenable,
    this.focusedVehicleId,
    this.focusedVehicleRequest = 0,
    required this.refreshIntervalSeconds,
    this.dragScrollController,
    this.onSelectedPathChanged,
    this.embedded = false,
    super.key,
  });

  final int routeKey;
  final BusProvider provider;
  final String routeId;
  final String? routeIdHint;
  final String routeName;
  final List<PathInfo> paths;
  final Map<int, List<StopInfo>> stopsByPath;
  final ValueListenable<Map<int, List<StopInfo>>>? liveStopsByPathListenable;
  final bool alwaysShowSeconds;
  final ValueListenable<int?> selectedPathIdListenable;
  final String? focusedVehicleId;
  final int focusedVehicleRequest;
  final int refreshIntervalSeconds;
  final ScrollController? dragScrollController;
  final ValueChanged<int>? onSelectedPathChanged;
  final bool embedded;

  @override
  State<RouteBusMapSheet> createState() => _RouteBusMapSheetState();
}

class _RouteBusMapSheetState extends State<RouteBusMapSheet>
    with SingleTickerProviderStateMixin {
  static const _simulationTick = Duration(milliseconds: 250);
  static const _snapToRouteThresholdMeters = 180.0;
  static const _offRouteThresholdMeters = 320.0;
  static const _cameraPadding = EdgeInsets.fromLTRB(20, 20, 20, 140);
  static const _userLocationFocusZoom = 16.4;

  final MapController _mapController = MapController();
  gmaps.GoogleMapController? _googleMapController;
  late final AnimationController _refreshProgressController;

  Timer? _refreshTimer;
  Timer? _simulationTimer;
  StreamSubscription<Position>? _userLocationSubscription;
  _RouteGeometry? _geometry;
  Map<int, List<StopInfo>> _stopsByPath = <int, List<StopInfo>>{};
  Map<String, _AnimatedBusState> _busStates = <String, _AnimatedBusState>{};
  int _refreshRequestSerial = 0;
  bool _isRefreshing = false;
  String? _error;
  String? _selectedBusId;
  int? _selectedStopId;
  bool _followSelectedBus = false;
  int _handledVehicleFocusRequest = -1;
  bool _showBuses = true;
  bool _showStops = true;
  LatLng? _userLocation;
  bool _didFitCurrentPathWithUserLocation = false;
  bool _didFocusInitialUserLocation = false;
  bool _isMovingGoogleCameraProgrammatically = false;
  gmaps.CameraPosition? _googleCameraPosition;
  final Map<String, gmaps.BitmapDescriptor> _googleStopIcons =
      <String, gmaps.BitmapDescriptor>{};
  final Set<String> _pendingGoogleStopIconKeys = <String>{};
  final Map<String, gmaps.BitmapDescriptor> _googleBusIcons =
      <String, gmaps.BitmapDescriptor>{};
  final Set<String> _pendingGoogleBusIconKeys = <String>{};
  gmaps.BitmapDescriptor? _googleUserLocationIcon;
  bool _isGeneratingGoogleUserLocationIcon = false;
  late int _activePathId;
  bool? _lastUseGoogleMapsRouteProvider;
  bool _osmMapReady = false;
  int _mapWidgetGeneration = 0;

  bool get _useGoogleMapsRouteProvider => useGoogleMapsProviderFor(
    AppControllerScope.read(context).settings.mobileMapProvider,
  );

  @override
  void initState() {
    super.initState();
    _activePathId =
        widget.selectedPathIdListenable.value ?? widget.paths.first.pathId;
    _stopsByPath = _copyStopsByPath(widget.stopsByPath);
    _refreshProgressController = AnimationController(vsync: this);
    widget.selectedPathIdListenable.addListener(_handleExternalPathSelection);
    widget.liveStopsByPathListenable?.addListener(_handleExternalStopsUpdate);
    _simulationTimer = Timer.periodic(_simulationTick, (_) {
      if (!mounted || _busStates.isEmpty) {
        return;
      }
      _syncSelectedBusCamera();
      setState(() {});
    });
    unawaited(_loadUserLocation());
    unawaited(_loadMapData(fitCamera: true));
  }

  @override
  void didUpdateWidget(covariant RouteBusMapSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPathIdListenable != widget.selectedPathIdListenable) {
      oldWidget.selectedPathIdListenable.removeListener(
        _handleExternalPathSelection,
      );
      widget.selectedPathIdListenable.addListener(_handleExternalPathSelection);
    }
    if (oldWidget.liveStopsByPathListenable !=
        widget.liveStopsByPathListenable) {
      oldWidget.liveStopsByPathListenable?.removeListener(
        _handleExternalStopsUpdate,
      );
      widget.liveStopsByPathListenable?.addListener(_handleExternalStopsUpdate);
      _handleExternalStopsUpdate();
    } else if (widget.liveStopsByPathListenable == null &&
        oldWidget.stopsByPath != widget.stopsByPath) {
      _applyStopsByPathSnapshot(widget.stopsByPath);
    }
    final routeIdentityChanged =
        oldWidget.routeKey != widget.routeKey ||
        oldWidget.provider != widget.provider ||
        oldWidget.routeId != widget.routeId ||
        oldWidget.embedded != widget.embedded;
    if (routeIdentityChanged) {
      _refreshTimer?.cancel();
      _refreshProgressController
        ..stop()
        ..value = 0;
      _invalidateMapLifecycle();
      final nextPathId =
          widget.selectedPathIdListenable.value ??
          (widget.paths.isNotEmpty ? widget.paths.first.pathId : _activePathId);
      setState(() {
        _activePathId = nextPathId;
        _stopsByPath = _copyStopsByPath(widget.stopsByPath);
        _selectedBusId = null;
        _selectedStopId = null;
        _followSelectedBus = false;
        _handledVehicleFocusRequest = -1;
        _didFitCurrentPathWithUserLocation = false;
        _didFocusInitialUserLocation = false;
        _error = null;
        _geometry = null;
        _busStates = <String, _AnimatedBusState>{};
      });
      unawaited(_loadMapData(fitCamera: true));
    } else if (oldWidget.focusedVehicleId != widget.focusedVehicleId ||
        oldWidget.focusedVehicleRequest != widget.focusedVehicleRequest) {
      _applyFocusedVehicleRequest();
    }
  }

  @override
  void dispose() {
    widget.selectedPathIdListenable.removeListener(
      _handleExternalPathSelection,
    );
    widget.liveStopsByPathListenable?.removeListener(
      _handleExternalStopsUpdate,
    );
    _refreshTimer?.cancel();
    _simulationTimer?.cancel();
    _userLocationSubscription?.cancel();
    _invalidateMapLifecycle();
    _refreshProgressController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final useGoogleMapsRouteProvider = useGoogleMapsProviderFor(
      AppControllerScope.of(context).settings.mobileMapProvider,
    );
    if (_lastUseGoogleMapsRouteProvider == useGoogleMapsRouteProvider) {
      return;
    }
    _lastUseGoogleMapsRouteProvider = useGoogleMapsRouteProvider;
    _invalidateMapLifecycle(invalidateRequests: false);
    final geometry = _geometry;
    if (geometry != null) {
      _fitCameraToGeometry(geometry);
      _syncSelectedBusCamera(force: true);
    }
  }

  int get _refreshSeconds => math.max(3, widget.refreshIntervalSeconds);

  _AnimatedBusState? get _selectedBusState {
    final selectedBusId = _selectedBusId;
    if (selectedBusId == null) {
      return null;
    }
    return _busStates[selectedBusId];
  }

  String? _findBusStateIdByVehicleId(
    String? vehicleId,
    Map<String, _AnimatedBusState> states,
  ) {
    final normalizedVehicleId = normalizeBusVehicleId(vehicleId);
    if (normalizedVehicleId == null) {
      return null;
    }
    for (final entry in states.entries) {
      if (normalizeBusVehicleId(entry.key) == normalizedVehicleId ||
          normalizeBusVehicleId(entry.value.bus.id) == normalizedVehicleId) {
        return entry.key;
      }
    }
    return null;
  }

  void _applyFocusedVehicleRequest() {
    if (widget.focusedVehicleRequest == _handledVehicleFocusRequest) {
      return;
    }
    final nextSelectedBusId = _findBusStateIdByVehicleId(
      widget.focusedVehicleId,
      _busStates,
    );
    if (nextSelectedBusId == null) {
      return;
    }
    setState(() {
      _selectedBusId = nextSelectedBusId;
      _selectedStopId = null;
      _followSelectedBus = true;
      _showBuses = true;
      _handledVehicleFocusRequest = widget.focusedVehicleRequest;
    });
    _syncSelectedBusCamera(force: true);
  }

  List<StopInfo> get _activePathStops =>
      _stopsByPath[_activePathId] ?? const <StopInfo>[];

  StopInfo? get _selectedStop {
    final selectedStopId = _selectedStopId;
    if (selectedStopId == null) {
      return null;
    }
    for (final stop in _activePathStops) {
      if (stop.stopId == selectedStopId) {
        return stop;
      }
    }
    return null;
  }

  void _handleExternalPathSelection() {
    final nextPathId = widget.selectedPathIdListenable.value;
    if (nextPathId == null || nextPathId == _activePathId) {
      return;
    }
    _switchPath(nextPathId, notifyParent: false);
  }

  void _handleExternalStopsUpdate() {
    final latestStopsByPath = widget.liveStopsByPathListenable?.value;
    if (latestStopsByPath == null || latestStopsByPath.isEmpty) {
      return;
    }
    _applyStopsByPathSnapshot(latestStopsByPath);
  }

  void _applyStopsByPathSnapshot(Map<int, List<StopInfo>> stopsByPath) {
    final nextStopsByPath = _copyStopsByPath(stopsByPath);
    final nextSelectedStopId =
        _selectedStopId != null &&
            (nextStopsByPath[_activePathId] ?? const <StopInfo>[]).any(
              (stop) => stop.stopId == _selectedStopId,
            )
        ? _selectedStopId
        : null;
    if (!mounted) {
      _stopsByPath = nextStopsByPath;
      _selectedStopId = nextSelectedStopId;
      return;
    }
    setState(() {
      _stopsByPath = nextStopsByPath;
      _selectedStopId = nextSelectedStopId;
    });
  }

  void _invalidateMapLifecycle({
    bool disposeGoogleController = true,
    bool invalidateRequests = true,
  }) {
    if (invalidateRequests) {
      _refreshRequestSerial += 1;
    }
    _mapWidgetGeneration += 1;
    _osmMapReady = false;
    _googleCameraPosition = null;
    _isMovingGoogleCameraProgrammatically = false;
    final controller = _googleMapController;
    _googleMapController = null;
    if (disposeGoogleController && controller != null) {
      try {
        controller.dispose();
      } catch (_) {
        // Ignore cleanup races while the platform view is tearing down.
      }
    }
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
    _invalidateMapLifecycle();
    setState(() {
      _activePathId = pathId;
      _selectedBusId = null;
      _selectedStopId = null;
      _followSelectedBus = false;
      _didFitCurrentPathWithUserLocation = false;
      _didFocusInitialUserLocation = false;
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
      final pathPointsFuture = controller.repository.getRoutePathPoints(
        widget.routeId,
        pathId: pathId,
      );
      final busesFuture = controller.repository.getRouteRealtimeBuses(
        widget.routeId,
        pathId: pathId,
      );
      final pathPoints = await pathPointsFuture;
      final buses = await busesFuture;
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
      final focusedBusId =
          widget.focusedVehicleRequest != _handledVehicleFocusRequest
          ? _findBusStateIdByVehicleId(widget.focusedVehicleId, nextStates)
          : null;
      final nextSelectedBusId =
          focusedBusId ??
          (_selectedBusId != null && nextStates.containsKey(_selectedBusId)
              ? _selectedBusId
              : null);
      final nextSelectedStopId = focusedBusId != null
          ? null
          : _selectedStopId != null &&
                (_stopsByPath[pathId] ?? const <StopInfo>[]).any(
                  (stop) => stop.stopId == _selectedStopId,
                )
          ? _selectedStopId
          : null;
      setState(() {
        _geometry = geometry;
        _busStates = nextStates;
        _selectedBusId = nextSelectedBusId;
        _selectedStopId = nextSelectedStopId;
        _followSelectedBus = focusedBusId != null
            ? true
            : nextSelectedBusId != null && _followSelectedBus;
        if (focusedBusId != null) {
          _showBuses = true;
          _handledVehicleFocusRequest = widget.focusedVehicleRequest;
        }
        _isRefreshing = false;
      });
      _scheduleNextRefresh();
      if (fitCamera) {
        final didFocusUser =
            !_didFocusInitialUserLocation &&
            _focusOnUserLocation(markInitial: true);
        if (!didFocusUser) {
          _fitCameraToGeometry(geometry);
        }
      }
      _syncSelectedBusCamera(force: true);
    } catch (error) {
      if (!mounted ||
          pathId != _activePathId ||
          requestId != _refreshRequestSerial) {
        return;
      }
      setState(() {
        _isRefreshing = false;
        _error = friendlyErrorMessage(error);
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

  Future<void> _loadUserLocation() async {
    try {
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
      Position? resolved = lastKnown;
      resolved ??= await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 4),
      );
      if (!mounted) {
        return;
      }

      final nextLocation = _toLatLngIfValid(
        resolved.latitude,
        resolved.longitude,
      );
      if (nextLocation == null) {
        return;
      }
      setState(() {
        _userLocation = nextLocation;
      });

      _userLocationSubscription?.cancel();
      _userLocationSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 8,
            ),
          ).listen((position) {
            final nextLocation = _toLatLngIfValid(
              position.latitude,
              position.longitude,
            );
            if (nextLocation == null || !mounted) {
              return;
            }
            if (!mounted) {
              return;
            }
            setState(() {
              _userLocation = nextLocation;
            });
            final geometry = _geometry;
            if (geometry != null) {
              if (_followSelectedBus) {
                _syncSelectedBusCamera(force: true);
              } else if (!_didFocusInitialUserLocation) {
                _focusOnUserLocation(markInitial: true);
              } else if (!_didFitCurrentPathWithUserLocation) {
                _fitCameraToGeometry(geometry);
              }
            }
          });

      final geometry = _geometry;
      if (geometry != null) {
        if (_followSelectedBus) {
          _syncSelectedBusCamera(force: true);
        } else if (!_didFocusInitialUserLocation) {
          _focusOnUserLocation(markInitial: true);
        } else if (!_didFitCurrentPathWithUserLocation) {
          _fitCameraToGeometry(geometry);
        }
      }
    } catch (_) {
      // Ignore location lookup failures and keep the map focused on the route.
    }
  }

  void _fitCameraToGeometry(_RouteGeometry geometry, {int? mapGeneration}) {
    final targetMapGeneration = mapGeneration ?? _mapWidgetGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          targetMapGeneration != _mapWidgetGeneration ||
          geometry.points.isEmpty) {
        return;
      }
      try {
        final fitPoints = <LatLng>[
          ...geometry.points.where(
            (p) => p.latitude.abs() <= 90 && p.longitude.abs() <= 180,
          ),
          ?_userLocation,
        ];
        if (fitPoints.isEmpty) {
          return;
        }
        final didFit = _useGoogleMapsRouteProvider
            ? _fitGoogleCameraToPoints(fitPoints)
            : _fitOsmCameraToPoints(fitPoints);
        if (didFit) {
          _didFitCurrentPathWithUserLocation = _userLocation != null;
        }
      } catch (_) {
        // Ignore fit errors from early controller lifecycle and wait for next refresh.
      }
    });
  }

  bool _fitOsmCameraToPoints(List<LatLng> fitPoints) {
    if (!_osmMapReady) {
      return false;
    }
    try {
      if (fitPoints.length == 1) {
        return _moveOsmCamera(fitPoints.first, 16);
      }
      final bounds = LatLngBounds.fromPoints(fitPoints);
      final clampedBounds = LatLngBounds(
        LatLng(
          bounds.south.clamp(-85.0, 85.0),
          bounds.west.clamp(-180.0, 180.0),
        ),
        LatLng(
          bounds.north.clamp(-85.0, 85.0),
          bounds.east.clamp(-180.0, 180.0),
        ),
      );
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: clampedBounds,
          padding: _userLocation != null
              ? const EdgeInsets.fromLTRB(20, 20, 20, 168)
              : _cameraPadding,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _fitGoogleCameraToPoints(List<LatLng> fitPoints) {
    final controller = _googleMapController;
    if (controller == null) {
      return false;
    }
    if (fitPoints.length == 1) {
      return _moveGoogleCamera(
        gmaps.CameraUpdate.newLatLngZoom(toGoogleLatLng(fitPoints.first), 16),
      );
    }
    return _moveGoogleCamera(
      gmaps.CameraUpdate.newLatLngBounds(
        googleBoundsFromLatLngs(fitPoints),
        _userLocation != null ? 168 : 140,
      ),
    );
  }

  bool _focusOnUserLocation({bool markInitial = false}) {
    final userLocation = _userLocation;
    if (userLocation == null) {
      return false;
    }

    if (_useGoogleMapsRouteProvider) {
      if (_googleMapController == null) {
        return false;
      }
      if (!_moveGoogleCamera(
        gmaps.CameraUpdate.newLatLngZoom(
          toGoogleLatLng(userLocation),
          _userLocationFocusZoom,
        ),
      )) {
        return false;
      }
    } else {
      if (!_moveOsmCamera(userLocation, _userLocationFocusZoom)) {
        return false;
      }
    }

    _didFitCurrentPathWithUserLocation = true;
    if (markInitial) {
      _didFocusInitialUserLocation = true;
    }
    return true;
  }

  void _handleRecenterToUser() {
    if (_userLocation == null) {
      unawaited(_loadUserLocation());
      return;
    }
    if (_followSelectedBus) {
      setState(() {
        _followSelectedBus = false;
      });
    }
    _focusOnUserLocation(markInitial: true);
  }

  bool _moveOsmCamera(LatLng center, double zoom) {
    if (!_osmMapReady) {
      return false;
    }
    try {
      _mapController.move(center, zoom);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _moveGoogleCamera(gmaps.CameraUpdate update) {
    final controller = _googleMapController;
    if (controller == null) {
      return false;
    }
    _isMovingGoogleCameraProgrammatically = true;
    try {
      unawaited(
        controller
            .animateCamera(update)
            .catchError((Object _) {
              if (identical(_googleMapController, controller)) {
                _googleMapController = null;
              }
            })
            .whenComplete(() {
              _isMovingGoogleCameraProgrammatically = false;
            }),
      );
      return true;
    } catch (_) {
      _isMovingGoogleCameraProgrammatically = false;
      if (identical(_googleMapController, controller)) {
        _googleMapController = null;
      }
      return false;
    }
  }

  LatLng? get _googleCameraCenter {
    final position = _googleCameraPosition;
    if (position == null) {
      return null;
    }
    return fromGoogleLatLng(position.target);
  }

  void _syncSelectedBusCamera({bool force = false}) {
    if (!_followSelectedBus) {
      return;
    }
    final geometry = _geometry;
    final selectedBus = _selectedBusState;
    if (geometry == null || selectedBus == null) {
      return;
    }

    try {
      final point = selectedBus.positionAt(DateTime.now(), geometry: geometry);
      if (_useGoogleMapsRouteProvider) {
        final currentCenter = _googleCameraCenter;
        if (!force &&
            currentCenter != null &&
            _distanceMetersBetween(currentCenter, point) < 8) {
          return;
        }
        _moveGoogleCamera(gmaps.CameraUpdate.newLatLng(toGoogleLatLng(point)));
        return;
      }
      if (!_osmMapReady) {
        return;
      }
      final currentCamera = _mapController.camera;
      final currentCenter = currentCamera.center;
      if (!force && _distanceMetersBetween(currentCenter, point) < 8) {
        return;
      }
      _moveOsmCamera(point, currentCamera.zoom);
    } catch (_) {
      // Ignore early camera lifecycle errors before the map is ready.
    }
  }

  void _applyViewportAfterMapReady(
    _RouteGeometry geometry, {
    required int mapGeneration,
  }) {
    if (!mounted || mapGeneration != _mapWidgetGeneration) {
      return;
    }
    final didFocusUser =
        !_didFocusInitialUserLocation &&
        _focusOnUserLocation(markInitial: true);
    if (!didFocusUser) {
      _fitCameraToGeometry(geometry, mapGeneration: mapGeneration);
    }
    _syncSelectedBusCamera(force: true);
  }

  Map<String, _AnimatedBusState> _buildAnimatedBusStates(
    _RouteGeometry geometry,
    List<RouteRealtimeBus> buses,
    Map<String, _AnimatedBusState> previousStates,
  ) {
    final now = DateTime.now();
    final nextStates = <String, _AnimatedBusState>{};

    for (final bus in buses) {
      final rawPoint = _toLatLngIfValid(bus.lat, bus.lon);
      if (rawPoint == null) {
        continue;
      }
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

  Offset _selectedPopupOffset(Alignment alignment) {
    if (alignment == Alignment.bottomCenter) {
      return const Offset(0, 16);
    }
    return const Offset(0, -32);
  }

  Map<int, List<StopInfo>> _copyStopsByPath(Map<int, List<StopInfo>> source) {
    return source.map(
      (pathId, stops) => MapEntry(pathId, List<StopInfo>.of(stops)),
    );
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
          if (!widget.embedded)
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
          SizedBox(height: widget.embedded ? 4 : 12),
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
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showBuses = !_showBuses;
                    if (!_showBuses) {
                      _selectedBusId = null;
                      _followSelectedBus = false;
                    }
                  });
                },
                tooltip: '公車',
                icon: Icon(
                  Icons.directions_bus_rounded,
                  color: _showBuses
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                ),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showStops = !_showStops;
                    if (!_showStops) {
                      _selectedStopId = null;
                    }
                  });
                },
                tooltip: '站牌',
                icon: Icon(
                  Icons.signpost_rounded,
                  color: _showStops
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                ),
                visualDensity: VisualDensity.compact,
              ),
              if (!widget.embedded) ...[
                const SizedBox(width: 4),
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
        child: Text('目前沒有可顯示的路線地圖資料', style: theme.textTheme.bodyMedium),
      );
    }

    final now = DateTime.now();
    final displayBuses = _busStates.values
        .map((busState) {
          final point = busState.positionAt(now, geometry: geometry);
          if (!_isValidLatLng(point)) {
            return null;
          }
          return _DisplayedBus(state: busState, point: point);
        })
        .whereType<_DisplayedBus>()
        .toList();
    final displayStops = _activePathStops
        .map((stop) {
          final point = _toLatLngIfValid(stop.lat, stop.lon);
          if (point == null) {
            return null;
          }
          return _DisplayedStop(stop: stop, point: point);
        })
        .whereType<_DisplayedStop>()
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
    final selectedStop = _selectedStop;
    _DisplayedStop? selectedDisplayStop;
    if (selectedStop != null) {
      for (final stop in displayStops) {
        if (stop.stop.stopId == selectedStop.stopId) {
          selectedDisplayStop = stop;
          break;
        }
      }
    }
    if (_useGoogleMapsRouteProvider) {
      _ensureGoogleStopIcons(theme, displayStops);
      _ensureGoogleBusIcons(displayBuses);
      _ensureGoogleUserLocationIcon();
    }
    final mapGeneration = _mapWidgetGeneration;
    final mapKey = ValueKey<String>(
      '${_useGoogleMapsRouteProvider ? 'google' : 'osm'}:'
      '${widget.provider.name}:${widget.routeId}:$_activePathId:'
      '${widget.embedded ? 'embedded' : 'sheet'}',
    );

    final hasGoogleBottomOverlay =
        _useGoogleMapsRouteProvider &&
        ((_showBuses && selectedDisplayBus != null) ||
            (_showStops && selectedDisplayStop != null));

    return Stack(
      children: [
        Positioned.fill(
          child: _useGoogleMapsRouteProvider
              ? _buildGoogleRouteMap(
                  key: mapKey,
                  mapGeneration: mapGeneration,
                  theme: theme,
                  geometry: geometry,
                  displayStops: displayStops,
                  displayBuses: displayBuses,
                )
              : FlutterMap(
                  key: mapKey,
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: geometry.points.first,
                    initialZoom: 13.5,
                    onMapReady: () {
                      if (!mounted || mapGeneration != _mapWidgetGeneration) {
                        return;
                      }
                      _osmMapReady = true;
                      _applyViewportAfterMapReady(
                        geometry,
                        mapGeneration: mapGeneration,
                      );
                    },
                    onTap: (_, point) {
                      if (_selectedBusId == null && _selectedStopId == null) {
                        return;
                      }
                      setState(() {
                        _selectedBusId = null;
                        _selectedStopId = null;
                        _followSelectedBus = false;
                      });
                    },
                    onPositionChanged: (_, hasGesture) {
                      if (!hasGesture || !_followSelectedBus) {
                        return;
                      }
                      setState(() {
                        _followSelectedBus = false;
                      });
                    },
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: mapTileUrlTemplate(theme.brightness),
                      subdomains: mapTileSubdomains(theme.brightness),
                      userAgentPackageName: 'tw.avianjay.taiwanbus.flutter',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: geometry.points,
                          strokeWidth: 5,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.88,
                          ),
                          borderColor: theme.colorScheme.surface,
                          borderStrokeWidth: 1.2,
                        ),
                      ],
                    ),
                    if (_userLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _userLocation!,
                            width: 20,
                            height: 20,
                            child: const _UserLocationMarker(),
                          ),
                        ],
                      ),
                    if (_showStops)
                      MarkerLayer(
                        markers: displayStops.map((stop) {
                          final selected = _selectedStopId == stop.stop.stopId;
                          return Marker(
                            point: stop.point,
                            width: selected ? 44 : 36,
                            height: selected ? 44 : 36,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedStopId =
                                      _selectedStopId == stop.stop.stopId
                                      ? null
                                      : stop.stop.stopId;
                                  _selectedBusId = null;
                                  _followSelectedBus = false;
                                });
                              },
                              child: _StopMarker(
                                stop: stop.stop,
                                alwaysShowSeconds: widget.alwaysShowSeconds,
                                selected: selected,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    if (_showBuses)
                      MarkerLayer(
                        markers: displayBuses.map((bus) {
                          final selected = _selectedBusId == bus.state.bus.id;
                          return Marker(
                            point: bus.point,
                            width: selected ? 48 : 40,
                            height: selected ? 48 : 40,
                            child: GestureDetector(
                              onTap: () {
                                final nextSelectedBusId =
                                    _selectedBusId == bus.state.bus.id
                                    ? null
                                    : bus.state.bus.id;
                                setState(() {
                                  _selectedBusId = nextSelectedBusId;
                                  _selectedStopId = null;
                                  _followSelectedBus =
                                      nextSelectedBusId != null;
                                });
                                if (nextSelectedBusId != null) {
                                  _syncSelectedBusCamera(force: true);
                                }
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
                    if (_showBuses && selectedDisplayBus != null)
                      MarkerLayer(
                        markers: [
                          () {
                            final displayedBus = selectedDisplayBus!;
                            final popupAlignment = _selectedPopupAlignment(
                              displayedBus.point,
                            );
                            return Marker(
                              point: displayedBus.point,
                              width: 224,
                              height: 124,
                              alignment: popupAlignment,
                              child: IgnorePointer(
                                child: Transform.translate(
                                  offset: _selectedPopupOffset(popupAlignment),
                                  child: _BusInfoPopupCompact(
                                    busState: displayedBus.state,
                                  ),
                                ),
                              ),
                            );
                          }(),
                        ],
                      ),
                    if (_showStops && selectedDisplayStop != null)
                      MarkerLayer(
                        markers: [
                          () {
                            final displayedStop = selectedDisplayStop!;
                            final popupAlignment = _selectedPopupAlignment(
                              displayedStop.point,
                            );
                            return Marker(
                              point: displayedStop.point,
                              width: 228,
                              height: 122,
                              alignment: popupAlignment,
                              child: IgnorePointer(
                                child: Transform.translate(
                                  offset: _selectedPopupOffset(popupAlignment),
                                  child: _StopInfoPopup(
                                    stop: displayedStop.stop,
                                    alwaysShowSeconds: widget.alwaysShowSeconds,
                                  ),
                                ),
                              ),
                            );
                          }(),
                        ],
                      ),
                  ],
                ),
        ),
        if (!widget.embedded)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(child: _buildTopProgressBar()),
          ),
        if (_useGoogleMapsRouteProvider &&
            _showBuses &&
            selectedDisplayBus != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 320,
                child: _BusInfoPopupCompact(busState: selectedDisplayBus.state),
              ),
            ),
          ),
        if (_useGoogleMapsRouteProvider &&
            _showStops &&
            selectedDisplayStop != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 328,
                child: _StopInfoPopup(
                  stop: selectedDisplayStop.stop,
                  alwaysShowSeconds: widget.alwaysShowSeconds,
                ),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: hasGoogleBottomOverlay ? 136 : 20,
          child: FloatingActionButton.small(
            heroTag: widget.embedded
                ? 'route-map-recenter-inline'
                : 'route-map-recenter-sheet',
            onPressed: _handleRecenterToUser,
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
      ],
    );
  }

  void _ensureGoogleStopIcons(
    ThemeData theme,
    List<_DisplayedStop> displayStops,
  ) {
    if (!_showStops || displayStops.isEmpty) {
      return;
    }

    final pixelRatio = MediaQuery.of(
      context,
    ).devicePixelRatio.clamp(1.0, 3.0).toDouble();
    final requests = <_GoogleStopIconRequest>[];

    for (final stop in displayStops) {
      for (final selected in <bool>[
        false,
        _selectedStopId == stop.stop.stopId,
      ]) {
        final eta = buildEtaPresentation(
          stop.stop,
          alwaysShowSeconds: widget.alwaysShowSeconds,
          brightness: theme.brightness,
          colorScheme: theme.colorScheme,
        );
        final key = _googleStopIconKey(
          eta: eta,
          selected: selected,
          pixelRatio: pixelRatio,
        );
        if (_googleStopIcons.containsKey(key) ||
            _pendingGoogleStopIconKeys.contains(key)) {
          continue;
        }
        _pendingGoogleStopIconKeys.add(key);
        requests.add(
          _GoogleStopIconRequest(
            key: key,
            eta: eta,
            selected: selected,
            pixelRatio: pixelRatio,
          ),
        );
      }
    }

    if (requests.isNotEmpty) {
      unawaited(_generateGoogleStopIcons(requests));
    }
  }

  String _googleStopIconKey({
    required EtaPresentation eta,
    required bool selected,
    required double pixelRatio,
  }) {
    return [
      selected ? 'selected' : 'normal',
      pixelRatio.toStringAsFixed(2),
      eta.text,
      eta.backgroundColor,
      eta.foregroundColor,
    ].join('|');
  }

  Future<void> _generateGoogleStopIcons(
    List<_GoogleStopIconRequest> requests,
  ) async {
    final generated = <String, gmaps.BitmapDescriptor>{};
    try {
      for (final request in requests) {
        final bytes = await _drawGoogleStopIcon(request);
        generated[request.key] = gmaps.BitmapDescriptor.bytes(
          bytes,
          imagePixelRatio: request.pixelRatio,
          width: request.logicalSize,
          height: request.logicalSize,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          for (final request in requests) {
            _pendingGoogleStopIconKeys.remove(request.key);
          }
          _googleStopIcons.addAll(generated);
        });
      }
    }
  }

  Future<Uint8List> _drawGoogleStopIcon(_GoogleStopIconRequest request) async {
    final pixelSize = (request.logicalSize * request.pixelRatio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(request.pixelRatio, request.pixelRatio);
    final center = ui.Offset(request.logicalSize / 2, request.logicalSize / 2);
    final rect = ui.Rect.fromCenter(
      center: center,
      width: request.badgeSize,
      height: request.badgeSize,
    );
    final radius = ui.Radius.circular(request.badgeSize * 0.31);
    final rrect = ui.RRect.fromRectAndRadius(rect, radius);

    canvas.drawRRect(
      rrect.shift(const ui.Offset(0, 2)),
      ui.Paint()
        ..color = Colors.black.withValues(alpha: 0.24)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    canvas.drawRRect(rrect, ui.Paint()..color = request.eta.backgroundColor);
    canvas.drawRRect(
      rrect,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = request.borderWidth
        ..color = Colors.white,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: request.eta.text,
        style: TextStyle(
          color: request.eta.foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: request.badgeSize * 0.24,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: request.badgeSize - 4);
    textPainter.paint(
      canvas,
      center - ui.Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelSize, pixelSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  void _ensureGoogleUserLocationIcon() {
    if (_googleUserLocationIcon != null ||
        _isGeneratingGoogleUserLocationIcon) {
      return;
    }

    _isGeneratingGoogleUserLocationIcon = true;
    final pixelRatio = MediaQuery.of(
      context,
    ).devicePixelRatio.clamp(1.0, 3.0).toDouble();

    unawaited(() async {
      gmaps.BitmapDescriptor? icon;
      try {
        final bytes = await _drawGoogleUserLocationIcon(pixelRatio);
        icon = gmaps.BitmapDescriptor.bytes(
          bytes,
          imagePixelRatio: pixelRatio,
          width: _GoogleUserLocationIconRequest.baseLogicalSize,
          height: _GoogleUserLocationIconRequest.baseLogicalSize,
        );
      } finally {
        if (mounted) {
          setState(() {
            _googleUserLocationIcon = icon ?? _googleUserLocationIcon;
            _isGeneratingGoogleUserLocationIcon = false;
          });
        } else {
          _isGeneratingGoogleUserLocationIcon = false;
        }
      }
    }());
  }

  void _ensureGoogleBusIcons(List<_DisplayedBus> displayBuses) {
    if (!_showBuses || displayBuses.isEmpty) {
      return;
    }

    final pixelRatio = MediaQuery.of(
      context,
    ).devicePixelRatio.clamp(1.0, 3.0).toDouble();
    final requests = <_GoogleBusIconRequest>[];

    for (final bus in displayBuses) {
      for (final selected in <bool>[
        false,
        _selectedBusId == bus.state.bus.id,
      ]) {
        final key = _googleBusIconKey(
          color: bus.state.status.color,
          selected: selected,
          pixelRatio: pixelRatio,
        );
        if (_googleBusIcons.containsKey(key) ||
            _pendingGoogleBusIconKeys.contains(key)) {
          continue;
        }
        _pendingGoogleBusIconKeys.add(key);
        requests.add(
          _GoogleBusIconRequest(
            key: key,
            color: bus.state.status.color,
            selected: selected,
            pixelRatio: pixelRatio,
          ),
        );
      }
    }

    if (requests.isNotEmpty) {
      unawaited(_generateGoogleBusIcons(requests));
    }
  }

  String _googleBusIconKey({
    required Color color,
    required bool selected,
    required double pixelRatio,
  }) {
    return [
      color.toARGB32().toRadixString(16),
      selected ? 'selected' : 'normal',
      pixelRatio.toStringAsFixed(2),
    ].join('|');
  }

  Future<void> _generateGoogleBusIcons(
    List<_GoogleBusIconRequest> requests,
  ) async {
    final generated = <String, gmaps.BitmapDescriptor>{};
    try {
      for (final request in requests) {
        final bytes = await _drawGoogleBusIcon(request);
        generated[request.key] = gmaps.BitmapDescriptor.bytes(
          bytes,
          imagePixelRatio: request.pixelRatio,
          width: request.logicalSize,
          height: request.logicalSize,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          for (final request in requests) {
            _pendingGoogleBusIconKeys.remove(request.key);
          }
          _googleBusIcons.addAll(generated);
        });
      }
    }
  }

  Future<Uint8List> _drawGoogleUserLocationIcon(double pixelRatio) async {
    final request = _GoogleUserLocationIconRequest(pixelRatio: pixelRatio);
    final pixelSize = (request.logicalSize * pixelRatio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(pixelRatio, pixelRatio);
    final center = ui.Offset(request.logicalSize / 2, request.logicalSize / 2);

    canvas.drawCircle(
      center,
      request.outerRadius,
      ui.Paint()..color = const Color(0x331E88E5),
    );
    canvas.drawCircle(
      center.translate(0, 1.5),
      request.innerRadius,
      ui.Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      center,
      request.innerRadius,
      ui.Paint()..color = const Color(0xFF1E88E5),
    );
    canvas.drawCircle(
      center,
      request.innerRadius,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelSize, pixelSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _drawGoogleBusIcon(_GoogleBusIconRequest request) async {
    final pixelSize = (request.logicalSize * request.pixelRatio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(request.pixelRatio, request.pixelRatio);
    final center = ui.Offset(request.logicalSize / 2, request.logicalSize / 2);
    final foreground = request.color.computeLuminance() > 0.45
        ? Colors.black87
        : Colors.white;

    canvas.drawCircle(
      center.translate(0, 1.5),
      request.radius,
      ui.Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      center,
      request.radius,
      ui.Paint()..color = request.color,
    );
    canvas.drawCircle(
      center,
      request.radius,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = request.borderWidth
        ..color = Colors.white,
    );

    final busIconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.directions_bus_rounded.codePoint),
        style: TextStyle(
          fontFamily: Icons.directions_bus_rounded.fontFamily,
          package: Icons.directions_bus_rounded.fontPackage,
          fontSize: request.iconSize,
          color: foreground,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    busIconPainter.paint(
      canvas,
      center - ui.Offset(busIconPainter.width / 2, busIconPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelSize, pixelSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  Widget _buildGoogleRouteMap({
    required Key key,
    required int mapGeneration,
    required ThemeData theme,
    required _RouteGeometry geometry,
    required List<_DisplayedStop> displayStops,
    required List<_DisplayedBus> displayBuses,
  }) {
    return gmaps.GoogleMap(
      key: key,
      initialCameraPosition: gmaps.CameraPosition(
        target: toGoogleLatLng(geometry.points.first),
        zoom: 13.5,
      ),
      mapType: gmaps.MapType.normal,
      style: googleMapStyleForBrightness(theme.brightness),
      gestureRecognizers: buildGoogleMapGestureRecognizers(),
      rotateGesturesEnabled: false,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      polylines: _buildGoogleRoutePolylines(theme, geometry),
      markers: _buildGoogleRouteMarkers(
        theme: theme,
        displayStops: displayStops,
        displayBuses: displayBuses,
      ),
      onMapCreated: (controller) {
        if (!mounted || mapGeneration != _mapWidgetGeneration) {
          controller.dispose();
          return;
        }
        final previousController = _googleMapController;
        _googleMapController = controller;
        _googleCameraPosition = gmaps.CameraPosition(
          target: toGoogleLatLng(geometry.points.first),
          zoom: 13.5,
        );
        if (previousController != null &&
            !identical(previousController, controller)) {
          try {
            previousController.dispose();
          } catch (_) {
            // Ignore replacement races while rebuilding the map view.
          }
        }
        _applyViewportAfterMapReady(geometry, mapGeneration: mapGeneration);
      },
      onTap: (_) {
        if (_selectedBusId == null && _selectedStopId == null) {
          return;
        }
        setState(() {
          _selectedBusId = null;
          _selectedStopId = null;
          _followSelectedBus = false;
        });
      },
      onCameraMoveStarted: () {
        if (_isMovingGoogleCameraProgrammatically || !_followSelectedBus) {
          return;
        }
        setState(() {
          _followSelectedBus = false;
        });
      },
      onCameraMove: (position) {
        _googleCameraPosition = position;
      },
    );
  }

  Set<gmaps.Polyline> _buildGoogleRoutePolylines(
    ThemeData theme,
    _RouteGeometry geometry,
  ) {
    final points = geometry.points.map(toGoogleLatLng).toList(growable: false);
    return {
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route-border'),
        points: points,
        color: theme.colorScheme.surface,
        width: 8,
        zIndex: 1,
      ),
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route'),
        points: points,
        color: theme.colorScheme.primary.withValues(alpha: 0.88),
        width: 5,
        zIndex: 2,
      ),
    };
  }

  Set<gmaps.Marker> _buildGoogleRouteMarkers({
    required ThemeData theme,
    required List<_DisplayedStop> displayStops,
    required List<_DisplayedBus> displayBuses,
  }) {
    final markers = <gmaps.Marker>{};
    final userLocation = _userLocation;
    if (userLocation != null) {
      final icon = _googleUserLocationIcon;
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('user-location'),
          position: toGoogleLatLng(userLocation),
          anchor: icon == null ? const Offset(0.5, 1) : const Offset(0.5, 0.5),
          icon:
              icon ??
              gmaps.BitmapDescriptor.defaultMarkerWithHue(
                gmaps.BitmapDescriptor.hueAzure,
              ),
          zIndexInt: 4,
        ),
      );
    }

    if (_showStops) {
      for (final stop in displayStops) {
        final selected = _selectedStopId == stop.stop.stopId;
        final eta = buildEtaPresentation(
          stop.stop,
          alwaysShowSeconds: widget.alwaysShowSeconds,
          brightness: theme.brightness,
          colorScheme: theme.colorScheme,
        );
        final iconKey = _googleStopIconKey(
          eta: eta,
          selected: selected,
          pixelRatio: MediaQuery.of(
            context,
          ).devicePixelRatio.clamp(1.0, 3.0).toDouble(),
        );
        markers.add(
          gmaps.Marker(
            markerId: gmaps.MarkerId('stop:${stop.stop.stopId}'),
            consumeTapEvents: true,
            position: toGoogleLatLng(stop.point),
            icon:
                _googleStopIcons[iconKey] ??
                gmaps.BitmapDescriptor.defaultMarkerWithHue(
                  selected
                      ? googleMarkerHueForColor(theme.colorScheme.primary)
                      : gmaps.BitmapDescriptor.hueCyan,
                ),
            infoWindow: gmaps.InfoWindow(
              title: stop.stop.stopName,
              snippet: eta.text.replaceAll('\n', ' '),
            ),
            zIndexInt: selected ? 3 : 1,
            onTap: () {
              setState(() {
                _selectedStopId = _selectedStopId == stop.stop.stopId
                    ? null
                    : stop.stop.stopId;
                _selectedBusId = null;
                _followSelectedBus = false;
              });
            },
          ),
        );
      }
    }

    if (_showBuses) {
      for (final bus in displayBuses) {
        final selected = _selectedBusId == bus.state.bus.id;
        final iconKey = _googleBusIconKey(
          color: bus.state.status.color,
          selected: selected,
          pixelRatio: MediaQuery.of(
            context,
          ).devicePixelRatio.clamp(1.0, 3.0).toDouble(),
        );
        final icon = _googleBusIcons[iconKey];
        markers.add(
          gmaps.Marker(
            markerId: gmaps.MarkerId('bus:${bus.state.bus.id}'),
            consumeTapEvents: true,
            position: toGoogleLatLng(bus.point),
            anchor: icon == null
                ? const Offset(0.5, 1)
                : const Offset(0.5, 0.5),
            icon:
                icon ??
                gmaps.BitmapDescriptor.defaultMarkerWithHue(
                  googleMarkerHueForColor(bus.state.status.color),
                ),
            infoWindow: gmaps.InfoWindow(
              title: bus.state.bus.id,
              snippet: bus.state.status.label,
            ),
            zIndexInt: selected ? 5 : 2,
            onTap: () {
              final nextSelectedBusId = _selectedBusId == bus.state.bus.id
                  ? null
                  : bus.state.bus.id;
              setState(() {
                _selectedBusId = nextSelectedBusId;
                _selectedStopId = null;
                _followSelectedBus = nextSelectedBusId != null;
              });
              if (nextSelectedBusId != null) {
                _syncSelectedBusCamera(force: true);
              }
            },
          ),
        );
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = widget.embedded
        ? BorderRadius.circular(28)
        : const BorderRadius.vertical(top: Radius.circular(28));

    return Material(
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      borderRadius: borderRadius,
      child: SafeArea(
        top: !widget.embedded,
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
          border: Border.all(color: Colors.white, width: selected ? 3 : 2),
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

class _StopMarker extends StatelessWidget {
  const _StopMarker({
    required this.stop,
    required this.alwaysShowSeconds,
    required this.selected,
  });

  final StopInfo stop;
  final bool alwaysShowSeconds;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.08 : 1,
      duration: const Duration(milliseconds: 180),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white, width: selected ? 2.5 : 1.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: EtaBadge(
            stop: stop,
            alwaysShowSeconds: alwaysShowSeconds,
            size: selected ? 36 : 30,
          ),
        ),
      ),
    );
  }
}

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1E88E5),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _BusInfoPopup extends StatelessWidget {
  const _BusInfoPopup({required this.busState});

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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
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

class _StopInfoPopup extends StatelessWidget {
  const _StopInfoPopup({required this.stop, required this.alwaysShowSeconds});

  final StopInfo stop;
  final bool alwaysShowSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eta = buildEtaPresentation(
      stop,
      alwaysShowSeconds: alwaysShowSeconds,
      brightness: theme.brightness,
    );

    return Material(
      elevation: 10,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EtaBadge(
              stop: stop,
              alwaysShowSeconds: alwaysShowSeconds,
              size: 40,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.stopName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _InfoChip(label: '站序', value: '${stop.sequence}'),
                      _InfoChip(
                        label: '到站',
                        value: eta.text.replaceAll('\n', ''),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusInfoPopupCompact extends StatelessWidget {
  const _BusInfoPopupCompact({required this.busState});

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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CompactInfoCell(
                    label: '速度',
                    value: busState.bus.speedKph == null
                        ? '--'
                        : '${busState.bus.speedKph!.round()} km/h',
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _CompactInfoCell(
                    label: '角度',
                    value: busState.bus.azimuth == null
                        ? '--'
                        : '${busState.bus.azimuth!.round()}°',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: _CompactInfoCell(
                    label: '更新',
                    value: _BusInfoPopup._formatTime(busState.bus.updatedAt),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _CompactInfoCell(
                    label: '狀態',
                    value: busState.mode == _BusMotionMode.snappedToRoute
                        ? '貼線'
                        : '離線 ${busState.distanceToRouteMeters.round()}m',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 188),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

class _CompactInfoCell extends StatelessWidget {
  const _CompactInfoCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

class _DisplayedBus {
  const _DisplayedBus({required this.state, required this.point});

  final _AnimatedBusState state;
  final LatLng point;
}

class _DisplayedStop {
  const _DisplayedStop({required this.stop, required this.point});

  final StopInfo stop;
  final LatLng point;
}

class _GoogleStopIconRequest {
  const _GoogleStopIconRequest({
    required this.key,
    required this.eta,
    required this.selected,
    required this.pixelRatio,
  });

  final String key;
  final EtaPresentation eta;
  final bool selected;
  final double pixelRatio;

  double get logicalSize => selected ? 44 : 36;

  double get badgeSize => selected ? 36 : 30;

  double get borderWidth => selected ? 2.5 : 1.8;
}

class _GoogleBusIconRequest {
  const _GoogleBusIconRequest({
    required this.key,
    required this.color,
    required this.selected,
    required this.pixelRatio,
  });

  final String key;
  final Color color;
  final bool selected;
  final double pixelRatio;

  double get logicalSize => selected ? 48 : 40;

  double get radius => selected ? 20 : 17;

  double get borderWidth => selected ? 3 : 2;

  double get iconSize => selected ? 24 : 20;
}

class _GoogleUserLocationIconRequest {
  const _GoogleUserLocationIconRequest({required this.pixelRatio});

  static const double baseLogicalSize = 24;

  final double pixelRatio;

  double get logicalSize => baseLogicalSize;

  double get outerRadius => 10;

  double get innerRadius => 7.2;
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

  LatLng positionAt(DateTime now, {required _RouteGeometry geometry}) {
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
    return (baseDistance + advanceMeters).clamp(
      0.0,
      geometry.totalLengthMeters,
    );
  }

  double _elapsedSeconds(DateTime now) {
    return math.max(0, now.difference(sampledAt).inMilliseconds / 1000.0);
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
    final latLngs = points
        .map((point) => _toLatLngIfValid(point.lat, point.lon))
        .whereType<LatLng>()
        .toList();
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

bool _isValidCoordinate(double latitude, double longitude) {
  return latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
}

bool _isValidLatLng(LatLng point) {
  return _isValidCoordinate(point.latitude, point.longitude);
}

LatLng? _toLatLngIfValid(double latitude, double longitude) {
  if (!_isValidCoordinate(latitude, longitude)) {
    return null;
  }
  return LatLng(latitude, longitude);
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

  return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
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
