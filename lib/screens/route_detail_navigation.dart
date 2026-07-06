import 'package:flutter/material.dart';

import '../core/app_routes.dart';
import '../core/models.dart';
import 'route_detail_screen.dart';

Route<void> buildRouteDetailRoute({
  required int routeKey,
  required BusProvider provider,
  String? routeIdHint,
  String? routeNameHint,
  int? initialPathId,
  int? initialStopId,
  int? initialDestinationPathId,
  int? initialDestinationStopId,
  bool suppressAutoDestinationSelection = false,
}) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(
      name: AppRoutes.routeDetailPath(
        provider: provider,
        routeKey: routeKey,
        routeId: routeIdHint,
        pathId: initialPathId,
        stopId: initialStopId,
        destinationPathId: initialDestinationPathId,
        destinationStopId: initialDestinationStopId,
      ),
    ),
    builder: (_) => RouteDetailScreen(
      routeKey: routeKey,
      provider: provider,
      routeIdHint: routeIdHint,
      routeNameHint: routeNameHint,
      initialPathId: initialPathId,
      initialStopId: initialStopId,
      initialDestinationPathId: initialDestinationPathId,
      initialDestinationStopId: initialDestinationStopId,
      suppressAutoDestinationSelection: suppressAutoDestinationSelection,
    ),
  );
}

/// Shows a one-off notice when [recordRouteSelection] auto-adds a
/// frequently-visited stop into the "常用" favorites group.
void showAutoFavoritedSnackBar(BuildContext context, FavoriteStop favorite) {
  final label = favorite.stopName?.trim().isNotEmpty == true
      ? favorite.stopName!.trim()
      : favorite.routeName?.trim().isNotEmpty == true
      ? favorite.routeName!.trim()
      : '這個站牌';
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('常搭這班車？已自動把「$label」加入常用最愛。')));
}

Future<void> openRouteDetailPage(
  BuildContext context, {
  required int routeKey,
  required BusProvider provider,
  String? routeIdHint,
  String? routeNameHint,
  int? initialPathId,
  int? initialStopId,
  int? initialDestinationPathId,
  int? initialDestinationStopId,
  bool suppressAutoDestinationSelection = false,
}) {
  return Navigator.of(context).push(
    buildRouteDetailRoute(
      routeKey: routeKey,
      provider: provider,
      routeIdHint: routeIdHint,
      routeNameHint: routeNameHint,
      initialPathId: initialPathId,
      initialStopId: initialStopId,
      initialDestinationPathId: initialDestinationPathId,
      initialDestinationStopId: initialDestinationStopId,
      suppressAutoDestinationSelection: suppressAutoDestinationSelection,
    ),
  );
}
