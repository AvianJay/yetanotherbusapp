import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class StorageService {
  static const _schemaVersionKey = 'storage_schema_version';
  static const _currentSchemaVersion = 2;
  static const _settingsKey = 'app_settings';
  static const _historyKey = 'search_history';
  static const _favoritesKey = 'favorite_groups';
  static const _routeUsageProfilesKey = 'route_usage_profiles';

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

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
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
    Map<String, List<FavoriteStop>> favoriteGroups,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = favoriteGroups.map(
      (key, value) =>
          MapEntry(key, value.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(_favoritesKey, jsonEncode(payload));
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
}
