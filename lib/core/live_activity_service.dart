import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LiveActivityDisplayState {
  const LiveActivityDisplayState({
    required this.stopId,
    required this.stopName,
    this.previousStopName,
    this.nextStopName,
    this.lineStopNames,
    this.lineCurrentStopIndex,
    this.lineHighlightedStopIndex,
    this.modeLabel,
    this.statusText,
    this.etaSeconds,
    this.etaMessage,
    this.vehicleId,
    this.progressValue,
    this.progressTotal,
  });

  final int stopId;
  final String stopName;
  final String? previousStopName;
  final String? nextStopName;
  final List<String>? lineStopNames;
  final int? lineCurrentStopIndex;
  final int? lineHighlightedStopIndex;
  final String? modeLabel;
  final String? statusText;
  final int? etaSeconds;
  final String? etaMessage;
  final String? vehicleId;
  final int? progressValue;
  final int? progressTotal;

  Map<String, Object?> toArguments() {
    return <String, Object?>{
      'displayStopId': stopId,
      'displayStopName': stopName,
      'previousStopName': previousStopName,
      'nextStopName': nextStopName,
      'lineStopNames': lineStopNames,
      'lineCurrentStopIndex': lineCurrentStopIndex,
      'lineHighlightedStopIndex': lineHighlightedStopIndex,
      'modeLabel': modeLabel,
      'statusText': statusText,
      'etaSeconds': etaSeconds,
      'etaMessage': etaMessage,
      'vehicleId': vehicleId,
      'progressValue': progressValue,
      'progressTotal': progressTotal,
    }..removeWhere((_, value) => value == null);
  }
}

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
    required int routeKey,
    required String provider,
    required int pathId,
    required LiveActivityDisplayState state,
  }) async {
    if (!_isIOS) {
      return false;
    }

    try {
      final arguments = <String, Object?>{
        'routeName': routeName,
        'pathName': pathName,
        'routeKey': routeKey,
        'provider': provider,
        'pathId': pathId,
        ...state.toArguments(),
      };
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

  static Future<void> updateLiveActivity(LiveActivityDisplayState state) async {
    if (!_isIOS || _activeActivityId == null) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(
        'updateLiveActivity',
        state.toArguments(),
      );
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
}
