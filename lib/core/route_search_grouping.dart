import 'models.dart';

class RouteSearchGroup {
  const RouteSearchGroup({required this.trunkName, required this.routes});

  final String trunkName;
  final List<RouteSummary> routes;
}

String routeFamilyName(String routeName) {
  final normalizedName = routeName.trim();
  final familyName = normalizedName.replaceFirst(RegExp(r'(?:延|跳蛙)+$'), '');
  return familyName.isEmpty ? normalizedName : familyName;
}

List<RouteSearchGroup> groupRouteSearchResults(List<RouteSummary> routes) {
  final groups = <String, List<RouteSummary>>{};
  final trunkNames = <String, String>{};
  for (final route in routes) {
    final resolvedTrunkName = routeFamilyName(route.routeName);
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
