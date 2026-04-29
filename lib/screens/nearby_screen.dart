import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/models.dart';
import 'route_detail_screen.dart';
import 'settings_screen.dart';
import '../widgets/background_image_wrapper.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  bool _loading = true;
  String? _error;
  List<NearbyStopResult> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNearbyStops();
    });
  }

  Future<void> _loadNearbyStops() async {
    final controller = AppControllerScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw StateError('定位服務尚未開啟。');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('沒有取得定位權限。');
      }

      final position = await Geolocator.getCurrentPosition();
      final results = await controller.getNearbyStops(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('附近站牌'),
        actions: [
          IconButton(
            onPressed: _loadNearbyStops,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: BackgroundImageWrapper(
        pageKey: 'nearby',
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: _loadNearbyStops,
                            child: const Text('重試'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                            },
                            child: const Text('前往設定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : _results.isEmpty
            ? const Center(child: Text('附近沒有找到站牌。'))
            : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _results[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        formatDistance(item.distanceMeters),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    title: Text(item.stop.stopName),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${busProviderFromString(item.route.sourceProvider).label} · ${item.route.routeName}',
                      ),
                    ),
                    onTap: () async {
                      final routeProvider = busProviderFromString(
                        item.route.sourceProvider,
                      );
                      await controller.recordRouteSelection(
                        provider: routeProvider,
                        routeKey: item.route.routeKey,
                        routeName: item.route.routeName,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RouteDetailScreen(
                            routeKey: item.route.routeKey,
                            provider: routeProvider,
                            routeIdHint: item.route.routeId,
                            routeNameHint: item.route.routeName,
                            initialPathId: item.stop.pathId,
                            initialStopId: item.stop.stopId,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      ),
    );
  }
}
