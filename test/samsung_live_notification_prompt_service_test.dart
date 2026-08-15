import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taiwanbus_flutter/core/android_trip_monitor.dart';
import 'package:taiwanbus_flutter/core/samsung_live_notification_prompt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tw.avianjay.taiwanbus.flutter/trip_monitor');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('recognizes Samsung devices on One UI 8.5 or newer', () {
    expect(
      SamsungLiveNotificationPromptService.isAffectedSamsungDevice(
        const AndroidDeviceInfo(
          manufacturer: 'samsung',
          brand: 'samsung',
          sdkVersion: 36,
          samsungPlatformVersion: 170500,
        ),
      ),
      isTrue,
    );
    expect(
      SamsungLiveNotificationPromptService.isAffectedSamsungDevice(
        const AndroidDeviceInfo(
          manufacturer: 'samsung',
          brand: 'samsung',
          sdkVersion: 36,
          samsungPlatformVersion: 170000,
        ),
      ),
      isFalse,
    );
    expect(
      SamsungLiveNotificationPromptService.isAffectedSamsungDevice(
        const AndroidDeviceInfo(
          manufacturer: 'Google',
          brand: 'google',
          sdkVersion: 36,
          samsungPlatformVersion: 170500,
        ),
      ),
      isFalse,
    );
    expect(
      SamsungLiveNotificationPromptService.isAffectedSamsungDevice(
        const AndroidDeviceInfo(
          manufacturer: 'samsung',
          brand: 'samsung',
          sdkVersion: 36,
        ),
      ),
      isFalse,
    );
    expect(
      SamsungLiveNotificationPromptService.isAffectedSamsungDevice(
        const AndroidDeviceInfo(
          manufacturer: 'samsung',
          brand: 'samsung',
          sdkVersion: 35,
          samsungPlatformVersion: 170500,
        ),
      ),
      isFalse,
    );
  });

  test('shows once when background monitoring is enabled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          if (methodCall.method == 'getAndroidDeviceInfo') {
            return <String, Object>{
              'manufacturer': 'samsung',
              'brand': 'samsung',
              'sdkVersion': 36,
              'samsungPlatformVersion': 170500,
            };
          }
          return null;
        });

    expect(
      await SamsungLiveNotificationPromptService.shouldShow(
        backgroundTripMonitorEnabled: true,
      ),
      isTrue,
    );

    await SamsungLiveNotificationPromptService.markShown();

    expect(
      await SamsungLiveNotificationPromptService.shouldShow(
        backgroundTripMonitorEnabled: true,
      ),
      isFalse,
    );
  });

  test(
    'does not inspect the device when background monitoring is off',
    () async {
      var methodCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            methodCalls += 1;
            return null;
          });

      expect(
        await SamsungLiveNotificationPromptService.shouldShow(
          backgroundTripMonitorEnabled: false,
        ),
        isFalse,
      );
      expect(methodCalls, 0);
    },
  );

  test('opens Samsung settings through the trip monitor channel', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
          capturedCall = methodCall;
          return true;
        });

    expect(
      await AndroidTripMonitor.openSamsungLiveNotificationSettings(),
      isTrue,
    );
    expect(capturedCall?.method, 'openSamsungLiveNotificationSettings');
  });

  test(
    'returns false when the Samsung settings channel is unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            throw MissingPluginException();
          });

      expect(
        await AndroidTripMonitor.openSamsungLiveNotificationSettings(),
        isFalse,
      );
    },
  );
}
