import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';

import 'android_home_integration.dart';
import 'announcement_models.dart';
import 'announcement_service.dart';
import 'account_sync_models.dart';
import 'account_sync_service.dart';
import 'android_trip_monitor.dart';
import 'app_analytics.dart';
import 'app_build_info.dart';
import 'app_launch_service.dart';
import 'app_update_installer.dart';
import 'app_update_service.dart';
import 'auth_service.dart';
import 'auth_token_store.dart';
import 'background_image_store.dart';
import 'bus_repository.dart';
import 'desktop_discord_presence_service.dart';
import 'ios_widget_integration.dart';
import 'live_activity_service.dart';
import 'models.dart';
import 'smart_route_service.dart';
import 'storage_service.dart';
import 'wear_os_integration.dart';

/// Thrown when the total number of favorite stops across all groups
/// has reached the maximum allowed limit.
class FavoriteGroupFullException implements Exception {
  final String groupName;
  final int maxStops;
  FavoriteGroupFullException(this.groupName, this.maxStops);

  @override
  String toString() =>
      'FavoriteGroupFullException: already have $maxStops favorite stops total';
}

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.storage,
    required this.analytics,
    required this.buildInfo,
    required this.appUpdateService,
    required this.appUpdateInstaller,
    required this.authService,
    required this.accountSyncService,
    AnnouncementService? announcementService,
  }) : announcementService = announcementService ?? AnnouncementService();

  static const defaultFavoriteGroupName = '收藏';
  static const Duration _accountSyncDebounce = Duration(seconds: 3);
  static const Duration _foregroundAccountSyncCooldown = Duration(minutes: 1);

  final BusRepository repository;
  final StorageService storage;
  final AppAnalytics analytics;
  final AppBuildInfo buildInfo;
  final AppUpdateService appUpdateService;
  final AppUpdateInstaller appUpdateInstaller;
  final AuthService authService;
  final AccountSyncService accountSyncService;
  final AnnouncementService announcementService;
  final BackgroundImageStore _backgroundImageStore = BackgroundImageStore();

  AppSettings _settings = AppSettings.defaults();
  AuthSession? _authSession;
  AuthAccount? _authAccount;
  AccountSyncLocalState _accountSyncLocalState = AccountSyncLocalState.empty();
  AccountSyncSummary? _accountSyncSummary;
  AnnouncementLocalState _announcementLocalState =
      AnnouncementLocalState.empty();
  List<AppAnnouncement> _announcements = const [];
  List<SearchHistoryEntry> _history = const [];
  Map<String, List<FavoriteStop>> _favoriteGroups = const {};
  List<RouteUsageProfile> _routeUsageProfiles = const [];
  List<FavoriteUsageProfile> _favoriteUsageProfiles = const [];
  int? _settingsLastModifiedAtMs;
  int? _favoriteGroupsLastModifiedAtMs;
  bool _initialized = false;
  Map<BusProvider, bool> _databaseReadyByProvider = {
    for (final provider in BusProvider.values) provider: false,
  };
  bool _checkingDatabase = false;
  bool _downloadingDatabase = false;
  bool _checkingAppUpdate = false;
  bool _authBusy = false;
  bool _authAccountLoading = false;
  bool _accountSyncBusy = false;
  bool _announcementsLoading = false;
  bool _startupAppUpdateChecked = false;
  bool _startupDatabaseUpdateChecked = false;
  AppUpdateCheckResult? _lastAppUpdateResult;
  Map<BusProvider, int> _pendingDatabaseUpdates = const {};
  String? _announcementsError;
  String? _accountSyncError;
  Timer? _scheduledAccountSyncTimer;
  int? _lastForegroundAccountSyncAtMs;
  String? _lastWearSmartSignature;
  int _lastWearSmartPushAtMs = 0;
  StreamSubscription<Map<String, Object?>>? _wearEventSubscription;

  AppSettings get settings => _settings;
  AuthSession? get authSession => _authSession;
  AuthAccount? get authAccount => _authAccount;
  AccountSyncSummary? get accountSyncSummary => _accountSyncSummary;
  bool get isAuthenticated => _authSession?.isAuthenticated ?? false;
  List<AppAnnouncement> get announcements => List.unmodifiable(_announcements);
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
      .followedBy(
        _favoriteUsageProfiles.map(
          (entry) =>
              '${entry.provider.name}:'
              '${entry.routeKey}:'
              '${entry.pathId}:'
              '${entry.stopId}:'
              '${entry.totalSelectionsAt()}:'
              '${entry.lastSelectedAtMsAt()}',
        ),
      )
      .followedBy(
        _favoriteGroups.entries.expand(
          (entry) => entry.value.map(
            (favorite) =>
                '${entry.key}:'
                '${favorite.provider.name}:'
                '${favorite.routeKey}:'
                '${favorite.pathId}:'
                '${favorite.stopId}:'
                '${favorite.stopName ?? ''}:'
                '${favorite.destinationPathId ?? 0}:'
                '${favorite.destinationStopId ?? 0}:'
                '${favorite.destinationStopName ?? ''}',
          ),
        ),
      )
      .join('|');
  bool get initialized => _initialized;
  bool get databaseReady => isDatabaseReady(_settings.provider);
  List<BusProvider> get selectedProviders =>
      List.unmodifiable(_settings.selectedProviders);
  List<BusProvider> get downloadedProviders => downloadableBusProviders()
      .where((provider) => _databaseReadyByProvider[provider] ?? false)
      .toList();
  List<BusProvider> get searchProviders {
    if (kIsWeb) {
      return List.unmodifiable(BusProvider.values);
    }
    final ordered = <BusProvider>[];
    final currentProvider = _settings.provider.supportsLocalDatabase
        ? _settings.provider
        : null;
    if (currentProvider != null) {
      ordered.add(currentProvider);
    }
    ordered.add(BusProvider.inter);
    for (final provider in _settings.selectedProviders) {
      if (!provider.supportsLocalDatabase || provider == currentProvider) {
        continue;
      }
      ordered.add(provider);
    }
    return List.unmodifiable(ordered);
  }

  bool get checkingDatabase => _checkingDatabase;
  bool get downloadingDatabase => _downloadingDatabase;
  bool get needsOnboarding => !_settings.hasCompletedOnboarding;
  bool get checkingAppUpdate => _checkingAppUpdate;
  bool get authBusy => _authBusy;
  bool get authAccountLoading => _authAccountLoading;
  bool get accountSyncBusy => _accountSyncBusy;
  bool get announcementsLoading => _announcementsLoading;
  AppUpdateCheckResult? get lastAppUpdateResult => _lastAppUpdateResult;
  Map<BusProvider, int> get pendingDatabaseUpdates =>
      Map.unmodifiable(_pendingDatabaseUpdates);
  bool get hasPendingDatabaseUpdates => _pendingDatabaseUpdates.isNotEmpty;
  String? get announcementsError => _announcementsError;
  String? get accountSyncError => _accountSyncError;
  bool get accountSyncEnabled => _accountSyncLocalState.syncEnabled == true;
  bool get shouldPromptToEnableAccountSync =>
      isAuthenticated && _accountSyncLocalState.syncEnabled == null;
  DateTime? get settingsLastModifiedAt =>
      _dateTimeFromMs(_settingsLastModifiedAtMs);
  DateTime? get favoriteGroupsLastModifiedAt =>
      _dateTimeFromMs(_favoriteGroupsLastModifiedAtMs);
  DateTime? get lastAccountSyncAt {
    final timestamps = <int>[
      if (_accountSyncLocalState.favorites.lastSuccessfulSyncAtMs != null)
        _accountSyncLocalState.favorites.lastSuccessfulSyncAtMs!,
      if (_accountSyncLocalState.preferences.lastSuccessfulSyncAtMs != null)
        _accountSyncLocalState.preferences.lastSuccessfulSyncAtMs!,
    ];
    if (timestamps.isEmpty) {
      return null;
    }
    timestamps.sort();
    return DateTime.fromMillisecondsSinceEpoch(timestamps.last);
  }

  bool get hasUnreadAnnouncements => _announcements.any(
    (announcement) => announcementService.shouldShowRedDot(
      announcement,
      _announcementLocalState,
    ),
  );

  bool isDatabaseReady(BusProvider provider) {
    return _databaseReadyByProvider[provider] ?? false;
  }

  Future<bool> isRouteMetadataDatabaseReady() {
    return repository.routeMetadataDatabaseExists();
  }

  bool shouldAskDownloadPrompt(BusProvider provider) {
    if (!provider.supportsLocalDatabase) {
      return false;
    }
    return !_settings.skipDownloadPromptProviders.contains(provider);
  }

  Future<void> initialize() async {
    await storage.migrateLegacyApiDataIfNeeded();
    await authService.initialize();
    _authSession = authService.session;
    await _loadAccountSyncLocalState();
    _settings = await storage.loadSettings();
    _settingsLastModifiedAtMs = await storage.loadSettingsLastModifiedAtMs();
    final normalizedBackgroundPaths = await _backgroundImageStore
        .normalizeSettingsPaths(_settings.pageBackgroundImagePaths);
    final normalizedBackgroundOpacities = Map<String, double>.from(
      _settings.pageBackgroundImageOpacities,
    )..removeWhere((key, _) => !normalizedBackgroundPaths.containsKey(key));
    if (!mapEquals(
          _settings.pageBackgroundImagePaths,
          normalizedBackgroundPaths,
        ) ||
        !mapEquals(
          _settings.pageBackgroundImageOpacities,
          normalizedBackgroundOpacities,
        )) {
      _settings = _settings.copyWith(
        pageBackgroundImagePaths: normalizedBackgroundPaths,
        pageBackgroundImageOpacities: normalizedBackgroundOpacities,
      );
      await _persistSettings(modifiedAtMs: _settingsLastModifiedAtMs);
    }
    _announcementLocalState = await storage.loadAnnouncementLocalState();
    _history = await storage.loadHistory();
    _favoriteGroups = await storage.loadFavoriteGroups();
    _favoriteGroupsLastModifiedAtMs = await storage
        .loadFavoriteGroupsLastModifiedAtMs();
    _routeUsageProfiles = await storage.loadRouteUsageProfiles();
    _favoriteUsageProfiles = await storage.loadFavoriteUsageProfiles();
    await AndroidHomeIntegration.updateFavoriteWidgetAutoRefreshMinutes(
      _settings.favoriteWidgetAutoRefreshMinutes,
    );
    await IOSWidgetIntegration.syncFavoriteGroups(
      _favoriteGroups,
      waitForBridge: true,
    );
    await _normalizeWearSelectedFavoriteIds(scheduleSync: false);
    await _syncWearOsSnapshot(requestRefresh: false);
    _attachWearOsEventStream();
    await AndroidHomeIntegration.syncSmartRouteNotifications(
      _settings.enableSmartRouteNotifications,
    );
    await refreshDatabaseState();
    await desktopDiscordPresenceService.refresh(settings: _settings);

    // Validate the persisted token against the server. If the token has
    // expired or been revoked the server will return 401/403, and we
    // silently clear the local session so the user sees the logged-out UI
    // instead of a stale authenticated state.
    if (_authSession != null) {
      try {
        _authAccount = await authService.fetchAccount();
      } on AuthTokenExpiredException {
        await _forceLocalLogout();
      } catch (_) {
        // Network errors are non-fatal; keep the session for now.
        _authAccount = null;
      }
    }

    if (accountSyncEnabled) {
      scheduleForegroundAccountSync(force: true);
    }

    _initialized = true;
    notifyListeners();
  }

  Future<bool> startAuthLogin(String provider) async {
    if (_authBusy) {
      return false;
    }
    _authBusy = true;
    notifyListeners();
    try {
      final opened = await authService.startLogin(provider);
      if (authService.session != _authSession) {
        _authSession = authService.session;
        if (_authSession != null) {
          await _loadAccountSyncLocalState();
          try {
            _authAccount = await authService.fetchAccount();
          } on AuthTokenExpiredException {
            await _forceLocalLogout();
          } catch (_) {
            _authAccount = null;
          }
          if (accountSyncEnabled) {
            scheduleForegroundAccountSync(force: true);
          }
        } else {
          _clearAccountSyncSessionData();
        }
      }
      return opened;
    } finally {
      _authBusy = false;
      notifyListeners();
    }
  }

  Future<void> completeAuthCallback(AppLaunchAction action) async {
    if (action.authError?.isNotEmpty == true) {
      throw Exception(action.authError);
    }
    final token = action.authToken;
    if (token == null || token.isEmpty) {
      throw Exception('Auth callback did not include a token.');
    }
    await authService.completeCallback(
      token: token,
      accountId: action.authAccountId ?? '',
      deviceId: action.authDeviceId ?? '',
      role: action.authRole ?? 'user',
      provider: action.authProvider ?? '',
      displayName: action.authDisplayName ?? '',
    );
    _authSession = authService.session;
    await _loadAccountSyncLocalState();
    try {
      _authAccount = await authService.fetchAccount();
    } on AuthTokenExpiredException {
      await _forceLocalLogout();
    } catch (_) {
      _authAccount = null;
    }
    if (accountSyncEnabled) {
      scheduleForegroundAccountSync(force: true);
    }
    notifyListeners();
  }

  Future<void> refreshAuthAccount() async {
    if (_authSession == null) {
      _authAccount = null;
      notifyListeners();
      return;
    }
    if (_authAccountLoading) {
      return;
    }

    _authAccountLoading = true;
    notifyListeners();
    try {
      _authAccount = await authService.fetchAccount();
    } on AuthTokenExpiredException {
      _authAccountLoading = false;
      await _forceLocalLogout();
      return;
    } finally {
      _authAccountLoading = false;
      notifyListeners();
    }
  }

  Future<void> logoutAuth() async {
    if (_authBusy) {
      return;
    }
    _authBusy = true;
    notifyListeners();
    try {
      await authService.logout();
      _authSession = null;
      _authAccount = null;
      _cancelScheduledAccountSync();
      _clearAccountSyncSessionData();
    } finally {
      _authBusy = false;
      notifyListeners();
    }
  }

  /// Silently clears the local auth state without contacting the server.
  /// Used when the server has already rejected the token (401/403), so
  /// there is no point in calling the server logout endpoint.
  Future<void> _forceLocalLogout() async {
    await authService.logout();
    _authSession = null;
    _authAccount = null;
    _cancelScheduledAccountSync();
    _clearAccountSyncSessionData();
    notifyListeners();
  }

  Future<void> _persistSettings({
    int? modifiedAtMs,
    bool scheduleSync = true,
  }) async {
    final effectiveModifiedAtMs =
        modifiedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    await storage.saveSettings(_settings, modifiedAtMs: effectiveModifiedAtMs);
    _settingsLastModifiedAtMs = effectiveModifiedAtMs;
    if (scheduleSync) {
      _scheduleChangeDrivenAccountSync();
    }
  }

  Future<void> _persistFavoriteGroups({
    int? modifiedAtMs,
    bool scheduleSync = true,
  }) async {
    final effectiveModifiedAtMs =
        modifiedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    await storage.saveFavoriteGroups(
      _favoriteGroups,
      modifiedAtMs: effectiveModifiedAtMs,
    );
    _favoriteGroupsLastModifiedAtMs = effectiveModifiedAtMs;
    if (scheduleSync) {
      _scheduleChangeDrivenAccountSync();
    }
  }

  Future<void> _loadAccountSyncLocalState() async {
    final accountId = _authSession?.accountId.trim() ?? '';
    if (accountId.isEmpty) {
      _accountSyncLocalState = AccountSyncLocalState.empty();
      _accountSyncSummary = null;
      _accountSyncError = null;
      return;
    }
    _accountSyncLocalState = await storage.loadAccountSyncLocalState(accountId);
    _accountSyncSummary = null;
    _accountSyncError = null;
  }

  Future<void> _saveAccountSyncLocalState() async {
    final accountId = _authSession?.accountId.trim() ?? '';
    if (accountId.isEmpty) {
      return;
    }
    await storage.saveAccountSyncLocalState(accountId, _accountSyncLocalState);
  }

  void _clearAccountSyncSessionData() {
    _accountSyncLocalState = AccountSyncLocalState.empty();
    _accountSyncSummary = null;
    _accountSyncError = null;
  }

  Future<void> setAccountSyncEnabled(
    bool enabled, {
    bool syncNow = true,
  }) async {
    _accountSyncLocalState = _accountSyncLocalState.copyWith(
      syncEnabled: enabled,
    );
    await _saveAccountSyncLocalState();
    notifyListeners();
    if (!enabled) {
      _cancelScheduledAccountSync();
      return;
    }
    if (syncNow) {
      await syncAllAccountData();
    } else {
      scheduleForegroundAccountSync(force: true);
    }
  }

  void scheduleForegroundAccountSync({bool force = false}) {
    if (!accountSyncEnabled || !isAuthenticated) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        _lastForegroundAccountSyncAtMs != null &&
        nowMs - _lastForegroundAccountSyncAtMs! <
            _foregroundAccountSyncCooldown.inMilliseconds) {
      return;
    }
    _lastForegroundAccountSyncAtMs = nowMs;
    _scheduleAccountSync(delay: Duration.zero);
  }

  void _scheduleChangeDrivenAccountSync() {
    if (!accountSyncEnabled || !isAuthenticated) {
      return;
    }
    _scheduleAccountSync(delay: _accountSyncDebounce);
  }

  void _scheduleAccountSync({required Duration delay}) {
    _scheduledAccountSyncTimer?.cancel();
    _scheduledAccountSyncTimer = Timer(delay, () {
      _scheduledAccountSyncTimer = null;
      unawaited(_runScheduledAccountSync());
    });
  }

  void _cancelScheduledAccountSync() {
    _scheduledAccountSyncTimer?.cancel();
    _scheduledAccountSyncTimer = null;
  }

  Future<void> _runScheduledAccountSync() async {
    if (!accountSyncEnabled || !isAuthenticated) {
      return;
    }
    if (_accountSyncBusy) {
      _scheduleAccountSync(delay: _accountSyncDebounce);
      return;
    }
    try {
      await syncAllAccountData();
    } catch (_) {
      // Keep the last sync error on the controller, but avoid interrupting
      // the user with an automatic-sync exception.
    }
  }

  AccountSyncNamespaceStatus accountSyncStatusFor(
    AccountSyncNamespace namespace,
  ) {
    return AccountSyncNamespaceStatus(
      namespace: namespace,
      localState: _accountSyncLocalState.stateFor(namespace),
      serverDocument: _accountSyncSummary?.documents[namespace],
      localModifiedAt: switch (namespace) {
        AccountSyncNamespace.favorites => favoriteGroupsLastModifiedAt,
        AccountSyncNamespace.preferences => settingsLastModifiedAt,
      },
    );
  }

  Future<void> refreshAccountSyncStatus() {
    if (_authSession == null) {
      _clearAccountSyncSessionData();
      notifyListeners();
      return Future.value();
    }
    return _runAccountSyncOperation(() async {
      await _refreshAccountSyncStatusCore();
    });
  }

  Future<void> syncAccountNamespace(
    AccountSyncNamespace namespace, {
    AccountSyncConflictPolicy conflictPolicy = AccountSyncConflictPolicy.abort,
  }) {
    return _runAccountSyncOperation(() async {
      _cancelScheduledAccountSync();
      await _syncAccountNamespaceCore(
        namespace,
        conflictPolicy: conflictPolicy,
      );
    });
  }

  Future<void> restoreAccountNamespace(AccountSyncNamespace namespace) {
    return _runAccountSyncOperation(() async {
      _cancelScheduledAccountSync();
      await _restoreAccountNamespaceCore(namespace);
    });
  }

  Future<void> syncAllAccountData({
    AccountSyncConflictPolicy conflictPolicy = AccountSyncConflictPolicy.abort,
  }) {
    return _runAccountSyncOperation(() async {
      _cancelScheduledAccountSync();
      await _refreshAccountSyncStatusCore();
      await _syncFavoritesWithSmartStrategy(
        preferredConflictPolicy: conflictPolicy,
      );
      await _syncPreferencesWithSmartStrategy();
    });
  }

  Future<void> restoreAllAccountData() {
    return _runAccountSyncOperation(() async {
      _cancelScheduledAccountSync();
      await _restoreAccountNamespaceCore(AccountSyncNamespace.favorites);
      await _restoreAccountNamespaceCore(AccountSyncNamespace.preferences);
    });
  }

  Future<void> _refreshAccountSyncStatusCore() async {
    final summary = await accountSyncService.fetchSummary();
    _accountSyncSummary = summary;
    _accountSyncError = null;
  }

  Future<void> _syncFavoritesWithSmartStrategy({
    required AccountSyncConflictPolicy preferredConflictPolicy,
  }) async {
    final namespace = AccountSyncNamespace.favorites;
    final status = accountSyncStatusFor(namespace);
    final localFavoriteCount = _favoriteGroups.values.fold<int>(
      0,
      (total, group) => total + group.length,
    );
    final effectiveConflictPolicy =
        preferredConflictPolicy == AccountSyncConflictPolicy.abort
        ? AccountSyncConflictPolicy.merge
        : preferredConflictPolicy;

    if (localFavoriteCount == 0 && status.hasCloudData) {
      await _restoreAccountNamespaceCore(namespace);
      return;
    }
    if (!status.hasCloudData) {
      if (localFavoriteCount > 0 || status.localChanges) {
        await _syncAccountNamespaceCore(
          namespace,
          conflictPolicy: effectiveConflictPolicy,
        );
      }
      return;
    }
    if (status.cloudChanges && !status.localChanges) {
      await _restoreAccountNamespaceCore(namespace);
      return;
    }
    if (status.localChanges || !status.hasEverSynced) {
      await _syncAccountNamespaceCore(
        namespace,
        conflictPolicy: effectiveConflictPolicy,
      );
    }
  }

  Future<void> _syncPreferencesWithSmartStrategy() async {
    final namespace = AccountSyncNamespace.preferences;
    final status = accountSyncStatusFor(namespace);

    if (status.hasCloudData && !status.hasEverSynced && !status.localChanges) {
      await _restoreAccountNamespaceCore(namespace);
      return;
    }
    if (status.cloudChanges && !status.localChanges) {
      await _restoreAccountNamespaceCore(namespace);
      return;
    }
    if (!status.hasCloudData || status.localChanges || !status.hasEverSynced) {
      await _syncAccountNamespaceCore(
        namespace,
        conflictPolicy: AccountSyncConflictPolicy.clientWins,
      );
    }
  }

  Future<void> _syncAccountNamespaceCore(
    AccountSyncNamespace namespace, {
    required AccountSyncConflictPolicy conflictPolicy,
  }) async {
    final session = _authSession;
    if (session == null || !session.isAuthenticated) {
      throw const AuthTokenExpiredException('登入後才能同步帳號資料。');
    }

    final localState = _accountSyncLocalState.stateFor(namespace);
    final localModifiedAtMs =
        _localModifiedAtMsForNamespace(namespace) ??
        DateTime.now().millisecondsSinceEpoch;
    final result = await accountSyncService.upsertDocument(
      namespace: namespace,
      payload: _buildSyncPayload(namespace),
      clientModifiedAt: DateTime.fromMillisecondsSinceEpoch(localModifiedAtMs),
      schemaVersion: namespace.schemaVersion,
      conflictPolicy: conflictPolicy,
      baseRevision: localState.lastSyncedServerRevision,
      baseEtag: localState.lastSyncedServerEtag,
    );

    final document = result.document;
    if (document != null) {
      await _applyRemoteDocument(namespace, document);
      return;
    }

    await _refreshAccountSyncStatusCore();
  }

  Future<void> _restoreAccountNamespaceCore(
    AccountSyncNamespace namespace,
  ) async {
    final session = _authSession;
    if (session == null || !session.isAuthenticated) {
      throw const AuthTokenExpiredException('登入後才能同步帳號資料。');
    }

    final document = await accountSyncService.fetchDocument(namespace);
    if (!document.hasData || document.payload == null) {
      throw Exception('${namespace.label} 尚未有可用的雲端備份。');
    }

    await _applyRemoteDocument(namespace, document);
  }

  Future<void> _applyRemoteDocument(
    AccountSyncNamespace namespace,
    AccountSyncDocument document,
  ) async {
    final updatedAtMs =
        document.updatedAt?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;

    switch (namespace) {
      case AccountSyncNamespace.favorites:
        _favoriteGroups = _favoriteGroupsFromSyncPayload(document.payload);
        await _persistFavoriteGroups(
          modifiedAtMs: updatedAtMs,
          scheduleSync: false,
        );
        await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
        await AndroidHomeIntegration.refreshFavoriteWidgets();
        await _syncWearOsSnapshot(requestRefresh: false);
      case AccountSyncNamespace.preferences:
        _settings = _settingsFromSyncPayload(document.payload);
        await _persistSettings(modifiedAtMs: updatedAtMs, scheduleSync: false);
        await _applySettingsSideEffects();
    }

    final previous = _accountSyncLocalState.stateFor(namespace);
    _accountSyncLocalState = _accountSyncLocalState.copyWithNamespace(
      namespace,
      previous.copyWith(
        lastSuccessfulSyncAtMs:
            document.lastSyncedAt?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        lastSyncedLocalModifiedAtMs: updatedAtMs,
        lastSyncedServerRevision: document.revision,
        lastSyncedServerEtag: document.etag,
        lastSyncedServerUpdatedAt: document.updatedAt
            ?.toUtc()
            .toIso8601String(),
        preservedPayload: namespace == AccountSyncNamespace.preferences
            ? document.payload
            : null,
        clearPreservedPayload: namespace == AccountSyncNamespace.favorites,
      ),
    );
    await _saveAccountSyncLocalState();
    _accountSyncSummary =
        (_accountSyncSummary ??
                const AccountSyncSummary(serverTime: null, documents: {}))
            .copyWithDocument(document);
    _accountSyncError = null;
  }

  Future<void> _applySettingsSideEffects() async {
    await AndroidHomeIntegration.updateFavoriteWidgetAutoRefreshMinutes(
      _settings.favoriteWidgetAutoRefreshMinutes,
    );
    await AndroidHomeIntegration.syncSmartRouteNotifications(
      _settings.enableSmartRouteNotifications,
    );
    await desktopDiscordPresenceService.refresh(settings: _settings);
    await _syncWearOsSnapshot(requestRefresh: false);
  }

  List<String> _availableWearFavoriteIds() {
    final seen = <String>{};
    final ids = <String>[];
    for (final favorites in _favoriteGroups.values) {
      for (final favorite in favorites) {
        if (seen.add(favorite.stableKey)) {
          ids.add(favorite.stableKey);
        }
      }
    }
    return ids;
  }

  Future<void> _normalizeWearSelectedFavoriteIds({
    bool selectAllIfEmpty = false,
    bool scheduleSync = true,
  }) async {
    final availableIds = _availableWearFavoriteIds();
    final availableSet = availableIds.toSet();
    var nextIds = _settings.wearSelectedFavoriteIds
        .where(availableSet.contains)
        .toSet()
        .toList(growable: false);
    if (selectAllIfEmpty && nextIds.isEmpty && availableIds.isNotEmpty) {
      nextIds = availableIds;
    }
    if (listEquals(nextIds, _settings.wearSelectedFavoriteIds)) {
      return;
    }

    _settings = _settings.copyWith(wearSelectedFavoriteIds: nextIds);
    await _persistSettings(scheduleSync: scheduleSync);
  }

  List<_WearFavoriteSelection> _selectedWearFavorites() {
    if (!_settings.wearSyncEnabled) {
      return const <_WearFavoriteSelection>[];
    }

    final selectedIds = _settings.wearSelectedFavoriteIds.toSet();
    if (selectedIds.isEmpty) {
      return const <_WearFavoriteSelection>[];
    }

    final result = <_WearFavoriteSelection>[];
    for (final entry in _favoriteGroups.entries) {
      for (final favorite in entry.value) {
        if (!selectedIds.contains(favorite.stableKey)) {
          continue;
        }
        result.add(
          _WearFavoriteSelection(groupName: entry.key, favorite: favorite),
        );
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _buildWearFavoritePayload() async {
    final selectedFavorites = _selectedWearFavorites();
    if (selectedFavorites.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final needsMetadata = selectedFavorites
        .map((entry) => entry.favorite)
        .where(
          (favorite) =>
              favorite.routeId?.trim().isNotEmpty != true ||
              favorite.routeName?.trim().isNotEmpty != true ||
              favorite.stopName?.trim().isNotEmpty != true,
        )
        .toList(growable: false);

    final resolvedByKey = <String, FavoriteResolvedItem>{};
    if (needsMetadata.isNotEmpty) {
      try {
        final resolvedItems = await repository.resolveFavoriteGroup(
          needsMetadata,
        );
        for (final item in resolvedItems) {
          resolvedByKey[item.reference.stableKey] = item;
        }
      } catch (_) {
        // Keep syncing any favorites that already have enough metadata.
      }
    }

    final payload = <Map<String, dynamic>>[];
    for (final selection in selectedFavorites) {
      final favorite = selection.favorite;
      final resolved = resolvedByKey[favorite.stableKey];
      final routeId = favorite.routeId?.trim().isNotEmpty == true
          ? favorite.routeId!.trim()
          : (resolved?.route.routeId.trim() ?? '');
      if (routeId.isEmpty) {
        continue;
      }

      final routeName = favorite.routeName?.trim().isNotEmpty == true
          ? favorite.routeName!.trim()
          : resolved?.route.routeName;
      final stopName = favorite.stopName?.trim().isNotEmpty == true
          ? favorite.stopName!.trim()
          : resolved?.stop.stopName;

      payload.add({
        'id': favorite.stableKey,
        'groupName': selection.groupName,
        ...favorite.toJson(),
        'routeId': routeId,
        if (routeName != null && routeName.isNotEmpty) 'routeName': routeName,
        if (stopName != null && stopName.isNotEmpty) 'stopName': stopName,
      });
    }

    return payload;
  }

  Future<WearOsSyncStatus> syncWearOsNow({bool requestRefresh = true}) async {
    await _syncWearOsSnapshot(requestRefresh: requestRefresh);
    return WearOsIntegration.getStatus();
  }

  void _attachWearOsEventStream() {
    _wearEventSubscription?.cancel();
    _wearEventSubscription = WearOsIntegration.events.listen(
      _handleWearOsEvent,
      onError: (_) {},
    );
  }

  Future<void> _handleWearOsEvent(Map<String, Object?> event) async {
    final kind = event['kind']?.toString();
    final payloadJson = event['payloadJson']?.toString();
    if (kind == null || payloadJson == null || payloadJson.isEmpty) {
      return;
    }
    switch (kind) {
      case 'add_favorite':
        try {
          final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
          await _handleWearAddFavoriteRequest(decoded);
        } catch (_) {
          // Ignore malformed payloads.
        }
        return;
    }
  }

  Future<void> _handleWearAddFavoriteRequest(
    Map<String, dynamic> payload,
  ) async {
    final provider = busProviderFromString(
      payload['provider']?.toString() ?? _settings.provider.name,
    );
    final pathId = (payload['pathId'] as num?)?.toInt() ?? 0;
    final stopId = (payload['stopId'] as num?)?.toInt() ?? 0;
    final routeIdRaw = payload['routeId']?.toString().trim() ?? '';
    final routeName = payload['routeName']?.toString();
    final stopName = payload['stopName']?.toString();
    if (routeIdRaw.isEmpty || stopId == 0) {
      return;
    }

    // Derive routeKey from numeric portion of routeId; if absent, the Wear OS
    // bridge already hashed the string above. `addFavoriteStop` ->
    // `resolveFavoriteGroup` will backfill any missing route metadata.
    final providedKey = (payload['routeKey'] as num?)?.toInt() ?? 0;
    var routeKey = providedKey;
    if (routeKey == 0) {
      final digits = RegExp(r'\d+').firstMatch(routeIdRaw)?.group(0);
      routeKey = int.tryParse(digits ?? '') ?? routeIdRaw.hashCode;
    }

    final favorite = FavoriteStop(
      provider: provider,
      routeKey: routeKey,
      pathId: pathId,
      stopId: stopId,
      routeId: routeIdRaw,
      routeName: routeName,
      stopName: stopName,
    );
    await addFavoriteStop(favorite);
  }

  Future<void> _syncWearOsSnapshot({bool requestRefresh = false}) async {
    await _normalizeWearSelectedFavoriteIds();
    final favorites = await _buildWearFavoritePayload();

    Map<String, dynamic>? smartSuggestionPayload;
    List<Map<String, dynamic>>? usageProfilesPayload;
    if (_settings.wearSyncEnabled && _settings.wearSmartSuggestionsEnabled) {
      usageProfilesPayload = _buildWearUsageProfilesPayload();
      smartSuggestionPayload = await _buildWearSmartSuggestionPayload();
    } else if (!_settings.wearSyncEnabled) {
      // When sync is disabled, also clear any leftover suggestion / profiles
      // by sending empty payloads via syncAll.
      usageProfilesPayload = const <Map<String, dynamic>>[];
      smartSuggestionPayload = null;
    }

    await WearOsIntegration.syncAll(
      syncEnabled: _settings.wearSyncEnabled,
      selectedFavoriteIds: _settings.wearSelectedFavoriteIds,
      favorites: favorites,
      smartSuggestion: smartSuggestionPayload,
      usageProfiles: usageProfilesPayload,
      requestRefresh: requestRefresh,
    );
  }

  List<Map<String, dynamic>> _buildWearUsageProfilesPayload() {
    final providerProfiles = _routeUsageProfiles
        .where((entry) => entry.provider == _settings.provider)
        .toList()
      ..sort((a, b) => b.totalOpens.compareTo(a.totalOpens));
    final limited = providerProfiles.take(40);
    return limited
        .map((profile) => {
              'provider': profile.provider.name,
              'routeKey': profile.routeKey,
              'routeName': profile.routeName,
              'totalOpens': profile.totalOpens,
              'lastOpenedAtMs': profile.lastOpenedAtMs,
              'hourlyOpens': profile.hourlyOpens.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
              'recentSelectionMs': profile.selectionTimestampsWithin(),
            })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _buildWearSmartSuggestionPayload() async {
    if (!_settings.enableSmartRecommendations) {
      return null;
    }
    SmartRouteSuggestion? suggestion;
    try {
      suggestion = await getSmartRouteSuggestion();
    } catch (_) {
      suggestion = null;
    }
    if (suggestion == null) {
      return null;
    }

    final detail = suggestion.detail;
    final routeId = detail?.route.routeId.trim().isNotEmpty == true
        ? detail!.route.routeId.trim()
        : '';
    if (routeId.isEmpty) {
      return null;
    }

    final stop = suggestion.recommendedStop;
    final path = suggestion.recommendedPath;
    return <String, dynamic>{
      'routeId': routeId,
      'routeName': suggestion.profile.routeName.isNotEmpty
          ? suggestion.profile.routeName
          : (detail?.route.routeName ?? routeId),
      'provider': suggestion.profile.provider.name,
      if (path != null) ...{
        'pathId': path.pathId,
        'pathName': path.name,
      },
      if (stop != null) ...{
        'stopId': stop.stopId,
        'stopName': stop.stopName,
      },
      'reason': suggestion.reason,
      if (suggestion.distanceMeters != null)
        'distanceMeters': suggestion.distanceMeters,
    };
  }

  Future<void> _runAccountSyncOperation(Future<void> Function() action) async {
    if (_accountSyncBusy) {
      throw StateError('同步進行中，請稍後再試。');
    }

    _accountSyncBusy = true;
    _accountSyncError = null;
    notifyListeners();
    try {
      await action();
    } on AuthTokenExpiredException {
      _accountSyncError = null;
      await _forceLocalLogout();
      rethrow;
    } catch (error) {
      if (error is! AccountSyncConflictException) {
        _accountSyncError = '$error';
      }
      rethrow;
    } finally {
      _accountSyncBusy = false;
      notifyListeners();
    }
  }

  Future<void> ensureAnnouncementsLoaded() async {
    if (_announcementsLoading ||
        _announcements.isNotEmpty ||
        _announcementsError != null) {
      return;
    }
    await refreshAnnouncements(force: true);
  }

  Future<void> refreshAnnouncements({bool force = false}) async {
    if (_announcementsLoading) {
      return;
    }
    if (!force && _announcements.isNotEmpty) {
      return;
    }

    _announcementsLoading = true;
    if (force || _announcements.isEmpty) {
      _announcementsError = null;
    }
    notifyListeners();
    try {
      _announcements = await announcementService.fetchAnnouncements(
        buildInfo: buildInfo,
      );
      _announcementsError = null;
    } catch (error) {
      _announcementsError = '$error';
    } finally {
      _announcementsLoading = false;
      notifyListeners();
    }
  }

  AppAnnouncement? findAnnouncementById(String announcementId) {
    final normalized = announcementId.trim();
    for (final announcement in _announcements) {
      if (announcement.id == normalized) {
        return announcement;
      }
    }
    return null;
  }

  AppAnnouncement? nextPendingAnnouncementPopup({
    Set<String> sessionDeferredIds = const <String>{},
  }) {
    final pending = announcementService.pendingPopups(
      _announcements,
      _announcementLocalState,
      sessionDeferredIds: sessionDeferredIds,
    );
    return pending.isEmpty ? null : pending.first;
  }

  Future<void> markAnnouncementListViewed() async {
    final nextState = announcementService.markListViewed(
      _announcementLocalState,
      _announcements,
    );
    await _updateAnnouncementLocalState(nextState);
  }

  Future<void> markAnnouncementPopupShown(AppAnnouncement announcement) async {
    final nextState = announcementService.markPopupShown(
      _announcementLocalState,
      announcement,
    );
    await _updateAnnouncementLocalState(nextState);
  }

  Future<void> dismissAnnouncementPopup(AppAnnouncement announcement) async {
    final nextState = announcementService.dismissPopup(
      _announcementLocalState,
      announcement,
    );
    await _updateAnnouncementLocalState(nextState);
  }

  Future<void> _updateAnnouncementLocalState(
    AnnouncementLocalState nextState,
  ) async {
    if (identical(nextState, _announcementLocalState)) {
      return;
    }
    _announcementLocalState = nextState;
    await storage.saveAnnouncementLocalState(nextState);
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
    if (!provider.supportsLocalDatabase) {
      provider = BusProvider.tpe;
    }
    final selected = _settings.selectedProviders.toSet();
    selected.add(provider);
    _settings = _settings.copyWith(
      provider: provider,
      selectedProviders: selected.toList(),
    );
    await _persistSettings();
    await analytics.logProviderChanged(
      provider: provider,
      selectedCount: _settings.selectedProviders.length,
    );
    await desktopDiscordPresenceService.refresh(settings: _settings);
    notifyListeners();
    await refreshDatabaseState();
  }

  Future<void> updateSelectedProviders(List<BusProvider> providers) async {
    final normalized = providers
        .where((provider) => provider.supportsLocalDatabase)
        .toSet()
        .toList();
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
    await _persistSettings();
    await analytics.logSelectedProvidersChanged(
      currentProvider: provider,
      selectedCount: normalized.length,
    );
    await desktopDiscordPresenceService.refresh(settings: _settings);
    notifyListeners();
    await refreshDatabaseState();
  }

  Future<void> toggleSelectedProvider(BusProvider provider, bool value) async {
    if (!provider.supportsLocalDatabase) {
      return;
    }
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
    if (!provider.supportsLocalDatabase) {
      return;
    }
    final next = _settings.skipDownloadPromptProviders.toSet();
    if (skip) {
      next.add(provider);
    } else {
      next.remove(provider);
    }
    _settings = _settings.copyWith(skipDownloadPromptProviders: next.toList());
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode themeMode) async {
    _settings = _settings.copyWith(themeMode: themeMode);
    await _persistSettings();
    await analytics.logThemeModeChanged(themeMode);
    notifyListeners();
  }

  Future<void> updateMobileMapProvider(MobileMapProvider provider) async {
    _settings = _settings.copyWith(mobileMapProvider: provider);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateWearSyncEnabled(bool value) async {
    final selectedIds = value && _settings.wearSelectedFavoriteIds.isEmpty
        ? _availableWearFavoriteIds()
        : _settings.wearSelectedFavoriteIds;
    _settings = _settings.copyWith(
      wearSyncEnabled: value,
      wearSelectedFavoriteIds: selectedIds,
    );
    await _persistSettings();
    await _syncWearOsSnapshot(requestRefresh: false);
    notifyListeners();
  }

  Future<void> updateWearSelectedFavoriteIds(List<String> ids) async {
    final availableSet = _availableWearFavoriteIds().toSet();
    final normalized = ids
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && availableSet.contains(item))
        .toSet()
        .toList(growable: false);
    _settings = _settings.copyWith(wearSelectedFavoriteIds: normalized);
    await _persistSettings();
    await _syncWearOsSnapshot(requestRefresh: false);
    notifyListeners();
  }

  Future<void> updateWearSmartSuggestionsEnabled(bool value) async {
    if (_settings.wearSmartSuggestionsEnabled == value) {
      return;
    }
    _settings = _settings.copyWith(wearSmartSuggestionsEnabled: value);
    await _persistSettings();
    await _syncWearOsSnapshot(requestRefresh: false);
    notifyListeners();
  }

  Future<void> updateUseAmoledDark(bool value) async {
    _settings = _settings.copyWith(useAmoledDark: value);
    await _persistSettings();
    await analytics.logAmoledPreferenceChanged(value);
    notifyListeners();
  }

  Future<void> updateSeedColor(Color? color) async {
    if (color != null) {
      _settings = _settings.copyWith(seedColor: color);
    } else {
      _settings = _settings.copyWith(clearSeedColor: true);
    }
    await _persistSettings();
    await analytics.logSeedColorChanged(usesCustomColor: color != null);
    notifyListeners();
  }

  Future<void> updateHomeBackgroundOpacity(double value) async {
    _settings = _settings.copyWith(homeBackgroundOpacity: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updatePageBackgroundImagePath(
    String pageKey,
    String? path,
  ) async {
    final updated = Map<String, String>.from(
      _settings.pageBackgroundImagePaths,
    );
    final updatedOpacities = Map<String, double>.from(
      _settings.pageBackgroundImageOpacities,
    );
    final hasPath = path != null && path.trim().isNotEmpty;
    if (hasPath) {
      updated[pageKey] = path;
    } else {
      updated.remove(pageKey);
      updatedOpacities.remove(pageKey);
    }
    await _saveBackgroundImageSettings(
      paths: updated,
      opacities: updatedOpacities,
    );
    await analytics.logPageBackgroundChanged(
      pageKey: pageKey,
      hasImage: hasPath,
    );
    notifyListeners();
  }

  Future<void> updatePageBackgroundImageOpacity(
    String pageKey,
    double opacity,
  ) async {
    final updated = Map<String, double>.from(
      _settings.pageBackgroundImageOpacities,
    );
    updated[pageKey] = opacity;
    _settings = _settings.copyWith(pageBackgroundImageOpacities: updated);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateAllPageBackgroundImageOpacity(double opacity) async {
    if (_settings.pageBackgroundImagePaths.isEmpty) {
      return;
    }

    final updated = Map<String, double>.from(
      _settings.pageBackgroundImageOpacities,
    );
    for (final key in _settings.pageBackgroundImagePaths.keys) {
      updated[key] = opacity;
    }
    _settings = _settings.copyWith(pageBackgroundImageOpacities: updated);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> applyBackgroundImageToAllPages(
    String path,
    double opacity,
  ) async {
    final allKeys = _allPageKeys;
    final existingPaths = Map<String, String>.from(
      _settings.pageBackgroundImagePaths,
    );
    final existingOpacities = Map<String, double>.from(
      _settings.pageBackgroundImageOpacities,
    );
    for (final key in allKeys) {
      existingPaths[key] = path;
      existingOpacities[key] = opacity;
    }
    await _saveBackgroundImageSettings(
      paths: existingPaths,
      opacities: existingOpacities,
    );
    await analytics.logBackgroundImagesApplied(pageCount: allKeys.length);
    notifyListeners();
  }

  Future<void> clearAllBackgroundImages() async {
    await _saveBackgroundImageSettings(paths: const {}, opacities: const {});
    await analytics.logBackgroundImagesCleared();
    notifyListeners();
  }

  static const _allPageKeys = [
    'bus',
    'route_detail',
    'search',
    'favorites',
    'nearby',
    'settings',
  ];

  Future<void> _saveBackgroundImageSettings({
    required Map<String, String> paths,
    required Map<String, double> opacities,
  }) async {
    final normalizedPaths = await _backgroundImageStore.normalizeSettingsPaths(
      paths,
    );
    final normalizedOpacities = Map<String, double>.from(opacities)
      ..removeWhere((key, _) => !normalizedPaths.containsKey(key));
    _settings = _settings.copyWith(
      pageBackgroundImagePaths: normalizedPaths,
      pageBackgroundImageOpacities: normalizedOpacities,
    );
    await _persistSettings();
  }

  Future<void> updateOverlayOpacity(double value) async {
    _settings = _settings.copyWith(overlayOpacity: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateAlwaysShowSeconds(bool value) async {
    _settings = _settings.copyWith(alwaysShowSeconds: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateEnableSmartRecommendations(bool value) async {
    _settings = _settings.copyWith(enableSmartRecommendations: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateEnableSmartRouteNotifications(bool value) async {
    _settings = _settings.copyWith(enableSmartRouteNotifications: value);
    await _persistSettings();
    await AndroidHomeIntegration.syncSmartRouteNotifications(value);
    notifyListeners();
  }

  Future<void> updateKeepScreenAwakeOnRouteDetail(bool value) async {
    _settings = _settings.copyWith(keepScreenAwakeOnRouteDetail: value);
    await _persistSettings();
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
    await _persistSettings();
    if (!value) {
      await AndroidTripMonitor.stop();
      await LiveActivityService.endLiveActivity();
    }
    notifyListeners();
  }

  Future<void> updateFavoriteWidgetAutoRefreshMinutes(int value) async {
    _settings = _settings.copyWith(favoriteWidgetAutoRefreshMinutes: value);
    await _persistSettings();
    await AndroidHomeIntegration.updateFavoriteWidgetAutoRefreshMinutes(value);
    notifyListeners();
  }

  Future<void> updateBusUpdateTime(int value) async {
    _settings = _settings.copyWith(busUpdateTime: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateBusErrorUpdateTime(int value) async {
    _settings = _settings.copyWith(busErrorUpdateTime: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateMaxHistory(int value) async {
    _settings = _settings.copyWith(maxHistory: value);
    _history = _history.take(value).toList();
    await _persistSettings();
    await storage.saveHistory(_history);
    notifyListeners();
  }

  Future<void> updateAppUpdateChannel(AppUpdateChannel value) async {
    _settings = _settings.copyWith(appUpdateChannel: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateAppUpdateCheckMode(AppUpdateCheckMode value) async {
    _settings = _settings.copyWith(appUpdateCheckMode: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateDatabaseAutoUpdateMode(
    DatabaseAutoUpdateMode value,
  ) async {
    _settings = _settings.copyWith(databaseAutoUpdateMode: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateDesktopDiscordPresenceEnabled(bool value) async {
    _settings = _settings.copyWith(desktopDiscordPresenceEnabled: value);
    await _persistSettings();
    await desktopDiscordPresenceService.refresh(settings: _settings);
    notifyListeners();
  }

  Future<void> updateDesktopDiscordShowProvider(bool value) async {
    _settings = _settings.copyWith(desktopDiscordShowProvider: value);
    await _persistSettings();
    await desktopDiscordPresenceService.refresh(settings: _settings);
    notifyListeners();
  }

  Future<void> updateDesktopDiscordShowScreen(bool value) async {
    _settings = _settings.copyWith(desktopDiscordShowScreen: value);
    await _persistSettings();
    await desktopDiscordPresenceService.refresh(settings: _settings);
    notifyListeners();
  }

  Future<void> updateDesktopDiscordShowRouteName(bool value) async {
    _settings = _settings.copyWith(desktopDiscordShowRouteName: value);
    await _persistSettings();
    await desktopDiscordPresenceService.refresh(settings: _settings);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _settings = _settings.copyWith(hasCompletedOnboarding: true);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> setOnboardingCompleted(bool value) async {
    _settings = _settings.copyWith(hasCompletedOnboarding: value);
    await _persistSettings();
    notifyListeners();
  }

  Future<void> updateEnableAds(bool value) async {
    _settings = _settings.copyWith(enableAds: value);
    await _persistSettings();
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
    await _persistSettings();
    notifyListeners();
  }

  Future<Map<BusProvider, int?>> checkDatabaseUpdates({
    Iterable<BusProvider>? providers,
  }) async {
    final targetProviders = (providers ?? _settings.selectedProviders)
        .where((provider) => provider.supportsLocalDatabase)
        .toList();
    final updates = await repository.checkForUpdates(
      providers: targetProviders,
    );
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
    if (AppBuildInfo.isAabBuild) {
      return const AppUpdateCheckResult(
        status: AppUpdateStatus.unavailable,
        message: 'Google Play 版本由商店自動更新。',
      );
    }
    if (_checkingAppUpdate) {
      return _lastAppUpdateResult ??
          const AppUpdateCheckResult(
            status: AppUpdateStatus.unavailable,
            message: '正在檢查 App 更新，請稍後再試。',
          );
    }

    _checkingAppUpdate = true;
    notifyListeners();
    try {
      final result = await appUpdateService.checkForUpdates(
        channel ?? _settings.appUpdateChannel,
      );
      _lastAppUpdateResult = result;
      await analytics.logAppUpdateChecked(
        channel: (channel ?? _settings.appUpdateChannel).name,
        status: result.status.name,
      );
      return result;
    } finally {
      _checkingAppUpdate = false;
      notifyListeners();
    }
  }

  Future<AppUpdateCheckResult?> maybeCheckForAppUpdateOnLaunch() async {
    if (AppBuildInfo.isAabBuild) {
      return null;
    }
    if (_startupAppUpdateChecked ||
        _settings.appUpdateCheckMode == AppUpdateCheckMode.off) {
      return null;
    }
    _startupAppUpdateChecked = true;
    return checkForAppUpdate();
  }

  Future<DatabaseStartupCheckResult?>
  maybeCheckForDatabaseUpdatesOnLaunch() async {
    if (_startupDatabaseUpdateChecked || kIsWeb) {
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
    // Desktop platforms always auto-download database updates regardless of
    // the saved mode, since they typically have stable Wi-Fi/Ethernet and
    // Connectivity detection may not work reliably on desktop.
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    return DatabaseStartupCheckResult(
      mode: isDesktop
          ? DatabaseAutoUpdateMode.always
          : _settings.databaseAutoUpdateMode,
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

  Future<void> downloadProviderDatabases(
    Iterable<BusProvider> providers,
  ) async {
    final targets = providers
        .where((provider) => provider.supportsLocalDatabase)
        .toSet()
        .toList();
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
      await analytics.logDatabasesDownloaded(
        providerCount: targets.length,
        includesCurrentProvider: targets.contains(_settings.provider),
      );
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
    return repository.searchRoutesFromApi(query, provider: targetProvider);
  }

  Future<List<RouteSummary>> searchRoutesAcrossSelected(String query) async {
    if (kIsWeb) {
      try {
        return await repository.searchRoutesAcrossApi(query);
      } catch (_) {
        // Fall back to per-provider API search until the global route search
        // endpoint is available everywhere.
      }
    }

    final results = <RouteSummary>[];
    for (final provider in searchProviders) {
      if (isDatabaseReady(provider)) {
        results.addAll(
          await repository.searchRoutes(query, provider: provider),
        );
      } else {
        results.addAll(
          await repository.searchRoutesFromApi(query, provider: provider),
        );
      }
    }

    return results;
  }

  Future<List<StopRouteSearchResult>> searchRoutesByStopAcrossSelected(
    String query,
  ) async {
    final results = <StopRouteSearchResult>[];
    for (final provider in searchProviders) {
      if (!isDatabaseReady(provider)) {
        continue;
      }
      results.addAll(
        await repository.searchRoutesByStopName(query, provider: provider),
      );
    }
    return results;
  }

  Future<List<StopRouteSearchResult>> searchRoutesByStop(
    String query, {
    required BusProvider provider,
  }) {
    return repository.searchRoutesByStopName(query, provider: provider);
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

  Future<List<StopInfo>> getStopsByRoute(
    int routeKey, {
    required BusProvider provider,
    String? routeIdHint,
  }) {
    return repository.getStopsByRoute(
      routeKey,
      provider: provider,
      routeIdHint: routeIdHint,
    );
  }

  Future<List<RouteAlert>> getRouteAlerts(String routeId) {
    return repository.fetchRouteAlerts(routeId);
  }

  Set<String> readRouteAlertIdsForRoute(String routeId) {
    final normalizedRouteId = routeId.trim();
    if (normalizedRouteId.isEmpty) {
      return const <String>{};
    }
    return _settings.readRouteAlerts
        .where((entry) => entry.routeId == normalizedRouteId)
        .map((entry) => entry.alertId)
        .toSet();
  }

  Future<void> syncReadRouteAlertsForRoute(
    String routeId, {
    required Iterable<String> activeAlertIds,
    Iterable<String> markAsReadAlertIds = const <String>[],
  }) async {
    final normalizedRouteId = routeId.trim();
    if (normalizedRouteId.isEmpty) {
      return;
    }

    final activeIds = activeAlertIds
        .map((alertId) => alertId.trim())
        .where((alertId) => alertId.isNotEmpty)
        .toSet();
    final readIdsToAdd = markAsReadAlertIds
        .map((alertId) => alertId.trim())
        .where((alertId) => alertId.isNotEmpty && activeIds.contains(alertId))
        .toSet();

    final nextReadRouteAlerts = <ReadRouteAlert>[];
    final seenAlertIdsForRoute = <String>{};

    for (final entry in _settings.readRouteAlerts) {
      if (entry.routeId != normalizedRouteId) {
        nextReadRouteAlerts.add(entry);
        continue;
      }
      if (activeIds.contains(entry.alertId) &&
          seenAlertIdsForRoute.add(entry.alertId)) {
        nextReadRouteAlerts.add(entry);
      }
    }

    for (final alertId in readIdsToAdd) {
      if (seenAlertIdsForRoute.add(alertId)) {
        nextReadRouteAlerts.add(
          ReadRouteAlert(routeId: normalizedRouteId, alertId: alertId),
        );
      }
    }

    if (listEquals(_settings.readRouteAlerts, nextReadRouteAlerts)) {
      return;
    }

    _settings = _settings.copyWith(readRouteAlerts: nextReadRouteAlerts);
    await _persistSettings();
    notifyListeners();
  }

  Future<List<NearbyStopResult>> getNearbyStops({
    required double latitude,
    required double longitude,
    BusProvider? provider,
    double radiusMeters = 500,
    int limit = 20,
  }) async {
    final targetProvider =
        provider ??
        nearestBusProvider(latitude: latitude, longitude: longitude);
    return repository.fetchNearbyStops(
      provider: targetProvider,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      limit: limit,
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
        pathName: route.description.trim().isNotEmpty
            ? route.description.trim()
            : null,
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
    _favoriteUsageProfiles = const [];
    await _persistSmartRouteProfiles();
  }

  Future<void> clearRouteSelectionHistory() async {
    _routeUsageProfiles =
        _routeUsageProfiles
            .map((profile) => profile.clearSelections())
            .where((profile) => profile.totalInteractions > 0)
            .toList()
          ..sort(_compareRouteUsageProfiles);
    _favoriteUsageProfiles = const [];
    await _persistSmartRouteProfiles();
  }

  Future<void> recordRouteSelection({
    required BusProvider provider,
    required int routeKey,
    required String routeName,
    FavoriteStop? favorite,
    DateTime? selectedAt,
    String source = 'unknown',
  }) async {
    final timestamp = selectedAt ?? DateTime.now();
    _routeUsageProfiles = _buildUpdatedRouteUsageProfiles(
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
    final selectedFavorite =
        favorite != null &&
            favorite.provider == provider &&
            favorite.routeKey == routeKey
        ? favorite
        : null;
    if (selectedFavorite != null) {
      _favoriteUsageProfiles = _buildUpdatedFavoriteUsageProfiles(
        selectedFavorite,
        timestamp,
      );
    }
    await _persistSmartRouteProfiles();
    await analytics.logRouteSelected(
      provider: provider,
      routeKey: routeKey,
      source: source,
    );
  }

  Future<void> recordRouteVisit(
    RouteSummary route, {
    required BusProvider provider,
    DateTime? openedAt,
  }) async {
    final timestamp = openedAt ?? DateTime.now();
    _routeUsageProfiles = _buildUpdatedRouteUsageProfiles(
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
    await _persistSmartRouteProfiles();
    await analytics.logRouteVisit(provider: provider, routeKey: route.routeKey);
  }

  List<RouteUsageProfile> _buildUpdatedRouteUsageProfiles({
    required BusProvider provider,
    required int routeKey,
    required RouteUsageProfile Function(RouteUsageProfile profile) record,
    required RouteUsageProfile Function() create,
  }) {
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
    return next;
  }

  List<FavoriteUsageProfile> _buildUpdatedFavoriteUsageProfiles(
    FavoriteStop favorite,
    DateTime timestamp,
  ) {
    final next = <FavoriteUsageProfile>[];
    var found = false;

    for (final profile in _favoriteUsageProfiles) {
      if (profile.matchesFavorite(favorite)) {
        next.add(profile.recordSelection(timestamp));
        found = true;
      } else {
        next.add(profile);
      }
    }

    if (!found) {
      next.add(
        FavoriteUsageProfile(
          provider: favorite.provider,
          routeKey: favorite.routeKey,
          pathId: favorite.pathId,
          stopId: favorite.stopId,
          selectionTimestampsMs: <int>[timestamp.millisecondsSinceEpoch],
        ),
      );
    }

    next.sort(_compareFavoriteUsageProfiles);
    return next;
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

  int _compareFavoriteUsageProfiles(
    FavoriteUsageProfile left,
    FavoriteUsageProfile right,
  ) {
    final totalCompare = right.totalSelectionsAt().compareTo(
      left.totalSelectionsAt(),
    );
    if (totalCompare != 0) {
      return totalCompare;
    }

    return right.lastSelectedAtMsAt().compareTo(left.lastSelectedAtMsAt());
  }

  Future<void> _persistSmartRouteProfiles() async {
    await storage.saveRouteUsageProfiles(_routeUsageProfiles);
    await storage.saveFavoriteUsageProfiles(_favoriteUsageProfiles);
    await AndroidHomeIntegration.syncSmartRouteNotifications(
      _settings.enableSmartRouteNotifications,
    );
    unawaited(_pushSmartSuggestionToWearOsIfNeeded());
    notifyListeners();
  }

  /// Pushes the latest smart suggestion + usage profiles to the watch.
  /// Debounces to once every 5 minutes when the smart-route signature hasn't
  /// changed, so we don't burn battery on identical payloads.
  Future<void> _pushSmartSuggestionToWearOsIfNeeded() async {
    if (!_settings.wearSyncEnabled || !_settings.wearSmartSuggestionsEnabled) {
      return;
    }
    final signature = smartRouteSignature;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final signatureUnchanged = _lastWearSmartSignature == signature;
    final tooSoon = nowMs - _lastWearSmartPushAtMs <
        const Duration(minutes: 5).inMilliseconds;
    if (signatureUnchanged && tooSoon) {
      return;
    }
    _lastWearSmartSignature = signature;
    _lastWearSmartPushAtMs = nowMs;
    try {
      final usage = _buildWearUsageProfilesPayload();
      final suggestion = await _buildWearSmartSuggestionPayload();
      await WearOsIntegration.syncUsageProfiles(usage);
      await WearOsIntegration.syncSmartSuggestion(suggestion);
    } catch (_) {
      // Reset signature so we retry next time something changes.
      _lastWearSmartSignature = null;
    }
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
      favoriteProfiles: _favoriteUsageProfiles.where(
        (entry) => entry.provider == _settings.provider,
      ),
      favorites: _favoriteGroups.values
          .expand((group) => group)
          .where((favorite) => favorite.provider == _settings.provider),
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
    await _persistFavoriteGroups();
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    await _syncWearOsSnapshot(requestRefresh: false);
    await analytics.logFavoriteGroupCreated(groupCount: _favoriteGroups.length);
    notifyListeners();
  }

  Future<void> deleteFavoriteGroup(String name) async {
    final next = {..._favoriteGroups};
    next.remove(name);
    _favoriteGroups = next;
    await _persistFavoriteGroups();
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    await _syncWearOsSnapshot(requestRefresh: false);
    await analytics.logFavoriteGroupDeleted(groupCount: _favoriteGroups.length);
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

    // Enforce maximum 25 stops across all groups (matches batch API limit
    // and account-sync server setting).
    const maxFavoritesTotal = 25;
    final currentTotal = _favoriteGroups.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    final alreadyExists =
        _favoriteGroups[targetGroup]?.any((item) => item.sameAs(favorite)) ??
        false;
    if (!alreadyExists && currentTotal >= maxFavoritesTotal) {
      throw FavoriteGroupFullException(targetGroup, maxFavoritesTotal);
    }

    final next = <String, List<FavoriteStop>>{
      for (final entry in _favoriteGroups.entries)
        entry.key: List<FavoriteStop>.from(entry.value),
    };
    next.putIfAbsent(targetGroup, () => <FavoriteStop>[]);
    final existingIndex = next[targetGroup]!.indexWhere(
      (item) => item.sameAs(favorite),
    );
    final replacedExisting = existingIndex != -1;
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
    await _persistFavoriteGroups();
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    await _syncWearOsSnapshot(requestRefresh: false);
    final savedFavorite = next[targetGroup]!.firstWhere(
      (item) => item.sameAs(favorite),
      orElse: () => favorite,
    );
    await analytics.logFavoriteStopSaved(
      provider: favorite.provider,
      routeKey: favorite.routeKey,
      replacedExisting: replacedExisting,
      hasDestination: savedFavorite.destinationStopId != null,
    );
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
    await _persistFavoriteGroups();
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    await _syncWearOsSnapshot(requestRefresh: false);
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
    await _persistFavoriteGroups();
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    await _syncWearOsSnapshot(requestRefresh: false);
    await analytics.logFavoriteStopRemoved(
      provider: favorite.provider,
      routeKey: favorite.routeKey,
      hadDestination: favorite.destinationStopId != null,
    );
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
    await _persistFavoriteGroups();
    await IOSWidgetIntegration.syncFavoriteGroups(_favoriteGroups);
    await AndroidHomeIntegration.refreshFavoriteWidgets();
    await _syncWearOsSnapshot(requestRefresh: false);
  }

  int? _localModifiedAtMsForNamespace(AccountSyncNamespace namespace) {
    return switch (namespace) {
      AccountSyncNamespace.favorites => _favoriteGroupsLastModifiedAtMs,
      AccountSyncNamespace.preferences => _settingsLastModifiedAtMs,
    };
  }

  Map<String, dynamic> _buildSyncPayload(AccountSyncNamespace namespace) {
    return switch (namespace) {
      AccountSyncNamespace.favorites => {
        'groups': _favoriteGroups.map(
          (key, value) => MapEntry(
            key,
            value.map((item) => item.toJson()).toList(growable: false),
          ),
        )..removeWhere((_, value) => value.isEmpty),
      },
      AccountSyncNamespace.preferences => _mergeJsonMaps(
        _accountSyncLocalState.preferences.preservedPayload ?? const {},
        _preferencesSyncPayloadFromSettings(_settings),
      ),
    };
  }

  AppSettings _settingsFromSyncPayload(Map<String, dynamic>? payload) {
    final merged = Map<String, dynamic>.from(_settings.toJson());
    final root = payload ?? const <String, dynamic>{};
    final appearance = _stringMap(root['appearance']);
    if (appearance != null) {
      _copyKnownKey(appearance, merged, 'themeMode');
      _copyKnownKey(appearance, merged, 'useAmoledDark');
      _copyKnownKey(appearance, merged, 'seedColor');
      _copyKnownKey(appearance, merged, 'homeBackgroundOpacity');
      _copyKnownKey(appearance, merged, 'overlayOpacity');
    }

    final usage = _stringMap(root['usage']);
    if (usage != null) {
      _copyKnownKey(usage, merged, 'alwaysShowSeconds');
      _copyKnownKey(usage, merged, 'enableSmartRecommendations');
      _copyKnownKey(usage, merged, 'enableSmartRouteNotifications');
      _copyKnownKey(usage, merged, 'keepScreenAwakeOnRouteDetail');
      _copyKnownKey(usage, merged, 'enableRouteBackgroundMonitor');
      _copyKnownKey(usage, merged, 'maxHistory');
    }

    final updates = _stringMap(root['updates']);
    if (updates != null) {
      _copyKnownKey(updates, merged, 'favoriteWidgetAutoRefreshMinutes');
      _copyKnownKey(updates, merged, 'busUpdateTime');
      _copyKnownKey(updates, merged, 'busErrorUpdateTime');
      _copyKnownKey(updates, merged, 'appUpdateChannel');
      _copyKnownKey(updates, merged, 'appUpdateCheckMode');
      _copyKnownKey(updates, merged, 'databaseAutoUpdateMode');
    }

    final platform = _stringMap(root['platform']);
    final mobile = _stringMap(platform?['mobile']);
    if (mobile != null) {
      _copyKnownKey(mobile, merged, 'mobileMapProvider');
      _copyKnownKey(mobile, merged, 'wearSyncEnabled');
      _copyKnownKey(mobile, merged, 'wearSelectedFavoriteIds');
      _copyKnownKey(mobile, merged, 'wearSmartSuggestionsEnabled');
    }
    final desktop = _stringMap(platform?['desktop']);
    if (desktop != null) {
      _copyKnownKey(desktop, merged, 'desktopDiscordPresenceEnabled');
      _copyKnownKey(desktop, merged, 'desktopDiscordShowProvider');
      _copyKnownKey(desktop, merged, 'desktopDiscordShowScreen');
      _copyKnownKey(desktop, merged, 'desktopDiscordShowRouteName');
    }

    return AppSettings.fromJson(merged);
  }

  Map<String, List<FavoriteStop>> _favoriteGroupsFromSyncPayload(
    Map<String, dynamic>? payload,
  ) {
    final rawGroups = _stringMap(payload?['groups']);
    if (rawGroups == null) {
      return {};
    }

    final groups = <String, List<FavoriteStop>>{};
    for (final entry in rawGroups.entries) {
      final groupName = entry.key.trim();
      final value = entry.value;
      if (groupName.isEmpty || value is! List) {
        continue;
      }
      final favorites = value
          .whereType<Map>()
          .map(
            (item) => FavoriteStop.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((favorite) => favorite.routeKey > 0 && favorite.stopId > 0)
          .toList(growable: false);
      if (favorites.isNotEmpty) {
        groups[groupName] = favorites;
      }
    }
    return groups;
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

  @override
  void dispose() {
    _cancelScheduledAccountSync();
    _wearEventSubscription?.cancel();
    super.dispose();
  }
}

class _WearFavoriteSelection {
  const _WearFavoriteSelection({
    required this.groupName,
    required this.favorite,
  });

  final String groupName;
  final FavoriteStop favorite;
}

Map<String, dynamic> _preferencesSyncPayloadFromSettings(AppSettings settings) {
  final json = settings.toJson();
  return {
    'appearance': {
      'themeMode': json['themeMode'],
      'useAmoledDark': json['useAmoledDark'],
      'seedColor': json['seedColor'],
      'homeBackgroundOpacity': json['homeBackgroundOpacity'],
      'overlayOpacity': json['overlayOpacity'],
    },
    'usage': {
      'alwaysShowSeconds': json['alwaysShowSeconds'],
      'enableSmartRecommendations': json['enableSmartRecommendations'],
      'enableSmartRouteNotifications': json['enableSmartRouteNotifications'],
      'keepScreenAwakeOnRouteDetail': json['keepScreenAwakeOnRouteDetail'],
      'enableRouteBackgroundMonitor': json['enableRouteBackgroundMonitor'],
      'maxHistory': json['maxHistory'],
    },
    'updates': {
      'favoriteWidgetAutoRefreshMinutes':
          json['favoriteWidgetAutoRefreshMinutes'],
      'busUpdateTime': json['busUpdateTime'],
      'busErrorUpdateTime': json['busErrorUpdateTime'],
      'appUpdateChannel': json['appUpdateChannel'],
      'appUpdateCheckMode': json['appUpdateCheckMode'],
      'databaseAutoUpdateMode': json['databaseAutoUpdateMode'],
    },
    'platform': {
      'mobile': {
        'mobileMapProvider': json['mobileMapProvider'],
        'wearSyncEnabled': json['wearSyncEnabled'],
        'wearSelectedFavoriteIds': json['wearSelectedFavoriteIds'],
        'wearSmartSuggestionsEnabled': json['wearSmartSuggestionsEnabled'],
      },
      'desktop': {
        'desktopDiscordPresenceEnabled': json['desktopDiscordPresenceEnabled'],
        'desktopDiscordShowProvider': json['desktopDiscordShowProvider'],
        'desktopDiscordShowScreen': json['desktopDiscordShowScreen'],
        'desktopDiscordShowRouteName': json['desktopDiscordShowRouteName'],
      },
    },
  };
}

Map<String, dynamic> _mergeJsonMaps(
  Map<String, dynamic> base,
  Map<String, dynamic> overlay,
) {
  final result = <String, dynamic>{
    for (final entry in base.entries) entry.key: _deepCloneJson(entry.value),
  };

  for (final entry in overlay.entries) {
    final existing = result[entry.key];
    final value = entry.value;
    if (existing is Map && value is Map) {
      result[entry.key] = _mergeJsonMaps(
        existing.map((key, value) => MapEntry(key.toString(), value)),
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
      continue;
    }
    result[entry.key] = _deepCloneJson(value);
  }
  return result;
}

void _copyKnownKey(
  Map<String, dynamic> from,
  Map<String, dynamic> to,
  String key,
) {
  if (from.containsKey(key)) {
    to[key] = _deepCloneJson(from[key]);
  }
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

DateTime? _dateTimeFromMs(int? value) {
  if (value == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value);
}

Object? _deepCloneJson(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is List) {
    return value.map(_deepCloneJson).toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), _deepCloneJson(item)),
    );
  }
  return '$value';
}
