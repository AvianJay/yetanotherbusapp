// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

// Re-export the real checker so the conditional import resolves the class.
export 'web_update_checker.dart';

import 'dart:html' as html;

import 'web_update_checker.dart';

/// Web: return a working checker instance.
WebUpdateChecker? createWebUpdateChecker() => WebUpdateChecker();

/// Web: reload the page to activate the new service worker.
void reloadPage() => html.window.location.reload();
