// Stub for non-web platforms: no web update checker available.

class WebUpdateCheckResult {
  const WebUpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.currentBuildNumber,
    required this.latestBuildNumber,
    required this.currentGitSha,
    required this.latestGitSha,
  });
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String currentBuildNumber;
  final String latestBuildNumber;
  final String currentGitSha;
  final String latestGitSha;
}

/// Stub: no-op checker on non-web platforms.
class WebUpdateChecker {
  Stream<WebUpdateCheckResult> get onUpdateAvailable =>
      const Stream.empty();
  void startPeriodicCheck() {}
  void stopPeriodicCheck() {}
  Future<WebUpdateCheckResult> checkNow() async => WebUpdateCheckResult(
        hasUpdate: false,
        currentVersion: '',
        latestVersion: '',
        currentBuildNumber: '',
        latestBuildNumber: '',
        currentGitSha: '',
        latestGitSha: '',
      );
}

/// Non-web: always returns null.
WebUpdateChecker? createWebUpdateChecker() => null;

/// Non-web: no-op.
void reloadPage() {}
