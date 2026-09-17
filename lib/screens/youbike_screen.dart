import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../app/bus_app.dart';
import '../core/debouncer.dart';
import '../core/request_sequence.dart';
import '../core/transit_repository.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/platform_map_provider.dart';
import '../widgets/ad_banner_widget.dart';

class YouBikeScreen extends StatefulWidget {
  const YouBikeScreen({
    required this.isActive,
    this.showAdBanner = true,
    super.key,
  });

  final bool isActive;
  final bool showAdBanner;

  @override
  State<YouBikeScreen> createState() => _YouBikeScreenState();
}

class _YouBikeScreenState extends State<YouBikeScreen>
    with SingleTickerProviderStateMixin {
  final TransitRepository _repo = TransitRepository.shared;
  final MapController _mapController = MapController();
  late final AnimationController _osmCameraAnimation;
  gmaps.GoogleMapController? _googleMapController;
  final Map<String, gmaps.BitmapDescriptor> _googleStationIcons =
      <String, gmaps.BitmapDescriptor>{};
  final Set<String> _pendingGoogleStationIconKeys = <String>{};
  gmaps.BitmapDescriptor? _googleUserLocationIcon;
  bool _isGeneratingGoogleUserLocationIcon = false;

  static const _defaultCenter = LatLng(25.033, 121.565); // Taipei
  static const _defaultZoom = 15.0;
  static const _searchRadius = 1500; // metres
  static const _splitLayoutBreakpoint = 1080.0;
  static const _mapMoveDebounce = Duration(milliseconds: 300);
  static const _cameraAnimationDuration = Duration(milliseconds: 320);

  LatLng _center = _defaultCenter;
  LatLng _googleCameraCenter = _defaultCenter;
  double _googleCameraZoom = _defaultZoom;
  LatLng? _userLocation;
  bool _locating = true;
  bool _loadingStations = false;
  List<BikeStation> _stations = [];
  BikeStation? _selectedStation;
  Timer? _refreshTimer;
  bool _usesSplitLayout = false;
  final _nearbyRequest = RequestSequence();
  final _mapMoveDebouncer = Debouncer(_mapMoveDebounce);
  LatLng? _osmCameraStart;
  LatLng? _osmCameraTarget;
  double? _osmCameraStartZoom;
  double? _osmCameraTargetZoom;

  bool get _useGoogleMapsPointProvider => useGoogleMapsProviderFor(
    AppControllerScope.read(context).settings.mobileMapProvider,
  );

  @override
  void initState() {
    super.initState();
    _osmCameraAnimation = AnimationController(
      vsync: this,
      duration: _cameraAnimationDuration,
    )..addListener(_animateOsmCamera);
    _initLocation();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapMoveDebouncer.dispose();
    _osmCameraAnimation
      ..removeListener(_animateOsmCamera)
      ..dispose();
    _googleMapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant YouBikeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) {
      return;
    }
    if (!widget.isActive) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    if (!_locating) {
      unawaited(_loadNearby(_center));
    }
  }

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _startWithDefault();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          _startWithDefault();
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _userLocation = loc;
        _center = loc;
        _locating = false;
      });
      _loadNearby(loc);
    } catch (_) {
      _startWithDefault();
    }
  }

  void _startWithDefault() {
    if (!mounted) return;
    setState(() => _locating = false);
    _loadNearby(_center);
  }

  Future<void> _loadNearby(LatLng loc) async {
    final request = _nearbyRequest.next();
    setState(() => _loadingStations = true);
    try {
      final stations = await _repo.getBikeNearby(
        lat: loc.latitude,
        lon: loc.longitude,
        radius: _searchRadius,
      );
      if (!mounted || !_nearbyRequest.isCurrent(request)) return;
      setState(() {
        _stations = stations;
        _center = loc;
      });
      if (widget.isActive) {
        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (!mounted || !widget.isActive) {
            _refreshTimer?.cancel();
            _refreshTimer = null;
            return;
          }
          unawaited(_loadNearby(_center));
        });
      }
    } catch (_) {
    } finally {
      if (mounted && _nearbyRequest.isCurrent(request)) {
        setState(() => _loadingStations = false);
      }
    }
  }

  Color _availabilityColor(BikeStation station) {
    final total = station.availableRent + station.availableReturn;
    final ratio = total > 0 ? station.availableRent / total : 0.0;
    if (station.availableRent == 0) return Colors.red.shade600;
    if (ratio < 0.25) return Colors.orange.shade600;
    return Colors.green.shade600;
  }

  void _onMapMoved() {
    final c = _mapController.camera.center;
    if (Geolocator.distanceBetween(
          _center.latitude,
          _center.longitude,
          c.latitude,
          c.longitude,
        ) >
        800) {
      _mapMoveDebouncer.schedule(() {
        if (!mounted) {
          return;
        }
        final center = _mapController.camera.center;
        if (Geolocator.distanceBetween(
              _center.latitude,
              _center.longitude,
              center.latitude,
              center.longitude,
            ) >
            800) {
          unawaited(_loadNearby(center));
        }
      });
    }
  }

  void _onGoogleCameraMove(gmaps.CameraPosition position) {
    _googleCameraCenter = fromGoogleLatLng(position.target);
    _googleCameraZoom = position.zoom;
  }

  void _onGoogleMapIdle() {
    if (Geolocator.distanceBetween(
          _center.latitude,
          _center.longitude,
          _googleCameraCenter.latitude,
          _googleCameraCenter.longitude,
        ) >
        800) {
      _loadNearby(_googleCameraCenter);
    }
  }

  void _selectStation(BikeStation station) {
    final point = _stationPointIfValid(station);
    setState(() => _selectedStation = station);
    if (point == null) {
      if (!_usesSplitLayout) {
        _showStationDetail(station);
      }
      return;
    }
    if (_useGoogleMapsPointProvider) {
      _googleCameraCenter = point;
      _googleMapController?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(
          toGoogleLatLng(point),
          _googleCameraZoom,
        ),
      );
    } else {
      _animateOsmCameraTo(point, _mapController.camera.zoom);
    }
    if (!_usesSplitLayout) {
      _showStationDetail(station);
    }
  }

  void _recenterToUser() {
    if (_userLocation != null) {
      if (_useGoogleMapsPointProvider) {
        _googleCameraCenter = _userLocation!;
        _googleCameraZoom = _defaultZoom;
        _googleMapController?.animateCamera(
          gmaps.CameraUpdate.newLatLngZoom(
            toGoogleLatLng(_userLocation!),
            _defaultZoom,
          ),
        );
      } else {
        _animateOsmCameraTo(_userLocation!, _defaultZoom);
      }
      _loadNearby(_userLocation!);
    }
  }

  void _animateOsmCameraTo(LatLng target, double targetZoom) {
    try {
      final camera = _mapController.camera;
      _osmCameraStart = camera.center;
      _osmCameraTarget = target;
      _osmCameraStartZoom = camera.zoom;
      _osmCameraTargetZoom = targetZoom;
      _osmCameraAnimation.forward(from: 0);
    } catch (_) {
      _mapController.move(target, targetZoom);
    }
  }

  void _animateOsmCamera() {
    final start = _osmCameraStart;
    final target = _osmCameraTarget;
    final startZoom = _osmCameraStartZoom;
    final targetZoom = _osmCameraTargetZoom;
    if (start == null ||
        target == null ||
        startZoom == null ||
        targetZoom == null) {
      return;
    }
    final progress = Curves.easeOutCubic.transform(_osmCameraAnimation.value);
    _mapController.move(
      LatLng(
        ui.lerpDouble(start.latitude, target.latitude, progress)!,
        ui.lerpDouble(start.longitude, target.longitude, progress)!,
      ),
      ui.lerpDouble(startZoom, targetZoom, progress)!,
    );
  }

  void _showNearbyStationsSheet() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 0.85,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('附近站點', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        '${_stations.length} 站',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _stations.isEmpty
                      ? Center(
                          child: Text(
                            '附近沒有站點',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          itemCount: _stations.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final station = _stations[index];
                            final color = _availabilityColor(station);
                            return ListTile(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _selectStation(station);
                              },
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: color,
                                radius: 18,
                                child: Text(
                                  '${station.availableRent}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              title: Text(
                                station.name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                _bikeAvailabilitySummary(station),
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: station.distanceMeters != null
                                  ? Text(
                                      _formatDist(
                                        station.distanceMeters!.toDouble(),
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    )
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showStationDetail(BikeStation station) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildStationDetailContent(theme, station),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStationDetailContent(ThemeData theme, BikeStation station) {
    final color = _availabilityColor(station);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color,
              radius: 24,
              child: Text(
                '${station.availableRent}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (station.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      station.address,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.pedal_bike_rounded,
                  color: Colors.green.shade600,
                  label: '一般車',
                  value: '${station.availableRentGeneral}',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.electric_bike_rounded,
                  color: Colors.orange.shade700,
                  label: '2.0E 電輔',
                  value: '${station.availableRentElectric}',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.local_parking_rounded,
                  color: Colors.blue.shade600,
                  label: '可還',
                  value: '${station.availableReturn}',
                ),
              ),
            ],
          ),
        ),
        if (station.distanceMeters != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.near_me_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '距離 ${_formatDist(station.distanceMeters!.toDouble())}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSplitStationSidebar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _selectedStation == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '站點資訊',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '按一下左側站點或地圖上的標記後，這裡就會顯示可借、可還與距離資訊。',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              avatar: const Icon(Icons.pedal_bike_rounded),
                              label: Text('附近 ${_stations.length} 站'),
                            ),
                            if (_userLocation != null)
                              const Chip(
                                avatar: Icon(Icons.my_location_rounded),
                                label: Text('已取得目前位置'),
                              ),
                          ],
                        ),
                      ],
                    )
                  : _buildStationDetailContent(theme, _selectedStation!),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '附近站點',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          '${_stations.length} 站',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _stations.isEmpty
                        ? Center(
                            child: Text(
                              '附近沒有站點',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: _stations.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final station = _stations[index];
                              final color = _availabilityColor(station);
                              final selected =
                                  _selectedStation?.name == station.name;
                              return ListTile(
                                selected: selected,
                                selectedTileColor: theme
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.28),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                onTap: () => _selectStation(station),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: color,
                                  radius: 18,
                                  child: Text(
                                    '${station.availableRent}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  station.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _bikeAvailabilitySummary(station),
                                  style: theme.textTheme.bodySmall,
                                ),
                                trailing: station.distanceMeters != null
                                    ? Text(
                                        _formatDist(
                                          station.distanceMeters!.toDouble(),
                                        ),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      )
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapContent({required bool useGoogleMapsPointProvider}) {
    final theme = Theme.of(context);
    if (useGoogleMapsPointProvider) {
      _ensureGoogleStationIcons();
      _ensureGoogleUserLocationIcon();
    }
    return Stack(
      children: [
        if (useGoogleMapsPointProvider)
          gmaps.GoogleMap(
            initialCameraPosition: gmaps.CameraPosition(
              target: toGoogleLatLng(_center),
              zoom: _defaultZoom,
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
            markers: _buildGoogleMarkers(theme),
            onMapCreated: (controller) {
              _googleMapController = controller;
              _googleCameraCenter = _center;
              _googleCameraZoom = _defaultZoom;
            },
            onCameraMove: _onGoogleCameraMove,
            onCameraIdle: _onGoogleMapIdle,
          )
        else
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _defaultZoom,
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  _onMapMoved();
                }
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
              if (_userLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 6,
                              color: Colors.black.withValues(alpha: 0.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: _stations
                    .map((station) {
                      final point = _stationPointIfValid(station);
                      if (point == null) {
                        return null;
                      }
                      final color = _availabilityColor(station);
                      final selected = _selectedStation?.name == station.name;
                      return Marker(
                        point: point,
                        width: selected ? 44 : 36,
                        height: selected ? 44 : 36,
                        child: GestureDetector(
                          onTap: () => _selectStation(station),
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? Colors.white : Colors.white70,
                                width: selected ? 3 : 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: selected ? 8 : 4,
                                  color: Colors.black.withValues(alpha: 0.3),
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Center(
                                  child: Text(
                                    '${station.availableRent}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (station.availableRentElectric > 0)
                                  Positioned(
                                    top: -3,
                                    right: -3,
                                    child: _ElectricBikeMapBadge(
                                      size: selected ? 17 : 15,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    })
                    .whereType<Marker>()
                    .toList(growable: false),
              ),
            ],
          ),
        if (_loadingStations)
          const Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
        if (_userLocation != null)
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: _recenterToUser,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),
      ],
    );
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
          width: _GoogleYouBikeUserLocationIcon.baseLogicalSize,
          height: _GoogleYouBikeUserLocationIcon.baseLogicalSize,
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

  void _ensureGoogleStationIcons() {
    if (_stations.isEmpty) {
      return;
    }

    final pixelRatio = MediaQuery.of(
      context,
    ).devicePixelRatio.clamp(1.0, 3.0).toDouble();
    final requests = <_GoogleYouBikeMarkerRequest>[];

    for (final station in _stations) {
      if (_stationPointIfValid(station) == null) {
        continue;
      }
      final selected =
          _selectedStation?.stationUid == station.stationUid &&
          _selectedStation?.stationId == station.stationId;
      for (final markerSelected in <bool>[false, selected]) {
        final request = _GoogleYouBikeMarkerRequest(
          key: _googleStationIconKey(
            countLabel: _bikeCountLabel(station),
            color: _availabilityColor(station),
            hasElectric: station.availableRentElectric > 0,
            selected: markerSelected,
            pixelRatio: pixelRatio,
          ),
          countLabel: _bikeCountLabel(station),
          color: _availabilityColor(station),
          hasElectric: station.availableRentElectric > 0,
          selected: markerSelected,
          pixelRatio: pixelRatio,
        );
        if (_googleStationIcons.containsKey(request.key) ||
            _pendingGoogleStationIconKeys.contains(request.key)) {
          continue;
        }
        _pendingGoogleStationIconKeys.add(request.key);
        requests.add(request);
      }
    }

    if (requests.isNotEmpty) {
      unawaited(_generateGoogleStationIcons(requests));
    }
  }

  String _googleStationIconKey({
    required String countLabel,
    required Color color,
    required bool hasElectric,
    required bool selected,
    required double pixelRatio,
  }) {
    return [
      countLabel,
      color.toARGB32().toRadixString(16),
      hasElectric ? 'electric' : 'standard',
      selected ? 'selected' : 'normal',
      pixelRatio.toStringAsFixed(2),
    ].join('|');
  }

  String _bikeCountLabel(BikeStation station) {
    if (station.availableRent > 99) {
      return '99+';
    }
    return '${station.availableRent}';
  }

  Future<void> _generateGoogleStationIcons(
    List<_GoogleYouBikeMarkerRequest> requests,
  ) async {
    final generated = <String, gmaps.BitmapDescriptor>{};
    try {
      for (final request in requests) {
        final bytes = await _drawGoogleStationIcon(request);
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
            _pendingGoogleStationIconKeys.remove(request.key);
          }
          _googleStationIcons.addAll(generated);
        });
      }
    }
  }

  Future<Uint8List> _drawGoogleUserLocationIcon(double pixelRatio) async {
    final request = _GoogleYouBikeUserLocationIcon(pixelRatio: pixelRatio);
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

  Future<Uint8List> _drawGoogleStationIcon(
    _GoogleYouBikeMarkerRequest request,
  ) async {
    final pixelSize = (request.logicalSize * request.pixelRatio).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(request.pixelRatio, request.pixelRatio);
    final center = ui.Offset(request.logicalSize / 2, request.logicalSize / 2);

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
        ..color = request.selected ? Colors.white : Colors.white70,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: request.countLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: request.fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: request.logicalSize - 8);
    textPainter.paint(
      canvas,
      center - ui.Offset(textPainter.width / 2, textPainter.height / 2),
    );

    if (request.hasElectric) {
      final badgeCenter = ui.Offset(request.logicalSize - 8, 8);
      canvas.drawCircle(
        badgeCenter,
        7,
        ui.Paint()..color = const Color(0xFF172033),
      );
      canvas.drawCircle(
        badgeCenter,
        7,
        ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white,
      );
      final bolt = ui.Path()
        ..moveTo(badgeCenter.dx - 1, badgeCenter.dy - 5)
        ..lineTo(badgeCenter.dx - 5, badgeCenter.dy + 1)
        ..lineTo(badgeCenter.dx - 1, badgeCenter.dy + 1)
        ..lineTo(badgeCenter.dx - 3, badgeCenter.dy + 6)
        ..lineTo(badgeCenter.dx + 5, badgeCenter.dy - 2)
        ..lineTo(badgeCenter.dx + 1, badgeCenter.dy - 2)
        ..close();
      canvas.drawPath(bolt, ui.Paint()..color = const Color(0xFFFFD54F));
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pixelSize, pixelSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  Set<gmaps.Marker> _buildGoogleMarkers(ThemeData theme) {
    final markers = <gmaps.Marker>{};
    final userLocation = _userLocation;
    if (userLocation != null) {
      final userIcon = _googleUserLocationIcon;
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('user-location'),
          position: toGoogleLatLng(userLocation),
          anchor: userIcon == null
              ? const Offset(0.5, 1)
              : const Offset(0.5, 0.5),
          icon:
              userIcon ??
              gmaps.BitmapDescriptor.defaultMarkerWithHue(
                gmaps.BitmapDescriptor.hueAzure,
              ),
          zIndexInt: 3,
        ),
      );
    }

    for (final station in _stations) {
      final point = _stationPointIfValid(station);
      if (point == null) {
        continue;
      }
      final color = _availabilityColor(station);
      final selected =
          _selectedStation?.stationUid == station.stationUid &&
          _selectedStation?.stationId == station.stationId;
      final iconKey = _googleStationIconKey(
        countLabel: _bikeCountLabel(station),
        color: color,
        hasElectric: station.availableRentElectric > 0,
        selected: selected,
        pixelRatio: MediaQuery.of(
          context,
        ).devicePixelRatio.clamp(1.0, 3.0).toDouble(),
      );
      final markerIcon = _googleStationIcons[iconKey];
      final id = station.stationUid.isNotEmpty
          ? station.stationUid
          : '${station.stationId}:${station.lat}:${station.lon}';
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('bike:$id'),
          position: toGoogleLatLng(point),
          anchor: markerIcon == null
              ? const Offset(0.5, 1)
              : const Offset(0.5, 0.5),
          icon:
              markerIcon ??
              gmaps.BitmapDescriptor.defaultMarkerWithHue(
                googleMarkerHueForColor(color),
              ),
          infoWindow: gmaps.InfoWindow(
            title: station.name,
            snippet: station.address.isEmpty ? null : station.address,
          ),
          zIndexInt: selected ? 2 : 1,
          onTap: () => _selectStation(station),
        ),
      );
    }
    return markers;
  }

  bool _isValidCoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;
  }

  LatLng? _stationPointIfValid(BikeStation station) {
    if (!_isValidCoordinate(station.lat, station.lon)) {
      return null;
    }
    return LatLng(station.lat, station.lon);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useGoogleMapsPointProvider = useGoogleMapsProviderFor(
      AppControllerScope.of(context).settings.mobileMapProvider,
    );
    final hasBackgroundImage = hasBackgroundImageForPage(
      AppControllerScope.of(context).settings,
      pageKey: 'bus',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplitLayout = constraints.maxWidth >= _splitLayoutBreakpoint;
        _usesSplitLayout = useSplitLayout;
        return Scaffold(
          backgroundColor: hasBackgroundImage ? Colors.transparent : null,
          appBar: AppBar(
            title: const Text('YABike'),
            automaticallyImplyLeading: false,
            actions: [
              if (!useSplitLayout)
                IconButton(
                  tooltip: '附近站點',
                  onPressed: _showNearbyStationsSheet,
                  icon: Badge(
                    isLabelVisible: _stations.isNotEmpty,
                    label: Text('${_stations.length}'),
                    child: const Icon(Icons.list_alt_rounded),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: _locating
                    ? const Center(child: CircularProgressIndicator())
                    : useSplitLayout
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 380,
                            child: _buildSplitStationSidebar(theme),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          Expanded(
                            child: _buildMapContent(
                              useGoogleMapsPointProvider:
                                  useGoogleMapsPointProvider,
                            ),
                          ),
                        ],
                      )
                    : _buildMapContent(
                        useGoogleMapsPointProvider: useGoogleMapsPointProvider,
                      ),
              ),
              if (widget.showAdBanner) const AdBannerWidget(),
            ],
          ),
        );
      },
    );
  }

  String _formatDist(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _bikeAvailabilitySummary(BikeStation station) {
    return '一般 ${station.availableRentGeneral} · '
        '2.0E ${station.availableRentElectric} · '
        '可還 ${station.availableReturn}';
  }
}

class _GoogleYouBikeMarkerRequest {
  const _GoogleYouBikeMarkerRequest({
    required this.key,
    required this.countLabel,
    required this.color,
    required this.hasElectric,
    required this.selected,
    required this.pixelRatio,
  });

  final String key;
  final String countLabel;
  final Color color;
  final bool hasElectric;
  final bool selected;
  final double pixelRatio;

  double get logicalSize => selected ? 44 : 36;

  double get radius => selected ? 19 : 16;

  double get borderWidth => selected ? 3 : 2;

  double get fontSize {
    if (countLabel.length >= 3) {
      return selected ? 10 : 9;
    }
    return selected ? 12 : 11;
  }
}

class _GoogleYouBikeUserLocationIcon {
  const _GoogleYouBikeUserLocationIcon({required this.pixelRatio});

  static const double baseLogicalSize = 28;

  final double pixelRatio;

  double get logicalSize => baseLogicalSize;

  double get outerRadius => 12;

  double get innerRadius => 8.6;
}

class _ElectricBikeMapBadge extends StatelessWidget {
  const _ElectricBikeMapBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Icon(
        Icons.bolt_rounded,
        size: size - 3,
        color: const Color(0xFFFFD54F),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
