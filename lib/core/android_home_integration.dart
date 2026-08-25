import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class AndroidHomeIntegration {
  AndroidHomeIntegration._();

  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/home_integration',
  );

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> pinFavoriteShortcut({
    required FavoriteItem favorite,
  }) async {
    if (!_isAndroid) {
      return false;
    }

    final result = await _channel.invokeMethod<bool>(
      'pinFavoriteShortcut',
      favorite.toJson(),
    );
    return result ?? false;
  }

  static Future<bool> pinStopShortcut({required FavoriteStop favorite}) =>
      pinFavoriteShortcut(favorite: favorite);

  static Future<void> refreshFavoriteWidgets() async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('refreshFavoriteWidgets');
  }

  static Future<void> updateFavoriteWidgetAutoRefreshMinutes(
    int minutes,
  ) async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('setFavoriteWidgetAutoRefreshMinutes', {
      'minutes': minutes,
    });
  }

  static Future<void> syncSmartRouteNotifications(bool enabled) async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('setSmartRouteNotificationsEnabled', {
      'enabled': enabled,
    });
  }

  static Future<void> setApplicationInForeground(bool value) async {
    if (!_isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('setApplicationInForeground', {
      'appInForeground': value,
    });
  }
}
