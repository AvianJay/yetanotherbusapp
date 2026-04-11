import 'package:flutter/widgets.dart';

import 'app/bus_app.dart';
import 'core/app_controller.dart';
import 'core/app_build_info.dart';
import 'core/app_launch_service.dart';
import 'core/app_update_installer.dart';
import 'core/app_update_service.dart';
import 'core/bus_repository.dart';
import 'core/database_factory.dart';
import 'core/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDatabaseFactory();
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

  runApp(BusApp(controller: controller));
}
