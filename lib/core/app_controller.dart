import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  static const defaultFavoriteGroupName = '我的最愛';

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
  Map<BusProvider, bool> _databaseReadyByProvider = {
    for (final provider in BusProvider.values) provider: false,
  };
  bool _checkingDatabase = false;
  bool _downloadingDatabase = false;
  bool _checkingAppUpdate = false;
  bool _startupAppUpdateChecked = false;
  bool _startupDatabaseUpdateChecked = false;
  AppUpdateCheckResult? _lastAppUpdateResult;
  Map<BusProvider, int> _pendingDatabaseUpdates = const {};

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
  bool get databaseReady => isDatabaseReady(_settings.provider);
  List<BusProvider> get selectedProviders =>
      List.unmodifiable(_settings.selectedProviders);
  List<BusProvider> get downloadedProviders => BusProvider.values
      .where((provider) => _databaseReadyByProvider[provider] ?? false)
      .toList();
  bool get checkingDatabase => _checkingDatabase;
  bool get downloadingDatabase => _downloadingDatabase;
  bool get needsOnboarding => !_settings.hasCompletedOnboarding;
  bool get checkingAppUpdate => _checkingAppUpdate;
  AppUpdateCheckResult? get lastAppUpdateResult => _lastAppUpdateResult;
  Map<BusProvider, int> get pendingDatabaseUpdates =>
      Map.unmodifiable(_pendingDatabaseUpdates);
  bool get hasPendingDatabaseUpdates => _pendingDatabaseUpdates.isNotEmpty;

  bool isDatabaseReady(BusProvider provider) {
    return _databaseReadyByProvider[provider] ?? false;
  }

  Future<bool> isRouteMetadataDatabaseReady() {
    return repository.routeMetadataDatabaseExists();
  }

  bool shouldAskDownloadPrompt(BusProvider provider) {
    return !_settings.skipDownloadPromptProviders.contains(provider);
  }

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
      final next = <BusProvider, bool>{};
      for (final provider in BusProvider.values) {
        next[provider] = await repository.databaseExists(provider);
      }
      _databaseReadyByProvider = next;
    } finally {
      _checkingDatabase = false;
      notifyListeners();
    }
  }

  Future<void> updateProvider(BusProvider provider) async {
    final selected = _settings.selectedProviders.toSet();
    selected.add(provider);
    _settings = _settings.copyWith(
      provider: provider,
      selectedProviders: selected.toList(),
    );
    await storage.saveSettings(_settings);
    notifyListeners();
    await refreshDatabaseState();
  }

  Future<void> updateSelectedProviders(List<BusProvider> providers) async {
    final normalized = providers.toSet().toList();
    if (normalized.isEmpty) {
      normalized.add(_settings.provider);
    }

    var provider = _settings.provider;
    if (!normalized.contains(provider)) {
      provider = normalized.first;
    }

    _settings = _settings.copyWith(
      provider: provider,
      selectedProviders: normalized,
    );
    await storage.saveSettings(_settings);
    notifyListeners();
    await refreshDatabaseState();
  }

  Future<void> toggleSelectedProvider(BusProvider provider, bool value) async {
    final next = _settings.selectedProviders.toSet();
    if (value) {
      next.add(provider);
    } else {
      next.remove(provider);
    }

    if (next.isEmpty) {
      next.add(_settings.provider);
    }

    await updateSelectedProviders(next.toList());
  }

  Future<void> setSkipDownloadPrompt(BusProvider provider, bool skip) async {
    final next = _settings.skipDownloadPromptProviders.toSet();
    if (skip) {
      next.add(provider);
    } else {
      next.remove(provider);
    }
    _settings = _settings.copyWith(skipDownloadPromptProviders: next.toList());
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode themeMode) async {
    _settings = _settings.copyWith(themeMode: themeMode);
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<void> updateUseAmoledDark(bool value) async {
    _settings = _settings.copyWith(useAmoledDark: value);
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

  Future<void> updateDatabaseAutoUpdateMode(DatabaseAutoUpdateMode value) async {
    _settings = _settings.copyWith(databaseAutoUpdateMode: value);
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
    return downloadProviderDatabase(_settings.provider);
  }

  Future<void> downloadProviderDatabase(BusProvider provider) async {
    await downloadProviderDatabases([provider]);
  }

  Future<void> deleteProviderDatabase(BusProvider provider) async {
    await repository.deleteProviderDatabase(provider);
    _databaseReadyByProvider = {..._databaseReadyByProvider, provider: false};
    _pendingDatabaseUpdates = {
      for (final entry in _pendingDatabaseUpdates.entries)
        if (entry.key != provider) entry.key: entry.value,
    };

    final selected = _settings.selectedProviders.toSet();
    selected.remove(provider);
    if (selected.isEmpty) {
      selected.add(
        _settings.provider == provider ? BusProvider.tpe : _settings.provider,
      );
    }

    var active = _settings.provider;
    if (active == provider || !selected.contains(active)) {
      active = selected.first;
    }

    _settings = _settings.copyWith(
      provider: active,
      selectedProviders: selected.toList(),
    );
    await storage.saveSettings(_settings);
    notifyListeners();
  }

  Future<Map<BusProvider, int?>> checkDatabaseUpdates({
    Iterable<BusProvider>? providers,
  }) async {
    final targetProviders = (providers ?? _settings.selectedProviders).toList();
    final updates = await repository.checkForUpdates(providers: targetProviders);
    final nextPending = {..._pendingDatabaseUpdates};
    for (final provider in targetProviders) {
      final version = updates[provider];
      if (version == null) {
        nextPending.remove(provider);
      } else {
        nextPending[provider] = version;
      }
    }
    _pendingDatabaseUpdates = nextPending;
    notifyListeners();
    return updates;
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

  Future<DatabaseStartupCheckResult?> maybeCheckForDatabaseUpdatesOnLaunch() async {
    if (_startupDatabaseUpdateChecked) {
      return null;
    }
    _startupDatabaseUpdateChecked = true;

    final updates = await checkDatabaseUpdates();
    final availableUpdates = <BusProvider, int>{};
    for (final entry in updates.entries) {
      final version = entry.value;
      if (version != null) {
        availableUpdates[entry.key] = version;
      }
    }

    final connectionKind = await _resolveDatabaseConnectionKind();
    return DatabaseStartupCheckResult(
      mode: _settings.databaseAutoUpdateMode,
      updates: availableUpdates,
      connectionKind: connectionKind,
    );
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

  Future<int?> localVersionForProvider(BusProvider provider) {
    return repository.getLocalVersion(provider);
  }

  Future<void> downloadSelectedProviderDatabases() async {
    await downloadProviderDatabases(_settings.selectedProviders);
  }

  Future<void> downloadProviderDatabases(Iterable<BusProvider> providers) async {
    final targets = providers.toSet().toList();
    if (targets.isEmpty) {
      return;
    }
    _downloadingDatabase = true;
    notifyListeners();
    try {
      for (final provider in targets) {
        await repository.downloadDatabase(provider);
        _databaseReadyByProvider = {
          ..._databaseReadyByProvider,
          provider: true,
        };
        _pendingDatabaseUpdates = {
          for (final entry in _pendingDatabaseUpdates.entries)
            if (entry.key != provider) entry.key: entry.value,
        };
      }
    } finally {
      _downloadingDatabase = false;
      notifyListeners();
    }
  }

  Future<void> updateSelectedProviderDatabasesIfNeeded() async {
    final updates = await checkDatabaseUpdates();
    final targets = updates.entries
        .where((entry) => entry.value != null)
        .map((entry) => entry.key)
        .toList();
    if (targets.isEmpty) {
      return;
    }
    await downloadProviderDatabases(targets);
  }

  Future<List<RouteSummary>> searchRoutes(
    String query, {
    BusProvider? provider,
  }) async {
    final targetProvider = provider ?? _settings.provider;
    if (isDatabaseReady(targetProvider)) {
      return repository.searchRoutes(query, provider: targetProvider);
    }
    if (shouldAskDownloadPrompt(targetProvider)) {
      throw DatabaseNotReadyException('尚未下載 ${targetProvider.label} 資料庫。');
    }
    return repository.searchRoutesFromApi(query, provider: targetProvider);
  }

  Future<List<RouteSummary>> searchRoutesAcrossSelected(String query) async {
    final results = <RouteSummary>[];
    for (final provider in _settings.selectedProviders) {
      if (isDatabaseReady(provider)) {
        results.addAll(
          await repository.searchRoutes(query, provider: provider),
        );
      } else if (!shouldAskDownloadPrompt(provider)) {
        results.addAll(
          await repository.searchRoutesFromApi(query, provider: provider),
        );
      }
    }

    results.sort((left, right) {
      final leftDownloaded = isDatabaseReady(
        busProviderFromString(left.sourceProvider),
      );
      final rightDownloaded = isDatabaseReady(
        busProviderFromString(right.sourceProvider),
      );
      if (leftDownloaded != rightDownloaded) {
        return leftDownloaded ? -1 : 1;
      }
      return left.routeName.compareTo(right.routeName);
    });

    return results;
  }

  Future<List<RouteSummary>> searchRoutesViaApi(
    String query, {
    required BusProvider provider,
  }) {
    return repository.searchRoutesFromApi(query, provider: provider);
  }

  Future<RouteDetailData> getRouteDetail(
    int routeKey, {
    BusProvider? provider,
    String? routeIdHint,
    String? routeNameHint,
  }) {
    return repository.getCompleteBusInfo(
      routeKey,
      provider: provider ?? _settings.provider,
      routeIdHint: routeIdHint,
      routeNameHint: routeNameHint,
    );
  }

  Future<List<RouteAlert>> getRouteAlerts(String routeId) {
    return repository.fetchRouteAlerts(routeId);
  }

  Future<List<NearbyStopResult>> getNearbyStops({
    required double latitude,
    required double longitude,
    BusProvider? provider,
  }) async {
    final targetProvider =
        provider ??
        nearestBusProvider(latitude: latitude, longitude: longitude);
    if (!isDatabaseReady(targetProvider)) {
      throw StateError('目前定位為 ${targetProvider.label}，尚未下載該縣市資料庫。');
    }
    return repository.fetchNearbyStops(
      provider: targetProvider,
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
        routeId: route.routeId,
        pathName: route.description.trim().isNotEmpty ? route.description.trim() : null,
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
        !isDatabaseReady(_settings.provider) ||
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
    final existingIndex = next[targetGroup]!.indexWhere(
      (item) => item.sameAs(favorite),
    );
    if (existingIndex == -1) {
      next[targetGroup]!.add(favorite);
    } else {
      final existing = next[targetGroup]![existingIndex];
      final routeId = favorite.routeId?.trim().isNotEmpty == true
          ? favorite.routeId
          : existing.routeId;
      final routeName = favorite.routeName?.trim().isNotEmpty == true
          ? favorite.routeName
          : existing.routeName;
      final stopName = favorite.stopName?.trim().isNotEmpty == true
          ? favorite.stopName
          : existing.stopName;
      final destinationStopId = favorite.destinationStopId;
      final mergedDestinationStopId =
          destinationStopId ?? existing.destinationStopId;
      final mergedDestinationPathId = mergedDestinationStopId == null
          ? null
          : (destinationStopId == null
                ? existing.destinationPathId
                : (favorite.destinationPathId ?? favorite.pathId));
      final mergedDestinationStopName = destinationStopId == null
          ? existing.destinationStopName
          : favorite.destinationStopName;

      next[targetGroup]![existingIndex] = FavoriteStop(
        provider: favorite.provider,
        routeKey: favorite.routeKey,
        pathId: favorite.pathId,
        stopId: favorite.stopId,
        routeId: routeId,
        routeName: routeName,
        stopName: stopName,
        destinationPathId: mergedDestinationPathId,
        destinationStopId: mergedDestinationStopId,
        destinationStopName: mergedDestinationStopName,
      );
    }

    _favoriteGroups = next;
    await storage.saveFavoriteGroups(_favoriteGroups);
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    notifyListeners();
    return targetGroup;
  }

  Future<bool> updateFavoriteDestination(
    String groupName,
    FavoriteStop favorite, {
    int? destinationPathId,
    int? destinationStopId,
    String? destinationStopName,
  }) async {
    final currentGroup = _favoriteGroups[groupName];
    if (currentGroup == null || currentGroup.isEmpty) {
      return false;
    }

    final normalizedDestinationStopId =
        destinationStopId != null && destinationStopId > 0
        ? destinationStopId
        : null;
    final normalizedDestinationPathId = normalizedDestinationStopId == null
        ? null
        : (destinationPathId ?? favorite.pathId);
    final normalizedDestinationStopName = normalizedDestinationStopId == null
        ? null
        : (destinationStopName?.trim().isNotEmpty == true
              ? destinationStopName!.trim()
              : null);

    var found = false;
    var didChange = false;
    final updatedGroup = currentGroup.map((item) {
      if (!item.sameAs(favorite)) {
        return item;
      }

      found = true;
      if (item.destinationPathId == normalizedDestinationPathId &&
          item.destinationStopId == normalizedDestinationStopId &&
          item.destinationStopName == normalizedDestinationStopName) {
        return item;
      }

      didChange = true;
      return FavoriteStop(
        provider: item.provider,
        routeKey: item.routeKey,
        pathId: item.pathId,
        stopId: item.stopId,
        routeId: item.routeId,
        routeName: item.routeName,
        stopName: item.stopName,
        destinationPathId: normalizedDestinationPathId,
        destinationStopId: normalizedDestinationStopId,
        destinationStopName: normalizedDestinationStopName,
      );
    }).toList();

    if (!found || !didChange) {
      return false;
    }

    _favoriteGroups = {..._favoriteGroups, groupName: updatedGroup};
    await storage.saveFavoriteGroups(_favoriteGroups);
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    notifyListeners();
    return true;
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
      final nextRouteId = favorite.routeId?.trim().isNotEmpty == true
          ? favorite.routeId
          : (resolved.route.routeId.trim().isNotEmpty
                ? resolved.route.routeId
                : null);

      if (nextRouteName == favorite.routeName &&
          nextStopName == favorite.stopName &&
          nextRouteId == favorite.routeId) {
        return favorite;
      }

      didChange = true;
      return FavoriteStop(
        provider: favorite.provider,
        routeKey: favorite.routeKey,
        pathId: favorite.pathId,
        stopId: favorite.stopId,
        routeId: nextRouteId,
        routeName: nextRouteName,
        stopName: nextStopName,
        destinationPathId: favorite.destinationPathId,
        destinationStopId: favorite.destinationStopId,
        destinationStopName: favorite.destinationStopName,
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

  Future<DatabaseConnectionKind> _resolveDatabaseConnectionKind() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.wifi)) {
        return DatabaseConnectionKind.wifi;
      }
      if (results.contains(ConnectivityResult.mobile)) {
        return DatabaseConnectionKind.cellular;
      }
      if (results.contains(ConnectivityResult.none)) {
        return DatabaseConnectionKind.offline;
      }
      if (results.any((result) => result != ConnectivityResult.none)) {
        return DatabaseConnectionKind.other;
      }
    } catch (_) {
      return DatabaseConnectionKind.unknown;
    }
    return DatabaseConnectionKind.unknown;
  }
}
