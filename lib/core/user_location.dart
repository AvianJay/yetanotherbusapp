import 'package:geolocator/geolocator.dart';

import 'transit_repository.dart';

/// A location attempt that failed for a reason worth telling the user about.
class LocationFailure implements Exception {
  const LocationFailure(this.message, {this.deniedForever = false});

  final String message;

  /// The user has to go into system settings; asking again will not help.
  final bool deniedForever;

  @override
  String toString() => message;
}

/// Resolves the device's position, throwing [LocationFailure] with a
/// ready-to-show Traditional Chinese message when it cannot.
///
/// This is the same service-check → permission → last-known → current-position
/// sequence that eight screens each hand-roll today (`nearby_screen.dart:58`,
/// `bus_map_screen.dart:636`, `youbike_screen.dart:111`, and friends). New code
/// should call this; migrating the existing eight is separate cleanup.
Future<Position> resolveUserPosition({
  Duration timeLimit = const Duration(seconds: 6),
  LocationAccuracy accuracy = LocationAccuracy.medium,
}) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationFailure('定位服務尚未開啟。');
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationFailure('沒有取得定位權限。', deniedForever: true);
  }
  if (permission == LocationPermission.denied) {
    throw const LocationFailure('沒有取得定位權限。');
  }

  Position? lastKnown;
  try {
    lastKnown = await Geolocator.getLastKnownPosition();
  } catch (_) {
    lastKnown = null;
  }

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );
  } catch (_) {
    if (lastKnown != null) {
      return lastKnown;
    }
    throw const LocationFailure('目前無法取得定位，請稍後再試。');
  }
}

/// A station plus how far the user is from it.
class NearestRailStation {
  const NearestRailStation({required this.station, required this.distanceMeters});

  final RailStation station;
  final double distanceMeters;
}

/// Closest station to the given point, or `null` if none has coordinates.
///
/// Linear scan over roughly 240 TRA (or 12 THSR) stations — cheap enough that
/// an index would be premature. Uses `Geolocator.distanceBetween` rather than
/// adding a fifth great-circle helper to this codebase.
NearestRailStation? nearestRailStation(
  List<RailStation> stations, {
  required double latitude,
  required double longitude,
}) {
  NearestRailStation? best;
  for (final station in stations) {
    if (station.lat == 0 && station.lon == 0) {
      continue;
    }
    final distance = Geolocator.distanceBetween(
      latitude,
      longitude,
      station.lat,
      station.lon,
    );
    if (best == null || distance < best.distanceMeters) {
      best = NearestRailStation(station: station, distanceMeters: distance);
    }
  }
  return best;
}
