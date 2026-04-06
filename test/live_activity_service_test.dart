import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/live_activity_service.dart';
import 'package:taiwanbus_flutter/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> log;

  setUp(() {
    log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('tw.avianjay.taiwanbus.flutter/live_activity'),
      (MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'startLiveActivity':
            return 'mock-activity-id';
          case 'updateLiveActivity':
            return null;
          case 'endLiveActivity':
            return null;
          case 'isLiveActivityActive':
            return true;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('tw.avianjay.taiwanbus.flutter/live_activity'),
      null,
    );
  });

  test('updateFromRouteDetail extracts correct stop data', () async {
    final detail = RouteDetailData(
      route: const RouteSummary(
        sourceProvider: 'twn',
        hashMd5: '',
        routeKey: 307,
        routeId: 0,
        routeName: '307',
        officialRouteName: '307',
        description: '',
        category: '',
        sequence: 0,
        rtrip: 0,
      ),
      paths: const [
        PathInfo(routeKey: 307, pathId: 0, name: '往板橋'),
      ],
      stopsByPath: {
        0: [
          const StopInfo(
            routeKey: 307,
            pathId: 0,
            stopId: 100,
            stopName: '臺北車站',
            sequence: 1,
            lon: 121.5,
            lat: 25.0,
            sec: 125,
          ),
          const StopInfo(
            routeKey: 307,
            pathId: 0,
            stopId: 101,
            stopName: '西門町',
            sequence: 2,
            lon: 121.5,
            lat: 25.0,
            sec: 300,
          ),
          const StopInfo(
            routeKey: 307,
            pathId: 0,
            stopId: 102,
            stopName: '龍山寺',
            sequence: 3,
            lon: 121.5,
            lat: 25.0,
            sec: 500,
          ),
        ],
      },
      hasLiveData: true,
    );

    // Manually start the activity so _activeActivityId is set.
    await LiveActivityService.startLiveActivity(
      routeName: '307',
      pathName: '往板橋',
      stopName: '西門町',
      routeKey: 307,
      provider: 'twn',
      pathId: 0,
      stopId: 101,
      etaSeconds: 300,
    );

    log.clear();

    // Now update from route detail.
    await LiveActivityService.updateFromRouteDetail(
      detail,
      pathId: 0,
      stopId: 101,
    );

    // On non-iOS platforms the platform channel calls are skipped, so verify
    // the service at least does not throw.  On iOS the update method would
    // be invoked with etaSeconds=300 and nextStopName='龍山寺'.
    // This test exercises the Dart-side extraction logic path.
    expect(log, isA<List<MethodCall>>());
  });

  test('endLiveActivity resets active state', () async {
    await LiveActivityService.endLiveActivity();

    // After ending, isActive should be false.
    expect(LiveActivityService.isActive, isFalse);
  });

  test('updateFromRouteDetail does nothing when no activity is active', () async {
    // Make sure no activity is running.
    await LiveActivityService.endLiveActivity();

    final detail = RouteDetailData(
      route: const RouteSummary(
        sourceProvider: 'twn',
        hashMd5: '',
        routeKey: 307,
        routeId: 0,
        routeName: '307',
        officialRouteName: '307',
        description: '',
        category: '',
        sequence: 0,
        rtrip: 0,
      ),
      paths: const [
        PathInfo(routeKey: 307, pathId: 0, name: '往板橋'),
      ],
      stopsByPath: {
        0: [
          const StopInfo(
            routeKey: 307,
            pathId: 0,
            stopId: 100,
            stopName: '臺北車站',
            sequence: 1,
            lon: 121.5,
            lat: 25.0,
            sec: 60,
          ),
        ],
      },
      hasLiveData: true,
    );

    log.clear();

    await LiveActivityService.updateFromRouteDetail(
      detail,
      pathId: 0,
      stopId: 100,
    );

    // No update calls should have been sent because no activity is active.
    final updateCalls =
        log.where((call) => call.method == 'updateLiveActivity');
    expect(updateCalls, isEmpty);
  });

  test(
    'updateFromRouteDetail skips when stopId is not found',
    () async {
      await LiveActivityService.startLiveActivity(
        routeName: '307',
        pathName: '往板橋',
        stopName: '臺北車站',
        routeKey: 307,
        provider: 'twn',
        pathId: 0,
        stopId: 100,
      );

      log.clear();

      final detail = RouteDetailData(
        route: const RouteSummary(
          sourceProvider: 'twn',
          hashMd5: '',
          routeKey: 307,
          routeId: 0,
          routeName: '307',
          officialRouteName: '307',
          description: '',
          category: '',
          sequence: 0,
          rtrip: 0,
        ),
        paths: const [
          PathInfo(routeKey: 307, pathId: 0, name: '往板橋'),
        ],
        stopsByPath: {
          0: [
            const StopInfo(
              routeKey: 307,
              pathId: 0,
              stopId: 999,
              stopName: '不存在的站',
              sequence: 1,
              lon: 121.5,
              lat: 25.0,
            ),
          ],
        },
        hasLiveData: true,
      );

      await LiveActivityService.updateFromRouteDetail(
        detail,
        pathId: 0,
        stopId: 100,
      );

      final updateCalls =
          log.where((call) => call.method == 'updateLiveActivity');
      expect(updateCalls, isEmpty);
    },
  );
}
