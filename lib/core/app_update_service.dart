import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_user_agent.dart';
import 'app_build_info.dart';
import 'friendly_error.dart';
import 'http_error_utils.dart';
import 'models.dart';

enum AppUpdateStatus { unavailable, upToDate, updateAvailable }

enum AppUpdatePackageFormat { apk, zip, exe, dmg, deb, appImage }

const _generatedReleaseDownloadTableStart =
    '<!-- YABUS_RELEASE_DOWNLOAD_TABLE_START -->';
const _generatedReleaseDownloadTableEnd =
    '<!-- YABUS_RELEASE_DOWNLOAD_TABLE_END -->';
final _fullGitShaPattern = RegExp(r'^[0-9a-f]{40}$');

bool _isFullGitSha(String value) => _fullGitShaPattern.hasMatch(value);

String? _nightlyShaFromTag(String value) {
  const prefix = 'nightly-';
  if (!value.startsWith(prefix)) {
    return null;
  }
  final sha = value.substring(prefix.length).trim().toLowerCase();
  return _isFullGitSha(sha) ? sha : null;
}

/// The preferred asset suffix for the current platform when checking
/// GitHub Release assets for a downloadable update.
String get _platformAssetSuffix {
  if (kIsWeb) {
    return '';
  }
  if (defaultTargetPlatform == TargetPlatform.windows) {
    return '-windows-x64-setup.exe';
  }
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return '-macos.dmg';
  }
  if (defaultTargetPlatform == TargetPlatform.linux) {
    return '-linux-amd64.deb';
  }
  return '.apk';
}

/// Map a release asset filename to the corresponding package format.
AppUpdatePackageFormat _packageFormatFromAssetName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.apk')) {
    return AppUpdatePackageFormat.apk;
  }
  if (lower.endsWith('setup.exe')) {
    return AppUpdatePackageFormat.exe;
  }
  if (lower.endsWith('.dmg')) {
    return AppUpdatePackageFormat.dmg;
  }
  if (lower.endsWith('.deb')) {
    return AppUpdatePackageFormat.deb;
  }
  if (lower.endsWith('.appimage')) {
    return AppUpdatePackageFormat.appImage;
  }
  return AppUpdatePackageFormat.zip;
}

String _stripGeneratedReleaseDownloadTable(String markdown) {
  var result = markdown;
  while (true) {
    final start = result.indexOf(_generatedReleaseDownloadTableStart);
    if (start == -1) {
      break;
    }
    final end = result.indexOf(
      _generatedReleaseDownloadTableEnd,
      start + _generatedReleaseDownloadTableStart.length,
    );
    if (end == -1) {
      result = result.substring(0, start);
      break;
    }
    result =
        result.substring(0, start) +
        result.substring(end + _generatedReleaseDownloadTableEnd.length);
  }
  return result.trim();
}

String _summarizeReleaseMarkdown(String markdown) {
  final firstLine = markdown
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) {
    return '';
  }
  return firstLine.replaceFirst(RegExp(r'^#+\s*'), '').trim();
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.channel,
    required this.currentVersionLabel,
    required this.latestVersionLabel,
    required this.title,
    required this.summary,
    required this.downloadUrl,
    required this.packageFormat,
    this.detailsUrl,
    this.notes,
  });

  final AppUpdateChannel channel;
  final String currentVersionLabel;
  final String latestVersionLabel;
  final String title;
  final String summary;
  final String downloadUrl;
  final AppUpdatePackageFormat packageFormat;
  final String? detailsUrl;
  final String? notes;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    required this.message,
    this.update,
  });

  final AppUpdateStatus status;
  final String message;
  final AppUpdateInfo? update;

  bool get hasUpdate =>
      status == AppUpdateStatus.updateAvailable && update != null;
}

class AppUpdateService {
  AppUpdateService({required this.buildInfo, http.Client? client})
    : _client = client ?? http.Client();

  final AppBuildInfo buildInfo;
  final http.Client _client;

  static const _githubApiVersion = '2022-11-28';

  Future<AppUpdateCheckResult> checkForUpdates(AppUpdateChannel channel) async {
    try {
      return switch (channel) {
        AppUpdateChannel.developer => const AppUpdateCheckResult(
          status: AppUpdateStatus.unavailable,
          message: '開發版不檢查 app 更新。',
        ),
        AppUpdateChannel.nightly => _checkNightlyUpdates(),
        AppUpdateChannel.release => _checkReleaseUpdates(),
      };
    } catch (error) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '檢查更新失敗：${friendlyErrorMessage(error)}',
      );
    }
  }

  Future<AppUpdateCheckResult> _checkNightlyUpdates() async {
    final currentSha = buildInfo.normalizedGitSha;
    if (!_isFullGitSha(currentSha)) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '這個安裝包沒有內建完整 commit 資訊，無法比較 nightly 更新。',
      );
    }

    final uri = Uri.https(
      'api.github.com',
      '/repos/${AppBuildInfo.repoOwner}/${AppBuildInfo.repoName}/releases',
      {'per_page': '30'},
    );
    final releases = await _getJson(uri) as List<dynamic>;
    final nightlyRelease = releases
        .whereType<Map<String, dynamic>>()
        .firstWhere(
          (release) =>
              release['prerelease'] == true &&
              _nightlyShaFromTag(release['tag_name']?.toString() ?? '') != null,
          orElse: () => const <String, dynamic>{},
        );
    final latestSha = _nightlyShaFromTag(
      nightlyRelease['tag_name']?.toString() ?? '',
    );
    if (latestSha == null) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '找不到可用的 nightly 發布版本。',
      );
    }

    if (latestSha == currentSha) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.upToDate,
        message: '目前已是最新 nightly commit：$currentSha',
      );
    }

    final assets = nightlyRelease['assets'] as List<dynamic>? ?? const [];
    final asset = _findPlatformReleaseAsset(assets);
    final assetName = asset['name'] as String? ?? '';
    final downloadUrl = asset['browser_download_url'] as String? ?? '';
    if (downloadUrl.isEmpty) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '最新 nightly 建置找不到此平台的下載檔。',
      );
    }

    final releaseNotes = (nightlyRelease['body'] as String? ?? '').trim();
    final compareUrl =
        'https://github.com/${AppBuildInfo.repoOwner}/${AppBuildInfo.repoName}/compare/$currentSha...$latestSha';

    return AppUpdateCheckResult(
      status: AppUpdateStatus.updateAvailable,
      message: '找到新的 nightly commit：$latestSha',
      update: AppUpdateInfo(
        channel: AppUpdateChannel.nightly,
        currentVersionLabel: currentSha,
        latestVersionLabel: latestSha,
        title: 'Nightly 更新：$latestSha',
        summary: 'Nightly 建置 ${latestSha.substring(0, 7)} 已可下載。',
        downloadUrl: downloadUrl,
        packageFormat: _packageFormatFromAssetName(assetName),
        detailsUrl: compareUrl,
        notes: releaseNotes.isEmpty
            ? '目前版本：$currentSha\n最新版本：$latestSha'
            : '$releaseNotes\n\n目前版本：$currentSha\n最新版本：$latestSha',
      ),
    );
  }

  Future<AppUpdateCheckResult> _checkReleaseUpdates() async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/${AppBuildInfo.repoOwner}/${AppBuildInfo.repoName}/releases/latest',
    );
    final payload = await _getJson(uri) as Map<String, dynamic>;
    final latestTag = (payload['tag_name'] as String? ?? '').trim();
    if (latestTag.isEmpty) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '找不到最新 release。',
      );
    }

    if (latestTag == buildInfo.version) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.upToDate,
        message: '目前已是最新 release：${buildInfo.version}',
      );
    }

    final assets = payload['assets'] as List<dynamic>? ?? const [];

    final platformAsset = _findPlatformReleaseAsset(assets);
    final assetName = platformAsset['name'] as String? ?? '';
    final body = (payload['body'] as String? ?? '').trim();
    final notes = _stripGeneratedReleaseDownloadTable(body);
    final summary = _summarizeReleaseMarkdown(notes);
    final releaseUrl = payload['html_url'] as String?;
    final downloadUrl = platformAsset['browser_download_url'] as String? ?? '';
    if (downloadUrl.isEmpty) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '發現新 release $latestTag，但下載連結無效。',
      );
    }

    return AppUpdateCheckResult(
      status: AppUpdateStatus.updateAvailable,
      message: '找到新的 release：$latestTag',
      update: AppUpdateInfo(
        channel: AppUpdateChannel.release,
        currentVersionLabel: buildInfo.version,
        latestVersionLabel: latestTag,
        title: 'Release 更新：$latestTag',
        summary: summary.isEmpty ? '新的 release 已可下載。' : summary,
        downloadUrl: downloadUrl,
        packageFormat: _packageFormatFromAssetName(assetName),
        detailsUrl: releaseUrl,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  Map<String, dynamic> _findPlatformReleaseAsset(List<dynamic> assets) {
    // Find the best-matching asset for the current platform.
    Map<String, dynamic>? platformAsset;
    final suffix = _platformAssetSuffix;
    if (suffix.isNotEmpty) {
      for (final asset in assets.whereType<Map<String, dynamic>>()) {
        final name = asset['name'] as String? ?? '';
        if (name.contains(suffix)) {
          platformAsset = asset;
          break;
        }
      }
    }

    // Fallback: try APK for mobile, generic zip otherwise.
    platformAsset ??= assets.whereType<Map<String, dynamic>>().firstWhere(
      (asset) =>
          (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
      orElse: () => assets.whereType<Map<String, dynamic>>().firstWhere(
        (asset) =>
            (asset['name'] as String? ?? '').toLowerCase().endsWith('.zip'),
        orElse: () => throw StateError('no matching asset'),
      ),
    );

    return platformAsset;
  }

  Future<Object?> _getJson(Uri uri) async {
    final response = await _client
        .get(
          uri,
          headers: ApiUserAgent.githubApplyTo(const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': _githubApiVersion,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        httpStatusMessage(response.statusCode, 'HTTP ${response.statusCode}'),
      );
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
