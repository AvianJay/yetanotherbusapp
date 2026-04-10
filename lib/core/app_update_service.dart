import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_build_info.dart';
import 'models.dart';

enum AppUpdateStatus { unavailable, upToDate, updateAvailable }

enum AppUpdatePackageFormat { apk, zip }

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
        message: '檢查更新失敗：$error',
      );
    }
  }

  Future<AppUpdateCheckResult> _checkNightlyUpdates() async {
    if (!buildInfo.hasKnownGitSha) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '這個安裝包沒有內建 commit 資訊，無法比較 nightly 更新。',
      );
    }

    final uri = Uri.https(
      'api.github.com',
      '/repos/${AppBuildInfo.repoOwner}/${AppBuildInfo.repoName}/actions/workflows/${AppBuildInfo.workflowIdForApi}/runs',
      {'branch': 'main', 'event': 'push', 'status': 'success', 'per_page': '1'},
    );
    final payload = await _getJson(uri) as Map<String, dynamic>;
    final workflowRuns = payload['workflow_runs'] as List<dynamic>? ?? const [];
    if (workflowRuns.isEmpty) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '找不到可用的 nightly 建置。',
      );
    }

    final latestRun = workflowRuns.first as Map<String, dynamic>;
    final latestSha = (latestRun['head_sha'] as String? ?? '')
        .trim()
        .toLowerCase();
    if (latestSha.isEmpty) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: 'nightly 建置沒有回傳有效的 commit。',
      );
    }

    final latestShortSha = latestSha.length <= 7
        ? latestSha
        : latestSha.substring(0, 7);
    if (latestShortSha == buildInfo.shortGitSha) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.upToDate,
        message: '目前已是最新 nightly commit：${buildInfo.shortGitSha}',
      );
    }

    final headCommit = latestRun['head_commit'] as Map<String, dynamic>?;
    final commitMessage = (headCommit?['message'] as String? ?? '')
        .trim()
        .split('\n')
        .firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '新的 nightly 建置已可下載。',
        );
    final compareUrl =
        'https://github.com/${AppBuildInfo.repoOwner}/${AppBuildInfo.repoName}/compare/${buildInfo.shortGitSha}...$latestShortSha';
    final downloadUrl =
        'https://nightly.link/${AppBuildInfo.repoOwner}/${AppBuildInfo.repoName}/workflows/${AppBuildInfo.workflowIdForNightlyLink}/main/${AppBuildInfo.nightlyArtifactName}.zip';

    return AppUpdateCheckResult(
      status: AppUpdateStatus.updateAvailable,
      message: '找到新的 nightly commit：$latestShortSha',
      update: AppUpdateInfo(
        channel: AppUpdateChannel.nightly,
        currentVersionLabel: buildInfo.shortGitSha,
        latestVersionLabel: latestShortSha,
        title: 'Nightly 更新：$latestShortSha',
        summary: commitMessage,
        downloadUrl: downloadUrl,
        packageFormat: AppUpdatePackageFormat.zip,
        detailsUrl: compareUrl,
        notes: '目前版本：${buildInfo.shortGitSha}\n最新版本：$latestShortSha',
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
    Map<String, dynamic>? apkAsset;
    for (final asset in assets.whereType<Map<String, dynamic>>()) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apkAsset = asset;
        break;
      }
    }

    if (apkAsset == null) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: '發現新 release $latestTag，但沒有 Android APK 可下載。',
      );
    }

    final body = (payload['body'] as String? ?? '').trim();
    final releaseUrl = payload['html_url'] as String?;
    final downloadUrl = apkAsset['browser_download_url'] as String? ?? '';
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
        summary: body.isEmpty ? '新的 release 已可下載。' : body.split('\n').first,
        downloadUrl: downloadUrl,
        packageFormat: AppUpdatePackageFormat.apk,
        detailsUrl: releaseUrl,
        notes: body.isEmpty ? null : body,
      ),
    );
  }

  Future<Object?> _getJson(Uri uri) async {
    final response = await _client
        .get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': _githubApiVersion,
            'User-Agent': 'YetAnotherBusApp',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }
}
