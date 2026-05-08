// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

Map<String, String>? takeWebAuthCallbackPayload() {
  final uri = Uri.parse(html.window.location.href);
  final normalizedPath = uri.path.isEmpty ? '/' : uri.path;
  if (normalizedPath != '/' && normalizedPath != '/auth-callback') {
    return null;
  }

  final params = <String, String>{...uri.queryParameters};
  if (uri.fragment.isNotEmpty) {
    try {
      params.addAll(Uri.splitQueryString(uri.fragment));
    } catch (_) {
      return null;
    }
  }
  if (!params.containsKey('token') && !params.containsKey('error')) {
    return null;
  }

  html.window.history.replaceState(null, 'YABus', '/');
  return {'target': 'auth_callback', ...params};
}
