import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/transit_repository.dart';
import '../widgets/background_image_wrapper.dart';
import '../widgets/transit_drawer.dart';

class YouBikeScreen extends StatefulWidget {
  const YouBikeScreen({required this.onModeChanged, super.key});

  final ValueChanged<TransitMode> onModeChanged;

  @override
  State<YouBikeScreen> createState() => _YouBikeScreenState();
}

class _YouBikeScreenState extends State<YouBikeScreen> {
  final TransitRepository _repo = TransitRepository();
  final MapController _mapController = MapController();

  static const _defaultCenter = LatLng(25.033, 121.565); // Taipei
  static const _defaultZoom = 15.0;
  static const _searchRadius = 1500; // metres

  LatLng _center = _defaultCenter;
  LatLng? _userLocation;
  bool _locating = true;
  bool _loadingStations = false;
  List<BikeStation> _stations = [];
  BikeStation? _selectedStation;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
    setState(() => _loadingStations = true);
    try {
      final stations = await _repo.getBikeNearby(
        lat: loc.latitude,
        lon: loc.longitude,
        radius: _searchRadius,
      );
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _center = loc;
      });
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _loadNearby(_center);
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingStations = false);
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
            _center.latitude, _center.longitude, c.latitude, c.longitude) >
        800) {
      _loadNearby(c);
    }
  }

  void _selectStation(BikeStation station) {
    setState(() => _selectedStation = station);
    _mapController.move(
      LatLng(station.lat, station.lon),
      _mapController.camera.zoom,
    );
    _showStationDetail(station);
  }

  void _recenterToUser() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, _defaultZoom);
      _loadNearby(_userLocation!);
    }
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
                      Text('${_stations.length} 站',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _stations.isEmpty
                      ? Center(
                          child: Text(
                            '附近沒有站點',
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
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
                                  horizontal: 4, vertical: 2),
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
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '可借 ${station.availableRent}  可還 ${station.availableReturn}',
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: station.distanceMeters != null
                                  ? Text(
                                      _formatDist(
                                          station.distanceMeters!.toDouble()),
                                      style: theme.textTheme.bodySmall?.copyWith(
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
    final color = _availabilityColor(station);
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
              // Handle
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
              // Station name and availability badge
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
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
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
              // Availability info
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
                        label: '可借',
                        value: '${station.availableRent}',
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
                    Container(
                      width: 1,
                      height: 40,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: _StatItem(
                        icon: Icons.grid_view_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                        label: '當前總計',
                        value: '${station.availableRent + station.availableReturn}',
                      ),
                    ),
                  ],
                ),
              ),
              if (station.distanceMeters != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.near_me_outlined,
                        size: 18, color: theme.colorScheme.primary),
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
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YABike'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
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
      drawer: TransitDrawer(
        currentMode: TransitMode.youbike,
        onModeChanged: widget.onModeChanged,
      ),
      body: BackgroundImageWrapper(
        pageKey: 'youbike',
        child: _locating
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Map
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
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'tw.avianjay.taiwanbus.flutter',
                    ),
                    // User location
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
                                border:
                                    Border.all(color: Colors.white, width: 3),
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
                    // Bike stations
                    MarkerLayer(
                      markers: _stations.map((station) {
                        final color = _availabilityColor(station);
                        final selected = _selectedStation?.name == station.name;
                        return Marker(
                          point: LatLng(station.lat, station.lon),
                          width: selected ? 44 : 36,
                          height: selected ? 44 : 36,
                          child: GestureDetector(
                            onTap: () => _selectStation(station),
                            child: Container(
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      selected ? Colors.white : Colors.white70,
                                  width: selected ? 3 : 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: selected ? 8 : 4,
                                    color: Colors.black.withValues(alpha: 0.3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  '${station.availableRent}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),

                // Loading indicator
                if (_loadingStations)
                  const Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),

                // Recenter FAB
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
            ),
      ),
    );
  }

  String _formatDist(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
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
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
