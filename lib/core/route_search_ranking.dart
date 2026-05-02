import 'models.dart';

typedef RouteSearchProviderPriority = int Function(BusProvider provider);

List<RouteSummary> sortRouteSummariesForQuery(
  Iterable<RouteSummary> routes, {
  required String query,
  RouteSearchProviderPriority? providerPriority,
}) {
  final sorted = routes.toList();
  sorted.sort(
    (left, right) => compareRouteSummarySearchPriority(
      left,
      right,
      query: query,
      providerPriority: providerPriority,
    ),
  );
  return sorted;
}

int compareRouteSummarySearchPriority(
  RouteSummary left,
  RouteSummary right, {
  required String query,
  RouteSearchProviderPriority? providerPriority,
}) {
  if (providerPriority != null) {
    final leftPriority = providerPriority(
      busProviderFromString(left.sourceProvider),
    );
    final rightPriority = providerPriority(
      busProviderFromString(right.sourceProvider),
    );
    if (leftPriority != rightPriority) {
      return leftPriority.compareTo(rightPriority);
    }
  }

  final normalizedQuery = _normalizeRouteSearchText(query);
  final leftRank = _RouteSearchRank.fromSummary(left, normalizedQuery);
  final rightRank = _RouteSearchRank.fromSummary(right, normalizedQuery);

  if (leftRank.matchTier != rightRank.matchTier) {
    return leftRank.matchTier.compareTo(rightRank.matchTier);
  }
  if (leftRank.lengthGap != rightRank.lengthGap) {
    return leftRank.lengthGap.compareTo(rightRank.lengthGap);
  }
  if (leftRank.nameLength != rightRank.nameLength) {
    return leftRank.nameLength.compareTo(rightRank.nameLength);
  }

  final routeNameCompare = leftRank.routeName.compareTo(rightRank.routeName);
  if (routeNameCompare != 0) {
    return routeNameCompare;
  }

  final routeIdCompare = leftRank.routeId.compareTo(rightRank.routeId);
  if (routeIdCompare != 0) {
    return routeIdCompare;
  }

  return leftRank.description.compareTo(rightRank.description);
}

class _RouteSearchRank {
  const _RouteSearchRank({
    required this.matchTier,
    required this.lengthGap,
    required this.nameLength,
    required this.routeName,
    required this.routeId,
    required this.description,
  });

  factory _RouteSearchRank.fromSummary(
    RouteSummary route,
    String normalizedQuery,
  ) {
    final routeName = _normalizeRouteSearchText(_displayRouteName(route));
    final routeId = _normalizeRouteSearchText(route.routeId);
    final description = _normalizeRouteSearchText(route.description);
    return _RouteSearchRank(
      matchTier: _matchTier(
        routeName,
        routeId,
        description,
        normalizedQuery,
      ),
      lengthGap: normalizedQuery.isEmpty
          ? 0
          : (routeName.length - normalizedQuery.length).abs(),
      nameLength: routeName.isEmpty ? 9999 : routeName.length,
      routeName: routeName,
      routeId: routeId,
      description: description,
    );
  }

  final int matchTier;
  final int lengthGap;
  final int nameLength;
  final String routeName;
  final String routeId;
  final String description;

  static int _matchTier(
    String routeName,
    String routeId,
    String description,
    String query,
  ) {
    if (query.isEmpty) {
      return 0;
    }
    if (routeName == query) {
      return 0;
    }
    if (routeName.startsWith(query)) {
      return 1;
    }
    if (routeName.contains(query)) {
      return 2;
    }
    if (routeId == query) {
      return 3;
    }
    if (routeId.contains(query)) {
      return 4;
    }
    if (description.contains(query)) {
      return 5;
    }
    return 6;
  }
}

String _displayRouteName(RouteSummary route) {
  final routeName = route.routeName.trim();
  if (routeName.isNotEmpty) {
    return routeName;
  }
  final officialRouteName = route.officialRouteName.trim();
  if (officialRouteName.isNotEmpty) {
    return officialRouteName;
  }
  return route.routeId.trim();
}

String _normalizeRouteSearchText(String value) {
  return value.trim().toLowerCase();
}