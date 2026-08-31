import 'models.dart';

/// Identity of one route+direction entry in the related-stop-routes sheet.
///
/// TDX publishes a *different* StopID per route and direction at the same
/// physical stop — 捷運南屯站(文心路) is 21746 for 綠3, 21884 for 73, 24080 for
/// 302 — so the two sources that feed the sheet disagree about stop IDs by
/// construction:
///
/// * The server passby endpoint stamps every route it returns with the
///   *requested* StopID, because it resolved them all from that one ID.
/// * The local name-based lookup carries each route's *own* StopID.
///
/// `routeId` + `pathId` is therefore the only pair that names the same entry in
/// both, and both sources emit at most one result per pair.
String stopRouteMergeKey(StopRouteSearchResult result) =>
    '${result.route.routeId.trim()}:${result.matchedStop.pathId}';

/// Combines the server passby results with the local name-based lookup.
///
/// Neither source is complete on its own: passby only covers the routes sharing
/// the queried StopID (often just the route the user is already looking at),
/// while the local lookup finds every sibling StopID but carries no realtime
/// data. Merging keeps the ETA *and* the full route list.
///
/// Passby entries win on collision — they already hold this stop's ETA.
/// [passbyKeys] names them so callers can skip the realtime fetch for those and
/// only request live data for the locally-sourced remainder.
({List<StopRouteSearchResult> results, Set<String> passbyKeys})
mergeStopRouteResults({
  required List<StopRouteSearchResult> passby,
  required List<StopRouteSearchResult> local,
}) {
  final merged = <String, StopRouteSearchResult>{};
  final passbyKeys = <String>{};

  for (final result in passby) {
    final key = stopRouteMergeKey(result);
    passbyKeys.add(key);
    merged.putIfAbsent(key, () => result);
  }
  for (final result in local) {
    merged.putIfAbsent(stopRouteMergeKey(result), () => result);
  }

  return (
    results: merged.values.toList(growable: false),
    passbyKeys: passbyKeys,
  );
}
