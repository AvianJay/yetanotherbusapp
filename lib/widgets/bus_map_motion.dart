import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/models.dart';
import 'bus_map_geometry.dart';

/// Where a bus *is* between two position reports.
///
/// TDX refreshes a vehicle every several seconds, so drawing raw fixes makes
/// buses teleport. A bus close enough to its route rides the line at its
/// reported speed; one too far off (a bad shape, a detour, a stale fix) is
/// dead-reckoned from its heading instead. Both blend toward each new sample
/// rather than snapping to it, which is what stops the jitter.
///
/// Lifted from `route_bus_map_sheet.dart` unchanged except for two things the
/// city-wide map needs: `now` and `refreshSeconds` are passed in rather than
/// read off widget state, and the geometry is optional so buses can still be
/// animated before (or without) a route line.

/// Within this distance of the line, a bus is drawn on it.
const double kBusSnapToRouteThresholdMeters = 180.0;

/// Beyond this, the bus is treated as off-route and dead-reckoned.
const double kBusOffRouteThresholdMeters = 320.0;

String _busIdKey(RouteRealtimeBus bus) => bus.id;

enum BusMotionMode { snappedToRoute, freeFloating }

class AnimatedBusState {
  const AnimatedBusState({
    required this.bus,
    required this.status,
    required this.mode,
    required this.routeDistanceAtSampleMeters,
    required this.sampledAt,
    required this.rawPoint,
    required this.speedMps,
    required this.azimuth,
    required this.distanceToRouteMeters,
  });

  final RouteRealtimeBus bus;
  final BusStatusDescriptor status;
  final BusMotionMode mode;
  final double? routeDistanceAtSampleMeters;
  final DateTime sampledAt;
  final LatLng rawPoint;
  final double speedMps;
  final double? azimuth;
  final double distanceToRouteMeters;

  LatLng positionAt(DateTime now, {RouteGeometry? geometry}) {
    if (geometry != null &&
        mode == BusMotionMode.snappedToRoute &&
        routeDistanceAtSampleMeters != null) {
      return geometry.pointAtDistance(
        distanceAlongRouteAt(now, geometry: geometry) ??
            routeDistanceAtSampleMeters!,
      );
    }
    return advanceOffRoutePoint(
      start: rawPoint,
      speedMps: speedMps,
      azimuth: azimuth,
      elapsedSeconds: _elapsedSeconds(now),
    );
  }

  double? distanceAlongRouteAt(DateTime now, {RouteGeometry? geometry}) {
    final baseDistance = routeDistanceAtSampleMeters;
    if (geometry == null ||
        mode != BusMotionMode.snappedToRoute ||
        baseDistance == null) {
      return null;
    }
    final advanceMeters = math.min(speedMps * _elapsedSeconds(now), 280.0);
    return (baseDistance + advanceMeters).clamp(
      0.0,
      geometry.totalLengthMeters,
    );
  }

  double _elapsedSeconds(DateTime now) {
    return math.max(0, now.difference(sampledAt).inMilliseconds / 1000.0);
  }
}

/// Fold a fresh batch of positions into the previous animation states.
///
/// [geometry] is the line the buses belong to; pass null when there is none to
/// snap to and every bus free-floats. [keyOf] decides how a bus is identified
/// across refreshes: the plate is enough on a single route, but a city-wide map
/// must qualify it, because one plate can serve two routes at once.
Map<String, AnimatedBusState> buildAnimatedBusStates(
  RouteGeometry? geometry,
  List<RouteRealtimeBus> buses,
  Map<String, AnimatedBusState> previousStates, {
  required DateTime now,
  required int refreshSeconds,
  String Function(RouteRealtimeBus bus) keyOf = _busIdKey,
}) {
  final nextStates = <String, AnimatedBusState>{};

  for (final bus in buses) {
    final rawPoint = toLatLngIfValid(bus.lat, bus.lon);
    if (rawPoint == null) {
      continue;
    }
    final key = keyOf(bus);
    final projection = geometry?.project(rawPoint);
    final previous = previousStates[key];
    final speedMps = (((bus.speedKph ?? 0) / 3.6).clamp(0, 36)).toDouble();
    final status = describeBusStatus(bus.statusCode);
    final sampleTime = effectiveBusSampleTime(
      bus.updatedAt,
      now,
      refreshSeconds: refreshSeconds,
    );
    final distanceToRoute =
        projection?.distanceToRouteMeters ?? double.infinity;

    if (geometry != null &&
        projection != null &&
        distanceToRoute <= kBusOffRouteThresholdMeters) {
      var baseDistance = projection.distanceAlongRouteMeters;
      final predictedPrevious = previous?.distanceAlongRouteAt(
        sampleTime,
        geometry: geometry,
      );
      if (predictedPrevious != null) {
        final delta = baseDistance - predictedPrevious;
        if (delta.abs() <= 180) {
          // Nudge toward the new fix instead of jumping, and lean against
          // going backwards: a bus that appears to reverse is nearly always a
          // noisy fix, not a bus reversing.
          final blendFactor = delta < 0 ? 0.18 : 0.35;
          baseDistance = predictedPrevious + delta * blendFactor;
        }
      }
      nextStates[key] = AnimatedBusState(
        bus: bus,
        status: status,
        mode: BusMotionMode.snappedToRoute,
        routeDistanceAtSampleMeters: baseDistance
            .clamp(0.0, geometry.totalLengthMeters)
            .toDouble(),
        sampledAt: sampleTime,
        rawPoint: rawPoint,
        speedMps: speedMps,
        azimuth: bus.azimuth,
        distanceToRouteMeters: distanceToRoute,
      );
      continue;
    }

    var basePoint = rawPoint;
    if (previous != null) {
      final predicted = previous.positionAt(sampleTime, geometry: geometry);
      final gap = distanceMetersBetween(predicted, rawPoint);
      if (gap <= kBusSnapToRouteThresholdMeters) {
        basePoint = lerpLatLng(predicted, rawPoint, 0.35);
      }
    }

    nextStates[key] = AnimatedBusState(
      bus: bus,
      status: status,
      mode: BusMotionMode.freeFloating,
      routeDistanceAtSampleMeters: null,
      sampledAt: sampleTime,
      rawPoint: basePoint,
      speedMps: speedMps,
      azimuth: bus.azimuth,
      distanceToRouteMeters: distanceToRoute,
    );
  }

  return nextStates;
}

/// When a reported position should be treated as having been taken.
///
/// A clock-skewed future timestamp would make a bus race ahead, and a very old
/// one would make it sprint to catch up, so both ends are clamped.
DateTime effectiveBusSampleTime(
  DateTime? updatedAt,
  DateTime now, {
  required int refreshSeconds,
}) {
  if (updatedAt == null) {
    return now;
  }
  if (updatedAt.isAfter(now)) {
    return now;
  }
  final oldestAllowed = now.subtract(
    Duration(seconds: math.max(refreshSeconds, 12)),
  );
  if (updatedAt.isBefore(oldestAllowed)) {
    return oldestAllowed;
  }
  return updatedAt;
}
