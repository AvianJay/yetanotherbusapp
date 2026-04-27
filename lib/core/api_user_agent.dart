import 'package:flutter/foundation.dart';

import 'app_build_info.dart';

class ApiUserAgent {
  ApiUserAgent._();

  static String? _configuredValue;

  static String get value => _configuredValue ?? _fallbackValue();

  static void configure(AppBuildInfo buildInfo) {
    _configuredValue = _build(buildInfo);
  }

  static Map<String, String> applyTo(Map<String, String> headers) {
    return <String, String>{
      ...headers,
      'User-Agent': value,
    };
  }

  static String _build(AppBuildInfo buildInfo) {
    final version = _sanitizeSegment(buildInfo.version, fallback: 'unknown');
    final commitHash = _sanitizeSegment(
      buildInfo.hasKnownGitSha ? buildInfo.gitSha : 'unknown',
      fallback: 'unknown',
    );
    return 'YABus/$version-$commitHash (${_platformName()})';
  }

  static String _fallbackValue() {
    return 'YABus/unknown-unknown (${_platformName()})';
  }

  static String _platformName() {
    if (kIsWeb) {
      return 'web';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  static String _sanitizeSegment(String value, {required String fallback}) {
    final sanitized = value.trim().replaceAll(RegExp(r'\s+'), '_');
    return sanitized.isEmpty ? fallback : sanitized;
  }
}