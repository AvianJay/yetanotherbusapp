import 'models.dart';

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const search = '/search';
  static const favorites = '/favorites';
  static const nearby = '/nearby';
  static const settings = '/settings';
  static const account = '/account';
  static const databaseSettings = '/database-settings';
  static const termsOfService = '/terms-of-service';
  static const privacyPolicy = '/privacy-policy';
  static const announcements = '/announcement';

  static const _supportedInternalHosts = <String>{'busapp.avianjay.sbs'};
  static const _legacyAliases = <String, String>{
    'search': search,
    'favorites': favorites,
    'favorite_groups': favorites,
    'nearby': nearby,
    'settings': settings,
    'account': account,
    'database_settings': databaseSettings,
    'terms-of-service': termsOfService,
    'privacy-policy': privacyPolicy,
    'announcement': announcements,
    'announcements': announcements,
  };

  static bool isSupportedInternalHost(String host) {
    return _supportedInternalHosts.contains(host.trim().toLowerCase());
  }

  static String normalize(String? rawLocation) {
    final trimmed = (rawLocation ?? '').trim();
    if (trimmed.isEmpty) {
      return home;
    }

    var normalized = trimmed;
    if (normalized.startsWith('/#')) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }

    if (!normalized.startsWith('/')) {
      final alias = _legacyAliases[normalized];
      if (alias != null) {
        return alias;
      }
      normalized = '/$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return home;
    }

    final alias = _legacyAliases[uri.path.replaceFirst(RegExp(r'^/+'), '')];
    final path = alias ?? (uri.path.isEmpty ? home : uri.path);
    return uri.replace(path: path).toString();
  }

  static String routeDetailPath({
    required BusProvider provider,
    required int routeKey,
    int? pathId,
    int? stopId,
    int? destinationPathId,
    int? destinationStopId,
  }) {
    final queryParameters = <String, String>{
      if (pathId != null) 'pathId': '$pathId',
      if (stopId != null) 'stopId': '$stopId',
      if (destinationPathId != null)
        'destinationPathId': '$destinationPathId',
      if (destinationStopId != null)
        'destinationStopId': '$destinationStopId',
    };
    return Uri(
      pathSegments: ['route', provider.name, '$routeKey'],
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }

  static String announcementDetailPath(String announcementId) {
    return Uri(pathSegments: ['announcement', announcementId]).toString();
  }
}

enum AppRouteKind {
  home,
  search,
  favorites,
  nearby,
  settings,
  account,
  databaseSettings,
  termsOfService,
  privacyPolicy,
  announcements,
  announcementDetail,
  routeDetail,
  stopDetail,
  unknown,
}

class AppRouteIntent {
  const AppRouteIntent({
    required this.kind,
    required this.location,
    this.provider,
    this.routeKey,
    this.pathId,
    this.stopId,
    this.destinationPathId,
    this.destinationStopId,
    this.announcementId,
    this.stopIdentifier,
  });

  final AppRouteKind kind;
  final String location;
  final BusProvider? provider;
  final int? routeKey;
  final int? pathId;
  final int? stopId;
  final int? destinationPathId;
  final int? destinationStopId;
  final String? announcementId;
  final String? stopIdentifier;
}

AppRouteIntent parseAppRoute(String? rawLocation) {
  final location = AppRoutes.normalize(rawLocation);
  final uri = Uri.tryParse(location);
  if (uri == null) {
    return const AppRouteIntent(
      kind: AppRouteKind.unknown,
      location: AppRoutes.home,
    );
  }

  if (uri.path == AppRoutes.home) {
    return const AppRouteIntent(kind: AppRouteKind.home, location: AppRoutes.home);
  }
  if (uri.path == AppRoutes.search) {
    return const AppRouteIntent(
      kind: AppRouteKind.search,
      location: AppRoutes.search,
    );
  }
  if (uri.path == AppRoutes.favorites) {
    return const AppRouteIntent(
      kind: AppRouteKind.favorites,
      location: AppRoutes.favorites,
    );
  }
  if (uri.path == AppRoutes.nearby) {
    return const AppRouteIntent(
      kind: AppRouteKind.nearby,
      location: AppRoutes.nearby,
    );
  }
  if (uri.path == AppRoutes.settings) {
    return const AppRouteIntent(
      kind: AppRouteKind.settings,
      location: AppRoutes.settings,
    );
  }
  if (uri.path == AppRoutes.account) {
    return const AppRouteIntent(
      kind: AppRouteKind.account,
      location: AppRoutes.account,
    );
  }
  if (uri.path == AppRoutes.databaseSettings) {
    return const AppRouteIntent(
      kind: AppRouteKind.databaseSettings,
      location: AppRoutes.databaseSettings,
    );
  }
  if (uri.path == AppRoutes.termsOfService) {
    return const AppRouteIntent(
      kind: AppRouteKind.termsOfService,
      location: AppRoutes.termsOfService,
    );
  }
  if (uri.path == AppRoutes.privacyPolicy) {
    return const AppRouteIntent(
      kind: AppRouteKind.privacyPolicy,
      location: AppRoutes.privacyPolicy,
    );
  }
  if (uri.path == AppRoutes.announcements) {
    return const AppRouteIntent(
      kind: AppRouteKind.announcements,
      location: AppRoutes.announcements,
    );
  }

  final segments = uri.pathSegments;
  if (segments.isEmpty) {
    return const AppRouteIntent(kind: AppRouteKind.home, location: AppRoutes.home);
  }

  if (segments.first == 'announcement' && segments.length >= 2) {
    return AppRouteIntent(
      kind: AppRouteKind.announcementDetail,
      location: location,
      announcementId: Uri.decodeComponent(segments[1]),
    );
  }

  if (segments.first == 'route' && segments.length >= 3) {
    final provider = _providerFromName(segments[1]);
    final routeKey = int.tryParse(segments[2]);
    if (provider != null && routeKey != null) {
      return AppRouteIntent(
        kind: AppRouteKind.routeDetail,
        location: location,
        provider: provider,
        routeKey: routeKey,
        pathId: _tryParseInt(uri.queryParameters['pathId']),
        stopId: _tryParseInt(uri.queryParameters['stopId']),
        destinationPathId: _tryParseInt(
          uri.queryParameters['destinationPathId'],
        ),
        destinationStopId: _tryParseInt(
          uri.queryParameters['destinationStopId'],
        ),
      );
    }
  }

  if (segments.first == 'stop' && segments.length >= 2) {
    return AppRouteIntent(
      kind: AppRouteKind.stopDetail,
      location: location,
      stopIdentifier: Uri.decodeComponent(segments[1]),
    );
  }

  return AppRouteIntent(kind: AppRouteKind.unknown, location: location);
}

int? _tryParseInt(String? value) {
  if (value == null) {
    return null;
  }
  return int.tryParse(value.trim());
}

BusProvider? _providerFromName(String rawValue) {
  final normalized = rawValue.trim().toLowerCase();
  for (final provider in BusProvider.values) {
    if (provider.name == normalized) {
      return provider;
    }
  }
  return null;
}