import 'models.dart';

class NearbyTransferStopGroup {
  const NearbyTransferStopGroup({
    required this.stopName,
    required this.distanceMeters,
    required this.routes,
  });

  final String stopName;
  final double distanceMeters;
  final List<NearbyStopResult> routes;
}

List<NearbyTransferStopGroup> groupNearbyTransferStops(
  List<NearbyStopResult> results,
) {
  final groups = <String, List<NearbyStopResult>>{};
  for (final result in results) {
    final stop = result.stop;
    final key =
        '${stop.stopName.trim()}:${stop.lat.toStringAsFixed(4)}:'
        '${stop.lon.toStringAsFixed(4)}';
    groups.putIfAbsent(key, () => <NearbyStopResult>[]).add(result);
  }

  final grouped = groups.values.map((routes) {
    routes.sort(
      (left, right) => left.route.routeName.compareTo(right.route.routeName),
    );
    return NearbyTransferStopGroup(
      stopName: routes.first.stop.stopName,
      distanceMeters: routes
          .map((result) => result.distanceMeters)
          .reduce((left, right) => left < right ? left : right),
      routes: List.unmodifiable(routes),
    );
  }).toList();
  grouped.sort(
    (left, right) => left.distanceMeters.compareTo(right.distanceMeters),
  );
  return grouped;
}
