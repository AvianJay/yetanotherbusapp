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
import 'package:taiwanbus_flutter/widgets/background_image_wrapper.dart';
import 'package:taiwanbus_flutter/screens/main_transit_shell.dart';
import 'package:taiwanbus_flutter/widgets/transit_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    controller = await _buildController();
  });
  tearDown(() => controller.dispose());

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

  testWidgets('mobile navigation stays below the scrollable page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 500),
            padding: EdgeInsets.only(top: 32, bottom: 24),
            viewPadding: EdgeInsets.only(top: 32, bottom: 24),
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
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      ),
    );
    final initialScrollOffset = scrollable.position.pixels;
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(initialScrollOffset));
    expect(tester.getTopLeft(navigation), navigationTop);

    await tester.tap(find.text('捷運'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.getTopLeft(find.byType(NavigationBar)), navigationTop);
  });

  for (final layout in [
    (
      name: 'no system insets',
      size: const Size(390, 600),
      padding: EdgeInsets.zero,
    ),
    (
      name: 'Android status and gesture bars',
      size: const Size(390, 600),
      padding: const EdgeInsets.only(top: 32, bottom: 24),
    ),
    (
      name: 'portrait display cutout',
      size: const Size(390, 600),
      padding: const EdgeInsets.only(top: 59, bottom: 34),
    ),
    (
      name: 'landscape display cutout',
      size: const Size(844, 390),
      padding: const EdgeInsets.fromLTRB(44, 0, 24, 21),
    ),
  ]) {
    testWidgets('all transit modes keep a 64dp bar with ${layout.name}', (
      tester,
    ) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: layout.size,
              padding: layout.padding,
              viewPadding: layout.padding,
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
      for (var index = 0; index < kTransitModeDestinations.length; index++) {
        await tester.tap(
          find.descendant(
            of: navigation,
            matching: find.text(kTransitModeDestinations[index].label),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(navigation, findsOneWidget);
        expect(tester.widget<NavigationBar>(navigation).selectedIndex, index);
        expect(
          tester.getRect(navigation),
          Rect.fromLTWH(
            layout.padding.left,
            layout.size.height - layout.padding.bottom - 64,
            layout.size.width - layout.padding.horizontal,
            64,
          ),
        );
        final page = find.byType(Scaffold);
        expect(page, findsOneWidget);
        expect(tester.getBottomLeft(page).dy, tester.getTopLeft(navigation).dy);
        expect(
          MediaQuery.paddingOf(tester.element(page)).top,
          layout.padding.top,
        );
        expect(MediaQuery.paddingOf(tester.element(page)).bottom, 0);

        // The navigation surface covers the full width and gesture inset,
        // independently of each page's cards, tint and background image.
        final surface = find
            .ancestor(of: navigation, matching: find.byType(Material))
            .first;
        expect(
          tester.getRect(surface),
          Rect.fromLTWH(
            0,
            layout.size.height - layout.padding.bottom - 64,
            layout.size.width,
            64 + layout.padding.bottom,
          ),
        );
        final material = tester.widget<Material>(surface);
        final colors = Theme.of(tester.element(navigation)).colorScheme;
        expect(material.color, colors.surfaceContainer);
        expect(
          material.shape,
          Border(top: BorderSide(color: colors.outlineVariant)),
        );
        for (final type in [ListView, Card, BackgroundImageWrapper]) {
          expect(
            find.ancestor(of: navigation, matching: find.byType(type)),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
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
