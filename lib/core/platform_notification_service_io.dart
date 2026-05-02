import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import 'platform_notification_service.dart';

/// Desktop notification service using `local_notifier` (Windows/Linux/macOS).
class _DesktopPlatformNotificationService extends PlatformNotificationService {
  _DesktopPlatformNotificationService() {
    _ensureSetup();
  }

  bool _setupDone = false;
  final Map<int, LocalNotification> _active = {};

  void _ensureSetup() {
    if (_setupDone || kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    _setupDone = true;
    // localNotifier.setup must be called after WidgetsFlutterBinding
    // is initialized, which it always is by the time this singleton
    // is first accessed in the route detail screen.
    try {
      localNotifier.setup(appName: 'YABus');
    } catch (_) {
      // Setup may fail on CI; ignore.
    }
  }

  @override
  bool get isSupported =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  Future<bool> requestPermission() async {
    // Desktop platforms don't have runtime permission prompts.
    return isSupported;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!isSupported) return;
    _ensureSetup();

    // Close any previous notification with the same id.
    await cancel(id);

    final notification = LocalNotification(
      identifier: 'yabus-$id',
      title: title,
      body: body,
    );
    _active[id] = notification;
    notification.show();
  }

  @override
  Future<void> cancel(int id) async {
    final existing = _active.remove(id);
    if (existing != null) {
      try {
        await existing.close();
      } catch (_) {}
    }
  }
}

PlatformNotificationService createPlatformNotificationService() =>
    _DesktopPlatformNotificationService();
