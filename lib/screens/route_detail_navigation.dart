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
