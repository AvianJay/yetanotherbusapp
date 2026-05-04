import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_update_installer.dart';
import 'app_update_service.dart';

class IoAppUpdateInstaller extends AppUpdateInstaller {
  const IoAppUpdateInstaller();

  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/update_installer',
  );

  @override
  bool get supportsInAppInstall =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  Future<AppUpdateInstallResult> installUpdate(
    AppUpdateInfo update, {
    AppUpdateInstallProgressCallback? onProgress,
  }) async {
    if (!supportsInAppInstall) {
      return const AppUpdateInstallResult(
        status: AppUpdateInstallStatus.unsupported,
        message: '這個平台不支援 app 內安裝更新。',
      );
    }

    // Desktop platforms: download installer and launch it.
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      return _installDesktopUpdate(update, onProgress: onProgress);
    }

    // Android path below.
    try {
      final canInstall =
          await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
      if (!canInstall) {
        await _channel.invokeMethod<void>('openInstallSettings');
        return const AppUpdateInstallResult(
          status: AppUpdateInstallStatus.permissionRequired,
          message: '請先允許這個 app 安裝未知應用程式，再重新點一次更新。',
        );
      }

      final updateDirectory = await _prepareUpdateDirectory();
      final downloadPath = p.join(
        updateDirectory.path,
        update.packageFormat == AppUpdatePackageFormat.zip
            ? 'update.zip'
            : 'update.apk',
      );
      final downloadFile = File(downloadPath);

      onProgress?.call(0, '下載更新中…');
      await _downloadFile(
        update.downloadUrl,
        downloadFile,
        onProgress: onProgress,
      );

      onProgress?.call(null, '整理安裝檔中…');
      final apkFile = switch (update.packageFormat) {
        AppUpdatePackageFormat.apk => downloadFile,
        AppUpdatePackageFormat.zip => await _extractApk(
          downloadFile,
          updateDirectory,
        ),
        _ => downloadFile,
      };

      onProgress?.call(null, '啟動安裝程式…');
      await _channel.invokeMethod<void>('installApk', {'path': apkFile.path});
      return const AppUpdateInstallResult(
        status: AppUpdateInstallStatus.launchedInstaller,
        message: '安裝程式已啟動。',
      );
    } catch (error) {
      return AppUpdateInstallResult(
        status: AppUpdateInstallStatus.failed,
        message: '下載或安裝更新失敗：$error',
      );
    }
  }

  Future<Directory> _prepareUpdateDirectory() async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'app_update'),
    );
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _downloadFile(
    String url,
    File targetFile, {
    AppUpdateInstallProgressCallback? onProgress,
  }) async {
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }

      final sink = targetFile.openWrite();
      try {
        var received = 0;
        final total = response.contentLength;
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            onProgress?.call(received / total, '下載更新中…');
          } else {
            onProgress?.call(null, '下載更新中…');
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  Future<File> _extractApk(File zipFile, Directory outputDirectory) async {
    final archive = ZipDecoder().decodeBytes(
      await zipFile.readAsBytes(),
      verify: false,
    );
    ArchiveFile? apkEntry;
    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase().endsWith('.apk')) {
        apkEntry = file;
        break;
      }
    }

    if (apkEntry == null) {
      throw const FormatException('nightly 壓縮檔裡找不到 APK。');
    }

    final outputFile = File(
      p.join(outputDirectory.path, p.basename(apkEntry.name)),
    );
    await outputFile.writeAsBytes(apkEntry.content as List<int>, flush: true);
    return outputFile;
  }

  Future<File> _extractPackagedInstaller(
    File zipFile,
    Directory outputDirectory,
    AppUpdatePackageFormat format,
  ) async {
    final archive = ZipDecoder().decodeBytes(
      await zipFile.readAsBytes(),
      verify: false,
    );
    final suffix = switch (format) {
      AppUpdatePackageFormat.exe => '.exe',
      AppUpdatePackageFormat.dmg => '.dmg',
      AppUpdatePackageFormat.deb => '.deb',
      AppUpdatePackageFormat.appImage => '.appimage',
      AppUpdatePackageFormat.apk => '.apk',
      AppUpdatePackageFormat.zip => '.zip',
    };

    ArchiveFile? installerEntry;
    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase().endsWith(suffix)) {
        installerEntry = file;
        break;
      }
    }

    if (installerEntry == null) {
      throw FormatException('nightly 壓縮檔裡找不到 ${suffix.toUpperCase()} 安裝檔。');
    }

    final outputFile = File(
      p.join(outputDirectory.path, p.basename(installerEntry.name)),
    );
    await outputFile.writeAsBytes(
      installerEntry.content as List<int>,
      flush: true,
    );
    return outputFile;
  }

  // ── Desktop update: download installer, then launch it ──────
  Future<AppUpdateInstallResult> _installDesktopUpdate(
    AppUpdateInfo update, {
    AppUpdateInstallProgressCallback? onProgress,
  }) async {
    final updateDirectory = await _prepareUpdateDirectory();

    // Derive local filename from download URL or package format.
    final uriName = p.basename(Uri.parse(update.downloadUrl).path);
    final localName = uriName.isNotEmpty
        ? uriName
        : switch (update.packageFormat) {
            AppUpdatePackageFormat.exe => 'YABus-setup.exe',
            AppUpdatePackageFormat.dmg => 'YABus-update.dmg',
            AppUpdatePackageFormat.deb => 'YABus-update.deb',
            AppUpdatePackageFormat.appImage => 'YABus-update.AppImage',
            _ => 'YABus-update.zip',
          };
    final downloadFile = File(p.join(updateDirectory.path, localName));

    try {
      onProgress?.call(0, '下載更新中…');
      await _downloadFile(
        update.downloadUrl,
        downloadFile,
        onProgress: onProgress,
      );

      var installerFile = downloadFile;
      if (p.extension(downloadFile.path).toLowerCase() == '.zip') {
        onProgress?.call(null, '整理安裝檔中…');
        installerFile = await _extractPackagedInstaller(
          downloadFile,
          updateDirectory,
          update.packageFormat,
        );
      }

      onProgress?.call(null, '準備關閉 App 並啟動安裝程式…');
      await _scheduleDesktopInstallerLaunch(
        installerFile,
        packageFormat: update.packageFormat,
      );

      return const AppUpdateInstallResult(
        status: AppUpdateInstallStatus.launchedInstaller,
        message: '安裝程式已排程。App 關閉後會自動啟動安裝程式。',
      );
    } catch (error) {
      return AppUpdateInstallResult(
        status: AppUpdateInstallStatus.failed,
        message: '下載或安裝更新失敗：$error',
      );
    }
  }

  Future<void> _scheduleDesktopInstallerLaunch(
    File installerFile, {
    required AppUpdatePackageFormat packageFormat,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _scheduleWindowsInstallerLaunch(
        installerFile,
        packageFormat: packageFormat,
      );
      return;
    }

    await _scheduleUnixInstallerLaunch(
      installerFile,
      packageFormat: packageFormat,
    );
  }

  Future<void> _scheduleWindowsInstallerLaunch(
    File installerFile, {
    required AppUpdatePackageFormat packageFormat,
  }) async {
    final installerPath = _quoteForPowerShell(installerFile.path);
    final argumentsClause = packageFormat == AppUpdatePackageFormat.exe
        ? ' -ArgumentList \'/S\''
        : '';
    final script =
        '''
\$pidToWait = $pid
while (Get-Process -Id \$pidToWait -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 300
}
Start-Process -FilePath $installerPath$argumentsClause
''';

    await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-Command',
      script,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> _scheduleUnixInstallerLaunch(
    File installerFile, {
    required AppUpdatePackageFormat packageFormat,
  }) async {
    final script = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => _buildMacInstallerLaunchScript(installerFile),
      TargetPlatform.linux => _buildLinuxInstallerLaunchScript(
        installerFile,
        packageFormat: packageFormat,
      ),
      _ => throw UnsupportedError('Unsupported desktop installer platform.'),
    };

    await Process.start('/bin/sh', [
      '-c',
      script,
    ], mode: ProcessStartMode.detached);
  }

  String _buildMacInstallerLaunchScript(File installerFile) {
    final installerPath = _quoteForShell(installerFile.path);
    return '''
while kill -0 $pid 2>/dev/null; do
  sleep 1
done
open $installerPath
''';
  }

  String _buildLinuxInstallerLaunchScript(
    File installerFile, {
    required AppUpdatePackageFormat packageFormat,
  }) {
    if (packageFormat == AppUpdatePackageFormat.appImage) {
      final currentExecutable = Platform.resolvedExecutable;
      final targetPath = p.join(
        p.dirname(currentExecutable),
        p.basename(currentExecutable),
      );
      final installerPath = _quoteForShell(installerFile.path);
      final quotedTargetPath = _quoteForShell(targetPath);
      return '''
while kill -0 $pid 2>/dev/null; do
  sleep 1
done
mv -f $installerPath $quotedTargetPath
chmod +x $quotedTargetPath
$quotedTargetPath >/dev/null 2>&1 &
''';
    }

    final installerPath = _quoteForShell(installerFile.path);
    return '''
while kill -0 $pid 2>/dev/null; do
  sleep 1
done
xdg-open $installerPath
''';
  }

  String _quoteForShell(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  String _quoteForPowerShell(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }
}

AppUpdateInstaller createPlatformAppUpdateInstaller() =>
    const IoAppUpdateInstaller();
