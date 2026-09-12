import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'package:taiwanbus_flutter/screens/favorites_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'reordering moves an item and keeps the others in relative order',
    () async {
      final controller = await _buildController();
      await _seedStops(controller, 'Stops', count: 4);

      await controller.reorderFavoriteItem('Stops', 2, 0);

      expect(_stopIdsIn(controller, 'Stops'), [3, 1, 2, 4]);
    },
  );

  test('reordering downwards places the item at the requested index', () async {
    final controller = await _buildController();
    await _seedStops(controller, 'Stops', count: 4);

    await controller.reorderFavoriteItem('Stops', 0, 3);

    expect(_stopIdsIn(controller, 'Stops'), [2, 3, 4, 1]);
  });

  test('the new order is persisted and survives a reload', () async {
    final controller = await _buildController();
    await _seedStops(controller, 'Stops', count: 3);

    await controller.reorderFavoriteItem('Stops', 2, 0);

    final stored = await StorageService().loadFavoriteGroups();
    final storedIds = stored['Stops']!
        .cast<FavoriteStop>()
        .map((favorite) => favorite.stopId)
        .toList();
    expect(storedIds, [3, 1, 2]);
  });

  test('a mixed group reorders regardless of item type', () async {
    final controller = await _buildController();
    await controller.addFavoriteGroup('Mixed', kind: FavoriteGroupKind.mixed);
    await controller.addFavoriteItem(
      const FavoriteRoute(
        provider: BusProvider.tpe,
        routeKey: 10,
        routeId: 'TPE-10',
        routeName: '307',
      ),
      groupName: 'Mixed',
    );
    await controller.addFavoriteItem(
      const FavoriteStation(
        provider: BusProvider.tpe,
        stationId: 'TPE-STATION',
        stationName: '臺北車站',
      ),
      groupName: 'Mixed',
    );
    await controller.addFavoriteItem(_stop(1), groupName: 'Mixed');

    // Move the 站牌 entry to the front, over a 路線 and an 整站 entry.
    await controller.reorderFavoriteItem('Mixed', 2, 0);

    expect(
      controller.favoritesInGroup('Mixed').map((item) => item.type).toList(),
      [
        FavoriteItemType.boarding,
        FavoriteItemType.route,
        FavoriteItemType.station,
      ],
    );
  });

  test(
    'no-op and out-of-range reorders change nothing and do not notify',
    () async {
      final controller = await _buildController();
      await _seedStops(controller, 'Stops', count: 3);

      var notifications = 0;
      void listener() => notifications += 1;
      controller.addListener(listener);
      addTearDown(() => controller.removeListener(listener));

      await controller.reorderFavoriteItem('Stops', 1, 1);
      await controller.reorderFavoriteItem('Stops', -1, 0);
      await controller.reorderFavoriteItem('Stops', 7, 0);
      await controller.reorderFavoriteItem('Missing group', 0, 1);

      expect(notifications, 0);
      expect(_stopIdsIn(controller, 'Stops'), [1, 2, 3]);

      // A real move still notifies exactly once.
      await controller.reorderFavoriteItem('Stops', 0, 2);
      expect(notifications, 1);
      expect(_stopIdsIn(controller, 'Stops'), [2, 3, 1]);
    },
  );

  test('an out-of-range target index is clamped into the group', () async {
    final controller = await _buildController();
    await _seedStops(controller, 'Stops', count: 3);

    await controller.reorderFavoriteItem('Stops', 0, 99);

    expect(_stopIdsIn(controller, 'Stops'), [2, 3, 1]);
  });

  testWidgets('long-press dragging a card reorders the group', (tester) async {
    try {
      final controller = await _buildController();
      await _seedRoutes(controller, 'Routes');
      await _pumpFavoritesScreen(tester, controller);

      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(_routeNamesIn(controller, 'Routes'), ['A路線', 'B路線', 'C路線']);

      final start = tester.getCenter(find.text('A路線'));
      final delta = tester.getCenter(find.text('B路線')).dy - start.dy;

      final gesture = await tester.startGesture(start);
      // Hold past the long-press threshold so the delayed drag recognizer wins.
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveBy(Offset(0, delta / 2));
      await tester.pump();
      await gesture.moveBy(Offset(0, delta / 2));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_routeNamesIn(controller, 'Routes'), ['B路線', 'A路線', 'C路線']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the sort toggle reveals a drag handle on every card', (
    tester,
  ) async {
    try {
      final controller = await _buildController();
      await _seedRoutes(controller, 'Routes');
      await _pumpFavoritesScreen(tester, controller);

      expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);

      await tester.tap(find.byIcon(Icons.swap_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(3));

      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpFavoritesScreen(
  WidgetTester tester,
  AppController controller,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 900);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: AppControllerScope(
        controller: controller,
        child: const FavoritesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Seeds a 路線 group, which renders straight from the stored reference and so
/// needs no network resolution.
Future<void> _seedRoutes(AppController controller, String groupName) async {
  await controller.addFavoriteGroup(groupName, kind: FavoriteGroupKind.route);
  for (final name in ['A路線', 'B路線', 'C路線']) {
    await controller.addFavoriteItem(
      FavoriteRoute(
        provider: BusProvider.tpe,
        routeKey: name.hashCode,
        routeId: 'TPE-$name',
        routeName: name,
      ),
      groupName: groupName,
    );
  }
}

List<String> _routeNamesIn(AppController controller, String groupName) {
  return controller
      .favoritesInGroup(groupName)
      .cast<FavoriteRoute>()
      .map((favorite) => favorite.routeName)
      .toList();
}

FavoriteStop _stop(int stopId) {
  return FavoriteStop(
    provider: BusProvider.tpe,
    routeKey: 100,
    pathId: 0,
    stopId: stopId,
    routeId: 'TPE-100',
    routeName: '307',
    stopName: '站牌 $stopId',
  );
}

List<int> _stopIdsIn(AppController controller, String groupName) {
  return controller
      .favoritesInGroup(groupName)
      .cast<FavoriteStop>()
      .map((favorite) => favorite.stopId)
      .toList();
}

Future<void> _seedStops(
  AppController controller,
  String groupName, {
  required int count,
}) async {
  await controller.addFavoriteGroup(groupName);
  for (var stopId = 1; stopId <= count; stopId += 1) {
    await controller.addFavoriteItem(_stop(stopId), groupName: groupName);
  }
  expect(
    _stopIdsIn(controller, groupName),
    List<int>.generate(count, (index) => index + 1),
  );
}

Future<AppController> _buildController() async {
  const buildInfo = AppBuildInfo(
    version: '1.0.0',
    buildNumber: '1',
    gitSha: 'test',
    defaultUpdateChannel: AppUpdateChannel.release,
  );
  final client = MockClient((_) async => http.Response('{}', 200));
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
  return controller;
}
