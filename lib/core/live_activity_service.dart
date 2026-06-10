import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LiveActivityDisplayState {
  const LiveActivityDisplayState({
    required this.stopId,
    required this.stopName,
    this.alertStopName,
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
    this.alertKind,
  });

  final int stopId;
  final String stopName;
  final String? alertStopName;
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
  final String? alertKind;

  Map<String, Object?> toArguments() {
    return <String, Object?>{
      'displayStopId': stopId,
      'displayStopName': stopName,
      'alertStopName': alertStopName,
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
      'alertKind': alertKind,
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

  /// The identifier of the most recently started Live Activity, if any.
  ///
  /// Callers that start an activity should hold on to this value and pass it
  /// back as `ownerActivityId` when updating or ending, so that a screen
  /// whose activity has been replaced (e.g. by another route screen) cannot
  /// overwrite the new activity with stale data for the wrong bus/route.
  static String? get activeActivityId => _activeActivityId;

  /// Whether [activityId] still identifies the currently active activity.
  static bool ownsActivity(String? activityId) {
    return activityId != null && activityId == _activeActivityId;
  }

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

  /// Updates the active Live Activity.
  ///
  /// When [ownerActivityId] is provided, the update is skipped unless it
  /// matches the currently active activity. Returns `true` when the native
  /// side reports the activity is still alive and was updated.
  static Future<bool> updateLiveActivity(
    LiveActivityDisplayState state, {
    String? ownerActivityId,
  }) async {
    if (!_isIOS || _activeActivityId == null) {
      return false;
    }
    if (ownerActivityId != null && ownerActivityId != _activeActivityId) {
      // Another caller owns the current activity; do not overwrite it with
      // data belonging to a different route/bus.
      return false;
    }

    try {
      final updated = await _channel.invokeMethod<bool>(
        'updateLiveActivity',
        state.toArguments(),
      );
      if (updated == false) {
        // The native side no longer has this activity (dismissed/ended).
        _activeActivityId = null;
        return false;
      }
      return true;
    } on PlatformException {
      // Ignore; activity may have been dismissed by the user.
      return false;
    } on MissingPluginException {
      // Ignore; plugin not registered yet.
      return false;
    }
  }

  /// Ends the active Live Activity.
  ///
  /// When [ownerActivityId] is provided, the activity is only ended if it
  /// matches the currently active one, so a disposed screen cannot tear down
  /// an activity started later by another screen.
  static Future<void> endLiveActivity({String? ownerActivityId}) async {
    if (!_isIOS) {
      return;
    }
    if (ownerActivityId != null && ownerActivityId != _activeActivityId) {
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
