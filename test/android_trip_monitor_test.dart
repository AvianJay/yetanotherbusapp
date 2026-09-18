import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/android_trip_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('lifecycle calls tolerate a detached platform channel', () async {
    const session = TripMonitorSession(
      providerName: 'txg',
      routeKey: 1,
      routeId: 'TXG1',
      routeName: '1',
      pathId: 0,
      pathName: '往終點',
      appInForeground: true,
      backgroundLocationAlwaysGranted: true,
      stops: <TripMonitorStop>[],
    );

    await AndroidTripMonitor.setAppInForeground(false);
    await AndroidTripMonitor.startOrUpdate(session);
    expect(await AndroidTripMonitor.isPausedFor(session), isFalse);
    await AndroidTripMonitor.stop();
  });
}
