import 'dart:math' as math;

import 'models.dart';

String routeFamilyName(String routeName) {
  final normalizedName = routeName.trim();
  final familyName = normalizedName.replaceFirst(RegExp(r'(?:延|跳蛙)+$'), '');
  return familyName.isEmpty ? normalizedName : familyName;
}

/// Whether two route-variant stops refer to the same side of a physical stop.
///
/// TDX commonly assigns different stop IDs to the same platform for separate
/// routes, so a matching nonempty raw ID is sufficient but not required.
/// Name and coordinates provide a conservative fallback for those cases.
bool routeFamilyStopsSharePhysicalSide(StopInfo first, StopInfo second) {
  final firstRawStopId = first.rawStopId?.trim();
  final secondRawStopId = second.rawStopId?.trim();
  if (firstRawStopId != null &&
      firstRawStopId.isNotEmpty &&
      firstRawStopId == secondRawStopId) {
    return true;
  }

  if (_normalizedStopName(first.stopName) !=
          _normalizedStopName(second.stopName) ||
      !_hasCoordinates(first) ||
      !_hasCoordinates(second)) {
    return false;
  }

  return _distanceMeters(first, second) <= 60;
}

/// Combines live data from route-family variants that serve one physical stop.
///
/// The selected route owns the stop identity. The earliest live ETA becomes
/// the shared badge value while vehicle and vehicle-specific ETA lists combine.
StopInfo mergeRouteFamilyStopLiveData(
  StopInfo baseStop,
  List<StopInfo> sharedStops,
) {
  final allStops = <StopInfo>[baseStop, ...sharedStops];
  final etaStops =
      allStops
          .where((stop) => effectiveStopEtaSeconds(stop) != null)
          .toList(growable: false)
        ..sort(
          (left, right) => effectiveStopEtaSeconds(
            left,
          )!.compareTo(effectiveStopEtaSeconds(right)!),
        );
  final primaryEtaStop = etaStops.isEmpty ? null : etaStops.first;
  final primaryMessageStop = allStops.firstWhere(
    (stop) => stop.msg?.trim().isNotEmpty == true,
    orElse: () => baseStop,
  );
  final busesById = <String, BusVehicle>{};
  final etasByKey = <String, StopEta>{};
  for (final stop in allStops) {
    for (final bus in stop.buses) {
      busesById.putIfAbsent(
        bus.id.trim().isEmpty ? '${bus.source}:${busesById.length}' : bus.id,
        () => bus,
      );
    }
    for (final eta in stop.etas) {
      final key =
          '${eta.vehicleId}:${eta.sec}:${eta.msg}:${eta.source}:${eta.estimated}';
      etasByKey.putIfAbsent(key, () => eta);
    }
  }

  return StopInfo(
    routeKey: baseStop.routeKey,
    pathId: baseStop.pathId,
    stopId: baseStop.stopId,
    rawStopId: baseStop.rawStopId,
    stopName: baseStop.stopName,
    sequence: baseStop.sequence,
    lon: baseStop.lon,
    lat: baseStop.lat,
    sec: primaryEtaStop?.sec,
    msg: primaryEtaStop == null ? primaryMessageStop.msg : null,
    t: primaryEtaStop?.t,
    buses: busesById.values.toList(growable: false),
    etas: etasByKey.values.toList(growable: false),
  );
}

String _normalizedStopName(String stopName) =>
    stopName.trim().replaceAll(RegExp(r'\s+'), '');

bool _hasCoordinates(StopInfo stop) => stop.lat != 0 || stop.lon != 0;

double _distanceMeters(StopInfo first, StopInfo second) {
  const earthRadiusMeters = 6378137.0;
  final latitudeDelta = _toRadians(second.lat - first.lat);
  final longitudeDelta = _toRadians(second.lon - first.lon);
  final a =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(_toRadians(first.lat)) *
          math.cos(_toRadians(second.lat)) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRadians(double degrees) => degrees * math.pi / 180;
