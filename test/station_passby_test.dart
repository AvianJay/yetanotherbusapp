import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:taiwanbus_flutter/screens/station_detail_screen.dart';

Map<String, Object?> _stationPayload() => {
  'city': 'TPE',
  'station_id': 'TPE-STATION-1',
  'station_name': '市政府',
  'station_name_en': 'City Hall',
  'lat': 25.04,
  'lon': 121.56,
  'sides': [
    {
      'side_id': 'TPE-STOP-A',
      'label': 'A',
      'direction': '往台北車站',
      'stop_uid': 'TPE-STOP-A',
      'stopid': 'STOP-A',
      'lat': 25.041,
      'lon': 121.561,
      'routes': [
        {
          'routeid': 'TPE0001',
          'route_name': '307',
          'route_name_en': '307',
          'pathid': 0,
          'path_name': '往撫遠街',
          'path_name_en': 'Outbound',
          'seq': 2,
          'stopid': 'STOP-A',
          'eta': 120,
          'message': '',
          'updated_at': 1000,
          'buses': <Object?>[],
          'etas': <Object?>[],
        },
      ],
    },
    {
      'side_id': 'TPE-STOP-B',
      'label': 'B',
      'direction': '往信義區',
      'stop_uid': 'TPE-STOP-B',
      'stopid': 'STOP-B',
      'lat': 25.039,
      'lon': 121.559,
      'routes': [
        {
          'routeid': 'TPE0002',
          'route_name': '藍1',
          'route_name_en': 'BL1',
          'pathid': 1,
          'path_name': '往南港',
          'path_name_en': 'Nangang',
          'seq': 5,
          'stopid': 'STOP-B',
          'eta': 60,
          'message': '',
          'updated_at': 1000,
          'buses': <Object?>[],
          'etas': <Object?>[],
        },
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('resolveStation sends authority and raw stop ID', () async {
    Uri? requestedUri;
    final repository = BusRepository(
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode(_stationPayload()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final station = await repository.resolveStation(
      'STOP-B',
      provider: BusProvider.tpe,
    );

    expect(requestedUri?.path, '/api/v1/stations/resolve');
    expect(requestedUri?.queryParameters, {'city': 'TPE', 'stopid': 'STOP-B'});
    expect(station?.stationId, 'TPE-STATION-1');
    expect(station?.sides.map((side) => side.label), ['A', 'B']);
    expect(station?.nextArrival?.sideLabel, 'B');
    expect(station?.nextArrival?.result.route.routeName, '藍1');
    expect(station?.nextArrival?.result.matchedStop.sec, 60);
  });

  test('getStationPassby rejects cross-city response', () async {
    final payload = _stationPayload()..['city'] = 'KHH';
    final repository = BusRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final station = await repository.getStationPassby(
      'TPE-STATION-1',
      provider: BusProvider.tpe,
    );

    expect(station, isNull);
  });

  test('station lookup returns null on 404', () async {
    final repository = BusRepository(
      client: MockClient((_) async => http.Response('{}', 404)),
    );

    expect(
      await repository.resolveStation('UNKNOWN', provider: BusProvider.tpe),
      isNull,
    );
  });

  testWidgets('station detail renders routes for every stable side', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode(_stationPayload()),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    const buildInfo = AppBuildInfo(
      version: '1.0.0',
      buildNumber: '1',
      gitSha: 'test',
      defaultUpdateChannel: AppUpdateChannel.release,
    );
    final controller = AppController(
      repository: BusRepository(client: client),
      storage: StorageService(),
      analytics: await AppAnalytics.initialize(),
      buildInfo: buildInfo,
      appUpdateService: AppUpdateService(buildInfo: buildInfo, client: client),
      appUpdateInstaller: createAppUpdateInstaller(),
      authService: AuthService(),
      accountSyncService: AccountSyncService(client: client),
    );
    addTearDown(controller.dispose);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AppControllerScope(
            controller: controller,
            child: const StationDetailScreen(
              provider: BusProvider.tpe,
              stationId: 'TPE-STATION-1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('市政府'), findsOneWidget);
      expect(find.text('A · 往台北車站'), findsOneWidget);
      expect(find.text('B · 往信義區'), findsOneWidget);
      expect(find.text('307'), findsOneWidget);

      await tester.tap(find.text('B · 往信義區'));
      await tester.pumpAndSettle();

      expect(find.text('藍1'), findsOneWidget);
      expect(find.text('往南港'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
