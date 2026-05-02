import 'platform_notification_service_stub.dart'
    if (dart.library.io) 'platform_notification_service_io.dart'
    if (dart.library.html) 'platform_notification_service_web.dart';

/// Unified notification API that works across Web and Desktop platforms.
///
/// On Web, this uses the browser Notification API via JS interop.
/// On Desktop (Windows/Linux/macOS), this uses the `local_notifier` plugin.
/// On mobile (Android/iOS), this is a no-op — those platforms have their own
/// notification paths (MethodChannel / flutter_local_notifications).
abstract class PlatformNotificationService {
  const PlatformNotificationService();

  /// Whether this platform supports showing notifications at all.
  bool get isSupported;

  /// Request notification permission from the OS / browser.
  /// Returns `true` if granted (or already granted).
  Future<bool> requestPermission();

  /// Show a simple notification with [title] and [body].
  /// [id] is used to later cancel the notification.
  Future<void> show({required int id, required String title, required String body});

  /// Cancel a previously shown notification by [id].
  Future<void> cancel(int id);
}

/// The shared singleton, created per-platform by conditional import.
final PlatformNotificationService platformNotifications =
    createPlatformNotificationService();
