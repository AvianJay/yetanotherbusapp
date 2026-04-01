import 'package:flutter/material.dart';

import 'app_build_info.dart';
import 'app_update_installer.dart';
import 'app_update_service.dart';
import 'bus_repository.dart';
import 'models.dart';
import 'storage_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.storage,
    required this.buildInfo,
    required this.appUpdateService,
    required this.appUpdateInstaller,
  });

  static const defaultFavoriteGroupName = '我的最愛';

  final BusRepository repository;
  final StorageService storage;
  final AppBuildInfo buildInfo;
  final AppUpdateService appUpdateService;
  final AppUpdateInstaller appUpdateInstaller;

  AppSettings _settings = AppSettings.defaults();
  List<SearchHistoryEntry> _history = const [];
  Map<String, List<FavoriteStop>> _favoriteGroups = const {};
  bool _initialized = false;
  bool _databaseReady = false;
  bool _checkingDatabase = false;
  bool _downloadingDatabase = false;
  bool _checkingAppUpdate = false;
  bool _startupAppUpdateChecked = false;
  AppUpdateCheckResult? _lastAppUpdateResult;

  AppSettings get settings => _settings;
  List<SearchHistoryEntry> get history => List.unmodifiable(_history);
  Map<String, List<FavoriteStop>> get favoriteGroups =>
      Map.unmodifiable(_favoriteGroups);
  List<String> get favoriteGroupNames => _favoriteGroups.keys.toList();
  bool get initialized => _initialized;
  bool get databaseReady => _databaseReady;
  bool get checkingDatabase => _checkingDatabase;
  bool get downloadingDatabase => _downloadingDatabase;
  bool get needsOnboarding => !_settings.hasCompletedOnboarding;
  bool get checkingAppUpdate => _checkingAppUpdate;
  AppUpdateCheckResult? get lastAppUpdateResult => _lastAppUpdateResult;

  Future<void> initialize() async {
    _settings = await storage.loadSettings();
    _history = await storage.loadHistory();
    _favoriteGroups = await storage.loadFavoriteGroups();
    await refreshDatabaseState();
    _initialized = true;
    notifyListeners();
  }

  Future<void> refreshDatabaseState() async {
    _checkingDatabase = true;
    notifyListeners();
    try {
      _databaseReady = await repository.databaseExists(_settings.provider);
    } finally {
      _checkingDatabase = false;
      notifyListeners();
    }
  }

  Future<void> updateProvider(BusProvider provider) async {
    _settings = _settings.copyWith(provider: provider);
    await storage.saveSettings(_settings);
    notifyListeners();
    await refreshDatabaseState();
  }

  Future<void> updateThemeMode(ThemeMode themeMode) async {
    _settings = _settings.copyWith(themeMode: themeMode);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateAlwaysShowSeconds(bool value) async {
    _settings = _settings.copyWith(alwaysShowSeconds: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateKeepScreenAwakeOnRouteDetail(bool value) async {
    _settings = _settings.copyWith(keepScreenAwakeOnRouteDetail: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateBusUpdateTime(int value) async {
    _settings = _settings.copyWith(busUpdateTime: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateBusErrorUpdateTime(int value) async {
    _settings = _settings.copyWith(busErrorUpdateTime: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateMaxHistory(int value) async {
    _settings = _settings.copyWith(maxHistory: value);
    _history = _history.take(value).toList();
    await storage.saveSettings(_settings);
    await storage.saveHistory(_history);
    notifyListeners();
  }

  Future<void> updateAppUpdateChannel(AppUpdateChannel value) async {
    _settings = _settings.copyWith(appUpdateChannel: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateAppUpdateCheckMode(AppUpdateCheckMode value) async {
    _settings = _settings.copyWith(appUpdateCheckMode: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _settings = _settings.copyWith(hasCompletedOnboarding: true);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> setOnboardingCompleted(bool value) async {
    _settings = _settings.copyWith(hasCompletedOnboarding: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> downloadCurrentProviderDatabase() async {
    _downloadingDatabase = true;
    notifyListeners();
    try {
      await repository.downloadDatabase(_settings.provider);
      _databaseReady = true;
    } finally {
      _downloadingDatabase = false;
      notifyListeners();
    }
  }

  Future<Map<BusProvider, int?>> checkDatabaseUpdates() {
    return repository.checkForUpdates();
  }

  Future<AppUpdateCheckResult> checkForAppUpdate({
    AppUpdateChannel? channel,
  }) async {
    if (_checkingAppUpdate) {
      return _lastAppUpdateResult ??
          const AppUpdateCheckResult(
            status: AppUpdateStatus.unavailable,
            message: '正在檢查更新中，請稍候。',
          );
    }

    _checkingAppUpdate = true;
    notifyListeners();
    try {
      final result = await appUpdateService.checkForUpdates(
        channel ?? _settings.appUpdateChannel,
      );
      _lastAppUpdateResult = result;
      return result;
    } finally {
      _checkingAppUpdate = false;
      notifyListeners();
    }
  }

  Future<AppUpdateCheckResult?> maybeCheckForAppUpdateOnLaunch() async {
    if (_startupAppUpdateChecked ||
        _settings.appUpdateCheckMode == AppUpdateCheckMode.off) {
      return null;
    }
    _startupAppUpdateChecked = true;
    return checkForAppUpdate();
  }

  Future<AppUpdateInstallResult> installAppUpdate(
    AppUpdateInfo update, {
    AppUpdateInstallProgressCallback? onProgress,
  }) {
    return appUpdateInstaller.installUpdate(update, onProgress: onProgress);
  }

  Future<int?> currentProviderLocalVersion() {
    return repository.getLocalVersion(_settings.provider);
  }

  Future<List<RouteSummary>> searchRoutes(
    String query, {
    BusProvider? provider,
  }) {
    return repository.searchRoutes(
      query,
      provider: provider ?? _settings.provider,
    );
  }

  Future<RouteDetailData> getRouteDetail(
    int routeKey, {
    BusProvider? provider,
  }) {
    return repository.getCompleteBusInfo(
      routeKey,
      provider: provider ?? _settings.provider,
    );
  }

  Future<List<NearbyStopResult>> getNearbyStops({
    required double latitude,
    required double longitude,
    BusProvider? provider,
  }) {
    return repository.fetchNearbyStops(
      provider: provider ?? _settings.provider,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> addHistoryEntry(
    RouteSummary route, {
    required BusProvider provider,
  }) async {
    _history = _history
        .where(
          (entry) =>
              !(entry.provider == provider && entry.routeKey == route.routeKey),
        )
        .toList();
    _history.insert(
      0,
      SearchHistoryEntry(
        provider: provider,
        routeKey: route.routeKey,
        routeName: route.routeName,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _history = _history.take(_settings.maxHistory).toList();
    await storage.saveHistory(_history);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = [];
    await storage.saveHistory(_history);
    notifyListeners();
  }

  Future<void> addFavoriteGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _favoriteGroups.containsKey(trimmed)) {
      return;
    }

    _favoriteGroups = {..._favoriteGroups, trimmed: <FavoriteStop>[]};
    await storage.saveFavoriteGroups(_favoriteGroups);
    notifyListeners();
  }

  Future<void> deleteFavoriteGroup(String name) async {
    final next = {..._favoriteGroups};
    next.remove(name);
    _favoriteGroups = next;
    await storage.saveFavoriteGroups(_favoriteGroups);
    notifyListeners();
  }

  Future<String> addFavoriteStop(
    FavoriteStop favorite, {
    String? groupName,
  }) async {
    final targetGroup = groupName?.trim().isNotEmpty == true
        ? groupName!.trim()
        : (_favoriteGroups.isEmpty
              ? defaultFavoriteGroupName
              : _favoriteGroups.keys.first);

    final next = <String, List<FavoriteStop>>{
      for (final entry in _favoriteGroups.entries)
        entry.key: List<FavoriteStop>.from(entry.value),
    };
    next.putIfAbsent(targetGroup, () => <FavoriteStop>[]);
    final alreadyExists = next[targetGroup]!.any(
      (item) => item.sameAs(favorite),
    );
    if (!alreadyExists) {
      next[targetGroup]!.add(favorite);
    }

    _favoriteGroups = next;
    await storage.saveFavoriteGroups(_favoriteGroups);
    notifyListeners();
    return targetGroup;
  }

  Future<void> removeFavoriteStop(
    String groupName,
    FavoriteStop favorite,
  ) async {
    final next = <String, List<FavoriteStop>>{
      for (final entry in _favoriteGroups.entries)
        entry.key: List<FavoriteStop>.from(entry.value),
    };
    next[groupName]?.removeWhere((item) => item.sameAs(favorite));
    _favoriteGroups = next;
    await storage.saveFavoriteGroups(_favoriteGroups);
    notifyListeners();
  }

  List<FavoriteStop> favoritesInGroup(String groupName) {
    return List.unmodifiable(_favoriteGroups[groupName] ?? const []);
  }

  Future<List<FavoriteResolvedItem>> resolveFavoriteGroup(String groupName) {
    return repository.resolveFavoriteGroup(favoritesInGroup(groupName));
  }
}
