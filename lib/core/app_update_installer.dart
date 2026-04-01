import 'app_update_installer_stub.dart'
    if (dart.library.io) 'app_update_installer_io.dart';
import 'app_update_service.dart';

typedef AppUpdateInstallProgressCallback =
    void Function(double? progress, String message);

enum AppUpdateInstallStatus {
  unsupported,
  permissionRequired,
  launchedInstaller,
  failed,
}

class AppUpdateInstallResult {
  const AppUpdateInstallResult({required this.status, required this.message});

  final AppUpdateInstallStatus status;
  final String message;

  bool get didLaunchInstaller =>
      status == AppUpdateInstallStatus.launchedInstaller;
}

abstract class AppUpdateInstaller {
  const AppUpdateInstaller();

  bool get supportsInAppInstall;

  Future<AppUpdateInstallResult> installUpdate(
    AppUpdateInfo update, {
    AppUpdateInstallProgressCallback? onProgress,
  });
}

AppUpdateInstaller createAppUpdateInstaller() =>
    createPlatformAppUpdateInstaller();
