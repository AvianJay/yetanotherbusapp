import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:taiwanbus_flutter/widgets/app_update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('nightly dialog shows short SHAs and download progress', (
    tester,
  ) async {
    const currentSha = 'abcdef0123456789abcdef0123456789abcdef01';
    const latestSha = '1234567890abcdef1234567890abcdef12345678';
    final installer = _ProgressInstaller();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final AppController controller;
    try {
      controller = await _buildController(installer);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    addTearDown(controller.dispose);

    const update = AppUpdateInfo(
      channel: AppUpdateChannel.nightly,
      currentVersionLabel: currentSha,
      latestVersionLabel: latestSha,
      title: 'Nightly 更新',
      summary: 'Nightly 建置 1234567 已可下載。',
      downloadUrl:
          'https://example.com/YABus-nightly-$latestSha-windows-x64-setup.exe',
      packageFormat: AppUpdatePackageFormat.exe,
      detailsUrl:
          'https://github.com/YetAnotherBusDeveloper/yetanotherbusapp/compare/$currentSha...$latestSha',
    );
    const result = AppUpdateCheckResult(
      status: AppUpdateStatus.updateAvailable,
      message: '找到新的 nightly commit',
      update: update,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAppUpdateDialog(
                context,
                controller: controller,
                result: result,
              ),
              child: const Text('顯示更新'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('顯示更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Nightly 更新'), findsOneWidget);
    expect(find.text('Nightly 建置 1234567 已可下載。'), findsOneWidget);
    expect(find.text('目前版本：abcdef0'), findsOneWidget);
    expect(find.text('最新版本：1234567'), findsOneWidget);
    expect(find.text('複製下載連結'), findsOneWidget);
    expect(find.text('稍後'), findsOneWidget);
    expect(find.text('下載並安裝'), findsOneWidget);

    final visibleText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    expect(visibleText, isNot(contains(currentSha)));
    expect(visibleText, isNot(contains(latestSha)));
    expect(visibleText, contains('abcdef0...1234567'));

    await tester.tap(find.text('下載並安裝'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('下載更新中…'), findsOneWidget);
    expect(installer.lastUpdate, same(update));

    installer.complete(
      const AppUpdateInstallResult(
        status: AppUpdateInstallStatus.failed,
        message: '測試下載失敗',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('測試下載失敗'), findsOneWidget);
  });
}

class _ProgressInstaller extends AppUpdateInstaller {
  final _completer = Completer<AppUpdateInstallResult>();
  AppUpdateInfo? lastUpdate;

  @override
  bool get supportsInAppInstall => true;

  @override
  Future<void> exitAfterLaunchingInstaller() async {}

  @override
  Future<AppUpdateInstallResult> installUpdate(
    AppUpdateInfo update, {
    AppUpdateInstallProgressCallback? onProgress,
  }) {
    lastUpdate = update;
    onProgress?.call(0.5, '下載更新中…');
    return _completer.future;
  }

  void complete(AppUpdateInstallResult result) {
    _completer.complete(result);
  }
}

Future<AppController> _buildController(AppUpdateInstaller installer) async {
  const buildInfo = AppBuildInfo(
    version: '1.0.0',
    buildNumber: '1',
    gitSha: 'abcdef0123456789abcdef0123456789abcdef01',
    defaultUpdateChannel: AppUpdateChannel.nightly,
  );
  final client = MockClient((_) async => http.Response('{}', 200));
  return AppController(
    repository: BusRepository(client: client),
    storage: StorageService(),
    analytics: await AppAnalytics.initialize(),
    buildInfo: buildInfo,
    appUpdateService: AppUpdateService(buildInfo: buildInfo, client: client),
    appUpdateInstaller: installer,
    authService: AuthService(),
    accountSyncService: AccountSyncService(client: client),
  );
}
