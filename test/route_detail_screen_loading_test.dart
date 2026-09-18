import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taiwanbus_flutter/app/bus_app.dart';
import 'package:taiwanbus_flutter/core/account_sync_service.dart';
import 'package:taiwanbus_flutter/core/app_analytics.dart';
import 'package:taiwanbus_flutter/core/app_build_info.dart';
import 'package:taiwanbus_flutter/core/app_controller.dart';
import 'package:taiwanbus_flutter/core/app_route_observer.dart';
import 'package:taiwanbus_flutter/core/app_update_installer.dart';
import 'package:taiwanbus_flutter/core/app_update_service.dart';
import 'package:taiwanbus_flutter/core/auth_service.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/storage_service.dart';
import 'package:taiwanbus_flutter/screens/route_detail_screen.dart';
import 'package:taiwanbus_flutter/widgets/eta_badge.dart';

class _Repository extends BusRepository {
  _Repository()
    : super(client: MockClient((_) async => http.Response('{}', 404)));
  final requests = <StreamController<RouteDetailUpdate>>[];

  @override
  Stream<RouteDetailUpdate> watchRouteDetail(
    int routeKey, {
    required BusProvider provider,
    String? routeIdHint,
    String? routeNameHint,
  }) {
    final stream = StreamController<RouteDetailUpdate>();
    requests.add(stream);
    return stream.stream;
  }
}

class _NoLocation extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;
}

RouteDetailData _detail({
  int? eta,
  String name = '測試路線',
  DateTime? updatedAt,
  List<String> family = const [],
}) => RouteDetailData(
  route: RouteSummary(
    sourceProvider: 'TPE',
    hashMd5: '',
    routeKey: 500,
    routeId: 'TPE500',
    routeName: name,
    officialRouteName: name,
    description: '',
    category: '',
    sequence: 0,
    rtrip: 0,
  ),
  paths: const [
    PathInfo(routeKey: 500, pathId: 0, name: '去程'),
    PathInfo(routeKey: 500, pathId: 1, name: '返程'),
  ],
  stopsByPath: {
    for (final path in [0, 1])
      path: [
        for (var i = 1; i <= 15; i++)
          StopInfo(
            routeKey: 500,
            pathId: path,
            stopId: i,
            stopName: '${path == 0 ? '去程' : '返程'}站$i',
            sequence: i,
            lat: 25,
            lon: 121,
            sec: eta,
            t: eta == null
                ? null
                : (updatedAt ?? DateTime.now()).toIso8601String(),
          ),
      ],
  },
  hasLiveData: eta != null,
  familyRouteIds: family,
);

Future<AppController> _controller(_Repository repository) async {
  const build = AppBuildInfo(
    version: '1.0.0',
    buildNumber: '1',
    gitSha: 'test',
    defaultUpdateChannel: AppUpdateChannel.release,
  );
  final client = MockClient((_) async => http.Response('{}', 404));
  final controller = AppController(
    repository: repository,
    storage: StorageService(),
    analytics: await AppAnalytics.initialize(),
    buildInfo: build,
    appUpdateService: AppUpdateService(buildInfo: build, client: client),
    appUpdateInstaller: createAppUpdateInstaller(),
    authService: AuthService(),
    accountSyncService: AccountSyncService(client: client),
  );
  await controller.updateDesktopDiscordPresenceEnabled(false);
  await controller.updateEnableRouteBackgroundMonitor(false);
  await controller.updateKeepScreenAwakeOnRouteDetail(false);
  await controller.updateEnableAds(false);
  return controller;
}

Future<void> _frames(WidgetTester tester, [int count = 5]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _screenTest(
  String name,
  Future<void> Function(WidgetTester, _Repository) body,
) {
  testWidgets(name, (tester) async {
    SharedPreferences.setMockInitialValues({});
    final previousLocation = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _NoLocation();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final repository = _Repository();
    final controller = await _controller(repository);
    try {
      await tester.pumpWidget(
        AppControllerScope(
          controller: controller,
          child: MaterialApp(
            navigatorObservers: [appRouteObserver],
            home: const RouteDetailScreen(
              routeKey: 500,
              provider: BusProvider.tpe,
              routeIdHint: 'TPE500',
              routeNameHint: '標題提示',
              initialPathId: 1,
              suppressAutoDestinationSelection: true,
            ),
          ),
        ),
      );
      await _frames(tester);
      await body(tester, repository);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final request in repository.requests) {
        unawaited(request.close());
      }
      await _frames(tester);
      controller.dispose();
      GeolocatorPlatform.instance = previousLocation;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  _screenTest(
    'shows hinted title, interactive stops and loading ETA before realtime',
    (tester, repository) async {
      expect(find.text('標題提示'), findsOneWidget);
      expect(find.text('正在載入站牌'), findsWidgets);
      final request = repository.requests.single;
      request.add(
        RouteDetailUpdate(detail: _detail(), phase: RouteDetailPhase.stops),
      );
      await _frames(tester);
      expect(find.text('返程站1'), findsOneWidget);
      expect(find.text('載入中'), findsWidgets);
      expect(find.byTooltip('公車地圖'), findsNothing);
      await tester.tap(find.text('去程'));
      await _frames(tester);
      expect(find.text('去程站1'), findsOneWidget);
      request.add(
        RouteDetailUpdate(
          detail: _detail(eta: 120),
          phase: RouteDetailPhase.realtime,
        ),
      );
      await _frames(tester);
      expect(find.text('載入中'), findsNothing);
      expect(find.byTooltip('公車地圖'), findsOneWidget);
      expect(find.text('去程站1'), findsOneWidget);
      expect(find.textContaining('秒後更新'), findsOneWidget);
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, -250));
      await _frames(tester);
      final positions = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .map((s) => s.position.pixels)
          .toList();
      request.add(
        RouteDetailUpdate(
          detail: _detail(eta: 60, family: ['TPE500', 'TPE501']),
          phase: RouteDetailPhase.family,
        ),
      );
      await _frames(tester);
      expect(
        tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .map((s) => s.position.pixels)
            .toList(),
        positions,
      );
    },
  );

  _screenTest(
    'failed realtime retains stops and retry rejects late previous results',
    (tester, repository) async {
      final first = repository.requests.single;
      first.add(
        RouteDetailUpdate(detail: _detail(), phase: RouteDetailPhase.stops),
      );
      first.add(
        RouteDetailUpdate(detail: _detail(), phase: RouteDetailPhase.realtime),
      );
      await _frames(tester);
      expect(find.text('返程站1'), findsOneWidget);
      expect(find.text('載入中'), findsNothing);
      expect(find.text('重試'), findsOneWidget);
      await tester.tap(find.text('重試'));
      await _frames(tester);
      expect(repository.requests, hasLength(2));
      first.add(
        RouteDetailUpdate(
          detail: _detail(eta: 10, name: '過期結果'),
          phase: RouteDetailPhase.family,
        ),
      );
      repository.requests.last.add(
        RouteDetailUpdate(
          detail: _detail(eta: 90),
          phase: RouteDetailPhase.realtime,
        ),
      );
      await _frames(tester);
      expect(find.text('過期結果'), findsNothing);
      expect(find.text('重試'), findsNothing);
    },
  );

  _screenTest(
    'failed refresh keeps recent timestamps but drops data older than 90 seconds',
    (tester, repository) async {
      final first = repository.requests.single;
      final timestamp = DateTime.now().subtract(const Duration(seconds: 30));
      first.add(
        RouteDetailUpdate(
          detail: _detail(eta: 120, updatedAt: timestamp),
          phase: RouteDetailPhase.realtime,
        ),
      );
      await _frames(tester);
      // An error offers retry while leaving the previously displayed snapshot.
      first.addError(Exception('offline'));
      await _frames(tester);
      await tester.tap(find.text('重試'));
      await _frames(tester);
      repository.requests.last.add(
        RouteDetailUpdate(detail: _detail(), phase: RouteDetailPhase.realtime),
      );
      await _frames(tester);
      var stop = tester.widgetList<EtaBadge>(find.byType(EtaBadge)).first.stop;
      expect(stop.sec, 120);
      expect(stop.t, timestamp.toIso8601String());
      // The new successful snapshot is already stale, then the next refresh fails.
      final oldTimestamp = DateTime.now().subtract(const Duration(seconds: 91));
      repository.requests.last.add(
        RouteDetailUpdate(
          detail: _detail(eta: 120, updatedAt: oldTimestamp),
          phase: RouteDetailPhase.family,
        ),
      );
      repository.requests.last.addError(Exception('offline'));
      await _frames(tester);
      await tester.tap(find.text('重試'));
      await _frames(tester);
      repository.requests.last.add(
        RouteDetailUpdate(detail: _detail(), phase: RouteDetailPhase.realtime),
      );
      await _frames(tester);
      stop = tester.widgetList<EtaBadge>(find.byType(EtaBadge)).first.stop;
      expect(stop.sec, isNull);
      expect(stop.t, isNull);
    },
  );

  _screenTest('leaving before the first response ignores late updates', (
    tester,
    repository,
  ) async {
    final first = repository.requests.single;
    await tester.pumpWidget(const SizedBox.shrink());
    first.add(
      RouteDetailUpdate(detail: _detail(), phase: RouteDetailPhase.stops),
    );
    await _frames(tester);
    expect(tester.takeException(), isNull);
    expect(repository.requests, hasLength(1));
  });
}
