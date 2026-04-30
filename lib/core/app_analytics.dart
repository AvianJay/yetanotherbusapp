import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'models.dart';

class AppAnalytics {
  AppAnalytics._(this.analytics)
    : observer = analytics == null
          ? null
          : FirebaseAnalyticsObserver(analytics: analytics);

  final FirebaseAnalytics? analytics;
  final FirebaseAnalyticsObserver? observer;

  bool get isEnabled => analytics != null;

  Future<void> logSearchExecuted({
    required int queryLength,
    required int resultsCount,
    required int providerCount,
    required int localProviderCount,
    required int remoteProviderCount,
  }) {
    return _logEvent('search_executed', {
      'query_length': queryLength,
      'results_count': resultsCount,
      'provider_count': providerCount,
      'local_provider_count': localProviderCount,
      'remote_provider_count': remoteProviderCount,
    });
  }

  Future<void> logSearchFailed({
    required int queryLength,
    required int providerCount,
  }) {
    return _logEvent('search_failed', {
      'query_length': queryLength,
      'provider_count': providerCount,
    });
  }

  Future<void> logRouteSelected({
    required BusProvider provider,
    required int routeKey,
    required String source,
  }) {
    return _logEvent('route_selected', {
      'provider': provider.name,
      'route_key': routeKey,
      'source': source,
    });
  }

  Future<void> logRouteVisit({
    required BusProvider provider,
    required int routeKey,
  }) {
    return _logEvent('route_visit_recorded', {
      'provider': provider.name,
      'route_key': routeKey,
    });
  }

  Future<void> logProviderChanged({
    required BusProvider provider,
    required int selectedCount,
  }) {
    return _logEvent('provider_changed', {
      'provider': provider.name,
      'selected_count': selectedCount,
    });
  }

  Future<void> logSelectedProvidersChanged({
    required BusProvider currentProvider,
    required int selectedCount,
  }) {
    return _logEvent('selected_providers_changed', {
      'provider': currentProvider.name,
      'selected_count': selectedCount,
    });
  }

  Future<void> logThemeModeChanged(ThemeMode themeMode) {
    return _logEvent('theme_mode_changed', {
      'theme_mode': themeMode.name,
    });
  }

  Future<void> logAmoledPreferenceChanged(bool enabled) {
    return _logEvent('amoled_theme_changed', {
      'enabled': enabled,
    });
  }

  Future<void> logSeedColorChanged({required bool usesCustomColor}) {
    return _logEvent('seed_color_changed', {
      'uses_custom_color': usesCustomColor,
    });
  }

  Future<void> logPageBackgroundChanged({
    required String pageKey,
    required bool hasImage,
  }) {
    return _logEvent('page_background_changed', {
      'page_key': pageKey,
      'has_image': hasImage,
    });
  }

  Future<void> logBackgroundImagesApplied({required int pageCount}) {
    return _logEvent('background_images_applied', {
      'page_count': pageCount,
    });
  }

  Future<void> logBackgroundImagesCleared() {
    return _logEvent('background_images_cleared');
  }

  Future<void> logFavoriteGroupCreated({required int groupCount}) {
    return _logEvent('favorite_group_created', {
      'group_count': groupCount,
    });
  }

  Future<void> logFavoriteGroupDeleted({required int groupCount}) {
    return _logEvent('favorite_group_deleted', {
      'group_count': groupCount,
    });
  }

  Future<void> logFavoriteStopSaved({
    required BusProvider provider,
    required int routeKey,
    required bool replacedExisting,
    required bool hasDestination,
  }) {
    return _logEvent('favorite_stop_saved', {
      'provider': provider.name,
      'route_key': routeKey,
      'replaced_existing': replacedExisting,
      'has_destination': hasDestination,
    });
  }

  Future<void> logFavoriteStopRemoved({
    required BusProvider provider,
    required int routeKey,
    required bool hadDestination,
  }) {
    return _logEvent('favorite_stop_removed', {
      'provider': provider.name,
      'route_key': routeKey,
      'had_destination': hadDestination,
    });
  }

  Future<void> logDatabasesDownloaded({
    required int providerCount,
    required bool includesCurrentProvider,
  }) {
    return _logEvent('databases_downloaded', {
      'provider_count': providerCount,
      'includes_current_provider': includesCurrentProvider,
    });
  }

  Future<void> logAppUpdateChecked({
    required String channel,
    required String status,
  }) {
    return _logEvent('app_update_checked', {
      'channel': channel,
      'status': status,
    });
  }

  Future<void> _logEvent(
    String name, [
    Map<String, Object?> parameters = const <String, Object?>{},
  ]) async {
    final analytics = this.analytics;
    if (analytics == null) {
      return;
    }

    try {
      await analytics.logEvent(
        name: name,
        parameters: _normalizeParameters(parameters),
      );
    } catch (_) {
      unawaited(Future<void>.value());
    }
  }

  Map<String, Object> _normalizeParameters(Map<String, Object?> parameters) {
    final normalized = <String, Object>{};
    for (final entry in parameters.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is bool) {
        normalized[entry.key] = value ? 1 : 0;
      } else if (value is num || value is String) {
        normalized[entry.key] = value;
      } else {
        normalized[entry.key] = value.toString();
      }
    }
    return normalized;
  }

  static Future<AppAnalytics> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return AppAnalytics._(null);
    }

    try {
      await Firebase.initializeApp();
      final analytics = FirebaseAnalytics.instance;
      await analytics.setAnalyticsCollectionEnabled(true);
      await analytics.logAppOpen();
      return AppAnalytics._(analytics);
    } catch (_) {
      return AppAnalytics._(null);
    }
  }
}
