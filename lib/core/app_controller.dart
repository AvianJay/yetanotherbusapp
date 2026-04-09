import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'android_home_integration.dart';
import 'android_trip_monitor.dart';
import 'app_build_info.dart';
import 'app_update_installer.dart';
import 'app_update_service.dart';
import 'bus_repository.dart';
import 'ios_widget_integration.dart';
import 'live_activity_service.dart';
import 'models.dart';
import 'smart_route_service.dart';
import 'storage_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.storage,
    required this.buildInfo,
    required this.appUpdateService,
    required this.appUpdateInstaller,
  });

  static const defaultFavoriteGroupName = 'Favorites';

  final BusRepository repository;
  final StorageService storage;
  final AppBuildInfo buildInfo;
  final AppUpdateService appUpdateService;
  final AppUpdateInstaller appUpdateInstaller;

  AppSettings _settings = AppSettings.defaults();
  List<SearchHistoryEntry> _history = const [];
  Map<String, List<FavoriteStop>> _favoriteGroups = const {};
  List<RouteUsageProfile> _routeUsageProfiles = const [];
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
  List<RouteUsageProfile> get routeUsageProfiles =>
      List.unmodifiable(_routeUsageProfiles);
  int get recordedRouteSelections => _routeUsageProfiles.fold(
    0,
    (total, entry) => total + entry.totalSelections,
  );
  String get smartRouteSignature => _routeUsageProfiles
      .map(
        (entry) =>
            '${entry.provider.name}:'
            '${entry.routeKey}:'
            '${entry.totalOpens}:'
            '${entry.lastOpenedAtMs}:'
            '${entry.totalSelections}:'
            '${entry.lastSelectedAtMs}',
      )
      .join('|');
  bool get initialized => _initialized;
  bool get databaseReady => _databaseReady;
  bool get checkingDatabase => _checkingDatabase;
  bool get downloadingDatabase => _downloadingDatabase;
  bool get needsOnboarding => !_settings.hasCompletedOnboarding;
  bool get checkingAppUpdate => _checkingAppUpdate;
  AppUpdateCheckResult? get lastAppUpdateResult => _lastAppUpdateResult;

  Future<void> initialize() async {
    await storage.migrateLegacyApiDataIfNeeded();
    _settings = await storage.loadSettings();
    _history = await storage.loadHistory();
    _favoriteGroups = await storage.loadFavoriteGroups();
    _routeUsageProfiles = await storage.loadRouteUsageProfiles();
    await AndroidHomeIntegration.updateFavoriteWidgetAutoRefreshMinutes(
      _settings.favoriteWidgetAutoRefreshMinutes,
    );
    await IOSWidgetIntegration.syncFavoriteGroups(
      _favoriteGroups,
      waitForBridge: true,
    );
    await AndroidHomeIntegration.syncSmartRouteNotifications(
      _settings.enableSmartRouteNotifications,
    );
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

  Future<void> updateEnableSmartRecommendations(bool value) async {
    _settings = _settings.copyWith(enableSmartRecommendations: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateEnableSmartRouteNotifications(bool value) async {
    _settings = _settings.copyWith(enableSmartRouteNotifications: value);
    await storage.saveSettings(_settings);
    await AndroidHomeIntegration.syncSmartRouteNotifications(value);
    notifyListeners();
  }

  Future<void> updateKeepScreenAwakeOnRouteDetail(bool value) async {
    _settings = _settings.copyWith(keepScreenAwakeOnRouteDetail: value);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateEnableRouteBackgroundMonitor(
    bool value, {
    bool markPromptSeen = true,
  }) async {
    _settings = _settings.copyWith(
      enableRouteBackgroundMonitor: value,
      hasSeenRouteBackgroundMonitorPrompt:
          markPromptSeen || _settings.hasSeenRouteBackgroundMonitorPrompt,
    );
    await storage.saveSettings(_settings);
    if (!value) {
      await AndroidTripMonitor.stop();
      await LiveActivityService.endLiveActivity();
    }
    notifyListeners();
  }

  Future<void> updateFavoriteWidgetAutoRefreshMinutes(int value) async {
    _settings = _settings.copyWith(favoriteWidgetAutoRefreshMinutes: value);
    await storage.saveSettings(_settings);
    await AndroidHomeIntegration.updateFavoriteWidgetAutoRefreshMinutes(value);
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
            message: 'An app update check is already in progress.',
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

  Future<void> clearRouteUsageProfiles() async {
    _routeUsageProfiles = const [];
    await storage.saveRouteUsageProfiles(_routeUsageProfiles);
    await AndroidHomeIntegration.syncSmartRouteNotifications(
      _settings.enableSmartRouteNotifications,
    );
    notifyListeners();
  }

  Future<void> clearRouteSelectionHistory() async {
    _routeUsageProfiles =
        _routeUsageProfiles
            .map((profile) => profile.clearSelections())
            .where((profile) => profile.totalInteractions > 0)
            .toList()
          ..sort(_compareRouteUsageProfiles);
    await storage.saveRouteUsageProfiles(_routeUsageProfiles);
    await AndroidHomeIntegration.syncSmartRouteNotifications(
      _settings.enableSmartRouteNotifications,
    );
    notifyListeners();
  }

  Future<void> recordRouteSelection({
    required BusProvider provider,
    required int routeKey,
    required String routeName,
    DateTime? selectedAt,
  }) async {
    final timestamp = selectedAt ?? DateTime.now();
    await _recordRouteActivity(
      provider: provider,
      routeKey: routeKey,
      record: (profile) =>
          profile.recordSelection(timestamp, routeName: routeName),
      create: () => RouteUsageProfile(
        provider: provider,
        routeKey: routeKey,
        routeName: routeName.trim(),
        totalOpens: 0,
        lastOpenedAtMs: 0,
        totalSelections: 1,
        lastSelectedAtMs: timestamp.millisecondsSinceEpoch,
        hourlySelections: <int, int>{timestamp.hour: 1},
      ),
    );
  }

  Future<void> recordRouteVisit(
    RouteSummary route, {
    required BusProvider provider,
    DateTime? openedAt,
  }) async {
    final timestamp = openedAt ?? DateTime.now();
    await _recordRouteActivity(
      provider: provider,
      routeKey: route.routeKey,
      record: (profile) =>
          profile.recordOpen(timestamp, routeName: route.routeName),
      create: () => RouteUsageProfile(
        provider: provider,
        routeKey: route.routeKey,
        routeName: route.routeName,
        totalOpens: 1,
        lastOpenedAtMs: timestamp.millisecondsSinceEpoch,
        hourlyOpens: <int, int>{timestamp.hour: 1},
      ),
    );
  }

  Future<void> _recordRouteActivity({
    required BusProvider provider,
    required int routeKey,
    required RouteUsageProfile Function(RouteUsageProfile profile) record,
    required RouteUsageProfile Function() create,
  }) async {
    final next = <RouteUsageProfile>[];
    var found = false;

    for (final profile in _routeUsageProfiles) {
      if (profile.provider == provider && profile.routeKey == routeKey) {
        next.add(record(profile));
        found = true;
      } else {
        next.add(profile);
      }
    }

    if (!found) {
      next.add(create());
    }

    next.sort(_compareRouteUsageProfiles);
    _routeUsageProfiles = next;
    await storage.saveRouteUsageProfiles(_routeUsageProfiles);
    await AndroidHomeIntegration.syncSmartRouteNotifications(
      _settings.enableSmartRouteNotifications,
    );
    notifyListeners();
  }

  int _compareRouteUsageProfiles(
    RouteUsageProfile left,
    RouteUsageProfile right,
  ) {
    final interactionCompare = right.totalInteractions.compareTo(
      left.totalInteractions,
    );
    if (interactionCompare != 0) {
      return interactionCompare;
    }

    final latestCompare = right.latestInteractionAtMs.compareTo(
      left.latestInteractionAtMs,
    );
    if (latestCompare != 0) {
      return latestCompare;
    }

    return right.totalOpens.compareTo(left.totalOpens);
  }

  Future<SmartRouteSuggestion?> getSmartRouteSuggestion({
    DateTime? now,
    Position? position,
  }) async {
    if (!_settings.enableSmartRecommendations ||
        !_databaseReady ||
        _routeUsageProfiles.isEmpty) {
      return null;
    }

    return SmartRouteService.loadSuggestion(
      repository: repository,
      profiles: _routeUsageProfiles.where(
        (entry) => entry.provider == _settings.provider,
      ),
      now: now ?? DateTime.now(),
      position: position,
    );
  }

  Future<void> addFavoriteGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _favoriteGroups.containsKey(trimmed)) {
      return;
    }

    _favoriteGroups = {..._favoriteGroups, trimmed: <FavoriteStop>[]};
    await storage.saveFavoriteGroups(_favoriteGroups);
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    notifyListeners();
  }

  Future<void> deleteFavoriteGroup(String name) async {
    final next = {..._favoriteGroups};
    next.remove(name);
    _favoriteGroups = next;
    await storage.saveFavoriteGroups(_favoriteGroups);
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
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
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
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
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    notifyListeners();
  }

  List<FavoriteStop> favoritesInGroup(String groupName) {
    return List.unmodifiable(_favoriteGroups[groupName] ?? const []);
  }

  Future<List<FavoriteResolvedItem>> resolveFavoriteGroup(
    String groupName,
  ) async {
    final items = await repository.resolveFavoriteGroup(
      favoritesInGroup(groupName),
    );
    await _persistFavoriteMetadata(groupName, items);
    return items;
  }

  Future<void> _persistFavoriteMetadata(
    String groupName,
    List<FavoriteResolvedItem> items,
  ) async {
    final current = _favoriteGroups[groupName];
    if (current == null || current.isEmpty || items.isEmpty) {
      return;
    }

    final resolvedByKey = <String, FavoriteResolvedItem>{
      for (final item in items)
        '${item.reference.provider.name}:'
                '${item.reference.routeKey}:'
                '${item.reference.pathId}:'
                '${item.reference.stopId}':
            item,
    };

    var didChange = false;
    final updatedGroup = current.map((favorite) {
      final resolved =
          resolvedByKey['${favorite.provider.name}:'
              '${favorite.routeKey}:'
              '${favorite.pathId}:'
              '${favorite.stopId}'];
      if (resolved == null) {
        return favorite;
      }

      final nextRouteName = favorite.routeName?.trim().isNotEmpty == true
          ? favorite.routeName
          : resolved.route.routeName;
      final nextStopName = favorite.stopName?.trim().isNotEmpty == true
          ? favorite.stopName
          : resolved.stop.stopName;

      if (nextRouteName == favorite.routeName &&
          nextStopName == favorite.stopName) {
        return favorite;
      }

      didChange = true;
      return FavoriteStop(
        provider: favorite.provider,
        routeKey: favorite.routeKey,
        pathId: favorite.pathId,
        stopId: favorite.stopId,
        routeName: nextRouteName,
        stopName: nextStopName,
      );
    }).toList();

    if (!didChange) {
      return;
    }

    _favoriteGroups = {..._favoriteGroups, groupName: updatedGroup};
    await storage.saveFavoriteGroups(_favoriteGroups);
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
  }
}
