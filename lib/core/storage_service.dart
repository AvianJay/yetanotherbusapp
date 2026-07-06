import 'dart:convert';

import 'announcement_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_sync_models.dart';
import 'models.dart';

class StorageService {
  static const _schemaVersionKey = 'storage_schema_version';
  static const _currentSchemaVersion = 2;
  static const _settingsKey = 'app_settings';
  static const _historyKey = 'search_history';
  static const _favoritesKey = 'favorite_groups';
  static const _routeUsageProfilesKey = 'route_usage_profiles';
  static const _favoriteUsageProfilesKey = 'favorite_usage_profiles';
  static const _stopVisitProfilesKey = 'stop_visit_profiles';
  static const _announcementLocalStateKey = 'announcement_local_state';
  static const _settingsLastModifiedAtKey = 'app_settings_last_modified_at_ms';
  static const _favoritesLastModifiedAtKey =
      'favorite_groups_last_modified_at_ms';
  static const _accountSyncStateKeyPrefix = 'account_sync_state';

  Future<void> migrateLegacyApiDataIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getInt(_schemaVersionKey) ?? 0;
    if (currentVersion >= _currentSchemaVersion) {
      return;
    }

    await prefs.remove(_settingsKey);
    await prefs.remove(_historyKey);
    await prefs.remove(_favoritesKey);
    await prefs.remove('tracked_buses');
    await prefs.remove(_routeUsageProfilesKey);
    await prefs.remove(_favoriteUsageProfilesKey);
    await prefs.setInt(_schemaVersionKey, _currentSchemaVersion);
  }

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      return AppSettings.defaults();
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> saveSettings(AppSettings settings, {int? modifiedAtMs}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    await prefs.setInt(
      _settingsLastModifiedAtKey,
      modifiedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<SearchHistoryEntry>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (entry) => SearchHistoryEntry.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((entry) => entry.routeKey > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveHistory(List<SearchHistoryEntry> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(history.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<Map<String, List<FavoriteStop>>> loadFavoriteGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .whereType<Map>()
              .map(
                (item) => FavoriteStop.fromJson(
                  item.map(
                    (itemKey, itemValue) =>
                        MapEntry(itemKey.toString(), itemValue),
                  ),
                ),
              )
              .where((item) => item.routeKey > 0 && item.stopId > 0)
              .toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFavoriteGroups(
    Map<String, List<FavoriteStop>> favoriteGroups, {
    int? modifiedAtMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = favoriteGroups.map(
      (key, value) =>
          MapEntry(key, value.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(_favoritesKey, jsonEncode(payload));
    await prefs.setInt(
      _favoritesLastModifiedAtKey,
      modifiedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<RouteUsageProfile>> loadRouteUsageProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_routeUsageProfilesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (entry) => RouteUsageProfile.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((entry) => entry.routeKey > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRouteUsageProfiles(List<RouteUsageProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _routeUsageProfilesKey,
      jsonEncode(profiles.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<List<FavoriteUsageProfile>> loadFavoriteUsageProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoriteUsageProfilesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (entry) => FavoriteUsageProfile.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where(
            (entry) =>
                entry.routeKey > 0 && entry.pathId >= 0 && entry.stopId > 0,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveFavoriteUsageProfiles(
    List<FavoriteUsageProfile> profiles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _favoriteUsageProfilesKey,
      jsonEncode(profiles.map((entry) => entry.toJson()).toList()),
    );
  }

  /// Tracks recent per-stop visit counts (regardless of favorite status),
  /// used to decide when a stop crosses the threshold for auto-favoriting.
  Future<List<FavoriteUsageProfile>> loadStopVisitProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stopVisitProfilesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (entry) => FavoriteUsageProfile.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where(
            (entry) =>
                entry.routeKey > 0 && entry.pathId >= 0 && entry.stopId > 0,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveStopVisitProfiles(
    List<FavoriteUsageProfile> profiles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _stopVisitProfilesKey,
      jsonEncode(profiles.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<AnnouncementLocalState> loadAnnouncementLocalState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_announcementLocalStateKey);
    if (raw == null || raw.isEmpty) {
      return AnnouncementLocalState.empty();
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AnnouncementLocalState.fromJson(decoded);
    } catch (_) {
      return AnnouncementLocalState.empty();
    }
  }

  Future<void> saveAnnouncementLocalState(AnnouncementLocalState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _announcementLocalStateKey,
      jsonEncode(state.toJson()),
    );
  }

  Future<int?> loadSettingsLastModifiedAtMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_settingsLastModifiedAtKey);
  }

  Future<int?> loadFavoriteGroupsLastModifiedAtMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_favoritesLastModifiedAtKey);
  }

  Future<AccountSyncLocalState> loadAccountSyncLocalState(
    String accountId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountSyncStateKey(accountId));
    if (raw == null || raw.isEmpty) {
      return AccountSyncLocalState.empty();
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AccountSyncLocalState.fromJson(decoded);
    } catch (_) {
      return AccountSyncLocalState.empty();
    }
  }

  Future<void> saveAccountSyncLocalState(
    String accountId,
    AccountSyncLocalState state,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _accountSyncStateKey(accountId),
      jsonEncode(state.toJson()),
    );
  }

  String _accountSyncStateKey(String accountId) {
    return '$_accountSyncStateKeyPrefix:${accountId.trim()}';
  }
}
