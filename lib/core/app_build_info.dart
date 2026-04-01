import 'package:package_info_plus/package_info_plus.dart';

import 'models.dart';

class AppBuildInfo {
  const AppBuildInfo({
    required this.version,
    required this.buildNumber,
    required this.gitSha,
    required this.defaultUpdateChannel,
  });

  static const repoOwner = String.fromEnvironment(
    'APP_REPO_OWNER',
    defaultValue: 'AvianJay',
  );
  static const repoName = String.fromEnvironment(
    'APP_REPO_NAME',
    defaultValue: 'yetanotherbusapp',
  );
  static const workflowIdForApi = String.fromEnvironment(
    'APP_WORKFLOW_API_ID',
    defaultValue: 'build.yml',
  );
  static const workflowIdForNightlyLink = String.fromEnvironment(
    'APP_WORKFLOW_NIGHTLY_ID',
    defaultValue: 'build',
  );
  static const nightlyArtifactName = String.fromEnvironment(
    'APP_NIGHTLY_ARTIFACT',
    defaultValue: 'android-apk-release',
  );

  static Future<AppBuildInfo> load() async {
    final packageInfo = await PackageInfo.fromPlatform();

    return AppBuildInfo(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      gitSha: const String.fromEnvironment(
        'APP_GIT_SHA',
        defaultValue: 'unknown',
      ).trim().toLowerCase(),
      defaultUpdateChannel: appUpdateChannelFromStringConst(
        const String.fromEnvironment(
          'APP_UPDATE_CHANNEL',
          defaultValue: 'nightly',
        ),
      ),
    );
  }

  final String version;
  final String buildNumber;
  final String gitSha;
  final AppUpdateChannel defaultUpdateChannel;

  bool get hasKnownGitSha => gitSha.isNotEmpty && gitSha != 'unknown';

  String get shortGitSha {
    if (!hasKnownGitSha) {
      return 'unknown';
    }
    return gitSha.length <= 7 ? gitSha : gitSha.substring(0, 7);
  }

  String get displayVersion => '$version+$buildNumber';
}
