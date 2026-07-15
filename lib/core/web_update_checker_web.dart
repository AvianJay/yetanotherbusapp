// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

// Re-export the real checker so the conditional import resolves the class.
export 'web_update_checker.dart';

import 'dart:async';
import 'dart:html' as html;

import 'web_update_checker.dart';

/// Web: return a working checker instance.
WebUpdateChecker? createWebUpdateChecker() => WebUpdateChecker();

/// Web: activate the newest service worker, then reload the page.
///
/// Reloading while the old service worker is still in control would serve
/// the old cache-first assets again. Triggering a registration update first
/// lets the new worker install (precaching the new build and deleting the
/// old cache via its versioned cache name) so a single reload picks up the
/// new deployment.
void reloadPage() {
  unawaited(_activateLatestServiceWorkerThenReload());
}

Future<void> _activateLatestServiceWorkerThenReload() async {
  try {
    final container = html.window.navigator.serviceWorker;
    if (container != null) {
      // dart:html types getRegistration() as non-nullable, but it resolves
      // with null when nothing is registered – hence the `is` check.
      final dynamic registration = await container
          .getRegistration()
          .timeout(const Duration(seconds: 4));
      if (registration is html.ServiceWorkerRegistration) {
        await registration.update().timeout(const Duration(seconds: 4));
        // Wait for any in-flight install to settle (skipWaiting activates
        // the new worker as soon as precaching finishes).
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while ((registration.installing != null ||
                registration.waiting != null) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }
  } catch (_) {
    // Fall through – reloading is still the best effort.
  }
  html.window.location.reload();
}
