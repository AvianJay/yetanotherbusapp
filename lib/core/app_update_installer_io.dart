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
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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

    final canInstall =
        await _channel.invokeMethod<bool>('canRequestPackageInstalls') ?? false;
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

    try {
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
}

AppUpdateInstaller createPlatformAppUpdateInstaller() =>
    const IoAppUpdateInstaller();
