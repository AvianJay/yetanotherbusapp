import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:taiwanbus_flutter/screens/search_screen.dart';
import 'package:taiwanbus_flutter/widgets/route_search_keypad.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mobile defaults to the route keypad and can switch input modes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final controller = await _createController();
      addTearDown(controller.dispose);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pumpSearchScreen(tester, controller, const Size(320, 568));

        expect(find.byType(RouteSearchKeypad), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('route-keypad-text')));
        await tester.pump();

        expect(find.byType(RouteSearchKeypad), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        expect(find.byKey(const ValueKey('show-route-keypad')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('show-route-keypad')));
        await tester.pump();

        expect(find.byType(RouteSearchKeypad), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );

        await tester.tap(find.byKey(const ValueKey('route-keypad-collapse')));
        await tester.pump();

        expect(find.byType(RouteSearchKeypad), findsNothing);
        expect(find.byKey(const ValueKey('show-route-keypad')), findsOneWidget);

        await tester.tap(find.byType(TextField));
        await tester.pump();

        expect(find.byType(RouteSearchKeypad), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('desktop keeps the normal editable search field', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final controller = await _createController();
    addTearDown(controller.dispose);
    try {
      await _pumpSearchScreen(tester, controller, const Size(800, 600));

      expect(find.byType(RouteSearchKeypad), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(find.byKey(const ValueKey('show-route-keypad')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<AppController> _createController() async {
  const buildInfo = AppBuildInfo(
    version: '1.0.0',
    buildNumber: '1',
    gitSha: 'test',
    defaultUpdateChannel: AppUpdateChannel.release,
  );
  final client = MockClient((_) async => http.Response('{}', 200));
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

Future<void> _pumpSearchScreen(
  WidgetTester tester,
  AppController controller,
  Size size,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: AppControllerScope(
        controller: controller,
        child: const SearchScreen(),
      ),
    ),
  );
}
