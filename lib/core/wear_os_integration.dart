import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WearOsSyncStatus {
  const WearOsSyncStatus({
    required this.connectedNodeCount,
    required this.connectedNodeNames,
  });

  static const empty = WearOsSyncStatus(
    connectedNodeCount: 0,
    connectedNodeNames: <String>[],
  );

  factory WearOsSyncStatus.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return empty;
    }

    return WearOsSyncStatus(
      connectedNodeCount: (map['connectedNodeCount'] as num?)?.toInt() ?? 0,
      connectedNodeNames:
          (map['connectedNodeNames'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
    );
  }

  final int connectedNodeCount;
  final List<String> connectedNodeNames;

  bool get hasConnectedNodes => connectedNodeCount > 0;
}

class WearOsIntegration {
  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/wear_os',
  );
  static const _eventChannel = EventChannel(
    'tw.avianjay.taiwanbus.flutter/wear_os_events',
  );

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Stream of inbound messages from the paired Wear OS device. Returns a
  /// stream that emits `{kind, payloadJson, receivedAtMs}` maps.
  static Stream<Map<String, Object?>> get events {
    if (!_supported) {
      return const Stream<Map<String, Object?>>.empty();
    }
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return event.map((key, value) => MapEntry(key.toString(), value));
      }
      return const <String, Object?>{};
    });
  }

  static Future<WearOsSyncStatus> getStatus() async {
    if (!_supported) {
      return WearOsSyncStatus.empty;
    }

    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getWearSyncStatus',
      );
      return WearOsSyncStatus.fromMap(result);
    } on MissingPluginException {
      return WearOsSyncStatus.empty;
    } on PlatformException catch (error) {
      debugPrint('WearOsIntegration getStatus failed: $error');
      return WearOsSyncStatus.empty;
    }
  }

  static Future<void> syncSettings({
    required bool syncEnabled,
    required List<String> selectedFavoriteIds,
  }) async {
    if (!_supported) {
      return;
    }

    await _invokeVoid('syncWearSettings', {
      'payloadJson': jsonEncode({
        'syncEnabled': syncEnabled,
        'selectedFavoriteIds': selectedFavoriteIds,
        'lastUpdatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }),
    });
  }

  static Future<void> syncFavorites(
    List<Map<String, dynamic>> favorites,
  ) async {
    if (!_supported) {
      return;
    }

    await _invokeVoid('syncWearFavorites', {
      'payloadJson': jsonEncode({
        'favorites': favorites,
        'lastUpdatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }),
    });
  }

  static Future<void> syncSmartSuggestion(
    Map<String, dynamic>? suggestion,
  ) async {
    if (!_supported) {
      return;
    }

    if (suggestion == null) {
      await _invokeVoid('clearWearSmartSuggestion');
      return;
    }

    await _invokeVoid('syncWearSmartSuggestion', {
      'payloadJson': jsonEncode({
        ...suggestion,
        'generatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'source': 'phone',
      }),
    });
  }

  static Future<void> syncUsageProfiles(
    List<Map<String, dynamic>> profiles,
  ) async {
    if (!_supported) {
      return;
    }

    await _invokeVoid('syncWearUsageProfiles', {
      'payloadJson': jsonEncode({
        'profiles': profiles,
        'lastUpdatedAtMs': DateTime.now().millisecondsSinceEpoch,
      }),
    });
  }

  static Future<void> cancelWearRefresh() async {
    if (!_supported) {
      return;
    }
    await _invokeVoid('cancelWearRefresh');
  }

  static Future<void> requestRefresh() async {
    if (!_supported) {
      return;
    }

    await _invokeVoid('requestWearRefresh');
  }

  static Future<WearOsSyncStatus> syncAll({
    required bool syncEnabled,
    required List<String> selectedFavoriteIds,
    required List<Map<String, dynamic>> favorites,
    Map<String, dynamic>? smartSuggestion,
    List<Map<String, dynamic>>? usageProfiles,
    bool requestRefresh = false,
  }) async {
    if (!_supported) {
      return WearOsSyncStatus.empty;
    }

    await syncSettings(
      syncEnabled: syncEnabled,
      selectedFavoriteIds: selectedFavoriteIds,
    );
    await syncFavorites(favorites);
    if (usageProfiles != null) {
      await syncUsageProfiles(usageProfiles);
    }
    await syncSmartSuggestion(smartSuggestion);
    if (requestRefresh) {
      await WearOsIntegration.requestRefresh();
    }
    return getStatus();
  }

  static Future<void> _invokeVoid(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      debugPrint('WearOsIntegration $method failed: $error');
    }
  }
}
