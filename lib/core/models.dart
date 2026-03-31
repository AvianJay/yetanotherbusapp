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

class AppSettings {
  const AppSettings({
    required this.provider,
    required this.themeMode,
    required this.alwaysShowSeconds,
    required this.busUpdateTime,
    required this.busErrorUpdateTime,
    required this.maxHistory,
    required this.hasCompletedOnboarding,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      provider: BusProvider.twn,
      themeMode: ThemeMode.system,
      alwaysShowSeconds: false,
      busUpdateTime: 10,
      busErrorUpdateTime: 3,
      maxHistory: 10,
      hasCompletedOnboarding: false,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      provider: busProviderFromString(json['provider'] as String? ?? 'twn'),
      themeMode: themeModeFromString(json['themeMode'] as String? ?? 'system'),
      alwaysShowSeconds: json['alwaysShowSeconds'] as bool? ?? false,
      busUpdateTime: json['busUpdateTime'] as int? ?? 10,
      busErrorUpdateTime: json['busErrorUpdateTime'] as int? ?? 3,
      maxHistory: json['maxHistory'] as int? ?? 10,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
    );
  }

  final BusProvider provider;
  final ThemeMode themeMode;
  final bool alwaysShowSeconds;
  final int busUpdateTime;
  final int busErrorUpdateTime;
  final int maxHistory;
  final bool hasCompletedOnboarding;

  AppSettings copyWith({
    BusProvider? provider,
    ThemeMode? themeMode,
    bool? alwaysShowSeconds,
    int? busUpdateTime,
    int? busErrorUpdateTime,
    int? maxHistory,
    bool? hasCompletedOnboarding,
  }) {
    return AppSettings(
      provider: provider ?? this.provider,
      themeMode: themeMode ?? this.themeMode,
      alwaysShowSeconds: alwaysShowSeconds ?? this.alwaysShowSeconds,
      busUpdateTime: busUpdateTime ?? this.busUpdateTime,
      busErrorUpdateTime: busErrorUpdateTime ?? this.busErrorUpdateTime,
      maxHistory: maxHistory ?? this.maxHistory,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'themeMode': themeMode.name,
      'alwaysShowSeconds': alwaysShowSeconds,
      'busUpdateTime': busUpdateTime,
      'busErrorUpdateTime': busErrorUpdateTime,
      'maxHistory': maxHistory,
      'hasCompletedOnboarding': hasCompletedOnboarding,
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
  });

  final RouteSummary route;
  final List<PathInfo> paths;
  final Map<int, List<StopInfo>> stopsByPath;
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

  final seconds = stop.sec ?? -1;
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

String formatDistance(double meters) {
  if (meters < 1000) {
    return '${meters.round()}m';
  }

  return '${(meters / 1000).toStringAsFixed(1)}km';
}
