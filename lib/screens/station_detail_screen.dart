import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../app/bus_app.dart';
import '../core/android_home_integration.dart';
import '../core/app_routes.dart';
import '../core/friendly_error.dart';
import '../core/models.dart';
import '../widgets/eta_badge.dart';

class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
    required this.provider,
    required this.stationId,
    this.stationName,
    super.key,
  });

  final BusProvider provider;
  final String stationId;
  final String? stationName;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  StationPassbyData? _station;
  String? _error;
  bool _loading = true;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _pinStationShortcut() async {
    final station = _station;
    final didPin = await AndroidHomeIntegration.pinFavoriteShortcut(
      favorite: FavoriteStation(
        provider: widget.provider,
        stationId: widget.stationId,
        stationName: station?.stationName ?? widget.stationName ?? '站牌',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(didPin ? '已送出站牌捷徑要求。' : '這台裝置不支援主畫面捷徑。')),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_station == null && _loading) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final station = await AppControllerScope.read(context).repository
          .getStationPassby(widget.stationId, provider: widget.provider);
      if (!mounted) return;
      setState(() {
        _station = station;
        _error = station == null ? '找不到這個站牌。' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final station = _station;
    return Scaffold(
      appBar: AppBar(
        title: Text(station?.stationName ?? widget.stationName ?? '站牌'),
        actions: [
          if (_isAndroid)
            IconButton(
              onPressed: () => unawaited(_pinStationShortcut()),
              tooltip: '將站牌新增到主畫面',
              icon: const Icon(Icons.add_to_home_screen_rounded),
            ),
          IconButton(
            onPressed: _loading ? null : () => unawaited(_load()),
            tooltip: '重新整理',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && station == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && station == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => unawaited(_load()),
                      child: const Text('重試'),
                    ),
                  ],
                ),
              ),
            )
          : _buildStation(station!),
    );
  }

  Widget _buildStation(StationPassbyData station) {
    final sides = station.sides;
    if (sides.isEmpty) {
      return const Center(child: Text('這個站牌目前沒有可顯示的側別。'));
    }
    return DefaultTabController(
      length: sides.length,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              isScrollable: sides.length > 3,
              tabs: [
                for (final side in sides)
                  Tab(
                    text: side.direction?.isNotEmpty == true
                        ? '${side.label} · ${side.direction}'
                        : '${side.label} 側',
                  ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: TabBarView(
              children: [for (final side in sides) _buildSide(side)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSide(StationSideData side) {
    if (side.routes.isEmpty) {
      return Center(child: Text('${side.label} 側目前沒有經過路線。'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: side.routes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final arrival = side.routes[index];
          final route = arrival.result.route;
          final stop = arrival.result.matchedStop;
          return Card(
            child: ListTile(
              leading: EtaBadge(
                stop: stop,
                alwaysShowSeconds: AppControllerScope.read(
                  context,
                ).settings.alwaysShowSeconds,
              ),
              title: Text(route.routeName),
              subtitle: Text(
                route.description.trim().isNotEmpty
                    ? route.description
                    : (side.direction ?? '${side.label} 側'),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.routeDetailPath(
                  provider: widget.provider,
                  routeKey: route.routeKey,
                  routeId: route.routeId,
                  pathId: stop.pathId,
                  stopId: stop.stopId,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
