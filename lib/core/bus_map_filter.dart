import 'models.dart';

/// Filtering for the 全公車地圖 screen, kept out of the widget so it can be
/// reasoned about (and tested) without a map on screen.

/// Every routeid the user has favourited in [provider].
///
/// Both favourite kinds count: a favourited route obviously, but also a
/// favourited boarding stop, since the route it belongs to is one the rider
/// cares about. Stops saved before routeids were stored have none, and are
/// simply skipped.
Set<String> favoriteRouteIdsFor(
  Map<String, List<FavoriteItem>> groups,
  BusProvider provider,
) {
  final routeIds = <String>{};
  for (final items in groups.values) {
    for (final item in items) {
      if (item.provider != provider) {
        continue;
      }
      if (item is FavoriteRoute) {
        final routeId = item.routeId.trim();
        if (routeId.isNotEmpty) {
          routeIds.add(routeId);
        }
      } else if (item is FavoriteStop) {
        final routeId = item.routeId?.trim();
        if (routeId != null && routeId.isNotEmpty) {
          routeIds.add(routeId);
        }
      }
    }
  }
  return routeIds;
}

/// Fold full-width digits and letters down so a query typed on a Chinese
/// keyboard still matches a route named with ASCII digits.
String normalizeRouteQuery(String value) {
  final buffer = StringBuffer();
  for (final rune in value.trim().toLowerCase().runes) {
    // Full-width ASCII occupies U+FF01..U+FF5E, a fixed offset from ASCII.
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().trim();
}

/// Whether [bus] should be drawn, given the current filters.
///
/// Favourite matching happens at family level for buses the feed could not pin
/// to one route: a rider who favourited 民權幹線去程半 still wants to see the
/// 民權幹線 buses, and the server cannot tell which variant each one is.
bool busMatchesFilters(
  CityBusSnapshot snapshot,
  CityBus bus, {
  required bool favoritesOnly,
  required Set<String> favoriteRouteIds,
  required String normalizedQuery,
}) {
  if (favoritesOnly && !_isFavorite(snapshot, bus, favoriteRouteIds)) {
    return false;
  }
  if (normalizedQuery.isEmpty) {
    return true;
  }
  final name = normalizeRouteQuery(snapshot.displayNameFor(bus));
  if (name.contains(normalizedQuery)) {
    return true;
  }
  return normalizeRouteQuery(bus.bus.id).contains(normalizedQuery);
}

bool _isFavorite(
  CityBusSnapshot snapshot,
  CityBus bus,
  Set<String> favoriteRouteIds,
) {
  if (favoriteRouteIds.isEmpty) {
    return false;
  }
  final routeId = bus.routeId;
  if (routeId != null) {
    return favoriteRouteIds.contains(routeId);
  }
  final family = snapshot.families[bus.routeUid];
  if (family == null) {
    return false;
  }
  return family.routeIds.any(favoriteRouteIds.contains);
}

/// The buses to draw, filtered and then trimmed to what the view can carry.
///
/// [visible] decides what is on screen; [limit] caps how many of those are
/// drawn at once. When the cap bites, the selected route comes first (the user
/// is looking at it), then favourites, then whatever is nearest the middle of
/// the screen, so the markers that disappear are the ones least likely to be
/// missed.
List<CityBus> visibleBusesFor(
  CityBusSnapshot snapshot, {
  required bool favoritesOnly,
  required Set<String> favoriteRouteIds,
  required String query,
  required bool Function(CityBus bus) visible,
  String? selectedGroupKey,
  int? limit,
  double? centerLat,
  double? centerLon,
}) {
  final normalizedQuery = normalizeRouteQuery(query);
  final matches = <CityBus>[];
  for (final bus in snapshot.buses) {
    if (!busMatchesFilters(
      snapshot,
      bus,
      favoritesOnly: favoritesOnly,
      favoriteRouteIds: favoriteRouteIds,
      normalizedQuery: normalizedQuery,
    )) {
      continue;
    }
    if (!visible(bus)) {
      continue;
    }
    matches.add(bus);
  }

  if (limit == null || matches.length <= limit) {
    return matches;
  }

  double rank(CityBus bus) {
    if (selectedGroupKey != null && bus.groupKey == selectedGroupKey) {
      return -2;
    }
    if (_isFavorite(snapshot, bus, favoriteRouteIds)) {
      return -1;
    }
    if (centerLat == null || centerLon == null) {
      return 0;
    }
    // Squared degrees is enough to order by; no need for real distance here.
    final dLat = bus.bus.lat - centerLat;
    final dLon = bus.bus.lon - centerLon;
    return dLat * dLat + dLon * dLon;
  }

  matches.sort((a, b) => rank(a).compareTo(rank(b)));
  return matches.sublist(0, limit);
}
