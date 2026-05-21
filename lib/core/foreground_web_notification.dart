import 'foreground_web_notification_stub.dart'
    if (dart.library.html) 'foreground_web_notification_web.dart';

Future<void> showForegroundWebNotification({
  required String title,
  required String body,
  required String routePath,
}) {
  return showForegroundWebNotificationImpl(
    title: title,
    body: body,
    routePath: routePath,
  );
}
