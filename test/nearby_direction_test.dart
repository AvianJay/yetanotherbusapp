import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:taiwanbus_flutter/core/app_update_installer.dart';
import 'package:taiwanbus_flutter/core/app_update_service.dart';
import 'package:taiwanbus_flutter/core/auth_service.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/storage_service.dart';
import 'package:taiwanbus_flutter/screens/nearby_screen.dart';

const _latitude = 25.0330;
const _longitude = 121.5654;

/// Two stops that share a name and a route, one per direction — the exact
/// shape issue #47 reports.
List<Map<String, Object?>> _nearbyPayload({
  required String outboundPathName,
  required String inboundPathName,
}) {
  return [
    {
      'routeid': 'TPE0001',
      'pathid': 0,
      'stopid': 'STOP-A',
      'stop_name': '市政府',
      'seq': 2,
      'lat': _latitude + 0.0001,
      'lon': _longitude,
      'distance': 20.0,
      'route_name': '307',
      'path_name': outboundPathName,
      'city_code': 'TPE',
    },
    {
      'routeid': 'TPE0001',
      'pathid': 1,
      'stopid': 'STOP-B',
      'stop_name': '市政府',
      'seq': 18,
      'lat': _latitude - 0.0001,
      'lon': _longitude,
      'distance': 30.0,
      'route_name': '307',
      'path_name': inboundPathName,
      'city_code': 'TPE',
    },
  ];
}

/// Enough of the platform interface for [NearbyScreen] to reach the repository.
class _FakeGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    return Position(
      latitude: _latitude,
      longitude: _longitude,
      timestamp: DateTime.utc(2024),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

Future<AppController> _buildController(http.Client client) async {
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

Future<void> _pumpNearbyScreen(
  WidgetTester tester, {
  required String outboundPathName,
  required String inboundPathName,
}) async {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/stops/nearby')) {
      return http.Response(
        jsonEncode(
          _nearbyPayload(
            outboundPathName: outboundPathName,
            inboundPathName: inboundPathName,
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    // Realtime is irrelevant here; 404 keeps the ETA badges empty.
    return http.Response('{}', 404);
  });

  final controller = await _buildController(client);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: AppControllerScope(
        controller: controller,
        child: const NearbyScreen(),
      ),
    ),
  );

  // pumpAndSettle is useless here: the loading spinner animates forever while
  // the repository does real filesystem work (probing for the city database
  // before falling back to the API), and pumpAndSettle only advances the fake
  // clock — it burns through its timeout in real milliseconds. runAsync gives
  // that I/O actual wall-clock time to finish.
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(Card).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Nearby results never rendered.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // No city database on disk, so fetchNearbyStops throws
  // DatabaseNotReadyException and falls through to the API path the MockClient
  // below serves.
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeolocatorPlatform.instance = _FakeGeolocator();
  });

  testWidgets('nearby rows show the destination of each direction', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpNearbyScreen(
        tester,
        outboundPathName: '往撫遠街',
        inboundPathName: '往捷運松山站',
      );

      // One card for the shared stop name, two rows inside it.
      expect(find.text('市政府'), findsOneWidget);
      expect(find.text('307'), findsNWidgets(2));

      expect(find.text('台北市 · 往撫遠街'), findsOneWidget);
      expect(find.text('台北市 · 往捷運松山站'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('nearby rows fall back to 去程/返程 without a path name', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpNearbyScreen(
        tester,
        outboundPathName: '',
        inboundPathName: 'Unknown',
      );

      expect(find.text('307'), findsNWidgets(2));
      expect(find.text('台北市 · 去程'), findsOneWidget);
      expect(find.text('台北市 · 返程'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('circular route repeating one destination still disambiguates', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpNearbyScreen(
        tester,
        outboundPathName: '往捷運麟光新村站',
        inboundPathName: '往捷運麟光新村站',
      );

      expect(find.text('台北市 · 往捷運麟光新村站（去程）'), findsOneWidget);
      expect(find.text('台北市 · 往捷運麟光新村站（返程）'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
