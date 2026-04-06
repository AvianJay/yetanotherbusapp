import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class IOSWidgetIntegration {
  IOSWidgetIntegration._();

  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/ios_widgets',
  );

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> syncFavoriteGroups(
    Map<String, List<FavoriteStop>> favoriteGroups,
    {
    bool waitForBridge = false,
  }
  ) async {
    if (!_isIOS) {
      return;
    }

    if (waitForBridge) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    final payload = favoriteGroups.map(
      (key, value) =>
          MapEntry(key, value.map((item) => item.toJson()).toList()),
    );
    final groupCount = favoriteGroups.length;

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _channel.invokeMethod<void>('syncFavoriteGroups', {
          'json': jsonEncode(payload),
        });
        return;
      } on MissingPluginException catch (error) {
        if (attempt == 3) {
          debugPrint(
            'IOSWidgetIntegration syncFavoriteGroups failed after 4 attempts '
            '(MissingPluginException, groups=$groupCount): $error',
          );
          return;
        }
      } on PlatformException catch (error) {
        if (attempt == 3) {
          debugPrint(
            'IOSWidgetIntegration syncFavoriteGroups failed after 4 attempts '
            '(PlatformException code=${error.code}, message=${error.message}, groups=$groupCount)',
          );
          return;
        }
      } catch (error) {
        if (attempt == 3) {
          debugPrint(
            'IOSWidgetIntegration syncFavoriteGroups failed after 4 attempts '
            '(unexpected, groups=$groupCount): $error',
          );
          return;
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}
