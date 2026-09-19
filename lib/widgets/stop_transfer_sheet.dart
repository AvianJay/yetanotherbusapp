import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/models.dart';
import '../core/route_direction_label.dart';
import '../core/transit_repository.dart';
import '../core/transfer_options.dart';

class StopTransferSheet extends StatefulWidget {
  const StopTransferSheet({
    required this.controller,
    required this.provider,
    required this.currentRouteId,
    required this.stop,
    super.key,
  });

  final AppController controller;
  final BusProvider provider;
  final String currentRouteId;
  final StopInfo stop;

  @override
  State<StopTransferSheet> createState() => _StopTransferSheetState();
}

class _StopTransferSheetState extends State<StopTransferSheet> {
  List<NearbyTransferStopGroup> _busGroups = const [];
  List<BikeStation> _bikeStations = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final stop = widget.stop;
    if (stop.lat == 0 && stop.lon == 0) {
      setState(() {
        _loading = false;
        _error = '這個站牌沒有座標資料，無法尋找附近轉乘。';
      });
      return;
    }

    try {
      final nearby = await widget.controller.getNearbyStops(
        provider: widget.provider,
        latitude: stop.lat,
        longitude: stop.lon,
        radiusMeters: 250,
        limit: 80,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _busGroups = groupNearbyTransferStops(
          nearby
              .where((result) => result.route.routeId != widget.currentRouteId)
              .toList(growable: false),
        );
      });
    } catch (_) {
      // The sheet can still show bike transfers when a city database is absent.
    }

    try {
      final bikes = await TransitRepository.shared.getBikeNearby(
        lat: stop.lat,
        lon: stop.lon,
        radius: 300,
      );
      if (!mounted) {
        return;
      }
      setState(() => _bikeStations = bikes);
    } catch (_) {
      // YouBike is optional for this view.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (_error case final error?) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error),
            ),
          );
        }
        if (_busGroups.isEmpty && _bikeStations.isEmpty) {
          return const Center(child: Text('這個站牌附近暫時沒有可顯示的轉乘方式。'));
        }
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text('附近轉乘', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.stop.stopName}・步行 250 公尺內的公車與 300 公尺內的 YouBike',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_busGroups.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('公車', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final group in _busGroups)
                Card(
                  child: ExpansionTile(
                    title: Text(group.stopName),
                    subtitle: Text(
                      '${formatDistance(group.distanceMeters)}・${group.routes.length} 條路線',
                    ),
                    children: [
                      for (final row in labelNearbyRouteDirections(
                        group.routes,
                      ))
                        ListTile(
                          leading: const Icon(Icons.directions_bus_rounded),
                          title: Text(row.result.route.routeName),
                          subtitle: Text(row.directionLabel),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(row.result),
                        ),
                    ],
                  ),
                ),
            ],
            if (_bikeStations.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('YouBike', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final station in _bikeStations)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.pedal_bike_rounded),
                    title: Text(station.name),
                    subtitle: Text(
                      '${station.distanceMeters == null ? '' : '${formatDistance(station.distanceMeters!.toDouble())}・'}可借 ${station.availableRent}・可還 ${station.availableReturn}',
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
