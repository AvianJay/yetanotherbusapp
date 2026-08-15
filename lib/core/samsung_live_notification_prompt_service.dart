import 'package:shared_preferences/shared_preferences.dart';

import 'android_trip_monitor.dart';

class SamsungLiveNotificationPromptService {
  SamsungLiveNotificationPromptService._();

  static const _promptSeenKey = 'samsung_live_notifications_prompt_seen_v1';

  static Future<bool> shouldShow({
    required bool backgroundTripMonitorEnabled,
  }) async {
    if (!backgroundTripMonitorEnabled) {
      return false;
    }

    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_promptSeenKey) == true) {
      return false;
    }

    try {
      final deviceInfo = await AndroidTripMonitor.getAndroidDeviceInfo();
      return isAffectedSamsungDevice(deviceInfo);
    } catch (_) {
      return false;
    }
  }

  static bool isAffectedSamsungDevice(AndroidDeviceInfo? deviceInfo) {
    if (deviceInfo == null || deviceInfo.sdkVersion < 36) {
      return false;
    }

    final manufacturer = deviceInfo.manufacturer.toLowerCase();
    final brand = deviceInfo.brand.toLowerCase();
    final isSamsung =
        manufacturer.contains('samsung') || brand.contains('samsung');
    return isSamsung &&
        (deviceInfo.samsungPlatformVersion ?? 0) >=
            minimumAffectedSamsungPlatformVersion;
  }

  static Future<void> markShown() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_promptSeenKey, true);
  }

  static const minimumAffectedSamsungPlatformVersion = 170500;
}
