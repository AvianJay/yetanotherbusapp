// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;

import 'platform_notification_service.dart';

class _WebPlatformNotificationService extends PlatformNotificationService {
  const _WebPlatformNotificationService();

  @override
  bool get isSupported {
    return js.context.hasProperty('Notification');
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    final permission = js.context['Notification']['permission'];
    if (permission == 'granted') return true;
    if (permission == 'denied') return false;
    final result = await js.context['Notification']
        .callMethod('requestPermission') as String?;
    return result == 'granted';
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!isSupported) return;
    final permission = js.context['Notification']['permission'];
    if (permission != 'granted') return;
    js.context['Notification'].newWithArguments(title, js.JsObject.jsify({
      'body': body,
      'icon': 'icons/Icon-192.png',
      'tag': 'yabus-$id',
    }));
  }

  @override
  Future<void> cancel(int id) async {
    if (!isSupported) return;
    // The Web Notification API does not expose a way to programmatically
    // close notifications by tag from Dart. Browsers auto-replace
    // notifications with the same tag, so re-showing with the same tag
    // replaces the previous one. For now, this is a no-op.
  }
}

PlatformNotificationService createPlatformNotificationService() =>
    const _WebPlatformNotificationService();
