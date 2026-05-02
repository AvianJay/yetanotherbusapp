// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

/// Result of a web update check comparing the cached app version
/// to the latest version.json served by the origin.
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

  @override
  String toString() =>
      'WebUpdateCheckResult(hasUpdate: $hasUpdate, '
      'current: $currentVersion+$currentBuildNumber, '
      'latest: $latestVersion+$latestBuildNumber)';
}

/// A web-only service that periodically checks /version.json
/// to detect when a newer build has been deployed.
class WebUpdateChecker {
  WebUpdateChecker() {
    _loadCurrentVersion();
  }

  static const _versionJsonPath = '/version.json';
  static const _checkInterval = Duration(minutes: 30);
  static const _requestTimeout = Duration(seconds: 6);

  String _currentVersion = '';
  String _currentBuildNumber = '';
  String _currentGitSha = '';
  bool _versionLoaded = false;

  final _controller = StreamController<WebUpdateCheckResult>.broadcast();

  /// A broadcast stream that emits a result each time a check completes
  /// and finds a newer version deployed.
  Stream<WebUpdateCheckResult> get onUpdateAvailable => _controller.stream;

  Timer? _periodicTimer;

  /// Start periodic update checks. Call once after the app is running.
  void startPeriodicCheck() {
    _periodicTimer?.cancel();
    // First check after a short delay so the app is fully loaded.
    _periodicTimer = Timer(const Duration(seconds: 15), () {
      _checkForUpdate();
      _periodicTimer = Timer.periodic(_checkInterval, (_) => _checkForUpdate());
    });
  }

  /// Stop periodic checks.
  void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Manually trigger a single check, returning the result.
  Future<WebUpdateCheckResult> checkNow() async {
    if (!_versionLoaded) {
      await _loadCurrentVersion();
    }
    return _checkForUpdate();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final response = await html.HttpRequest.getString(_versionJsonPath)
          .timeout(_requestTimeout);
      final data = jsonDecode(response) as Map<String, dynamic>;
      _currentVersion = (data['version'] as String?) ?? '';
      _currentBuildNumber = (data['buildNumber'] as String?) ?? '';
      _currentGitSha = (data['gitSha'] as String?) ?? '';
      _versionLoaded = true;
    } catch (_) {
      // version.json might not exist in dev mode; that's fine.
      _versionLoaded = true;
    }
  }

  Future<WebUpdateCheckResult> _checkForUpdate() async {
    if (!_versionLoaded) {
      await _loadCurrentVersion();
    }

    try {
      // Bust any intermediate cache by appending a timestamp param.
      final uri = Uri.parse('$_versionJsonPath?_=${DateTime.now().millisecondsSinceEpoch}');
      final response = await html.HttpRequest.getString(uri.toString())
          .timeout(_requestTimeout);
      final data = jsonDecode(response) as Map<String, dynamic>;

      final latestVersion = (data['version'] as String?) ?? '';
      final latestBuildNumber = (data['buildNumber'] as String?) ?? '';
      final latestGitSha = (data['gitSha'] as String?) ?? '';

      final hasUpdate = _isNewer(
        currentVersion: _currentVersion,
        currentBuildNumber: _currentBuildNumber,
        currentGitSha: _currentGitSha,
        latestVersion: latestVersion,
        latestBuildNumber: latestBuildNumber,
        latestGitSha: latestGitSha,
      );

      final result = WebUpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: _currentVersion,
        latestVersion: latestVersion,
        currentBuildNumber: _currentBuildNumber,
        latestBuildNumber: latestBuildNumber,
        currentGitSha: _currentGitSha,
        latestGitSha: latestGitSha,
      );

      if (hasUpdate) {
        _controller.add(result);
      }

      return result;
    } catch (_) {
      return WebUpdateCheckResult(
        hasUpdate: false,
        currentVersion: _currentVersion,
        latestVersion: _currentVersion,
        currentBuildNumber: _currentBuildNumber,
        latestBuildNumber: _currentBuildNumber,
        currentGitSha: _currentGitSha,
        latestGitSha: _currentGitSha,
      );
    }
  }

  /// Determine whether the latest deployed build is newer than the
  /// one the user is currently running.
  ///
  /// Strategy:
  /// 1. If the version strings differ, the higher one is newer.
  /// 2. If versions are equal but build numbers differ (both numeric),
  ///    the higher build number is newer.
  /// 3. If versions and build numbers match but git SHAs differ,
  ///    consider it an update (same version, different commit).
  static bool _isNewer({
    required String currentVersion,
    required String currentBuildNumber,
    required String currentGitSha,
    required String latestVersion,
    required String latestBuildNumber,
    required String latestGitSha,
  }) {
    // If the current version was never loaded, we can't compare.
    if (currentVersion.isEmpty) return false;
    if (latestVersion.isEmpty) return false;

    // Version string comparison.
    if (latestVersion != currentVersion) {
      // Try semantic version comparison.
      final cmp = _compareSemanticVersions(latestVersion, currentVersion);
      if (cmp != 0) return cmp > 0;
      // Fall through if we can't parse.
      return latestVersion.compareTo(currentVersion) > 0;
    }

    // Same version: compare build numbers if both numeric.
    final currentBuild = int.tryParse(currentBuildNumber);
    final latestBuild = int.tryParse(latestBuildNumber);
    if (currentBuild != null && latestBuild != null) {
      return latestBuild > currentBuild;
    }

    // Same version, can't compare builds: check git SHA.
    if (latestGitSha.isNotEmpty &&
        currentGitSha.isNotEmpty &&
        latestGitSha != currentGitSha) {
      return true;
    }

    return false;
  }

  /// Compare two dot-separated version strings semantically.
  /// Returns negative if [a] < [b], positive if [a] > [b], 0 if equal.
  static int _compareSemanticVersions(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < len; i++) {
      final numA = int.tryParse(partsA.elementAt(i)) ?? -1;
      final numB = int.tryParse(partsB.elementAt(i)) ?? -1;
      if (numA != numB) return numA.compareTo(numB);
    }
    return 0;
  }
}
