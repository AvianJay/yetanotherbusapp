import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../core/models.dart';

/// Route geometry and the spherical maths the bus maps share.
///
/// Lifted verbatim out of `route_bus_map_sheet.dart` so the city-wide map can
/// snap buses to a line the same way the per-route sheet does. Behaviour is
/// unchanged; only the names became public.

bool isValidCoordinate(double latitude, double longitude) {
  return latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
}

bool isValidLatLng(LatLng point) {
  return isValidCoordinate(point.latitude, point.longitude);
}

LatLng? toLatLngIfValid(double latitude, double longitude) {
  if (!isValidCoordinate(latitude, longitude)) {
    return null;
  }
  return LatLng(latitude, longitude);
}

class RouteProjection {
  const RouteProjection({
    required this.snappedPoint,
    required this.distanceToRouteMeters,
    required this.distanceAlongRouteMeters,
  });

  final LatLng snappedPoint;
  final double distanceToRouteMeters;
  final double distanceAlongRouteMeters;
}

class _ProjectedSegmentPoint {
  const _ProjectedSegmentPoint({
    required this.projectedPoint,
    required this.segmentT,
  });

  final LatLng projectedPoint;
  final double segmentT;
}

_ProjectedSegmentPoint _projectOntoSegment(
  LatLng point,
  LatLng start,
  LatLng end,
) {
  final referenceLat = (start.latitude + end.latitude + point.latitude) / 3;
  final pointXy = _toMeters(point, referenceLat: referenceLat);
  final startXy = _toMeters(start, referenceLat: referenceLat);
  final endXy = _toMeters(end, referenceLat: referenceLat);
  final segmentDx = endXy.dx - startXy.dx;
  final segmentDy = endXy.dy - startXy.dy;
  final segmentLengthSquared = segmentDx * segmentDx + segmentDy * segmentDy;
  if (segmentLengthSquared == 0) {
    return _ProjectedSegmentPoint(projectedPoint: start, segmentT: 0);
  }

  final rawT =
      ((pointXy.dx - startXy.dx) * segmentDx +
          (pointXy.dy - startXy.dy) * segmentDy) /
      segmentLengthSquared;
  final t = rawT.clamp(0.0, 1.0);
  return _ProjectedSegmentPoint(
    projectedPoint: lerpLatLng(start, end, t),
    segmentT: t,
  );
}

LatLng advanceOffRoutePoint({
  required LatLng start,
  required double speedMps,
  required double? azimuth,
  required double elapsedSeconds,
}) {
  if (speedMps <= 0 || azimuth == null) {
    return start;
  }
  final distanceMeters = math.min(speedMps * elapsedSeconds, 240.0);
  final angularDistance = distanceMeters / 6378137.0;
  final bearing = azimuth * math.pi / 180;
  final lat1 = start.latitude * math.pi / 180;
  final lon1 = start.longitude * math.pi / 180;

  final sinLat1 = math.sin(lat1);
  final cosLat1 = math.cos(lat1);
  final sinAngular = math.sin(angularDistance);
  final cosAngular = math.cos(angularDistance);

  final lat2 = math.asin(
    sinLat1 * cosAngular + cosLat1 * sinAngular * math.cos(bearing),
  );
  final lon2 =
      lon1 +
      math.atan2(
        math.sin(bearing) * sinAngular * cosLat1,
        cosAngular - sinLat1 * math.sin(lat2),
      );

  return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
}

double distanceMetersBetween(LatLng left, LatLng right) {
  const earthRadius = 6378137.0;
  final dLat = _degreesToRadians(right.latitude - left.latitude);
  final dLon = _degreesToRadians(right.longitude - left.longitude);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(left.latitude)) *
          math.cos(_degreesToRadians(right.latitude)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double bearingBetween(LatLng start, LatLng end) {
  final lat1 = _degreesToRadians(start.latitude);
  final lat2 = _degreesToRadians(end.latitude);
  final dLon = _degreesToRadians(end.longitude - start.longitude);
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

({double dx, double dy}) _toMeters(
  LatLng point, {
  required double referenceLat,
}) {
  final radians = _degreesToRadians(referenceLat);
  return (
    dx: point.longitude * 111320.0 * math.cos(radians),
    dy: point.latitude * 110540.0,
  );
}

LatLng lerpLatLng(LatLng start, LatLng end, double t) {
  final clampedT = t.clamp(0.0, 1.0);
  return LatLng(
    start.latitude + (end.latitude - start.latitude) * clampedT,
    start.longitude + (end.longitude - start.longitude) * clampedT,
  );
}

class RouteGeometry {
  RouteGeometry._({
    required this.points,
    required this.cumulativeDistances,
    required this.segmentBearings,
    required this.totalLengthMeters,
  });

  factory RouteGeometry.fromPoints(List<RoutePathPoint> points) {
    final latLngs = points
        .map((point) => toLatLngIfValid(point.lat, point.lon))
        .whereType<LatLng>()
        .toList();
    if (latLngs.length <= 1) {
      return RouteGeometry._(
        points: latLngs,
        cumulativeDistances: const <double>[0],
        segmentBearings: const <double>[0],
        totalLengthMeters: 0,
      );
    }

    final cumulative = <double>[0];
    final bearings = <double>[];
    var total = 0.0;
    for (var index = 0; index < latLngs.length - 1; index++) {
      final start = latLngs[index];
      final end = latLngs[index + 1];
      total += distanceMetersBetween(start, end);
      cumulative.add(total);
      bearings.add(bearingBetween(start, end));
    }
    bearings.add(bearings.isEmpty ? 0 : bearings.last);

    return RouteGeometry._(
      points: latLngs,
      cumulativeDistances: cumulative,
      segmentBearings: bearings,
      totalLengthMeters: total,
    );
  }

  final List<LatLng> points;
  final List<double> cumulativeDistances;
  final List<double> segmentBearings;
  final double totalLengthMeters;

  RouteProjection project(LatLng point) {
    if (points.length <= 1) {
      return RouteProjection(
        snappedPoint: points.isEmpty ? point : points.first,
        distanceToRouteMeters: points.isEmpty
            ? double.infinity
            : distanceMetersBetween(point, points.first),
        distanceAlongRouteMeters: 0,
      );
    }

    var bestDistance = double.infinity;
    LatLng? bestPoint;
    var bestAlongDistance = 0.0;

    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      final projected = _projectOntoSegment(point, start, end);
      final distance = distanceMetersBetween(point, projected.projectedPoint);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = projected.projectedPoint;
        final segmentLength = distanceMetersBetween(start, end);
        bestAlongDistance =
            cumulativeDistances[index] + segmentLength * projected.segmentT;
      }
    }

    return RouteProjection(
      snappedPoint: bestPoint ?? points.first,
      distanceToRouteMeters: bestDistance,
      distanceAlongRouteMeters: bestAlongDistance,
    );
  }

  LatLng pointAtDistance(double distanceMeters) {
    if (points.isEmpty) {
      return const LatLng(0, 0);
    }
    if (points.length == 1 || distanceMeters <= 0) {
      return points.first;
    }
    if (distanceMeters >= totalLengthMeters) {
      return points.last;
    }

    for (var index = 0; index < cumulativeDistances.length - 1; index++) {
      final segmentStartDistance = cumulativeDistances[index];
      final segmentEndDistance = cumulativeDistances[index + 1];
      if (distanceMeters > segmentEndDistance) {
        continue;
      }
      final segmentLength = segmentEndDistance - segmentStartDistance;
      final t = segmentLength == 0
          ? 0.0
          : (distanceMeters - segmentStartDistance) / segmentLength;
      return lerpLatLng(points[index], points[index + 1], t);
    }
    return points.last;
  }
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180;
