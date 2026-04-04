import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class StorageService {
  static const _settingsKey = 'app_settings';
  static const _historyKey = 'search_history';
  static const _favoritesKey = 'favorite_groups';
  static const _trackedBusesKey = 'tracked_buses';

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

  Future<List<TrackedBus>> loadTrackedBuses() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trackedBusesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (entry) => TrackedBus.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((entry) => entry.vehicleId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveTrackedBuses(List<TrackedBus> trackedBuses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _trackedBusesKey,
      jsonEncode(trackedBuses.map((entry) => entry.toJson()).toList()),
    );
  }
}
