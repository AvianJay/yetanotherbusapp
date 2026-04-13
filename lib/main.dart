import 'package:flutter/material.dart';

import 'app/bus_app.dart';
import 'core/app_controller.dart';
import 'core/app_build_info.dart';
import 'core/app_launch_service.dart';
import 'core/app_update_installer.dart';
import 'core/app_update_service.dart';
import 'core/bus_repository.dart';
import 'core/database_factory.dart';
import 'core/storage_service.dart';
import 'widgets/startup_splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<AppController> _controllerFuture = _initializeController();

  Future<AppController> _initializeController() async {
    await AppLaunchService.instance.initialize();
    final buildInfo = await AppBuildInfo.load();

    final controller = AppController(
      repository: BusRepository(),
      storage: StorageService(),
      buildInfo: buildInfo,
      appUpdateService: AppUpdateService(buildInfo: buildInfo),
      appUpdateInstaller: createAppUpdateInstaller(),
    );
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return BusApp(controller: snapshot.requireData);
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: StartupSplashScreen(
            errorMessage: snapshot.hasError ? '${snapshot.error}' : null,
          ),
        );
      },
    );
  }
}
