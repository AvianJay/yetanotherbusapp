import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_routes.dart';

Future<bool> openAppLink(BuildContext context, String href) async {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) {
    return false;
  }
  return openAppUri(context, uri);
}

Future<bool> openAppUri(BuildContext context, Uri uri) async {
  final internalLocation = _internalLocationForUri(uri);
  if (internalLocation != null) {
    await Navigator.of(context).pushNamed(internalLocation);
    return true;
  }

  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

String? _internalLocationForUri(Uri uri) {
  Uri normalized = uri;
  if (uri.hasScheme) {
    final scheme = uri.scheme.trim().toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    if (!AppRoutes.isSupportedInternalHost(uri.host)) {
      return null;
    }
    normalized = Uri(
      path: uri.path.isEmpty ? AppRoutes.home : uri.path,
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  } else if (uri.path.isNotEmpty && !uri.path.startsWith('/')) {
    normalized = Uri(
      path: '/${uri.path}',
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }

  final intent = parseAppRoute(normalized.toString());
  switch (intent.kind) {
    case AppRouteKind.home:
    case AppRouteKind.search:
    case AppRouteKind.favorites:
    case AppRouteKind.nearby:
    case AppRouteKind.settings:
    case AppRouteKind.account:
    case AppRouteKind.databaseSettings:
    case AppRouteKind.termsOfService:
    case AppRouteKind.privacyPolicy:
    case AppRouteKind.announcements:
    case AppRouteKind.announcementDetail:
    case AppRouteKind.routeDetail:
      return intent.location;
    case AppRouteKind.stopDetail:
    case AppRouteKind.unknown:
      return null;
  }
}