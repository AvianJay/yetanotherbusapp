import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TripMonitorStop {
  const TripMonitorStop({
    required this.stopId,
    required this.stopName,
    required this.sequence,
    required this.lat,
    required this.lon,
  });

  final int stopId;
  final String stopName;
  final int sequence;
  final double lat;
  final double lon;

  Map<String, Object?> toMap() {
    return {
      'stopId': stopId,
      'stopName': stopName,
      'sequence': sequence,
      'lat': lat,
      'lon': lon,
    };
  }
}

class TripMonitorSession {
  const TripMonitorSession({
    required this.providerName,
    required this.routeKey,
    this.routeId,
    required this.routeName,
    required this.pathId,
    required this.pathName,
    required this.appInForeground,
    required this.backgroundLocationAlwaysGranted,
    required this.stops,
    this.initialLatitude,
    this.initialLongitude,
    this.boardingStopId,
    this.boardingStopName,
    this.destinationStopId,
    this.destinationStopName,
  });

  final String providerName;
  final int routeKey;
  final String? routeId;
  final String routeName;
  final int pathId;
  final String pathName;
  final bool appInForeground;
  final bool backgroundLocationAlwaysGranted;
  final List<TripMonitorStop> stops;
  final double? initialLatitude;
  final double? initialLongitude;
  final int? boardingStopId;
  final String? boardingStopName;
  final int? destinationStopId;
  final String? destinationStopName;

  Map<String, Object?> toMap() {
    return {
      'provider': providerName,
      'routeKey': routeKey,
      'routeId': routeId,
      'routeName': routeName,
      'pathId': pathId,
      'pathName': pathName,
      'appInForeground': appInForeground,
      'backgroundLocationAlwaysGranted': backgroundLocationAlwaysGranted,
      'initialLatitude': initialLatitude,
      'initialLongitude': initialLongitude,
      'boardingStopId': boardingStopId,
      'boardingStopName': boardingStopName,
      'destinationStopId': destinationStopId,
      'destinationStopName': destinationStopName,
      'stops': stops.map((stop) => stop.toMap()).toList(),
    };
  }
}

class AndroidTripMonitor {
  AndroidTripMonitor._();

  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/trip_monitor',
  );

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> requestNotificationPermission() async {
    if (!_isAndroid) {
      return false;
    }
    return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false;
  }

  static Future<void> startOrUpdate(TripMonitorSession session) async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('startOrUpdateTripMonitor', {
      'session': session.toMap(),
    });
  }

  static Future<void> setAppInForeground(bool value) async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('setTripMonitorAppInForeground', {
      'appInForeground': value,
    });
  }

  static Future<void> pause(
    TripMonitorSession session, {
    String reason = 'user',
  }) async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('pauseTripMonitor', {
      'session': session.toMap(),
      'reason': reason,
    });
  }

  static Future<void> resume() async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('resumeTripMonitor');
  }

  static Future<bool> isPausedFor(TripMonitorSession session) async {
    if (!_isAndroid) {
      return false;
    }
    return await _channel.invokeMethod<bool>('isTripMonitorPaused', {
          'session': session.toMap(),
        }) ??
        false;
  }

  static Future<void> stop() async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('stopTripMonitor');
  }
}
