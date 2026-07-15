{{flutter_js}}
{{flutter_build_config}}

// YABus manages its own service worker (web/sw.js, registered in index.html).
// Don't pass serviceWorkerSettings here: the default bootstrap would register
// Flutter's deprecated flutter_service_worker.js over our scope-/ registration
// whenever one exists, and that worker unregisters itself on activation and
// force-navigates every client – an extra reload on each visit and a race
// against our own caching worker.
_flutter.loader.load();
