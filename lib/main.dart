import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app/bus_app.dart';
import 'core/announcement_push_service.dart';
import 'core/account_sync_service.dart';
import 'core/app_controller.dart';
import 'core/app_analytics.dart';
import 'core/app_build_info.dart';
import 'core/app_launch_service.dart';
import 'core/app_update_installer.dart';
import 'core/app_update_service.dart';
import 'core/api_user_agent.dart';
import 'core/auth_service.dart';
import 'core/bus_repository.dart';
import 'core/database_factory.dart';
import 'core/friendly_error.dart';
import 'core/storage_service.dart';
import 'core/ad_service.dart';

Future<void> main(List<String> args) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await configureDatabaseFactory();
  try {
    await AppLaunchService.instance.initialize(initialArguments: args);
    final analytics = await AppAnalytics.initialize();
    final buildInfo = await AppBuildInfo.load();
    ApiUserAgent.configure(buildInfo);

    final controller = AppController(
      repository: BusRepository(),
      storage: StorageService(),
      analytics: analytics,
      buildInfo: buildInfo,
      appUpdateService: AppUpdateService(buildInfo: buildInfo),
      appUpdateInstaller: createAppUpdateInstaller(),
      authService: AuthService(),
      accountSyncService: AccountSyncService(),
    );
    await controller.initialize();
    unawaited(AdService.instance.initialize());
    runApp(BusApp(controller: controller, analytics: analytics));
    unawaited(AnnouncementPushService.instance.initialize());
  } catch (error) {
    runApp(
      _StartupErrorApp(
        message: friendlyErrorMessage(
          error,
          fallback: '啟動時發生未預期的錯誤，請稍後再試。',
        ),
        detail: '$error',
      ),
    );
  } finally {
    FlutterNativeSplash.remove();
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message, required this.detail});

  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '啟動失敗',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  if (detail != message) ...[
                    const SizedBox(height: 16),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
