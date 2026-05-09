import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'announcement_models.dart';
import 'api_config.dart';
import 'api_user_agent.dart';
import 'app_build_info.dart';

class AnnouncementService {
  AnnouncementService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AppAnnouncement>> fetchAnnouncements({
    required AppBuildInfo buildInfo,
  }) async {
    final platform = currentPlatform;
    final version = _normalizedVersion(buildInfo.version);
    final queryParameters = <String, String>{'platform': platform};
    if (version != null) {
      queryParameters['version'] = version;
    }

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/announcements',
    ).replace(queryParameters: queryParameters);
    final response = await _client.get(
      uri,
      headers: ApiUserAgent.applyTo(const {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, '公告載入失敗。'));
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException('Invalid announcements payload.');
    }

    return decoded
        .whereType<Map>()
        .map(
          (entry) => AppAnnouncement.fromJson(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((announcement) => announcement.id.isNotEmpty)
        .where((announcement) => matchesCurrentClient(announcement, buildInfo))
        .toList(growable: false);
  }

  bool matchesCurrentClient(
    AppAnnouncement announcement,
    AppBuildInfo buildInfo,
  ) {
    final targets = announcement.targets;
    if (targets == null) {
      return true;
    }

    final platforms = targets.platforms;
    if (platforms != null && platforms.isNotEmpty) {
      if (!platforms.contains(currentPlatform)) {
        return false;
      }
    }

    final versionConstraint = targets.versionConstraint;
    final currentVersion = _normalizedVersion(buildInfo.version);
    if (versionConstraint != null && currentVersion != null) {
      return _matchesVersionConstraint(currentVersion, versionConstraint);
    }
    if (versionConstraint != null && currentVersion == null) {
      return false;
    }
    return true;
  }

  bool shouldShowRedDot(
    AppAnnouncement announcement,
    AnnouncementLocalState localState,
  ) {
    switch (announcement.behavior.redDot) {
      case AnnouncementRepeatBehavior.forever:
        return true;
      case AnnouncementRepeatBehavior.once:
        return !localState.viewedRedDotIds.contains(announcement.id);
    }
  }

  List<AppAnnouncement> pendingPopups(
    Iterable<AppAnnouncement> announcements,
    AnnouncementLocalState localState, {
    Set<String> sessionDeferredIds = const <String>{},
  }) {
    final pending = announcements.where((announcement) {
      if (sessionDeferredIds.contains(announcement.id)) {
        return false;
      }
      switch (announcement.behavior.popup) {
        case AnnouncementRepeatBehavior.once:
          return !localState.shownPopupIds.contains(announcement.id);
        case AnnouncementRepeatBehavior.forever:
          return !localState.dismissedPopupIds.contains(announcement.id);
      }
    }).toList(growable: false);
    pending.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return pending;
  }

  AnnouncementLocalState markListViewed(
    AnnouncementLocalState localState,
    Iterable<AppAnnouncement> announcements,
  ) {
    final nextViewed = {...localState.viewedRedDotIds};
    var changed = false;
    for (final announcement in announcements) {
      if (announcement.behavior.redDot != AnnouncementRepeatBehavior.once) {
        continue;
      }
      changed = nextViewed.add(announcement.id) || changed;
    }
    if (!changed) {
      return localState;
    }
    return localState.copyWith(viewedRedDotIds: nextViewed);
  }

  AnnouncementLocalState markPopupShown(
    AnnouncementLocalState localState,
    AppAnnouncement announcement,
  ) {
    if (announcement.behavior.popup != AnnouncementRepeatBehavior.once) {
      return localState;
    }
    final nextShown = {...localState.shownPopupIds};
    if (!nextShown.add(announcement.id)) {
      return localState;
    }
    return localState.copyWith(shownPopupIds: nextShown);
  }

  AnnouncementLocalState dismissPopup(
    AnnouncementLocalState localState,
    AppAnnouncement announcement,
  ) {
    if (announcement.behavior.popup != AnnouncementRepeatBehavior.forever) {
      return localState;
    }
    final nextDismissed = {...localState.dismissedPopupIds};
    if (!nextDismissed.add(announcement.id)) {
      return localState;
    }
    return localState.copyWith(dismissedPopupIds: nextDismissed);
  }

  String get currentPlatform {
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
}

String _errorMessage(http.Response response, String fallback) {
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map && decoded['detail'] != null) {
      final detail = '${decoded['detail']}'.trim();
      if (detail.isNotEmpty) {
        return detail;
      }
    }
  } catch (_) {
    // Ignore malformed error payloads and keep the fallback.
  }
  return fallback;
}

String? _normalizedVersion(String rawVersion) {
  final normalized = rawVersion.trim();
  if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

bool _matchesVersionConstraint(String currentVersion, String constraint) {
  final currentParts = _parseVersion(currentVersion);
  for (final rawPart in constraint.split(',')) {
    final part = rawPart.trim();
    if (part.isEmpty) {
      continue;
    }

    final match = RegExp(
      r'^(>=|<=|>|<|==|=)?\s*(\d+(?:\.\d+)*)$',
    ).firstMatch(part);
    if (match == null) {
      return false;
    }

    final operator = match.group(1) ?? '=';
    final expectedParts = _parseVersion(match.group(2)!);
    final comparison = _compareVersions(currentParts, expectedParts);
    switch (operator) {
      case '>=':
        if (comparison < 0) {
          return false;
        }
      case '>':
        if (comparison <= 0) {
          return false;
        }
      case '<=':
        if (comparison > 0) {
          return false;
        }
      case '<':
        if (comparison >= 0) {
          return false;
        }
      case '=':
      case '==':
        if (comparison != 0) {
          return false;
        }
    }
  }
  return true;
}

List<int> _parseVersion(String value) {
  return value.split('.').map((part) => int.parse(part)).toList(growable: false);
}

int _compareVersions(List<int> left, List<int> right) {
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index += 1) {
    final leftValue = index < left.length ? left[index] : 0;
    final rightValue = index < right.length ? right[index] : 0;
    if (leftValue < rightValue) {
      return -1;
    }
    if (leftValue > rightValue) {
      return 1;
    }
  }
  return 0;
}