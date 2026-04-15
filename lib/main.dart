import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'app/bus_app.dart';
import 'core/app_controller.dart';
import 'core/app_analytics.dart';
import 'core/app_build_info.dart';
import 'core/app_launch_service.dart';
import 'core/app_update_installer.dart';
import 'core/app_update_service.dart';
import 'core/bus_repository.dart';
import 'core/database_factory.dart';
import 'core/storage_service.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  configureDatabaseFactory();
  try {
    await AppLaunchService.instance.initialize();
    final analytics = await AppAnalytics.initialize();
    final buildInfo = await AppBuildInfo.load();

    final controller = AppController(
      repository: BusRepository(),
      storage: StorageService(),
      buildInfo: buildInfo,
      appUpdateService: AppUpdateService(buildInfo: buildInfo),
      appUpdateInstaller: createAppUpdateInstaller(),
    );
    await controller.initialize();
    runApp(BusApp(controller: controller, analytics: analytics));
  } catch (error) {
    runApp(_StartupErrorApp(error: '$error'));
  } finally {
    FlutterNativeSplash.remove();
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final String error;

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
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
