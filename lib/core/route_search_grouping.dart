import 'models.dart';

class RouteSearchGroup {
  const RouteSearchGroup({required this.trunkName, required this.routes});

  final String trunkName;
  final List<RouteSummary> routes;
}

List<RouteSearchGroup> groupRouteSearchResults(List<RouteSummary> routes) {
  final groups = <String, List<RouteSummary>>{};
  final trunkNames = <String, String>{};
  for (final route in routes) {
    final routeName = route.routeName.trim();
    final trunkName = routeName.replaceFirst(RegExp(r'(?:延|跳蛙)+$'), '');
    final resolvedTrunkName = trunkName.isEmpty ? routeName : trunkName;
    final key = '${route.sourceProvider}:$resolvedTrunkName';
    groups.putIfAbsent(key, () => <RouteSummary>[]).add(route);
    trunkNames[key] = resolvedTrunkName;
  }
  return groups.entries
      .map(
        (entry) => RouteSearchGroup(
          trunkName: trunkNames[entry.key]!,
          routes: List.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
}
