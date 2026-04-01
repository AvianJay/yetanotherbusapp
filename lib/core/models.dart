import 'package:flutter/material.dart';

enum BusProvider {
  twn,
  tcc,
  tpe;

  String get label => switch (this) {
    BusProvider.twn => '全台',
    BusProvider.tcc => '台中',
    BusProvider.tpe => '雙北',
  };

  String get databaseFileName => 'bus_$name.sqlite';

  String get dataUrlTextFile => switch (this) {
    BusProvider.twn => 'dataurl.txt',
    BusProvider.tcc => 'dataurl_tcc.txt',
    BusProvider.tpe => 'dataurl_tpe.txt',
  };

  String get archiveFileName => 'dat_${name}_zh.gz';
}

BusProvider busProviderFromString(String value) {
  return BusProvider.values.firstWhere(
    (provider) => provider.name == value,
    orElse: () => BusProvider.twn,
  );
}

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

class AppSettings {
  const AppSettings({
    required this.provider,
    required this.themeMode,
    required this.alwaysShowSeconds,
    required this.keepScreenAwakeOnRouteDetail,
    required this.busUpdateTime,
    required this.busErrorUpdateTime,
    required this.maxHistory,
    required this.hasCompletedOnboarding,
    required this.appUpdateChannel,
    required this.appUpdateCheckMode,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      provider: BusProvider.twn,
      themeMode: ThemeMode.system,
      alwaysShowSeconds: false,
      keepScreenAwakeOnRouteDetail: true,
      busUpdateTime: 10,
      busErrorUpdateTime: 3,
      maxHistory: 10,
      hasCompletedOnboarding: false,
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
    return AppSettings(
      provider: busProviderFromString(json['provider'] as String? ?? 'twn'),
      themeMode: themeModeFromString(json['themeMode'] as String? ?? 'system'),
      alwaysShowSeconds: json['alwaysShowSeconds'] as bool? ?? false,
      keepScreenAwakeOnRouteDetail:
          json['keepScreenAwakeOnRouteDetail'] as bool? ?? true,
      busUpdateTime: json['busUpdateTime'] as int? ?? 10,
      busErrorUpdateTime: json['busErrorUpdateTime'] as int? ?? 3,
      maxHistory: json['maxHistory'] as int? ?? 10,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
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
  final ThemeMode themeMode;
  final bool alwaysShowSeconds;
  final bool keepScreenAwakeOnRouteDetail;
  final int busUpdateTime;
  final int busErrorUpdateTime;
  final int maxHistory;
  final bool hasCompletedOnboarding;
  final AppUpdateChannel appUpdateChannel;
  final AppUpdateCheckMode appUpdateCheckMode;

  AppSettings copyWith({
    BusProvider? provider,
    ThemeMode? themeMode,
    bool? alwaysShowSeconds,
    bool? keepScreenAwakeOnRouteDetail,
    int? busUpdateTime,
    int? busErrorUpdateTime,
    int? maxHistory,
    bool? hasCompletedOnboarding,
    AppUpdateChannel? appUpdateChannel,
    AppUpdateCheckMode? appUpdateCheckMode,
  }) {
    return AppSettings(
      provider: provider ?? this.provider,
      themeMode: themeMode ?? this.themeMode,
      alwaysShowSeconds: alwaysShowSeconds ?? this.alwaysShowSeconds,
      keepScreenAwakeOnRouteDetail:
          keepScreenAwakeOnRouteDetail ?? this.keepScreenAwakeOnRouteDetail,
      busUpdateTime: busUpdateTime ?? this.busUpdateTime,
      busErrorUpdateTime: busErrorUpdateTime ?? this.busErrorUpdateTime,
      maxHistory: maxHistory ?? this.maxHistory,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      appUpdateChannel: appUpdateChannel ?? this.appUpdateChannel,
      appUpdateCheckMode: appUpdateCheckMode ?? this.appUpdateCheckMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'themeMode': themeMode.name,
      'alwaysShowSeconds': alwaysShowSeconds,
      'keepScreenAwakeOnRouteDetail': keepScreenAwakeOnRouteDetail,
      'busUpdateTime': busUpdateTime,
      'busErrorUpdateTime': busErrorUpdateTime,
      'maxHistory': maxHistory,
      'hasCompletedOnboarding': hasCompletedOnboarding,
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
    required this.timestampMs,
  });

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SearchHistoryEntry(
      provider: busProviderFromString(json['provider'] as String? ?? 'twn'),
      routeKey: json['routeKey'] as int? ?? 0,
      routeName: json['routeName'] as String? ?? '',
      timestampMs: json['timestampMs'] as int? ?? 0,
    );
  }

  final BusProvider provider;
  final int routeKey;
  final String routeName;
  final int timestampMs;

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'routeKey': routeKey,
      'routeName': routeName,
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
  });

  factory FavoriteStop.fromJson(Map<String, dynamic> json) {
    return FavoriteStop(
      provider: busProviderFromString(json['provider'] as String? ?? 'twn'),
      routeKey: json['routeKey'] as int? ?? 0,
      pathId: json['pathId'] as int? ?? 0,
      stopId: json['stopId'] as int? ?? 0,
    );
  }

  final BusProvider provider;
  final int routeKey;
  final int pathId;
  final int stopId;

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'routeKey': routeKey,
      'pathId': pathId,
      'stopId': stopId,
    };
  }

  bool sameAs(FavoriteStop other) {
    return provider == other.provider &&
        routeKey == other.routeKey &&
        pathId == other.pathId &&
        stopId == other.stopId;
  }
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
      routeId: (map['route_id'] as num?)?.toInt() ?? 0,
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
  final int routeId;
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
}) {
  final message = stop.msg?.trim() ?? '';
  if (message.isNotEmpty) {
    return EtaPresentation(
      text: message == '即將進站' ? '即將\n進站' : message,
      backgroundColor: Colors.teal.shade50,
      foregroundColor: Colors.teal.shade900,
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
    backgroundColor: urgent ? Colors.orange.shade700 : const Color(0xFFE2F4F1),
    foregroundColor: urgent ? Colors.white : const Color(0xFF0D4E57),
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
