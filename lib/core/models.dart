import 'dart:math' as math;

import 'package:flutter/material.dart';

enum BusProvider {
  kee('KEE', '基隆市', 25.1283, 121.7419),
  tpe('TPE', '台北市', 25.0330, 121.5654),
  nwt('NWT', '新北市', 25.0119, 121.4638),
  tao('TAO', '桃園市', 24.9937, 121.3010),
  hsz('HSZ', '新竹市', 24.8042, 120.9717),
  hsq('HSQ', '新竹縣', 24.8396, 121.0047),
  mia('MIA', '苗栗縣', 24.5602, 120.8214),
  txg('TXG', '台中市', 24.1477, 120.6736),
  cha('CHA', '彰化縣', 24.0817, 120.5380),
  nan('NAN', '南投縣', 23.9157, 120.6639),
  yun('YUN', '雲林縣', 23.7092, 120.4313),
  cyi('CYI', '嘉義市', 23.4801, 120.4491),
  cyq('CYQ', '嘉義縣', 23.4586, 120.3326),
  tnn('TNN', '台南市', 22.9999, 120.2269),
  khh('KHH', '高雄市', 22.6273, 120.3014),
  pif('PIF', '屏東縣', 22.5519, 120.5487),
  ila('ILA', '宜蘭縣', 24.7570, 121.7532),
  hua('HUA', '花蓮縣', 23.9872, 121.6015),
  ttt('TTT', '台東縣', 22.7583, 121.1444),
  pen('PEN', '澎湖縣', 23.5655, 119.5865),
  kin('KIN', '金門縣', 24.4326, 118.3171),
  lie('LIE', '連江縣', 26.1600, 119.9510);

  const BusProvider(
    this.prefix,
    this.label,
    this.centerLatitude,
    this.centerLongitude,
  );

  final String prefix;
  final String label;
  final double centerLatitude;
  final double centerLongitude;

  String get databaseFileName => 'bus_${name}_v2.sqlite';
}

BusProvider busProviderFromString(String value) {
  final normalized = value.trim().toLowerCase();
  switch (normalized) {
    case 'tpe':
      return BusProvider.tpe;
    case 'tcc':
      return BusProvider.txg;
    case 'twn':
      return BusProvider.nwt;
  }

  return BusProvider.values.firstWhere(
    (provider) =>
        provider.name == normalized ||
        provider.prefix.toLowerCase() == normalized,
    orElse: () => BusProvider.tpe,
  );
}

BusProvider nearestBusProvider({
  required double latitude,
  required double longitude,
}) {
  // Phase 1: Check bounding-box containment.
  final contained = <BusProvider>[];
  for (final provider in BusProvider.values) {
    final bounds = _providerBounds[provider];
    if (bounds != null &&
        latitude >= bounds.south &&
        latitude <= bounds.north &&
        longitude >= bounds.west &&
        longitude <= bounds.east) {
      contained.add(provider);
    }
  }
  if (contained.length == 1) return contained.first;

  // Phase 2: Ambiguous or no bounding-box match → nearest center.
  final candidates =
      contained.isNotEmpty ? contained : BusProvider.values.toList();
  BusProvider best = candidates.first;
  var bestDistance = double.infinity;
  for (final provider in candidates) {
    final distance = _distanceMeters(
      latitude,
      longitude,
      provider.centerLatitude,
      provider.centerLongitude,
    );
    if (distance < bestDistance) {
      best = provider;
      bestDistance = distance;
    }
  }
  return best;
}

class _LatLngBounds {
  const _LatLngBounds(this.south, this.west, this.north, this.east);
  final double south;
  final double west;
  final double north;
  final double east;
}

/// Approximate administrative bounding boxes for cities whose shapes make
/// simple center-point distance unreliable.
const _providerBounds = <BusProvider, _LatLngBounds>{
  BusProvider.kee: _LatLngBounds(25.0878, 121.6396, 25.1940, 121.8090),
  BusProvider.tpe: _LatLngBounds(24.9607, 121.4570, 25.2101, 121.6659),
  BusProvider.nwt: _LatLngBounds(24.6712, 121.2831, 25.2994, 121.9976),
  BusProvider.tao: _LatLngBounds(24.7384, 121.0960, 25.1166, 121.3988),
  BusProvider.hsz: _LatLngBounds(24.7473, 120.9148, 24.8434, 121.0316),
  BusProvider.hsq: _LatLngBounds(24.3879, 120.9240, 24.8790, 121.3405),
  BusProvider.txg: _LatLngBounds(24.0089, 120.4710, 24.4106, 121.0310),
  BusProvider.tnn: _LatLngBounds(22.8563, 120.0390, 23.4390, 120.6530),
  BusProvider.khh: _LatLngBounds(22.4705, 120.1800, 23.4710, 120.8595),
};


ThemeMode themeModeFromString(String value) {
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => ThemeMode.system,
  );
}

enum AppUpdateChannel {
  developer,
  nightly,
  release;

  String get label => switch (this) {
    AppUpdateChannel.developer => '開發版',
    AppUpdateChannel.nightly => 'Nightly',
    AppUpdateChannel.release => 'Release',
  };

  String get description => switch (this) {
    AppUpdateChannel.developer => '不檢查 app 更新',
    AppUpdateChannel.nightly => '比對最新成功建置的 commit',
    AppUpdateChannel.release => '比對 GitHub 最新發行版',
  };
}

AppUpdateChannel appUpdateChannelFromString(String value) {
  return AppUpdateChannel.values.firstWhere(
    (channel) => channel.name == value,
    orElse: () => _defaultAppUpdateChannel(),
  );
}

AppUpdateChannel _defaultAppUpdateChannel() {
  return appUpdateChannelFromStringConst(
    const String.fromEnvironment('APP_UPDATE_CHANNEL', defaultValue: 'nightly'),
  );
}

AppUpdateChannel appUpdateChannelFromStringConst(String value) {
  return switch (value) {
    'developer' => AppUpdateChannel.developer,
    'release' => AppUpdateChannel.release,
    _ => AppUpdateChannel.nightly,
  };
}

enum AppUpdateCheckMode {
  off,
  notify,
  popup;

  String get label => switch (this) {
    AppUpdateCheckMode.off => '關閉',
    AppUpdateCheckMode.notify => '通知',
    AppUpdateCheckMode.popup => '跳窗',
  };

  String get description => switch (this) {
    AppUpdateCheckMode.off => '只在手動檢查時顯示',
    AppUpdateCheckMode.notify => '啟動後用通知提示',
    AppUpdateCheckMode.popup => '啟動後直接跳出更新視窗',
  };
}

AppUpdateCheckMode appUpdateCheckModeFromString(String value) {
  return AppUpdateCheckMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () =>
        const String.fromEnvironment(
              'APP_UPDATE_CHANNEL',
              defaultValue: 'nightly',
            ) ==
            'developer'
        ? AppUpdateCheckMode.off
        : AppUpdateCheckMode.popup,
  );
}

enum DatabaseAutoUpdateMode {
  off,
  checkPopup,
  checkNotify,
  always,
  wifiOnly,
  cellularOnly;

  String get label => switch (this) {
    DatabaseAutoUpdateMode.off => '不檢查',
    DatabaseAutoUpdateMode.checkPopup => '檢查更新並彈窗',
    DatabaseAutoUpdateMode.checkNotify => '檢查更新並提示',
    DatabaseAutoUpdateMode.always => '總是自動更新',
    DatabaseAutoUpdateMode.wifiOnly => '僅 Wi‑Fi 自動更新',
    DatabaseAutoUpdateMode.cellularOnly => '僅行動數據自動更新',
  };

  String get description => switch (this) {
    DatabaseAutoUpdateMode.off => '啟動時不主動檢查資料庫更新。',
    DatabaseAutoUpdateMode.checkPopup => '啟動時檢查更新，若有新版本就彈出提示。',
    DatabaseAutoUpdateMode.checkNotify => '啟動時檢查更新，若有新版本就顯示提示。',
    DatabaseAutoUpdateMode.always => '啟動時有新版本就直接下載並更新。',
    DatabaseAutoUpdateMode.wifiOnly => '僅在 Wi‑Fi 連線時自動更新，其他網路只保留提示。',
    DatabaseAutoUpdateMode.cellularOnly =>
      '僅在行動數據連線時自動更新，其他網路只保留提示。',
  };
}

DatabaseAutoUpdateMode databaseAutoUpdateModeFromString(String value) {
  return DatabaseAutoUpdateMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => DatabaseAutoUpdateMode.checkPopup,
  );
}

enum DatabaseConnectionKind {
  wifi,
  cellular,
  other,
  offline,
  unknown;
}

class DatabaseStartupCheckResult {
  const DatabaseStartupCheckResult({
    required this.mode,
    required this.updates,
    required this.connectionKind,
  });

  final DatabaseAutoUpdateMode mode;
  final Map<BusProvider, int> updates;
  final DatabaseConnectionKind connectionKind;

  bool get hasUpdates => updates.isNotEmpty;

  bool get shouldShowPopup =>
      hasUpdates && mode == DatabaseAutoUpdateMode.checkPopup;

  bool get shouldShowNotification =>
      hasUpdates && mode == DatabaseAutoUpdateMode.checkNotify;

  bool get shouldAutoDownload => switch (mode) {
    DatabaseAutoUpdateMode.always =>
      hasUpdates && connectionKind != DatabaseConnectionKind.offline,
    DatabaseAutoUpdateMode.wifiOnly =>
      hasUpdates && connectionKind == DatabaseConnectionKind.wifi,
    DatabaseAutoUpdateMode.cellularOnly =>
      hasUpdates && connectionKind == DatabaseConnectionKind.cellular,
    _ => false,
  };

  String? get deferredReason => switch (mode) {
    DatabaseAutoUpdateMode.wifiOnly
        when hasUpdates && connectionKind != DatabaseConnectionKind.wifi =>
      '有資料庫更新，但目前不是 Wi‑Fi，已略過自動更新。',
    DatabaseAutoUpdateMode.cellularOnly
        when hasUpdates && connectionKind != DatabaseConnectionKind.cellular =>
      '有資料庫更新，但目前不是行動數據，已略過自動更新。',
    _ => null,
  };
}

class AppSettings {
  const AppSettings({
    required this.provider,
    required this.selectedProviders,
    required this.skipDownloadPromptProviders,
    required this.themeMode,
    required this.alwaysShowSeconds,
    required this.enableSmartRecommendations,
    required this.enableSmartRouteNotifications,
    required this.keepScreenAwakeOnRouteDetail,
    required this.enableRouteBackgroundMonitor,
    required this.hasSeenRouteBackgroundMonitorPrompt,
    required this.favoriteWidgetAutoRefreshMinutes,
    required this.busUpdateTime,
    required this.busErrorUpdateTime,
    required this.maxHistory,
    required this.hasCompletedOnboarding,
    required this.databaseAutoUpdateMode,
    required this.appUpdateChannel,
    required this.appUpdateCheckMode,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      provider: BusProvider.tpe,
      selectedProviders: const [BusProvider.tpe],
      skipDownloadPromptProviders: const [],
      themeMode: ThemeMode.system,
      alwaysShowSeconds: false,
      enableSmartRecommendations: true,
      enableSmartRouteNotifications: false,
      keepScreenAwakeOnRouteDetail: true,
      enableRouteBackgroundMonitor: false,
      hasSeenRouteBackgroundMonitorPrompt: false,
      favoriteWidgetAutoRefreshMinutes: 0,
      busUpdateTime: 10,
      busErrorUpdateTime: 3,
      maxHistory: 10,
      hasCompletedOnboarding: false,
      databaseAutoUpdateMode: DatabaseAutoUpdateMode.checkPopup,
      appUpdateChannel: _defaultAppUpdateChannel(),
      appUpdateCheckMode:
          const String.fromEnvironment(
                'APP_UPDATE_CHANNEL',
                defaultValue: 'nightly',
              ) ==
              'developer'
          ? AppUpdateCheckMode.off
          : AppUpdateCheckMode.popup,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final provider = busProviderFromString(
      json['provider'] as String? ?? 'tpe',
    );
    final selectedProvidersRaw = json['selectedProviders'];
    final selectedProviders = selectedProvidersRaw is List
        ? selectedProvidersRaw
              .map((item) => busProviderFromString(item.toString()))
              .toSet()
              .toList()
        : <BusProvider>[provider];
    if (!selectedProviders.contains(provider)) {
      selectedProviders.insert(0, provider);
    }

    final skipPromptRaw = json['skipDownloadPromptProviders'];
    final skipPromptProviders = skipPromptRaw is List
        ? skipPromptRaw
              .map((item) => busProviderFromString(item.toString()))
              .toSet()
              .toList()
        : <BusProvider>[];

    return AppSettings(
      provider: provider,
      selectedProviders: selectedProviders,
      skipDownloadPromptProviders: skipPromptProviders,
      themeMode: themeModeFromString(json['themeMode'] as String? ?? 'system'),
      alwaysShowSeconds: json['alwaysShowSeconds'] as bool? ?? false,
      enableSmartRecommendations:
          json['enableSmartRecommendations'] as bool? ?? true,
      enableSmartRouteNotifications:
          json['enableSmartRouteNotifications'] as bool? ?? false,
      keepScreenAwakeOnRouteDetail:
          json['keepScreenAwakeOnRouteDetail'] as bool? ?? true,
      enableRouteBackgroundMonitor:
          json['enableRouteBackgroundMonitor'] as bool? ?? false,
      hasSeenRouteBackgroundMonitorPrompt:
          json['hasSeenRouteBackgroundMonitorPrompt'] as bool? ?? false,
      favoriteWidgetAutoRefreshMinutes:
          json['favoriteWidgetAutoRefreshMinutes'] as int? ?? 0,
      busUpdateTime: json['busUpdateTime'] as int? ?? 10,
      busErrorUpdateTime: json['busErrorUpdateTime'] as int? ?? 3,
      maxHistory: json['maxHistory'] as int? ?? 10,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      databaseAutoUpdateMode: databaseAutoUpdateModeFromString(
        json['databaseAutoUpdateMode'] as String? ?? 'checkPopup',
      ),
      appUpdateChannel: appUpdateChannelFromString(
        json['appUpdateChannel'] as String? ??
            const String.fromEnvironment(
              'APP_UPDATE_CHANNEL',
              defaultValue: 'nightly',
            ),
      ),
      appUpdateCheckMode: appUpdateCheckModeFromString(
        json['appUpdateCheckMode'] as String? ??
            (const String.fromEnvironment(
                      'APP_UPDATE_CHANNEL',
                      defaultValue: 'nightly',
                    ) ==
                    'developer'
                ? 'off'
                : 'popup'),
      ),
    );
  }

  final BusProvider provider;
  final List<BusProvider> selectedProviders;
  final List<BusProvider> skipDownloadPromptProviders;
  final ThemeMode themeMode;
  final bool alwaysShowSeconds;
  final bool enableSmartRecommendations;
  final bool enableSmartRouteNotifications;
  final bool keepScreenAwakeOnRouteDetail;
  final bool enableRouteBackgroundMonitor;
  final bool hasSeenRouteBackgroundMonitorPrompt;
  final int favoriteWidgetAutoRefreshMinutes;
  final int busUpdateTime;
  final int busErrorUpdateTime;
  final int maxHistory;
  final bool hasCompletedOnboarding;
  final DatabaseAutoUpdateMode databaseAutoUpdateMode;
  final AppUpdateChannel appUpdateChannel;
  final AppUpdateCheckMode appUpdateCheckMode;

  AppSettings copyWith({
    BusProvider? provider,
    List<BusProvider>? selectedProviders,
    List<BusProvider>? skipDownloadPromptProviders,
    ThemeMode? themeMode,
    bool? alwaysShowSeconds,
    bool? enableSmartRecommendations,
    bool? enableSmartRouteNotifications,
    bool? keepScreenAwakeOnRouteDetail,
    bool? enableRouteBackgroundMonitor,
    bool? hasSeenRouteBackgroundMonitorPrompt,
    int? favoriteWidgetAutoRefreshMinutes,
    int? busUpdateTime,
    int? busErrorUpdateTime,
    int? maxHistory,
    bool? hasCompletedOnboarding,
    DatabaseAutoUpdateMode? databaseAutoUpdateMode,
    AppUpdateChannel? appUpdateChannel,
    AppUpdateCheckMode? appUpdateCheckMode,
  }) {
    return AppSettings(
      provider: provider ?? this.provider,
      selectedProviders: selectedProviders ?? this.selectedProviders,
      skipDownloadPromptProviders:
          skipDownloadPromptProviders ?? this.skipDownloadPromptProviders,
      themeMode: themeMode ?? this.themeMode,
      alwaysShowSeconds: alwaysShowSeconds ?? this.alwaysShowSeconds,
      enableSmartRecommendations:
          enableSmartRecommendations ?? this.enableSmartRecommendations,
      enableSmartRouteNotifications:
          enableSmartRouteNotifications ?? this.enableSmartRouteNotifications,
      keepScreenAwakeOnRouteDetail:
          keepScreenAwakeOnRouteDetail ?? this.keepScreenAwakeOnRouteDetail,
      enableRouteBackgroundMonitor:
          enableRouteBackgroundMonitor ?? this.enableRouteBackgroundMonitor,
      hasSeenRouteBackgroundMonitorPrompt:
          hasSeenRouteBackgroundMonitorPrompt ??
          this.hasSeenRouteBackgroundMonitorPrompt,
      favoriteWidgetAutoRefreshMinutes:
          favoriteWidgetAutoRefreshMinutes ??
          this.favoriteWidgetAutoRefreshMinutes,
      busUpdateTime: busUpdateTime ?? this.busUpdateTime,
      busErrorUpdateTime: busErrorUpdateTime ?? this.busErrorUpdateTime,
      maxHistory: maxHistory ?? this.maxHistory,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      databaseAutoUpdateMode:
          databaseAutoUpdateMode ?? this.databaseAutoUpdateMode,
      appUpdateChannel: appUpdateChannel ?? this.appUpdateChannel,
      appUpdateCheckMode: appUpdateCheckMode ?? this.appUpdateCheckMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'selectedProviders': selectedProviders.map((item) => item.name).toList(),
      'skipDownloadPromptProviders': skipDownloadPromptProviders
          .map((item) => item.name)
          .toList(),
      'themeMode': themeMode.name,
      'alwaysShowSeconds': alwaysShowSeconds,
      'enableSmartRecommendations': enableSmartRecommendations,
      'enableSmartRouteNotifications': enableSmartRouteNotifications,
      'keepScreenAwakeOnRouteDetail': keepScreenAwakeOnRouteDetail,
      'enableRouteBackgroundMonitor': enableRouteBackgroundMonitor,
      'hasSeenRouteBackgroundMonitorPrompt':
          hasSeenRouteBackgroundMonitorPrompt,
      'favoriteWidgetAutoRefreshMinutes': favoriteWidgetAutoRefreshMinutes,
      'busUpdateTime': busUpdateTime,
      'busErrorUpdateTime': busErrorUpdateTime,
      'maxHistory': maxHistory,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'databaseAutoUpdateMode': databaseAutoUpdateMode.name,
      'appUpdateChannel': appUpdateChannel.name,
      'appUpdateCheckMode': appUpdateCheckMode.name,
    };
  }
}

class SearchHistoryEntry {
  const SearchHistoryEntry({
    required this.provider,
    required this.routeKey,
    required this.routeName,
    this.routeId,
    required this.timestampMs,
  });

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SearchHistoryEntry(
      provider: busProviderFromString(json['provider'] as String? ?? 'tpe'),
      routeKey: (json['routeKey'] as num?)?.toInt() ?? 0,
      routeName: json['routeName'] as String? ?? '',
      routeId: (json['routeId'] as String?)?.trim().isNotEmpty == true
          ? (json['routeId'] as String).trim()
          : null,
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }

  final BusProvider provider;
  final int routeKey;
  final String routeName;
  final String? routeId;
  final int timestampMs;

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'routeKey': routeKey,
      'routeName': routeName,
      if (routeId != null) 'routeId': routeId,
      'timestampMs': timestampMs,
    };
  }
}

class FavoriteStop {
  const FavoriteStop({
    required this.provider,
    required this.routeKey,
    required this.pathId,
    required this.stopId,
    this.routeId,
    this.routeName,
    this.stopName,
    this.destinationPathId,
    this.destinationStopId,
    this.destinationStopName,
  });

  factory FavoriteStop.fromJson(Map<String, dynamic> json) {
    return FavoriteStop(
      provider: busProviderFromString(json['provider'] as String? ?? 'tpe'),
      routeKey: (json['routeKey'] as num?)?.toInt() ?? 0,
      pathId: (json['pathId'] as num?)?.toInt() ?? 0,
      stopId: (json['stopId'] as num?)?.toInt() ?? 0,
      routeId: (json['routeId'] as String?)?.trim().isNotEmpty == true
          ? (json['routeId'] as String).trim()
          : null,
      routeName: json['routeName'] as String?,
      stopName: json['stopName'] as String?,
      destinationPathId: (json['destinationPathId'] as num?)?.toInt(),
      destinationStopId: (json['destinationStopId'] as num?)?.toInt(),
      destinationStopName:
          (json['destinationStopName'] as String?)?.trim().isNotEmpty == true
          ? (json['destinationStopName'] as String).trim()
          : null,
    );
  }

  final BusProvider provider;
  final int routeKey;
  final int pathId;
  final int stopId;
  final String? routeId;
  final String? routeName;
  final String? stopName;
  final int? destinationPathId;
  final int? destinationStopId;
  final String? destinationStopName;

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'routeKey': routeKey,
      'pathId': pathId,
      'stopId': stopId,
      if (routeId != null) 'routeId': routeId,
      if (routeName != null) 'routeName': routeName,
      if (stopName != null) 'stopName': stopName,
      if (destinationPathId != null) 'destinationPathId': destinationPathId,
      if (destinationStopId != null) 'destinationStopId': destinationStopId,
      if (destinationStopName != null)
        'destinationStopName': destinationStopName,
    };
  }

  bool sameAs(FavoriteStop other) {
    return provider == other.provider &&
        routeKey == other.routeKey &&
        pathId == other.pathId &&
        stopId == other.stopId;
  }
}

class RouteUsageProfile {
  const RouteUsageProfile({
    required this.provider,
    required this.routeKey,
    required this.routeName,
    required this.totalOpens,
    required this.lastOpenedAtMs,
    this.totalSelections = 0,
    this.lastSelectedAtMs = 0,
    this.hourlyOpens = const <int, int>{},
    this.hourlySelections = const <int, int>{},
  });

  factory RouteUsageProfile.fromJson(Map<String, dynamic> json) {
    final rawHourlyOpens = json['hourlyOpens'];
    final hourlyOpens = <int, int>{};
    if (rawHourlyOpens is Map) {
      rawHourlyOpens.forEach((key, value) {
        final hour = int.tryParse(key.toString());
        final count = (value as num?)?.toInt();
        if (hour != null &&
            hour >= 0 &&
            hour < 24 &&
            count != null &&
            count > 0) {
          hourlyOpens[hour] = count;
        }
      });
    }

    return RouteUsageProfile(
      provider: busProviderFromString(json['provider'] as String? ?? 'tpe'),
      routeKey: (json['routeKey'] as num?)?.toInt() ?? 0,
      routeName: json['routeName'] as String? ?? '',
      totalOpens: (json['totalOpens'] as num?)?.toInt() ?? 0,
      lastOpenedAtMs: (json['lastOpenedAtMs'] as num?)?.toInt() ?? 0,
      totalSelections: (json['totalSelections'] as num?)?.toInt() ?? 0,
      lastSelectedAtMs: (json['lastSelectedAtMs'] as num?)?.toInt() ?? 0,
      hourlyOpens: hourlyOpens,
      hourlySelections: _decodeHourlyCounts(json['hourlySelections']),
    );
  }

  final BusProvider provider;
  final int routeKey;
  final String routeName;
  final int totalOpens;
  final int lastOpenedAtMs;
  final int totalSelections;
  final int lastSelectedAtMs;
  final Map<int, int> hourlyOpens;
  final Map<int, int> hourlySelections;

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'routeKey': routeKey,
      'routeName': routeName,
      'totalOpens': totalOpens,
      'lastOpenedAtMs': lastOpenedAtMs,
      'totalSelections': totalSelections,
      'lastSelectedAtMs': lastSelectedAtMs,
      'hourlyOpens': hourlyOpens.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'hourlySelections': hourlySelections.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    };
  }

  int countAtHour(int hour) => hourlyOpens[hour] ?? 0;
  int selectionCountAtHour(int hour) => hourlySelections[hour] ?? 0;
  int combinedCountAtHour(int hour) =>
      countAtHour(hour) + selectionCountAtHour(hour);
  int get totalInteractions => totalOpens + totalSelections;
  int get latestInteractionAtMs =>
      lastOpenedAtMs > lastSelectedAtMs ? lastOpenedAtMs : lastSelectedAtMs;

  int get preferredHour {
    var bestHour = 0;
    var bestCount = -1;
    for (var hour = 0; hour < 24; hour++) {
      final count = combinedCountAtHour(hour);
      if (count > bestCount) {
        bestHour = hour;
        bestCount = count;
      }
    }
    return bestHour;
  }

  RouteUsageProfile recordOpen(DateTime openedAt, {String? routeName}) {
    final hour = openedAt.hour;
    final nextHourlyOpens = <int, int>{...hourlyOpens};
    nextHourlyOpens[hour] = (nextHourlyOpens[hour] ?? 0) + 1;
    return RouteUsageProfile(
      provider: provider,
      routeKey: routeKey,
      routeName: routeName?.trim().isNotEmpty == true
          ? routeName!.trim()
          : this.routeName,
      totalOpens: totalOpens + 1,
      lastOpenedAtMs: openedAt.millisecondsSinceEpoch,
      totalSelections: totalSelections,
      lastSelectedAtMs: lastSelectedAtMs,
      hourlyOpens: nextHourlyOpens,
      hourlySelections: hourlySelections,
    );
  }

  RouteUsageProfile recordSelection(DateTime selectedAt, {String? routeName}) {
    final hour = selectedAt.hour;
    final nextHourlySelections = <int, int>{...hourlySelections};
    nextHourlySelections[hour] = (nextHourlySelections[hour] ?? 0) + 1;
    return RouteUsageProfile(
      provider: provider,
      routeKey: routeKey,
      routeName: routeName?.trim().isNotEmpty == true
          ? routeName!.trim()
          : this.routeName,
      totalOpens: totalOpens,
      lastOpenedAtMs: lastOpenedAtMs,
      totalSelections: totalSelections + 1,
      lastSelectedAtMs: selectedAt.millisecondsSinceEpoch,
      hourlyOpens: hourlyOpens,
      hourlySelections: nextHourlySelections,
    );
  }

  RouteUsageProfile clearSelections() {
    return RouteUsageProfile(
      provider: provider,
      routeKey: routeKey,
      routeName: routeName,
      totalOpens: totalOpens,
      lastOpenedAtMs: lastOpenedAtMs,
      hourlyOpens: hourlyOpens,
    );
  }

  static Map<int, int> _decodeHourlyCounts(Object? rawCounts) {
    final counts = <int, int>{};
    if (rawCounts is! Map) {
      return counts;
    }
    rawCounts.forEach((key, value) {
      final hour = int.tryParse(key.toString());
      final count = (value as num?)?.toInt();
      if (hour != null &&
          hour >= 0 &&
          hour < 24 &&
          count != null &&
          count > 0) {
        counts[hour] = count;
      }
    });
    return counts;
  }
}

class SmartRouteSuggestion {
  const SmartRouteSuggestion({
    required this.profile,
    required this.score,
    required this.reason,
    this.detail,
    this.nearestStop,
    this.nearestPath,
    this.distanceMeters,
  });

  final RouteUsageProfile profile;
  final double score;
  final String reason;
  final RouteDetailData? detail;
  final StopInfo? nearestStop;
  final PathInfo? nearestPath;
  final double? distanceMeters;
}

class RouteSummary {
  const RouteSummary({
    required this.sourceProvider,
    required this.hashMd5,
    required this.routeKey,
    required this.routeId,
    required this.routeName,
    required this.officialRouteName,
    required this.description,
    required this.category,
    required this.sequence,
    required this.rtrip,
  });

  factory RouteSummary.fromMap(Map<String, Object?> map) {
    return RouteSummary(
      sourceProvider: map['provider'] as String? ?? '',
      hashMd5: map['hash_md5'] as String? ?? '',
      routeKey: (map['route_key'] as num?)?.toInt() ?? 0,
      routeId: map['route_id']?.toString() ?? '',
      routeName: map['route_name'] as String? ?? '',
      officialRouteName: map['official_route_name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: map['category'] as String? ?? '',
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      rtrip: (map['rtrip'] as num?)?.toInt() ?? 0,
    );
  }

  final String sourceProvider;
  final String hashMd5;
  final int routeKey;
  final String routeId;
  final String routeName;
  final String officialRouteName;
  final String description;
  final String category;
  final int sequence;
  final int rtrip;
}

class PathInfo {
  const PathInfo({
    required this.routeKey,
    required this.pathId,
    required this.name,
  });

  factory PathInfo.fromMap(Map<String, Object?> map) {
    return PathInfo(
      routeKey: (map['route_key'] as num?)?.toInt() ?? 0,
      pathId: (map['path_id'] as num?)?.toInt() ?? 0,
      name: map['path_name'] as String? ?? '',
    );
  }

  final int routeKey;
  final int pathId;
  final String name;
}

class RoutePathPoint {
  const RoutePathPoint({
    required this.lat,
    required this.lon,
  });

  final double lat;
  final double lon;
}

class RouteRealtimeBus {
  const RouteRealtimeBus({
    required this.id,
    required this.routeId,
    required this.pathId,
    required this.lat,
    required this.lon,
    this.speedKph,
    this.azimuth,
    this.statusCode,
    this.updatedAt,
  });

  final String id;
  final String routeId;
  final int? pathId;
  final double lat;
  final double lon;
  final double? speedKph;
  final double? azimuth;
  final int? statusCode;
  final DateTime? updatedAt;
}

class BusStatusDescriptor {
  const BusStatusDescriptor({
    required this.code,
    required this.label,
    required this.color,
  });

  final int? code;
  final String label;
  final Color color;
}

BusStatusDescriptor describeBusStatus(int? statusCode) {
  return switch (statusCode) {
    0 => const BusStatusDescriptor(
      code: 0,
      label: '正常',
      color: Color(0xFF2E7D32),
    ),
    1 => const BusStatusDescriptor(
      code: 1,
      label: '車禍',
      color: Color(0xFFC62828),
    ),
    2 => const BusStatusDescriptor(
      code: 2,
      label: '故障',
      color: Color(0xFFEF6C00),
    ),
    3 => const BusStatusDescriptor(
      code: 3,
      label: '塞車',
      color: Color(0xFFAD7B00),
    ),
    4 => const BusStatusDescriptor(
      code: 4,
      label: '緊急求援',
      color: Color(0xFFD81B60),
    ),
    5 => const BusStatusDescriptor(
      code: 5,
      label: '加油',
      color: Color(0xFF1565C0),
    ),
    90 => const BusStatusDescriptor(
      code: 90,
      label: '不明',
      color: Color(0xFF6D4C41),
    ),
    91 => const BusStatusDescriptor(
      code: 91,
      label: '去回不明',
      color: Color(0xFF455A64),
    ),
    98 => const BusStatusDescriptor(
      code: 98,
      label: '偏移路線',
      color: Color(0xFF8E24AA),
    ),
    99 => const BusStatusDescriptor(
      code: 99,
      label: '非營運狀態',
      color: Color(0xFF616161),
    ),
    100 => const BusStatusDescriptor(
      code: 100,
      label: '客滿',
      color: Color(0xFFE64A19),
    ),
    101 => const BusStatusDescriptor(
      code: 101,
      label: '包車出租',
      color: Color(0xFF00897B),
    ),
    255 || null => const BusStatusDescriptor(
      code: null,
      label: '未知',
      color: Color(0xFF78909C),
    ),
    _ => BusStatusDescriptor(
      code: statusCode,
      label: '未知($statusCode)',
      color: const Color(0xFF78909C),
    ),
  };
}

class BusVehicle {
  const BusVehicle({
    required this.id,
    required this.type,
    required this.note,
    required this.full,
    required this.carOnStop,
  });

  final String id;
  final String type;
  final String note;
  final bool full;
  final bool carOnStop;
}

class StopInfo {
  const StopInfo({
    required this.routeKey,
    required this.pathId,
    required this.stopId,
    required this.stopName,
    required this.sequence,
    required this.lon,
    required this.lat,
    this.sec,
    this.msg,
    this.t,
    this.buses = const [],
  });

  factory StopInfo.fromMap(Map<String, Object?> map) {
    return StopInfo(
      routeKey: (map['route_key'] as num?)?.toInt() ?? 0,
      pathId: (map['path_id'] as num?)?.toInt() ?? 0,
      stopId: (map['stop_id'] as num?)?.toInt() ?? 0,
      stopName: map['stop_name'] as String? ?? '',
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      lon: (map['lon'] as num?)?.toDouble() ?? 0,
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
    );
  }

  final int routeKey;
  final int pathId;
  final int stopId;
  final String stopName;
  final int sequence;
  final double lon;
  final double lat;
  final int? sec;
  final String? msg;
  final String? t;
  final List<BusVehicle> buses;

  StopInfo copyWith({
    int? sec,
    String? msg,
    String? t,
    List<BusVehicle>? buses,
  }) {
    return StopInfo(
      routeKey: routeKey,
      pathId: pathId,
      stopId: stopId,
      stopName: stopName,
      sequence: sequence,
      lon: lon,
      lat: lat,
      sec: sec ?? this.sec,
      msg: msg ?? this.msg,
      t: t ?? this.t,
      buses: buses ?? this.buses,
    );
  }
}

class RouteDetailData {
  const RouteDetailData({
    required this.route,
    required this.paths,
    required this.stopsByPath,
    required this.hasLiveData,
  });

  final RouteSummary route;
  final List<PathInfo> paths;
  final Map<int, List<StopInfo>> stopsByPath;
  final bool hasLiveData;
}

class NearbyStopResult {
  const NearbyStopResult({
    required this.route,
    required this.stop,
    required this.distanceMeters,
  });

  final RouteSummary route;
  final StopInfo stop;
  final double distanceMeters;
}

class FavoriteResolvedItem {
  const FavoriteResolvedItem({
    required this.reference,
    required this.route,
    required this.stop,
  });

  final FavoriteStop reference;
  final RouteSummary route;
  final StopInfo stop;
}

class EtaPresentation {
  const EtaPresentation({
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String text;
  final Color backgroundColor;
  final Color foregroundColor;
}

EtaPresentation buildEtaPresentation(
  StopInfo stop, {
  required bool alwaysShowSeconds,
  Brightness brightness = Brightness.light,
}) {
  final isDark = brightness == Brightness.dark;
  final message = stop.msg?.trim() ?? '';
  if (message.isNotEmpty) {
    return EtaPresentation(
      text: message == '即將進站'
          ? '即將\n進站'
          : message == '末班駛離'
          ? '末班\n駛離'
          : message,
      backgroundColor: isDark ? const Color(0xFF16383D) : Colors.teal.shade50,
      foregroundColor: isDark ? const Color(0xFFBEECEF) : Colors.teal.shade900,
    );
  }

  final seconds = stop.sec;
  if (seconds == null) {
    return const EtaPresentation(
      text: '--',
      backgroundColor: Color(0xFF364152),
      foregroundColor: Color(0xFFD8E2F1),
    );
  }

  if (seconds <= 0) {
    return EtaPresentation(
      text: '進站中',
      backgroundColor: Colors.red.shade800,
      foregroundColor: Colors.white,
    );
  }

  if (seconds < 60) {
    return EtaPresentation(
      text: '$seconds秒',
      backgroundColor: Colors.red.shade600,
      foregroundColor: Colors.white,
    );
  }

  final minutes = seconds ~/ 60;
  final leftoverSeconds = seconds % 60;
  final urgent = minutes < 3;

  return EtaPresentation(
    text: alwaysShowSeconds ? '$minutes分\n$leftoverSeconds秒' : '$minutes分',
    backgroundColor: urgent
        ? Colors.orange.shade700
        : (isDark ? const Color(0xFF233A41) : const Color(0xFFE2F4F1)),
    foregroundColor: urgent
        ? Colors.white
        : (isDark ? const Color(0xFFD7F1F3) : const Color(0xFF0D4E57)),
  );
}

bool hasRealtimeStopData(StopInfo stop) {
  return stop.sec != null ||
      (stop.msg?.trim().isNotEmpty ?? false) ||
      (stop.t?.trim().isNotEmpty ?? false) ||
      stop.buses.isNotEmpty;
}

String formatDistance(double meters) {
  if (meters < 1000) {
    return '${meters.round()}m';
  }

  return '${(meters / 1000).toStringAsFixed(1)}km';
}

double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6378.137;
  final dLat = _degreesToRadians(lat2 - lat1);
  final dLon = _degreesToRadians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(lat1)) *
          math.cos(_degreesToRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c * 1000;
}

double _degreesToRadians(double degree) => degree * math.pi / 180;

class RouteAlert {
  const RouteAlert({
    required this.alertId,
    required this.title,
    required this.description,
    required this.status,
    required this.cause,
    required this.effect,
    required this.direction,
    required this.scope,
    required this.stopIds,
    required this.startTime,
    required this.endTime,
    required this.publishTime,
    required this.updatedTime,
  });

  factory RouteAlert.fromJson(Map<String, dynamic> json) {
    return RouteAlert(
      alertId: json['alert_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      status: (json['status'] as num?)?.toInt(),
      cause: (json['cause'] as num?)?.toInt(),
      effect: (json['effect'] as num?)?.toInt(),
      direction: (json['direction'] as num?)?.toInt(),
      scope: json['scope']?.toString(),
      stopIds: (json['stop_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      startTime: (json['start_time'] as num?)?.toInt(),
      endTime: (json['end_time'] as num?)?.toInt(),
      publishTime: (json['publish_time'] as num?)?.toInt(),
      updatedTime: (json['updated_time'] as num?)?.toInt(),
    );
  }

  final String alertId;
  final String title;
  final String description;
  final int? status;
  final int? cause;
  final int? effect;
  final int? direction;
  final String? scope;
  final List<String> stopIds;
  final int? startTime;
  final int? endTime;
  final int? publishTime;
  final int? updatedTime;

  String get statusText => switch (status) {
        0 => '全部營運停止',
        1 => '全部營運正常',
        2 => '有異常狀況',
        _ => '未知',
      };

  Color get statusColor => switch (status) {
        0 => const Color(0xFFD32F2F),
        1 => const Color(0xFF388E3C),
        2 => const Color(0xFFF57C00),
        _ => const Color(0xFF757575),
      };

  String get causeText => switch (cause) {
        1 => '事故',
        2 => '維護檢修',
        3 => '技術問題',
        4 => '施工',
        5 => '醫療緊急狀況',
        6 => '氣候',
        7 => '示威遊行',
        8 => '政治活動/維安',
        9 => '假日/節慶',
        10 => '罷工',
        11 => '活動',
        254 => '其他',
        _ => '',
      };

  String get effectText => switch (effect) {
        1 => '車輛改道/站牌不停靠',
        2 => '班次增加',
        3 => '班次減少',
        4 => '班次取消',
        5 => '班次改變',
        6 => '站點異動',
        7 => '重大延遲',
        254 => '其他影響',
        _ => '',
      };

  bool get isNegative =>
      status == 0 ||
      status == 2 ||
      effect == 1 ||
      effect == 3 ||
      effect == 4 ||
      effect == 7;
}

class RouteOperator {
  final String operatorId;
  final String name;
  final String? nameEn;
  final String? code;
  final String? phone;
  final String? email;
  final String? url;

  const RouteOperator({
    required this.operatorId,
    required this.name,
    this.nameEn,
    this.code,
    this.phone,
    this.email,
    this.url,
  });

  factory RouteOperator.fromJson(Map<String, dynamic> json) => RouteOperator(
        operatorId: json['operator_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        nameEn: json['name_en'] as String?,
        code: json['code'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        url: json['url'] as String?,
      );
}

class RouteScheduleEntry {
  final String subrouteUid;
  final int direction;
  final String kind; // 'frequency' or 'timetable'
  final int seq;
  final Map<String, dynamic> serviceDays;
  final Map<String, dynamic> payload;

  const RouteScheduleEntry({
    required this.subrouteUid,
    required this.direction,
    required this.kind,
    required this.seq,
    required this.serviceDays,
    required this.payload,
  });

  factory RouteScheduleEntry.fromJson(Map<String, dynamic> json) =>
      RouteScheduleEntry(
        subrouteUid: json['subroute_uid'] as String? ?? '',
        direction: json['direction'] as int? ?? 0,
        kind: json['kind'] as String? ?? '',
        seq: json['seq'] as int? ?? 0,
        serviceDays: json['service_days'] as Map<String, dynamic>? ?? {},
        payload: json['payload'] as Map<String, dynamic>? ?? {},
      );

  bool get isFrequency => kind == 'frequency';

  String get serviceDaysSummary {
    final days = <String>[];
    if (serviceDays['mon'] == 1) days.add('一');
    if (serviceDays['tue'] == 1) days.add('二');
    if (serviceDays['wed'] == 1) days.add('三');
    if (serviceDays['thu'] == 1) days.add('四');
    if (serviceDays['fri'] == 1) days.add('五');
    if (serviceDays['sat'] == 1) days.add('六');
    if (serviceDays['sun'] == 1) days.add('日');
    if (serviceDays['holiday'] == 1) days.add('假');
    if (days.isEmpty) return '無';
    return days.join('、');
  }

  String get displayText {
    if (isFrequency) {
      final start = payload['start'] ?? '';
      final end = payload['end'] ?? '';
      final minH = payload['min_headway'];
      final maxH = payload['max_headway'];
      if (minH == maxH) {
        return '$start - $end 每$minH分';
      }
      return '$start - $end 每$minH-$maxH分';
    }
    final tripId = payload['trip_id'] ?? '';
    final stops = payload['stop_times'] as List<dynamic>? ?? [];
    if (stops.isNotEmpty) {
      final first = stops.first as Map<String, dynamic>;
      return '${first['departure'] ?? ''} (班次$tripId)';
    }
    return '班次$tripId';
  }
}
