import 'platform_notification_service.dart';

/// Stub for platforms that don't need platform notifications (mobile).
class _StubPlatformNotificationService extends PlatformNotificationService {
  const _StubPlatformNotificationService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}

PlatformNotificationService createPlatformNotificationService() =>
    const _StubPlatformNotificationService();
