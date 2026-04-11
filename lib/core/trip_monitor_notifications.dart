import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'android_trip_monitor.dart';

class TripMonitorNotifications {
  TripMonitorNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    if (kIsWeb) {
      return false;
    }

    await initialize();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidTripMonitor.requestNotificationPermission();
      case TargetPlatform.iOS:
        final implementation = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await implementation?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      default:
        return false;
    }
  }

  static Future<void> showBoardingCheckPrompt({
    required String routeName,
    required String boardingStopName,
    String? destinationStopName,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    await initialize();
    final body = destinationStopName == null || destinationStopName.trim().isEmpty
        ? '$boardingStopName 的公車已經到了，你有上車嗎？'
        : '$boardingStopName 的公車已經到了，你有上車嗎？已上車的話會繼續提醒你前往 $destinationStopName。';

    await _plugin.show(
      6201,
      '$routeName 上車確認',
      body,
      const NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }

  static Future<void> cancelBoardingCheckPrompt() async {
    if (kIsWeb) {
      return;
    }
    await initialize();
    await _plugin.cancel(6201);
  }
}
