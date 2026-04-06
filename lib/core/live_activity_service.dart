import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class LiveActivityService {
  LiveActivityService._();

  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/live_activity',
  );

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static String? _activeActivityId;

  static bool get isActive => _activeActivityId != null;

  static Future<bool> startLiveActivity({
    required String routeName,
    required String pathName,
    required String stopName,
    required int routeKey,
    required String provider,
    required int pathId,
    required int stopId,
    int? etaSeconds,
    String? etaMessage,
    String? vehicleId,
    String? nextStopName,
  }) async {
    if (!_isIOS) {
      return false;
    }

    try {
      final arguments = <String, Object?>{
        'routeName': routeName,
        'pathName': pathName,
        'stopName': stopName,
        'routeKey': routeKey,
        'provider': provider,
        'pathId': pathId,
        'stopId': stopId,
        'etaSeconds': etaSeconds,
        'etaMessage': etaMessage,
        'vehicleId': vehicleId,
        'nextStopName': nextStopName,
      }..removeWhere((_, value) => value == null);
      final result = await _channel.invokeMethod<String>(
        'startLiveActivity',
        arguments,
      );
      _activeActivityId = result;
      return result != null;
    } on PlatformException {
      _activeActivityId = null;
      return false;
    } on MissingPluginException {
      _activeActivityId = null;
      return false;
    }
  }

  static Future<void> updateLiveActivity({
    int? etaSeconds,
    String? etaMessage,
    String? vehicleId,
    String? nextStopName,
  }) async {
    if (!_isIOS || _activeActivityId == null) {
      return;
    }

    try {
      final arguments = <String, Object?>{
        'etaSeconds': etaSeconds,
        'etaMessage': etaMessage,
        'vehicleId': vehicleId,
        'nextStopName': nextStopName,
      }..removeWhere((_, value) => value == null);
      await _channel.invokeMethod<void>('updateLiveActivity', arguments);
    } on PlatformException {
      // Ignore; activity may have been dismissed by the user.
    } on MissingPluginException {
      // Ignore; plugin not registered yet.
    }
  }

  static Future<void> endLiveActivity() async {
    if (!_isIOS) {
      return;
    }

    _activeActivityId = null;
    try {
      await _channel.invokeMethod<void>('endLiveActivity');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  static Future<bool> isLiveActivityActive() async {
    if (!_isIOS) {
      return false;
    }

    try {
      final result =
          await _channel.invokeMethod<bool>('isLiveActivityActive') ?? false;
      return result;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Extracts the live stop data for [stopId] from the route detail and
  /// pushes it to the active Dynamic Island.
  static Future<void> updateFromRouteDetail(
    RouteDetailData detail, {
    required int pathId,
    required int stopId,
  }) async {
    if (!_isIOS || _activeActivityId == null) {
      return;
    }

    final pathStops = detail.stopsByPath[pathId] ?? const <StopInfo>[];
    StopInfo? targetStop;
    String? nextStopName;
    for (var i = 0; i < pathStops.length; i++) {
      if (pathStops[i].stopId == stopId) {
        targetStop = pathStops[i];
        if (i + 1 < pathStops.length) {
          nextStopName = pathStops[i + 1].stopName;
        }
        break;
      }
    }

    if (targetStop == null) {
      return;
    }

    final vehicleId =
        targetStop.buses.isNotEmpty ? targetStop.buses.first.id : null;

    await updateLiveActivity(
      etaSeconds: targetStop.sec,
      etaMessage: targetStop.msg,
      vehicleId: vehicleId,
      nextStopName: nextStopName,
    );
  }
}
