import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../app/bus_app.dart';
import '../core/app_controller.dart';
import '../core/app_route_observer.dart';
import '../core/bus_map_filter.dart';
import '../core/friendly_error.dart';
import '../core/http_error_utils.dart';
import '../core/models.dart';
import '../core/relative_time_formatter.dart';
import '../core/route_direction_label.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/bus_map_geometry.dart';
import '../widgets/bus_map_markers.dart';
import '../widgets/bus_map_motion.dart';
import '../widgets/platform_map_provider.dart';
import 'adaptive_settings_presenter.dart';
import 'route_detail_navigation.dart';

/// Every bus in one city on one map.
///
/// The city is the unit because that is what the feed is: one request returns a
/// whole authority's fleet, and mixing authorities would multiply the polling
/// for a view nobody asked for. Route lines and stops are loaded only for the
/// bus a rider taps: a whole city's shapes run to hundreds of thousands of
/// points, so drawing them all is not an option, and a single tapped route is
/// the only one whose detail is worth the request.
class BusMapScreen extends StatefulWidget {
  const BusMapScreen({
    this.initialProvider,
    this.initialZoom,
    this.tileProvider,
    super.key,
  });

  final BusProvider? initialProvider;

  /// Where the camera starts. Defaults to a whole-city view, where buses are
  /// shown as clustered counts rather than individually.
  final double? initialZoom;

  /// Test seam: lets a widget test render the map without fetching tiles.
  final TileProvider? tileProvider;

  @override
  State<BusMapScreen> createState() => _BusMapScreenState();
}

class _BusMapScreenState extends State<BusMapScreen>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  static const _simulationTick = Duration(milliseconds: 250);
  static const _splitLayoutBreakpoint = 1080.0;
  static const _cityZoom = 12.0;
  double get _openingZoom => widget.initialZoom ?? _cityZoom;
  static const _userZoom = 15.0;

  static const _viewportPadding = 0.2;
  // How far in a cluster tap takes you.
  static const _clusterZoomStep = 2.0;

  final MapController _mapController = MapController();
  gmaps.GoogleMapController? _googleMapController;
  final TextEditingController _filterController = TextEditingController();
  late final AnimationController _refreshProgressController;

  late BusProvider _provider;
  bool _readInitialProvider = false;

  CityBusSnapshot? _snapshot;
  Map<String, AnimatedBusState> _busStates = const {};
  Map<String, CityBus> _busByKey = const {};

  String? _selectedBusKey;
  String? _selectedGroupKey;
  int? _selectedPathId;
  RouteGeometry? _selectedGeometry;
  List<StopInfo> _selectedStops = const [];

  bool _favoritesOnly = false;
  String _nameFilter = '';
  bool _showFilterField = false;

  LatLng? _userLocation;
  String? _error;
  bool _unsupported = false;
  bool _isRefreshing = false;
  bool _hasLoadedOnce = false;

  Timer? _refreshTimer;
  Timer? _simulationTimer;
  int _refreshRequestSerial = 0;
  int _contextRequestSerial = 0;
  int _backoffSeconds = 0;

  ModalRoute<dynamic>? _route;
  bool _isRouteVisible = true;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  LatLngBounds? _visibleBounds;
  late double _zoom = _openingZoom;
  String? _osmMarkerCacheKey;
  List<Marker> _cachedOsmMarkers = const [];
  final Map<String, gmaps.BitmapDescriptor> _googleClusterIcons =
      <String, gmaps.BitmapDescriptor>{};
  final Set<String> _pendingGoogleClusterIconKeys = <String>{};
  bool _isMovingCameraProgrammatically = false;
  final Map<String, gmaps.BitmapDescriptor> _googleBusIcons =
      <String, gmaps.BitmapDescriptor>{};
  final Set<String> _pendingGoogleBusIconKeys = <String>{};
  gmaps.BitmapDescriptor? _googleUserLocationIcon;
  bool _isGeneratingGoogleUserLocationIcon = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshProgressController = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_readInitialProvider) {
      _readInitialProvider = true;
      final controller = AppControllerScope.read(context);
      _provider = widget.initialProvider ?? controller.settings.provider;
      controller.analytics.logBusMapOpened(
        provider: _provider,
        source: widget.initialProvider == null ? 'home_card' : 'deep_link',
      );
      unawaited(_loadBuses(fitCamera: true));
      unawaited(_locateSilently());
    }

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
  }

  @override
  void dispose() {
    if (_route != null) {
      appRouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _simulationTimer?.cancel();
    _refreshProgressController.dispose();
    _filterController.dispose();
    _googleMapController?.dispose();
    super.dispose();
  }

  // -- lifecycle ------------------------------------------------------------

  /// Whether this screen should be spending network and frames right now.
  bool get _isActive =>
      _isRouteVisible &&
      (_appLifecycleState == AppLifecycleState.resumed ||
          _appLifecycleState == AppLifecycleState.inactive);

  @override
  void didPush() => _isRouteVisible = true;

  @override
  void didPopNext() {
    _isRouteVisible = true;
    _resumeLoops();
  }

  @override
  void didPushNext() {
    _isRouteVisible = false;
    _pauseLoops();
  }

  @override
  void didPop() {
    _isRouteVisible = false;
    _pauseLoops();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (_isActive) {
      _resumeLoops();
    } else {
      _pauseLoops();
    }
  }

  /// Stop everything and disown any reply still in flight.
  ///
  /// Without the serial bump a response that lands after the pause would
  /// re-arm the timer and quietly resume polling behind another screen.
  void _pauseLoops() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _refreshProgressController.stop();
    _refreshRequestSerial += 1;
    _contextRequestSerial += 1;
  }

  void _resumeLoops() {
    if (!_isActive || !mounted) {
      return;
    }
    if (_selectedGroupKey != null) {
      _startSimulationTimer();
    }
    unawaited(_loadBuses());
  }

  /// Interpolating positions only matters for the route being watched; running
  /// it for a whole city would rebuild thousands of markers four times a second
  /// to move dots nobody is looking at.
  void _startSimulationTimer() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(_simulationTick, (_) {
      if (!mounted || !_isActive || _selectedGroupKey == null || _isClustered) {
        return;
      }
      setState(() {});
    });
  }

  // -- data -----------------------------------------------------------------

  /// Never poll faster than the server refreshes: extra requests would return
  /// the identical cached body and spend the map's rate-limit budget for it.
  int get _refreshSeconds {
    final controller = AppControllerScope.read(context);
    final serverTtl = _snapshot?.ttlSeconds ?? 15;
    return math.max(controller.settings.busUpdateTime, serverTtl);
  }

  Future<void> _loadBuses({bool fitCamera = false}) async {
    if (!mounted) {
      return;
    }
    final controller = AppControllerScope.read(context);
    final provider = _provider;
    final requestId = ++_refreshRequestSerial;
    setState(() {
      _isRefreshing = true;
      if (_unsupported) {
        _unsupported = false;
      }
    });

    try {
      final snapshot = await controller.repository.getCityRealtimeBuses(
        provider,
      );
      if (!mounted ||
          requestId != _refreshRequestSerial ||
          provider != _provider) {
        return;
      }
      _applySnapshot(snapshot);
      setState(() {
        _error = null;
        _backoffSeconds = 0;
        _isRefreshing = false;
        _hasLoadedOnce = true;
      });
      if (fitCamera) {
        _moveCamera(_providerCenter(provider), _openingZoom);
      }
    } catch (error) {
      if (!mounted ||
          requestId != _refreshRequestSerial ||
          provider != _provider) {
        return;
      }
      setState(() {
        _isRefreshing = false;
        _hasLoadedOnce = true;
        if (error is CityBusFeedUnavailableException) {
          _unsupported = true;
          _error = null;
          _snapshot = null;
          _busStates = const {};
          _busByKey = const {};
        } else {
          _error = friendlyErrorMessage(error);
          // Keep the last snapshot on screen: stale buses beat a blank map.
          _backoffSeconds = switch (_backoffSeconds) {
            0 => 15,
            15 => 30,
            _ => 60,
          };
        }
      });
    }
    if (!_unsupported) {
      _scheduleNextRefresh();
    }
  }

  void _applySnapshot(CityBusSnapshot snapshot) {
    final now = DateTime.now();
    final refreshSeconds = _refreshSeconds;
    final selectedGroupKey = _selectedGroupKey;

    final selected = <RouteRealtimeBus>[];
    final others = <RouteRealtimeBus>[];
    final byKey = <String, CityBus>{};
    for (final cityBus in snapshot.buses) {
      byKey[cityBus.stateKey] = cityBus;
      if (selectedGroupKey != null && cityBus.groupKey == selectedGroupKey) {
        selected.add(cityBus.bus);
      } else {
        others.add(cityBus.bus);
      }
    }

    String keyOf(RouteRealtimeBus bus) => '${bus.routeId}|${bus.id}';

    // Only the watched route has geometry to ride; the rest simply appear where
    // they were last reported.
    final states = <String, AnimatedBusState>{
      ...buildAnimatedBusStates(
        null,
        others,
        _busStates,
        now: now,
        refreshSeconds: refreshSeconds,
        keyOf: keyOf,
      ),
      ...buildAnimatedBusStates(
        _selectedGeometry,
        selected,
        _busStates,
        now: now,
        refreshSeconds: refreshSeconds,
        keyOf: keyOf,
      ),
    };

    final selectedBusKey = _selectedBusKey;
    setState(() {
      _snapshot = snapshot;
      _busByKey = byKey;
      _busStates = states;
      if (selectedBusKey != null && !byKey.containsKey(selectedBusKey)) {
        // The bus finished its trip while we were watching it.
        _selectedBusKey = null;
      }
    });
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    if (!mounted || !_isActive) {
      return;
    }
    final seconds = _backoffSeconds > 0 ? _backoffSeconds : _refreshSeconds;
    _refreshProgressController
      ..stop()
      ..duration = Duration(seconds: seconds)
      ..value = 0;
    unawaited(_refreshProgressController.forward(from: 0));
    _refreshTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) {
        return;
      }
      unawaited(_loadBuses());
    });
  }

  // -- selection ------------------------------------------------------------

  void _selectBus(String stateKey) {
    if (_selectedBusKey == stateKey) {
      _clearSelection();
      return;
    }
    final cityBus = _busByKey[stateKey];
    if (cityBus == null) {
      return;
    }
    setState(() {
      _selectedBusKey = stateKey;
      _selectedGroupKey = cityBus.groupKey;
      _selectedPathId = cityBus.bus.pathId ?? 0;
      _selectedGeometry = null;
      _selectedStops = const [];
    });
    _startSimulationTimer();
    unawaited(_loadSelectedRouteContext(cityBus));
  }

  void _clearSelection() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _contextRequestSerial += 1;
    setState(() {
      _selectedBusKey = null;
      _selectedGroupKey = null;
      _selectedPathId = null;
      _selectedGeometry = null;
      _selectedStops = const [];
    });
  }

  /// Load the line and the stops for the tapped bus's route.
  ///
  /// The two ids differ for buses the feed could not pin down: the shape often
  /// lives on a row that has no stops at all.
  Future<void> _loadSelectedRouteContext(CityBus cityBus) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    final controller = AppControllerScope.read(context);
    final serial = ++_contextRequestSerial;
    final pathId = cityBus.bus.pathId ?? 0;
    final geometryRouteId = snapshot.geometryRouteIdFor(cityBus);
    final detailRouteId = snapshot.detailRouteIdFor(cityBus);

    // Deliberately independent: plenty of routes have stops but no usable
    // shape, and one missing piece must not take the other down with it.
    Object? failure;
    final pointsFuture = geometryRouteId == null
        ? Future<List<RoutePathPoint>>.value(const [])
        : controller.repository
              .getRoutePathPoints(geometryRouteId, pathId: pathId)
              .catchError((Object error) {
                failure ??= error;
                return const <RoutePathPoint>[];
              });
    final stopsFuture = detailRouteId == null
        ? Future<List<StopInfo>>.value(const [])
        : controller.repository
              .getStopsByRoute(
                controller.repository.routeKeyForRouteId(detailRouteId),
                provider: _provider,
                routeIdHint: detailRouteId,
              )
              .catchError((Object error) {
                failure ??= error;
                return const <StopInfo>[];
              });

    final points = await pointsFuture;
    final stops = await stopsFuture;
    if (!mounted ||
        serial != _contextRequestSerial ||
        _selectedBusKey != cityBus.stateKey) {
      return;
    }

    final geometry = points.length >= 2
        ? RouteGeometry.fromPoints(points)
        : null;
    setState(() {
      _selectedGeometry = geometry;
      _selectedStops = stops
          .where((stop) => stop.pathId == pathId)
          .toList(growable: false);
    });
    _snapToSelectedGeometry(geometry);

    // Only complain when nothing at all could be drawn: a missing line while
    // the stops arrived is not worth interrupting for.
    final error = failure;
    if (error != null && geometry == null && _selectedStops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法載入路線資料：${friendlyErrorMessage(error)}')),
      );
    }
  }

  /// Re-run the animation for the watched route now that it has a line to ride.
  void _snapToSelectedGeometry(RouteGeometry? geometry) {
    final snapshot = _snapshot;
    final selectedGroupKey = _selectedGroupKey;
    if (geometry == null || snapshot == null || selectedGroupKey == null) {
      return;
    }
    final selected = snapshot.buses
        .where((cityBus) => cityBus.groupKey == selectedGroupKey)
        .map((cityBus) => cityBus.bus)
        .toList(growable: false);
    final states = buildAnimatedBusStates(
      geometry,
      selected,
      _busStates,
      now: DateTime.now(),
      refreshSeconds: _refreshSeconds,
      keyOf: (bus) => '${bus.routeId}|${bus.id}',
    );
    setState(() => _busStates = {..._busStates, ...states});
  }

  Future<void> _openRouteDetail(CityBus cityBus, {StopInfo? stop}) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    final detailRouteId = snapshot.detailRouteIdFor(cityBus);
    if (detailRouteId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('這條路線目前沒有可查詢的詳細資料。')));
      return;
    }
    final controller = AppControllerScope.read(context);
    final routeName = snapshot.displayNameFor(cityBus);
    final autoFavorited = await controller.recordRouteSelection(
      provider: _provider,
      routeKey: controller.repository.routeKeyForRouteId(detailRouteId),
      routeName: routeName,
      source: stop == null ? 'bus_map_bus' : 'bus_map_stop',
      pathId: stop?.pathId ?? cityBus.bus.pathId,
      stopId: stop?.stopId,
      stopName: stop?.stopName,
    );
    if (!mounted) {
      return;
    }
    if (autoFavorited != null) {
      showAutoFavoritedSnackBar(context, autoFavorited);
    }
    await openRouteDetailPage(
      context,
      routeKey: controller.repository.routeKeyForRouteId(detailRouteId),
      provider: _provider,
      routeIdHint: detailRouteId,
      routeNameHint: routeName,
      initialPathId: stop?.pathId ?? cityBus.bus.pathId,
      initialStopId: stop?.stopId,
    );
  }

  // -- camera / location ----------------------------------------------------

  LatLng _providerCenter(BusProvider provider) =>
      LatLng(provider.centerLatitude, provider.centerLongitude);

  void _moveCamera(LatLng target, double zoom) {
    _zoom = zoom;
    final googleController = _googleMapController;
    if (googleController != null) {
      _isMovingCameraProgrammatically = true;
      googleController
          .animateCamera(
            gmaps.CameraUpdate.newLatLngZoom(toGoogleLatLng(target), zoom),
          )
          .whenComplete(() => _isMovingCameraProgrammatically = false);
      return;
    }
    try {
      _mapController.move(target, zoom);
    } catch (_) {
      // The controller is not attached yet; the initial camera already matches.
    }
  }

  Future<void> _switchProvider(BusProvider provider) async {
    if (provider == _provider) {
      return;
    }
    _clearSelection();
    setState(() {
      _provider = provider;
      _snapshot = null;
      _busStates = const {};
      _busByKey = const {};
      _error = null;
      _unsupported = false;
      _backoffSeconds = 0;
      _hasLoadedOnce = false;
    });
    AppControllerScope.read(
      context,
    ).analytics.logBusMapCityChanged(provider: provider);
    _moveCamera(_providerCenter(provider), _cityZoom);
    await _loadBuses();
  }

  /// Show the user's dot if we already have permission, without prompting.
  Future<void> _locateSilently() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition();
      if (!mounted) {
        return;
      }
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // Location is a nicety here; the city centre is a fine default.
    }
  }

  Future<void> _locateMe() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showLocationHint('定位服務尚未開啟。');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showLocationHint('沒有取得定位權限。', offerSettings: true);
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) {
        return;
      }
      final here = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = here);
      _moveCamera(here, _userZoom);

      final nearest = nearestBusProvider(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (nearest != _provider) {
        final previous = _provider;
        await _switchProvider(nearest);
        if (!mounted) {
          return;
        }
        _moveCamera(here, _userZoom);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已切換至${nearest.label}'),
            action: SnackBarAction(
              label: '復原',
              onPressed: () => unawaited(_switchProvider(previous)),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showLocationHint(friendlyErrorMessage(error));
      }
    }
  }

  void _showLocationHint(String message, {bool offerSettings = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: offerSettings
            ? SnackBarAction(
                label: '前往設定',
                onPressed: () => openAdaptiveSettingsScreen(context),
              )
            : null,
      ),
    );
  }

  // -- viewport -------------------------------------------------------------

  /// How many markers the current zoom can carry.
  ///
  /// Zoomed in, the viewport itself is the limit. Zoomed out it is not: a whole
  /// city fits, and drawing every bus costs frames to produce a mush of pins.
  /// How many individual markers the current zoom is allowed to draw.
  ///
  /// Clustering handles the wide views, so this only bounds the zoomed-in ones.
  /// The numbers are deliberately modest: every marker is a platform-channel
  /// update on Google Maps, and the app runs on phones where a few hundred of
  /// those drops frames.
  int? get _markerLimit {
    if (_zoom >= 15) {
      return null;
    }
    if (_zoom >= 14) {
      return 300;
    }
    return 150;
  }

  bool _isWithinViewport(CityBus bus) {
    final bounds = _visibleBounds;
    if (bounds == null) {
      return true;
    }
    final latSpan = (bounds.north - bounds.south) * _viewportPadding;
    final lonSpan = (bounds.east - bounds.west) * _viewportPadding;
    return bus.bus.lat >= bounds.south - latSpan &&
        bus.bus.lat <= bounds.north + latSpan &&
        bus.bus.lon >= bounds.west - lonSpan &&
        bus.bus.lon <= bounds.east + lonSpan;
  }

  /// True when individual buses would be an unreadable smear.
  bool get _isClustered => _zoom < kBusClusterMaxZoom;

  List<CityBus> _visibleBuses(Set<String> favoriteRouteIds) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const [];
    }
    final bounds = _visibleBounds;
    return visibleBusesFor(
      snapshot,
      favoritesOnly: _favoritesOnly,
      favoriteRouteIds: favoriteRouteIds,
      query: _nameFilter,
      visible: _isWithinViewport,
      selectedGroupKey: _selectedGroupKey,
      limit: _markerLimit,
      centerLat: bounds == null ? null : (bounds.north + bounds.south) / 2,
      centerLon: bounds == null ? null : (bounds.east + bounds.west) / 2,
    );
  }

  /// What to actually draw: individual buses, plus clusters for the rest.
  ///
  /// The watched route is never clustered — the rider is following it — so it
  /// stays as real markers even while everything else collapses into bubbles.
  _BusMapDrawSet _drawSet(Set<String> favoriteRouteIds) {
    final buses = _visibleBuses(favoriteRouteIds);
    if (!_isClustered) {
      return _BusMapDrawSet(buses: buses, clusters: const []);
    }
    final selectedGroupKey = _selectedGroupKey;
    final individual = <CityBus>[];
    final clusterable = <CityBus>[];
    for (final bus in buses) {
      if (selectedGroupKey != null && bus.groupKey == selectedGroupKey) {
        individual.add(bus);
      } else {
        clusterable.add(bus);
      }
    }
    return _BusMapDrawSet(
      buses: individual,
      clusters: clusterBuses(clusterable, clusterCellDegrees(_zoom)),
    );
  }

  void _zoomIntoCluster(BusCluster cluster) {
    _moveCamera(
      LatLng(cluster.lat, cluster.lon),
      math.min(_zoom + _clusterZoomStep, 18),
    );
  }

  int _matchingBusCount(Set<String> favoriteRouteIds) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return 0;
    }
    final normalizedQuery = normalizeRouteQuery(_nameFilter);
    return snapshot.buses
        .where(
          (bus) => busMatchesFilters(
            snapshot,
            bus,
            favoritesOnly: _favoritesOnly,
            favoriteRouteIds: favoriteRouteIds,
            normalizedQuery: normalizedQuery,
          ),
        )
        .length;
  }

  /// Where to draw a bus right now.
  ///
  /// Only the watched route is interpolated. Everything else sits at its last
  /// reported position until the next poll: dead-reckoning a few hundred buses
  /// four times a second costs a frame each time and moves dots too small to
  /// see, and it makes every marker look changed to the platform layer.
  LatLng _pointFor(CityBus bus, DateTime now) {
    if (bus.groupKey != _selectedGroupKey) {
      return LatLng(bus.bus.lat, bus.bus.lon);
    }
    final state = _busStates[bus.stateKey];
    if (state == null) {
      return LatLng(bus.bus.lat, bus.bus.lon);
    }
    return state.positionAt(now, geometry: _selectedGeometry);
  }

  Color _colorFor(CityBus bus) =>
      (_busStates[bus.stateKey]?.status ??
              describeBusStatus(bus.bus.statusCode))
          .color;

  double _opacityFor(CityBus bus) {
    if (_selectedGroupKey == null || bus.groupKey == _selectedGroupKey) {
      return 1;
    }
    return 0.35;
  }

  // -- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final theme = Theme.of(context);
    final favoriteRouteIds = favoriteRouteIdsFor(
      controller.favoriteGroups,
      _provider,
    );
    final drawSet = _drawSet(favoriteRouteIds);
    final useSplitLayout =
        MediaQuery.sizeOf(context).width >= _splitLayoutBreakpoint;
    final selectedBus = _selectedBusKey == null
        ? null
        : _busByKey[_selectedBusKey];

    final map = _unsupported
        ? _buildUnsupportedNotice(theme)
        : _buildMap(theme, drawSet, controller.settings.mobileMapProvider);

    final overlay = Stack(
      children: [
        Positioned.fill(child: map),
        if (!_unsupported)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _buildStatusChips(theme, drawSet, favoriteRouteIds),
          ),
        if (!useSplitLayout && selectedBus != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _BusMapSelectionCard(
              snapshot: _snapshot!,
              cityBus: selectedBus,
              state: _busStates[selectedBus.stateKey],
              stops: _selectedStops,
              pathId: _selectedPathId,
              onOpenDetail: () => unawaited(_openRouteDetail(selectedBus)),
              onShowWholeRoute: _fitSelectedRoute,
              onClose: _clearSelection,
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: _showFilterField
            ? _buildFilterField(theme)
            : Text('全公車地圖 · ${_provider.label}'),
        actions: [
          IconButton(
            tooltip: _showFilterField ? '關閉篩選' : '篩選路線',
            icon: Icon(
              _showFilterField ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() {
                _showFilterField = !_showFilterField;
                if (!_showFilterField) {
                  _filterController.clear();
                  _nameFilter = '';
                }
              });
            },
          ),
          IconButton(
            tooltip: '只看最愛路線',
            isSelected: _favoritesOnly,
            icon: const Icon(Icons.favorite_border_rounded),
            selectedIcon: const Icon(Icons.favorite_rounded),
            onPressed: () {
              setState(() => _favoritesOnly = !_favoritesOnly);
              AppControllerScope.read(
                context,
              ).analytics.logBusMapFilterToggled(favoritesOnly: _favoritesOnly);
            },
          ),
          if (!kIsWeb)
            IconButton(
              tooltip: '定位',
              icon: const Icon(Icons.my_location_rounded),
              onPressed: () => unawaited(_locateMe()),
            ),
          PopupMenuButton<BusProvider>(
            tooltip: '切換縣市',
            icon: const Icon(Icons.location_city_rounded),
            onSelected: (provider) => unawaited(_switchProvider(provider)),
            itemBuilder: (context) => _providerMenuItems(controller),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: AnimatedBuilder(
            animation: _refreshProgressController,
            builder: (context, _) => LinearProgressIndicator(
              minHeight: 2,
              value: _isRefreshing ? null : _refreshProgressController.value,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: useSplitLayout
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 380,
                        child: _buildSidebar(theme, selectedBus),
                      ),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      Expanded(child: overlay),
                    ],
                  )
                : overlay,
          ),
          const AdBannerWidget(),
        ],
      ),
    );
  }

  List<PopupMenuEntry<BusProvider>> _providerMenuItems(
    AppController controller,
  ) {
    final selected = controller.selectedProviders;
    final rest = BusProvider.values
        .where((provider) => !selected.contains(provider))
        .toList(growable: false);
    return [
      for (final provider in selected)
        CheckedPopupMenuItem<BusProvider>(
          value: provider,
          checked: provider == _provider,
          child: Text(provider.label),
        ),
      if (selected.isNotEmpty && rest.isNotEmpty) const PopupMenuDivider(),
      for (final provider in rest)
        CheckedPopupMenuItem<BusProvider>(
          value: provider,
          checked: provider == _provider,
          child: Text(provider.label),
        ),
    ];
  }

  Widget _buildFilterField(ThemeData theme) {
    return TextField(
      controller: _filterController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        hintText: '篩選路線名稱或車牌',
        border: InputBorder.none,
      ),
      onChanged: (value) => setState(() => _nameFilter = value),
    );
  }

  Widget _buildStatusChips(
    ThemeData theme,
    _BusMapDrawSet drawSet,
    Set<String> favoriteRouteIds,
  ) {
    final shownCount = drawSet.buses.length + drawSet.clusteredBusCount;
    final snapshot = _snapshot;
    final matching = _matchingBusCount(favoriteRouteIds);
    final chips = <Widget>[];

    if (_error != null) {
      chips.add(
        _StatusChip(
          icon: Icons.cloud_off_rounded,
          label: _error!,
          onTap: () => unawaited(_loadBuses()),
          emphasize: true,
        ),
      );
    } else if (snapshot == null) {
      chips.add(
        _StatusChip(
          icon: Icons.directions_bus_rounded,
          label: _hasLoadedOnce ? '目前沒有公車資料' : '正在載入公車位置…',
        ),
      );
    } else {
      final updated = snapshot.updatedAt;
      chips.add(
        _StatusChip(
          icon: Icons.directions_bus_rounded,
          label: updated == null
              ? '$matching 輛公車'
              : '$matching 輛公車 · ${formatRelativeTimestamp(updated)}',
        ),
      );
      if (drawSet.clusters.isNotEmpty) {
        chips.add(
          const _StatusChip(icon: Icons.zoom_in_rounded, label: '放大或點圓圈看個別公車'),
        );
      } else if (shownCount < matching) {
        chips.add(
          _StatusChip(
            icon: Icons.zoom_in_rounded,
            label: '顯示 $shownCount／$matching 輛，放大看更多',
          ),
        );
      }
      if (matching == 0 && snapshot.buses.isNotEmpty) {
        chips.add(
          _StatusChip(
            icon: Icons.filter_alt_off_rounded,
            label: _favoritesOnly ? '最愛中沒有此縣市的路線' : '找不到符合的公車',
            onTap: () {
              setState(() {
                _favoritesOnly = false;
                _nameFilter = '';
                _filterController.clear();
              });
            },
          ),
        );
      }
      if (snapshot.stale) {
        chips.add(
          const _StatusChip(icon: Icons.history_rounded, label: '資料可能不是最新'),
        );
      }
      if (snapshot.truncated) {
        chips.add(
          const _StatusChip(
            icon: Icons.warning_amber_rounded,
            label: '資料可能不完整',
          ),
        );
      }
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _buildUnsupportedNotice(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '此縣市暫不支援全公車地圖',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '可以從右上角切換其他縣市。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme, CityBus? selectedBus) {
    final snapshot = _snapshot;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (selectedBus != null && snapshot != null) ...[
          _BusMapSelectionCard(
            snapshot: snapshot,
            cityBus: selectedBus,
            state: _busStates[selectedBus.stateKey],
            stops: _selectedStops,
            pathId: _selectedPathId,
            onOpenDetail: () => unawaited(_openRouteDetail(selectedBus)),
            onShowWholeRoute: _fitSelectedRoute,
            onClose: _clearSelection,
          ),
          const SizedBox(height: 16),
          if (_selectedStops.isNotEmpty)
            Text('沿途站牌', style: theme.textTheme.titleSmall),
          for (final stop in _selectedStops)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text('${stop.sequence}'),
              title: Text(stop.stopName),
              onTap: () => unawaited(_openRouteDetail(selectedBus, stop: stop)),
            ),
        ] else
          Text(
            '點一輛公車就能看到它的路線、方向與沿途站牌。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }

  void _fitSelectedRoute() {
    final geometry = _selectedGeometry;
    if (geometry == null || geometry.points.isEmpty) {
      return;
    }
    final googleController = _googleMapController;
    if (googleController != null) {
      _isMovingCameraProgrammatically = true;
      googleController
          .animateCamera(
            gmaps.CameraUpdate.newLatLngBounds(
              googleBoundsFromLatLngs(geometry.points),
              mapBoundsDefaultPadding,
            ),
          )
          .whenComplete(() => _isMovingCameraProgrammatically = false);
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(geometry.points),
          padding: const EdgeInsets.all(mapBoundsDefaultPadding),
        ),
      );
    } catch (_) {
      // Controller not ready; the user can pan.
    }
  }

  // -- map backends ---------------------------------------------------------

  Widget _buildMap(
    ThemeData theme,
    _BusMapDrawSet drawSet,
    MobileMapProvider mapProvider,
  ) {
    if (useGoogleMapsProviderFor(mapProvider)) {
      return _buildGoogleMap(theme, drawSet);
    }
    return _buildFlutterMap(theme, drawSet);
  }

  Widget _buildFlutterMap(ThemeData theme, _BusMapDrawSet drawSet) {
    final buses = drawSet.buses;
    final now = DateTime.now();
    final geometry = _selectedGeometry;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _providerCenter(_provider),
        initialZoom: _openingZoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: (_, _) {
          if (_selectedBusKey != null) {
            _clearSelection();
          }
        },
        onMapReady: _syncFlutterMapViewport,
        onMapEvent: (event) {
          if (event is MapEventMoveEnd ||
              event is MapEventFlingAnimationEnd ||
              event is MapEventDoubleTapZoomEnd ||
              event is MapEventScrollWheelZoom) {
            _syncFlutterMapViewport();
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: mapTileUrlTemplate(theme.brightness),
          subdomains: mapTileSubdomains(theme.brightness),
          userAgentPackageName: 'tw.avianjay.taiwanbus.flutter',
          tileProvider: widget.tileProvider,
        ),
        if (geometry != null && geometry.points.length >= 2)
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
        if (_userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _userLocation!,
                width: 20,
                height: 20,
                child: const BusMapUserLocationMarker(),
              ),
            ],
          ),
        if (_selectedStops.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final stop in _selectedStops)
                if (toLatLngIfValid(stop.lat, stop.lon) case final point?)
                  Marker(
                    point: point,
                    width: 26,
                    height: 26,
                    child: GestureDetector(
                      onTap: () {
                        final selected = _selectedBusKey == null
                            ? null
                            : _busByKey[_selectedBusKey];
                        if (selected != null) {
                          unawaited(_openRouteDetail(selected, stop: stop));
                        }
                      },
                      child: _RouteStopDot(name: stop.stopName),
                    ),
                  ),
            ],
          ),
        if (drawSet.clusters.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final cluster in drawSet.clusters)
                Marker(
                  point: LatLng(cluster.lat, cluster.lon),
                  width: clusterMarkerSize(cluster.count),
                  height: clusterMarkerSize(cluster.count),
                  child: GestureDetector(
                    onTap: () => _zoomIntoCluster(cluster),
                    child: BusMapClusterMarker(count: cluster.count),
                  ),
                ),
            ],
          ),
        MarkerLayer(markers: _osmBusMarkers(buses, now)),
      ],
    );
  }

  /// Bus markers for `flutter_map`, reusing the widgets that have not moved.
  ///
  /// Only the watched route changes between polls, so handing Flutter the very
  /// same `Marker` instances for everything else lets it skip those subtrees
  /// entirely instead of laying out hundreds of identical dots every tick.
  List<Marker> _osmBusMarkers(List<CityBus> buses, DateTime now) {
    final cacheKey = _staticMarkerCacheKey(buses);
    final selectedGroupKey = _selectedGroupKey;
    if (cacheKey != _osmMarkerCacheKey) {
      _osmMarkerCacheKey = cacheKey;
      _cachedOsmMarkers = [
        for (final bus in buses)
          if (bus.groupKey != selectedGroupKey) _osmBusMarker(bus, now),
      ];
    }
    return [
      ..._cachedOsmMarkers,
      for (final bus in buses)
        if (bus.groupKey == selectedGroupKey) _osmBusMarker(bus, now),
    ];
  }

  Marker _osmBusMarker(CityBus bus, DateTime now) {
    final selected = bus.stateKey == _selectedBusKey;
    return Marker(
      point: _pointFor(bus, now),
      width: selected ? 48 : 40,
      height: selected ? 48 : 40,
      child: GestureDetector(
        onTap: () => _selectBus(bus.stateKey),
        child: Opacity(
          opacity: _opacityFor(bus),
          child: BusMapBusMarker(
            color: _colorFor(bus),
            selected: selected,
            label: '${_snapshot!.displayNameFor(bus)} ${bus.bus.id}',
          ),
        ),
      ),
    );
  }

  /// Identifies a set of markers that does not move between animation ticks.
  String _staticMarkerCacheKey(List<CityBus> buses) {
    return [
      _snapshot?.updatedAt?.millisecondsSinceEpoch ?? 0,
      buses.length,
      _selectedGroupKey ?? '',
      _selectedBusKey ?? '',
      _favoritesOnly,
      _nameFilter,
      _zoom.toStringAsFixed(1),
    ].join('|');
  }

  void _syncFlutterMapViewport() {
    if (!mounted) {
      return;
    }
    try {
      final camera = _mapController.camera;
      setState(() {
        _visibleBounds = camera.visibleBounds;
        _zoom = camera.zoom;
      });
    } catch (_) {
      // Camera is unavailable until the map is laid out.
    }
  }

  Widget _buildGoogleMap(ThemeData theme, _BusMapDrawSet drawSet) {
    _ensureGoogleIcons(theme, drawSet);
    final now = DateTime.now();
    final geometry = _selectedGeometry;
    final center = _providerCenter(_provider);

    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: toGoogleLatLng(center),
        zoom: _openingZoom,
      ),
      mapType: gmaps.MapType.normal,
      style: googleMapStyleForBrightness(theme.brightness),
      gestureRecognizers: buildGoogleMapGestureRecognizers(),
      rotateGesturesEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      polylines: {
        if (geometry != null && geometry.points.length >= 2)
          gmaps.Polyline(
            polylineId: const gmaps.PolylineId('selected-route'),
            points: geometry.points.map(toGoogleLatLng).toList(growable: false),
            color: theme.colorScheme.primary.withValues(alpha: 0.88),
            width: 5,
          ),
      },
      markers: _buildGoogleMarkers(theme, drawSet, now),
      onMapCreated: (controller) {
        _googleMapController = controller;
        unawaited(_syncGoogleViewport());
      },
      onTap: (_) {
        if (_selectedBusKey != null) {
          _clearSelection();
        }
      },
      onCameraMove: (position) => _zoom = position.zoom,
      onCameraIdle: () {
        if (_isMovingCameraProgrammatically) {
          return;
        }
        unawaited(_syncGoogleViewport());
      },
    );
  }

  Future<void> _syncGoogleViewport() async {
    final controller = _googleMapController;
    if (controller == null) {
      return;
    }
    try {
      final region = await controller.getVisibleRegion();
      final zoom = await controller.getZoomLevel();
      if (!mounted) {
        return;
      }
      setState(() {
        _visibleBounds = LatLngBounds(
          fromGoogleLatLng(region.southwest),
          fromGoogleLatLng(region.northeast),
        );
        _zoom = zoom;
      });
    } catch (_) {
      // The platform view can report before it is ready.
    }
  }

  Set<gmaps.Marker> _buildGoogleMarkers(
    ThemeData theme,
    _BusMapDrawSet drawSet,
    DateTime now,
  ) {
    final buses = drawSet.buses;
    final markers = <gmaps.Marker>{};
    final pixelRatioForClusters = MediaQuery.of(
      context,
    ).devicePixelRatio.clamp(1.0, 3.0).toDouble();
    for (final cluster in drawSet.clusters) {
      final icon =
          _googleClusterIcons[googleClusterIconKey(
            count: cluster.count,
            pixelRatio: pixelRatioForClusters,
          )];
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('cluster:${cluster.key}'),
          position: gmaps.LatLng(cluster.lat, cluster.lon),
          consumeTapEvents: true,
          anchor: icon == null ? const Offset(0.5, 1) : const Offset(0.5, 0.5),
          icon:
              icon ??
              gmaps.BitmapDescriptor.defaultMarkerWithHue(
                googleMarkerHueForColor(theme.colorScheme.primaryContainer),
              ),
          infoWindow: gmaps.InfoWindow(title: '${cluster.count} 輛公車'),
          zIndexInt: 1,
          onTap: () => _zoomIntoCluster(cluster),
        ),
      );
    }
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

    final selectedBus = _selectedBusKey == null
        ? null
        : _busByKey[_selectedBusKey];
    for (final stop in _selectedStops) {
      final point = toLatLngIfValid(stop.lat, stop.lon);
      if (point == null) {
        continue;
      }
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('stop:${stop.stopId}'),
          position: toGoogleLatLng(point),
          consumeTapEvents: true,
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueCyan,
          ),
          infoWindow: gmaps.InfoWindow(title: stop.stopName),
          zIndexInt: 1,
          onTap: selectedBus == null
              ? null
              : () => unawaited(_openRouteDetail(selectedBus, stop: stop)),
        ),
      );
    }

    final pixelRatio = MediaQuery.of(
      context,
    ).devicePixelRatio.clamp(1.0, 3.0).toDouble();
    for (final bus in buses) {
      final selected = bus.stateKey == _selectedBusKey;
      final key = googleBusIconKey(
        color: _colorFor(bus),
        selected: selected,
        pixelRatio: pixelRatio,
      );
      final icon = _googleBusIcons[key];
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('bus:${bus.stateKey}'),
          position: toGoogleLatLng(_pointFor(bus, now)),
          consumeTapEvents: true,
          // Dimming with alpha rather than a second set of rasterised icons
          // keeps the bitmap cache to one entry per colour.
          alpha: _opacityFor(bus),
          anchor: icon == null ? const Offset(0.5, 1) : const Offset(0.5, 0.5),
          icon:
              icon ??
              gmaps.BitmapDescriptor.defaultMarkerWithHue(
                googleMarkerHueForColor(_colorFor(bus)),
              ),
          infoWindow: gmaps.InfoWindow(
            title: _snapshot!.displayNameFor(bus),
            snippet: bus.bus.id,
          ),
          zIndexInt: selected ? 3 : 2,
          onTap: () => _selectBus(bus.stateKey),
        ),
      );
    }
    return markers;
  }

  void _ensureGoogleIcons(ThemeData theme, _BusMapDrawSet drawSet) {
    final pixelRatio = MediaQuery.of(
      context,
    ).devicePixelRatio.clamp(1.0, 3.0).toDouble();
    final clusterRequests = <int>[];
    for (final cluster in drawSet.clusters) {
      final key = googleClusterIconKey(
        count: cluster.count,
        pixelRatio: pixelRatio,
      );
      if (_googleClusterIcons.containsKey(key) ||
          _pendingGoogleClusterIconKeys.contains(key)) {
        continue;
      }
      _pendingGoogleClusterIconKeys.add(key);
      clusterRequests.add(cluster.count);
    }
    if (clusterRequests.isNotEmpty) {
      unawaited(
        _generateGoogleClusterIcons(theme, clusterRequests, pixelRatio),
      );
    }

    final buses = drawSet.buses;
    final requests = <GoogleBusIconRequest>[];
    for (final bus in buses) {
      for (final selected in <bool>[false, bus.stateKey == _selectedBusKey]) {
        final key = googleBusIconKey(
          color: _colorFor(bus),
          selected: selected,
          pixelRatio: pixelRatio,
        );
        if (_googleBusIcons.containsKey(key) ||
            _pendingGoogleBusIconKeys.contains(key)) {
          continue;
        }
        _pendingGoogleBusIconKeys.add(key);
        requests.add(
          GoogleBusIconRequest(
            key: key,
            color: _colorFor(bus),
            selected: selected,
            pixelRatio: pixelRatio,
          ),
        );
      }
    }
    if (requests.isNotEmpty) {
      unawaited(_generateGoogleBusIcons(requests));
    }
    if (_userLocation != null &&
        _googleUserLocationIcon == null &&
        !_isGeneratingGoogleUserLocationIcon) {
      _isGeneratingGoogleUserLocationIcon = true;
      unawaited(_generateGoogleUserLocationIcon(pixelRatio));
    }
  }

  Future<void> _generateGoogleBusIcons(
    List<GoogleBusIconRequest> requests,
  ) async {
    final generated = <String, gmaps.BitmapDescriptor>{};
    try {
      for (final request in requests) {
        final bytes = await drawGoogleBusIcon(request);
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

  Future<void> _generateGoogleClusterIcons(
    ThemeData theme,
    List<int> counts,
    double pixelRatio,
  ) async {
    final generated = <String, gmaps.BitmapDescriptor>{};
    final keys = <String>[];
    try {
      for (final count in counts) {
        final key = googleClusterIconKey(count: count, pixelRatio: pixelRatio);
        keys.add(key);
        final bytes = await drawGoogleClusterIcon(
          count: count,
          pixelRatio: pixelRatio,
          background: theme.colorScheme.primaryContainer,
          foreground: theme.colorScheme.onPrimaryContainer,
          border: theme.colorScheme.surface,
        );
        final size = clusterMarkerSize(count);
        generated[key] = gmaps.BitmapDescriptor.bytes(
          bytes,
          imagePixelRatio: pixelRatio,
          width: size,
          height: size,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingGoogleClusterIconKeys.removeAll(keys);
          _googleClusterIcons.addAll(generated);
        });
      }
    }
  }

  Future<void> _generateGoogleUserLocationIcon(double pixelRatio) async {
    try {
      final Uint8List bytes = await drawGoogleUserLocationIcon(pixelRatio);
      if (!mounted) {
        return;
      }
      setState(() {
        _googleUserLocationIcon = gmaps.BitmapDescriptor.bytes(
          bytes,
          imagePixelRatio: pixelRatio,
          width: GoogleUserLocationIconRequest.baseLogicalSize,
          height: GoogleUserLocationIconRequest.baseLogicalSize,
        );
      });
    } finally {
      _isGeneratingGoogleUserLocationIcon = false;
    }
  }
}

/// What one frame of the map should draw.
///
/// Zoomed in these are all individual buses; zoomed out most of them collapse
/// into [clusters] and only the watched route stays drawn bus by bus.
class _BusMapDrawSet {
  const _BusMapDrawSet({required this.buses, required this.clusters});

  final List<CityBus> buses;
  final List<BusCluster> clusters;

  int get clusteredBusCount =>
      clusters.fold(0, (total, cluster) => total + cluster.count);
}

/// A stop on the route being watched. Deliberately plain: the city map has no
/// ETA to show, so the badge the route sheet uses would be an empty promise.
class _RouteStopDot extends StatelessWidget {
  const _RouteStopDot({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colorScheme.primary, width: 3),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    this.onTap,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = emphasize
        ? colorScheme.errorContainer
        : colorScheme.surface.withValues(alpha: 0.94);
    final foreground = emphasize
        ? colorScheme.onErrorContainer
        : colorScheme.onSurface;

    return Material(
      color: background,
      elevation: 2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: foreground),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 16, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What the rider sees about the bus they tapped.
class _BusMapSelectionCard extends StatelessWidget {
  const _BusMapSelectionCard({
    required this.snapshot,
    required this.cityBus,
    required this.state,
    required this.stops,
    required this.pathId,
    required this.onOpenDetail,
    required this.onShowWholeRoute,
    required this.onClose,
  });

  final CityBusSnapshot snapshot;
  final CityBus cityBus;
  final AnimatedBusState? state;
  final List<StopInfo> stops;
  final int? pathId;
  final VoidCallback onOpenDetail;
  final VoidCallback onShowWholeRoute;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = snapshot.displayNameFor(cityBus);
    final status = state?.status ?? describeBusStatus(cityBus.bus.statusCode);
    final family = snapshot.families[cityBus.routeUid];
    final ambiguous = snapshot.isAmbiguous(cityBus);
    final direction = routeDirectionLabel(
      pathName: stops.isEmpty ? null : stops.last.stopName,
      pathId: pathId ?? cityBus.bus.pathId,
      routeName: name,
    );
    final speedKph = cityBus.bus.speedKph;
    final updatedAt = cityBus.bus.updatedAt;

    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '取消選取',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClose,
                ),
              ],
            ),
            if (direction.isNotEmpty)
              Text(direction, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(cityBus.bus.id),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: status.color,
                  label: Text(
                    status.label,
                    style: TextStyle(
                      color: status.color.computeLuminance() > 0.45
                          ? Colors.black87
                          : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (speedKph != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${speedKph.round()} km/h'),
                  ),
                if (updatedAt != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(formatRelativeTimestamp(updatedAt)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '同路線 ${snapshot.siblingCountFor(cityBus)} 輛行駛中',
              style: theme.textTheme.bodySmall,
            ),
            if (ambiguous && family != null) ...[
              const SizedBox(height: 6),
              Text(
                family.isBareCode
                    ? '這輛車的路線代碼是 ${cityBus.routeUid}，尚無路線名稱。'
                    : '這輛車屬於「${family.name}」路線群，無法判定是哪個區間班次。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onOpenDetail,
                  icon: const Icon(Icons.list_alt_rounded),
                  label: const Text('路線詳情'),
                ),
                OutlinedButton.icon(
                  onPressed: onShowWholeRoute,
                  icon: const Icon(Icons.route_rounded),
                  label: const Text('顯示整條路線'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
