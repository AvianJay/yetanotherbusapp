import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class TransitMapPoint {
  const TransitMapPoint({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.subtitle,
    this.badge,
    this.color,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final String? subtitle;
  final String? badge;
  final Color? color;

  bool get hasValidLocation =>
      latitude.isFinite &&
      longitude.isFinite &&
      (latitude != 0 || longitude != 0) &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  LatLng get latLng => LatLng(latitude, longitude);
}

class TransitStationMap extends StatefulWidget {
  const TransitStationMap({
    required this.points,
    this.selectedPointId,
    this.onPointSelected,
    this.height = 320,
    this.emptyLabel = '目前沒有可顯示的站點位置。',
    super.key,
  });

  final List<TransitMapPoint> points;
  final String? selectedPointId;
  final ValueChanged<TransitMapPoint>? onPointSelected;
  final double height;
  final String emptyLabel;

  @override
  State<TransitStationMap> createState() => _TransitStationMapState();
}

class _TransitStationMapState extends State<TransitStationMap> {
  final MapController _mapController = MapController();

  List<TransitMapPoint> get _validPoints => widget.points
      .where((point) => point.hasValidLocation)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _fitCamera();
  }

  @override
  void didUpdateWidget(covariant TransitStationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points ||
        oldWidget.selectedPointId != widget.selectedPointId) {
      _fitCamera();
    }
  }

  void _fitCamera() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _validPoints.isEmpty) {
        return;
      }
      try {
        final selectedPoint = _selectedPoint;
        if (selectedPoint != null) {
          _mapController.move(selectedPoint.latLng, 14.5);
          return;
        }
        if (_validPoints.length == 1) {
          _mapController.move(_validPoints.first.latLng, 14.5);
          return;
        }
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(
              _validPoints
                  .map((point) => point.latLng)
                  .where(
                    (p) => p.latitude.abs() <= 90 && p.longitude.abs() <= 180,
                  )
                  .toList(growable: false),
            ),
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
          ),
        );
      } catch (_) {
        // Ignore early controller lifecycle fit failures.
      }
    });
  }

  TransitMapPoint? get _selectedPoint {
    final selectedPointId = widget.selectedPointId;
    if (selectedPointId == null) {
      return null;
    }
    for (final point in _validPoints) {
      if (point.id == selectedPointId) {
        return point;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_validPoints.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            widget.emptyLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(23.7, 121.0),
                initialZoom: 7.2,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'tw.avianjay.taiwanbus.flutter',
                ),
                MarkerLayer(
                  markers: _validPoints
                      .map((point) {
                        final selected = point.id == widget.selectedPointId;
                        return Marker(
                          point: point.latLng,
                          width: selected ? 160 : 148,
                          height: selected ? 70 : 62,
                          child: GestureDetector(
                            onTap: () => widget.onPointSelected?.call(point),
                            child: _TransitPointMarker(
                              point: point,
                              selected: selected,
                              labelMaxWidth: selected ? 104 : 92,
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ],
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton.tonalIcon(
                onPressed: _fitCamera,
                icon: const Icon(Icons.center_focus_strong_rounded),
                label: const Text('置中'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitPointMarker extends StatelessWidget {
  const _TransitPointMarker({
    required this.point,
    required this.selected,
    required this.labelMaxWidth,
  });

  final TransitMapPoint point;
  final bool selected;
  final double labelMaxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerColor = point.color ?? theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(
              alpha: selected ? 0.96 : 0.9,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? markerColor : theme.colorScheme.outlineVariant,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.18 : 0.1),
                blurRadius: selected ? 10 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: selected ? 12 : 10,
                height: selected ? 12 : 10,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMaxWidth),
                child: Text(
                  point.badge?.isNotEmpty == true
                      ? '${point.badge} ${point.label}'
                      : point.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(width: 2, height: 10, color: markerColor),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: markerColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ],
    );
  }
}
