// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;

Future<void> showForegroundWebNotificationImpl({
  required String title,
  required String body,
  required String routePath,
}) async {
  if (!js.context.hasProperty('Notification')) {
    return;
  }
  final permission = js.context['Notification']['permission'];
  if (permission != 'granted') {
    return;
  }

  js.JsObject(js.context['Notification'], [
    title,
    js.JsObject.jsify({
      'body': body,
      'icon': 'icons/Icon-192.png',
      'tag': 'yabus-announcement-${routePath.hashCode}',
    }),
  ]);
}
