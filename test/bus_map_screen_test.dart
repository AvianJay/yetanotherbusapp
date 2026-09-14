import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
import 'package:taiwanbus_flutter/screens/bus_map_screen.dart';
import 'package:taiwanbus_flutter/widgets/bus_map_markers.dart';

/// The map is mostly about restraint: showing buses it can explain, hiding the
/// ones a filter excludes, and above all not polling while nobody is looking.

const _snapshotBody = {
  'city': 'Taipei',
  'prefix': 'TPE',
  'updated_at': 1757145600,
  'ttl': 15,
  'stale': false,
  'truncated': false,
  'buses': [
    {
      'id': 'KKA-1234',
      'routeid': 'TPE101320',
      'route_uid': 'TPE10132',
      'direction': 0,
      'lat': 25.0330,
      'lon': 121.5654,
      'speed': 20,
      'azimuth': 90,
      'status': 0,
      'time': 1757145590,
    },
    {
      'id': 'EAL-0562',
      'routeid': null,
      'route_uid': 'TPE10231',
      'direction': 0,
      'lat': 25.0340,
      'lon': 121.5664,
      'speed': 0,
      'azimuth': 180,
      'status': 0,
      'time': 1757145592,
    },
  ],
  'routes': {
    'TPE101320': {'name': '234', 'route_uid': 'TPE10132'},
  },
  'families': {
    'TPE10231': {
      'name': '民權幹線',
      'stops_routeid': 'TPE10231',
      'geometry_routeid': 'TPE10231',
      'routeids': ['TPE10231', 'TPE162593'],
    },
  },
};

const _stopsBody = {
  'routeid': 'TPE101320',
  'name': '234',
  'paths': [
    {
      'pathid': 0,
      'name': 'Outbound',
      'stops': [
        {
          'stopid': 'S1',
          'seq': 1,
          'name': '西門',
          'lat': 25.0331,
          'lon': 121.5650,
        },
        {
          'stopid': 'S2',
          'seq': 2,
          'name': '北門',
          'lat': 25.0345,
          'lon': 121.5660,
        },
      ],
    },
  ],
};

class _FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;
}

MockClient _failingClient(_RequestLog log, int status) {
  return MockClient((request) async {
    log.paths.add(request.url.path);
    return http.Response('{"detail":"nope"}', status);
  });
}

/// Counts what the screen actually asks the network for.
class _RequestLog {
  final List<String> paths = [];

  int count(String needle) =>
      paths.where((path) => path.contains(needle)).length;
}

MockClient _mockClient(_RequestLog log, {int ttl = 15}) {
  return MockClient((request) async {
    final path = request.url.path;
    log.paths.add(path);
    if (path.endsWith('/api/v1/cities/TPE/buses')) {
      return http.Response(
        jsonEncode({..._snapshotBody, 'ttl': ttl}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (path.contains('/paths/0/points')) {
      return http.Response(
        jsonEncode({'routeid': 'TPE101320', 'pathid': 0, 'polyline': ''}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (path.endsWith('/stops')) {
      return http.Response(
        jsonEncode(_stopsBody),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response('{}', 404);
  });
}

Future<AppController> _createController(http.Client client) async {
  const buildInfo = AppBuildInfo(
    version: '1.0.0',
    buildNumber: '1',
    gitSha: 'test',
    defaultUpdateChannel: AppUpdateChannel.release,
  );
  return AppController(
    repository: BusRepository(client: client),
    storage: StorageService(),
    analytics: await AppAnalytics.initialize(),
    buildInfo: buildInfo,
    appUpdateService: AppUpdateService(buildInfo: buildInfo, client: client),
    appUpdateInstaller: createAppUpdateInstaller(),
    authService: AuthService(),
    accountSyncService: AccountSyncService(client: client),
  );
}

/// Pumps the map. [zoom] decides whether buses draw individually (the default
/// here) or collapse into clustered counts, as they do on a whole-city view.
/// [textScale] mimics a rider who has turned the display size up.
Future<void> _pumpMap(
  WidgetTester tester,
  AppController controller, {
  double zoom = 15,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [appRouteObserver],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: AppControllerScope(
          controller: controller,
          child: BusMapScreen(
            initialProvider: BusProvider.tpe,
            initialZoom: zoom,
            tileProvider: _NoopTileProvider(),
          ),
        ),
      ),
    ),
  );
}

/// Taps the bus the fixture names '234' and waits for its sheet.
Future<void> _selectTheResolvedBus(WidgetTester tester, _RequestLog log) async {
  final marker = find.byWidgetPredicate(
    (widget) => widget is BusMapBusMarker && widget.label == '234 KKA-1234',
  );
  await tester.tap(marker, warnIfMissed: false);
  await _pumpUntil(
    tester,
    () => find.text('路線詳情').evaluate().isNotEmpty,
    reason: 'selection sheet never appeared',
  );
  // The stops arrive a moment after the sheet; wait for them so callers can
  // rely on the route's pins being on the map.
  await _pumpUntil(
    tester,
    () => log.count('/stops') == 1,
    reason: 'stops were never requested for the tapped route',
  );
}

/// Renders a blank tile so the test never reaches for the network.
class _NoopTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(_transparentPng));
}

const _transparentPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

/// Drives animations forward a fixed amount. `pumpAndSettle` cannot be used on
/// this screen: the refresh progress bar animates for as long as it is open.
Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 24,
  Duration step = const Duration(milliseconds: 40),
}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(step);
  }
}

/// Let real time pass and repaint, without waiting for animations that never
/// end (the refresh progress bar runs for as long as the screen is open).
Future<void> _advance(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pump();
  await tester.pump();
}

/// The screen loads asynchronously, so settle by polling rather than
/// pumpAndSettle, which never returns while the progress bar animates.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String reason = 'condition never became true',
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (condition()) {
      return;
    }
  }
  fail(reason);
}

/// Same harness, but the server refuses every request.
void _failingMapTest(
  String description,
  int status,
  Future<void> Function(WidgetTester tester, AppController controller) body,
) {
  testWidgets(description, (tester) async {
    SharedPreferences.setMockInitialValues({});
    GeolocatorPlatform.instance = _FakeGeolocator();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final controller = await _createController(
      _failingClient(_RequestLog(), status),
    );
    try {
      await body(tester, controller);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// Runs [body] with the map rendered on the flutter_map backend.
///
/// The platform override has to be cleared inside the test body: the framework
/// asserts on it before tearDown gets a turn.
void _mapTest(
  String description,
  Future<void> Function(
    WidgetTester tester,
    _RequestLog log,
    AppController controller,
  )
  body, {
  int ttl = 15,
}) {
  testWidgets(description, (tester) async {
    SharedPreferences.setMockInitialValues({});
    GeolocatorPlatform.instance = _FakeGeolocator();
    // Windows has no Google Maps, so the flutter_map branch renders.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final log = _RequestLog();
    final controller = await _createController(_mockClient(log, ttl: ttl));
    try {
      await body(tester, log, controller);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  _mapTest('draws every bus the city feed returned', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
      reason: 'bus markers never rendered',
    );

    expect(find.byType(BusMapBusMarker), findsNWidgets(2));
    expect(log.count('/cities/TPE/buses'), 1);
  });

  _mapTest('a bus the feed could not pin down is still named', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
    );

    final labels = tester
        .widgetList<BusMapBusMarker>(find.byType(BusMapBusMarker))
        .map((marker) => marker.label)
        .toList();

    expect(labels, contains('234 KKA-1234'));
    expect(labels, contains('民權幹線 EAL-0562'));
  });

  _mapTest('favourites-only keeps a bus favourited by any family member', (
    tester,
    log,
    controller,
  ) async {
    // A 區間 variant, not the trunk the bus is reported under.
    await controller.addFavoriteGroup('路線', kind: FavoriteGroupKind.route);
    await controller.addFavoriteItem(
      const FavoriteRoute(
        provider: BusProvider.tpe,
        routeKey: 1,
        routeId: 'TPE162593',
        routeName: '民權幹線去程半',
      ),
      groupName: '路線',
    );

    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
    );

    await tester.tap(find.byTooltip('只看最愛路線'));
    await tester.pump();

    final labels = tester
        .widgetList<BusMapBusMarker>(find.byType(BusMapBusMarker))
        .map((marker) => marker.label)
        .toList();
    expect(labels, ['民權幹線 EAL-0562']);
  });

  _mapTest('the name filter narrows to one route', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
    );

    await tester.tap(find.byTooltip('篩選路線'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '234');
    await tester.pump();

    expect(find.byType(BusMapBusMarker), findsOneWidget);
  });

  _mapTest('tapping a bus loads exactly one route line and stop list', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
    );

    await _selectTheResolvedBus(tester, log);

    // Exactly one of each: a tap must not fan out into a request per bus.
    expect(log.count('/points'), 1);
    expect(log.count('/stops'), 1);
    expect(find.text('顯示整條路線'), findsOneWidget);
    // On a phone-sized viewport the stops are map pins, not a list.
    expect(find.byTooltip('西門'), findsOneWidget);
  });

  _mapTest('polling stops behind another screen and resumes on return', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().isNotEmpty,
    );
    final afterLoad = log.count('/cities/TPE/buses');

    // Something else takes the screen: the map must go quiet.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('別的頁')),
      ),
    );
    // Not pumpAndSettle: the refresh progress bar animates forever, so it
    // would never settle. Wait past the repository's own short cache too, so
    // that a resumed poll would have to reach the network to be counted.
    await _advance(tester, const Duration(seconds: 4));

    expect(
      log.count('/cities/TPE/buses'),
      afterLoad,
      reason: 'the map kept polling while another screen was on top',
    );

    navigator.pop();
    await _advance(tester, const Duration(milliseconds: 400));
    await _pumpUntil(
      tester,
      () => log.count('/cities/TPE/buses') > afterLoad,
      reason: 'polling never resumed after returning to the map',
    );
  });

  _failingMapTest(
    'a failing server offers a retry rather than a blank map',
    500,
    (tester, controller) async {
      await _pumpMap(tester, controller);
      await _pumpUntil(
        tester,
        () => find.byIcon(Icons.cloud_off_rounded).evaluate().isNotEmpty,
        reason: 'no error chip appeared',
      );

      // The map itself is still there to pan around.
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    },
  );

  _failingMapTest(
    'a server without the endpoint says so instead of erroring',
    404,
    (tester, controller) async {
      await _pumpMap(tester, controller);
      await _pumpUntil(
        tester,
        () => find.text('此縣市暫不支援全公車地圖').evaluate().isNotEmpty,
        reason: 'unsupported notice never appeared',
      );

      // Not an error: the city switcher is still the way out.
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
      expect(find.byTooltip('切換縣市'), findsOneWidget);
    },
  );

  _mapTest('zoomed out the buses collapse into count bubbles', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller, zoom: 11);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapClusterMarker).evaluate().isNotEmpty,
      reason: 'buses never clustered at a whole-city zoom',
    );

    expect(find.byType(BusMapClusterMarker), findsWidgets);
    expect(find.byType(BusMapBusMarker), findsNothing);
    expect(find.text('放大或點圓圈看個別公車'), findsOneWidget);

    // Nothing is lost: the two buses are accounted for in the bubbles.
    final total = tester
        .widgetList<BusMapClusterMarker>(find.byType(BusMapClusterMarker))
        .fold<int>(0, (sum, marker) => sum + marker.count);
    expect(total, 2);
  });

  _mapTest('the selection sheet can be dragged down out of the way', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
    );
    await _selectTheResolvedBus(tester, log);

    final sheet = find.byType(DraggableScrollableSheet);
    expect(sheet, findsOneWidget);
    final restTop = tester.getTopLeft(find.text('路線詳情')).dy;

    // Drag the handle down: the sheet should sink, giving the map back.
    await tester.drag(find.text('234'), const Offset(0, 260));
    await _pumpFrames(tester);

    expect(
      tester.getTopLeft(find.text('234')).dy,
      greaterThan(restTop - 100),
      reason: 'the sheet did not move down when dragged',
    );
    // Still selected: the route line and its stops stay on the map.
    expect(find.byTooltip('西門'), findsOneWidget);
  });

  _mapTest('a rebuild underneath does not disturb the sheet', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
    );
    await _selectTheResolvedBus(tester, log);

    final sheet = find.byType(DraggableScrollableSheet);
    final before = tester.widget<DraggableScrollableSheet>(sheet);

    // Anything that rebuilds the screen — a poll landing, the timestamp
    // ticking over — must hand the sheet the very same snap sizes. The SDK
    // compares that list by identity and re-snaps when it differs, which threw
    // the sheet back to a stop mid-drag.
    await tester.tap(find.byTooltip('只看最愛路線'));
    await tester.pump();
    await tester.tap(find.byTooltip('只看最愛路線'));
    await tester.pump();

    final after = tester.widget<DraggableScrollableSheet>(sheet);
    expect(
      identical(after.snapSizes, before.snapSizes),
      isTrue,
      reason: 'new snapSizes on rebuild makes the SDK re-snap the sheet',
    );
    expect(after.minChildSize, before.minChildSize);
    expect(after.maxChildSize, before.maxChildSize);
  });

  _mapTest('at a large display size the sheet still leaves the map visible', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller, textScale: 2.0);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().length == 2,
    );
    await _selectTheResolvedBus(tester, log);

    // The whole point of the sheet: however big the text, it must not take the
    // screen, because the rider is here to see where the bus is.
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final sheetTop = tester
        .getTopLeft(find.byType(DraggableScrollableSheet))
        .dy;
    final sheetRect = tester.getRect(find.text('234'));

    expect(sheetTop, lessThan(screenHeight));
    expect(
      sheetRect.top,
      greaterThan(screenHeight * 0.25),
      reason: 'the sheet should still start below the top quarter of the map',
    );
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  _mapTest('backgrounding the app stops the polling too', (
    tester,
    log,
    controller,
  ) async {
    await _pumpMap(tester, controller);
    await _pumpUntil(
      tester,
      () => find.byType(BusMapBusMarker).evaluate().isNotEmpty,
    );
    final afterLoad = log.count('/cities/TPE/buses');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _advance(tester, const Duration(milliseconds: 400));

    expect(log.count('/cities/TPE/buses'), afterLoad);
  });
}
