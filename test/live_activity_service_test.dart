import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/live_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tw.avianjay.taiwanbus.flutter/live_activity');

  late List<MethodCall> log;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
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
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      null,
    );
  });

  test('startLiveActivity sends route and display arguments', () async {
    final state = LiveActivityDisplayState(
      stopId: 101,
      stopName: '西門町',
      modeLabel: '尚未上車',
      etaSeconds: 300,
      progressValue: 2,
      progressTotal: 5,
    );

    final didStart = await LiveActivityService.startLiveActivity(
      routeName: '307',
      pathName: '往板橋',
      routeKey: 307,
      provider: 'twn',
      pathId: 0,
      state: state,
    );

    expect(didStart, isTrue);
    expect(LiveActivityService.isActive, isTrue);
    expect(log, hasLength(1));
    expect(log.single.method, 'startLiveActivity');

    final args = log.single.arguments as Map<dynamic, dynamic>;
    expect(args['routeName'], '307');
    expect(args['pathName'], '往板橋');
    expect(args['routeKey'], 307);
    expect(args['provider'], 'twn');
    expect(args['pathId'], 0);
    expect(args['displayStopId'], 101);
    expect(args['displayStopName'], '西門町');
    expect(args['modeLabel'], '尚未上車');
    expect(args['etaSeconds'], 300);
    expect(args['progressValue'], 2);
    expect(args['progressTotal'], 5);
    expect(args.containsKey('etaMessage'), isFalse);
  });

  test('updateLiveActivity sends display-only payload when active', () async {
    await LiveActivityService.startLiveActivity(
      routeName: '307',
      pathName: '往板橋',
      routeKey: 307,
      provider: 'twn',
      pathId: 0,
      state: const LiveActivityDisplayState(stopId: 100, stopName: '臺北車站'),
    );

    log.clear();

    await LiveActivityService.updateLiveActivity(
      const LiveActivityDisplayState(
        stopId: 102,
        stopName: '龍山寺',
        modeLabel: '已上車',
        statusText: '最近站牌 西門町',
        etaMessage: '進站中',
      ),
    );

    expect(log, hasLength(1));
    expect(log.single.method, 'updateLiveActivity');
    final args = log.single.arguments as Map<dynamic, dynamic>;
    expect(args['displayStopId'], 102);
    expect(args['displayStopName'], '龍山寺');
    expect(args['modeLabel'], '已上車');
    expect(args['statusText'], '最近站牌 西門町');
    expect(args['etaMessage'], '進站中');
    expect(args.containsKey('routeName'), isFalse);
  });

  test('updateLiveActivity does nothing when no activity is active', () async {
    await LiveActivityService.endLiveActivity();
    log.clear();

    await LiveActivityService.updateLiveActivity(
      const LiveActivityDisplayState(stopId: 101, stopName: '西門町'),
    );

    expect(log, isEmpty);
  });

  test('endLiveActivity resets active state', () async {
    await LiveActivityService.startLiveActivity(
      routeName: '307',
      pathName: '往板橋',
      routeKey: 307,
      provider: 'twn',
      pathId: 0,
      state: const LiveActivityDisplayState(stopId: 100, stopName: '臺北車站'),
    );

    log.clear();
    await LiveActivityService.endLiveActivity();

    expect(LiveActivityService.isActive, isFalse);
    expect(log, hasLength(1));
    expect(log.single.method, 'endLiveActivity');
  });

  test('isLiveActivityActive delegates to method channel', () async {
    final isLiveActive = await LiveActivityService.isLiveActivityActive();

    expect(isLiveActive, isTrue);
    expect(log, hasLength(1));
    expect(log.single.method, 'isLiveActivityActive');
  });

  test('startLiveActivity returns false on non-iOS platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    log.clear();

    final didStart = await LiveActivityService.startLiveActivity(
      routeName: '307',
      pathName: '往板橋',
      routeKey: 307,
      provider: 'twn',
      pathId: 0,
      state: const LiveActivityDisplayState(stopId: 101, stopName: '西門町'),
    );

    expect(didStart, isFalse);
    expect(log, isEmpty);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
}
