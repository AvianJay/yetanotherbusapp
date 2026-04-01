import 'app_update_installer.dart';
import 'app_update_service.dart';

class StubAppUpdateInstaller extends AppUpdateInstaller {
  const StubAppUpdateInstaller();

  @override
  bool get supportsInAppInstall => false;

  @override
  Future<AppUpdateInstallResult> installUpdate(
    AppUpdateInfo update, {
    AppUpdateInstallProgressCallback? onProgress,
  }) async {
    return const AppUpdateInstallResult(
      status: AppUpdateInstallStatus.unsupported,
      message: '這個平台不支援 app 內安裝更新。',
    );
  }
}

AppUpdateInstaller createPlatformAppUpdateInstaller() =>
    const StubAppUpdateInstaller();
