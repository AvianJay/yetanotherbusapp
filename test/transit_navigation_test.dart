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
import 'package:taiwanbus_flutter/screens/main_transit_shell.dart';
import 'package:taiwanbus_flutter/widgets/transit_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('transit destinations use the canonical navigation order', () {
    expect(
      kTransitModeDestinations.map((destination) => destination.mode),
      orderedEquals(const [
        TransitMode.bus,
        TransitMode.metro,
        TransitMode.thsr,
        TransitMode.tra,
        TransitMode.youbike,
      ]),
    );
    expect(
      kTransitModeDestinations.map((destination) => destination.label),
      orderedEquals(const ['公車', '捷運', '高鐵', '台鐵', 'YouBike']),
    );
  });

  testWidgets(
    'mobile navigation stays below the scrollable page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = await _buildController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 500),
              padding: EdgeInsets.only(bottom: 24),
            ),
            child: AppControllerScope(
              controller: controller,
              child: const MainTransitShell(),
            ),
          ),
        ),
      );
      await tester.pump();

      final navigation = find.byType(NavigationBar);
      final navigationSafeArea = find.ancestor(
        of: navigation,
        matching: find.byType(SafeArea),
      );
      expect(navigation, findsOneWidget);
      expect(navigationSafeArea, findsOneWidget);
      expect(tester.getSize(navigation).height, 64);
      expect(tester.getBottomLeft(navigation).dy, 476);
      expect(tester.getBottomLeft(navigationSafeArea).dy, 500);
      expect(
        find.ancestor(of: navigation, matching: find.byType(ListView)),
        findsNothing,
      );

      final navigationTop = tester.getTopLeft(navigation);
      final firstCardTop = tester.getTopLeft(find.text('搜尋路線'));
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('搜尋路線')).dy,
        lessThan(firstCardTop.dy),
      );
      expect(tester.getTopLeft(navigation), navigationTop);

      await tester.tap(find.text('捷運'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.getTopLeft(find.byType(NavigationBar)), navigationTop);
    },
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
  await controller.updateDesktopDiscordPresenceEnabled(false);
  return controller;
}
