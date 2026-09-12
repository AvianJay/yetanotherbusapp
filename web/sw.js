/// YABus Service Worker – versioned app-shell cache and network-first
/// navigation.
///
/// BUILD_VERSION is stamped at deploy time by scripts/stamp-web-build.mjs,
/// so every deployment ships a byte-different sw.js with its own cache name.
/// Installing the new worker precaches the new build; activating it deletes
/// only prior YABus caches, so clients switch to the new build atomically after
/// one reload. The build stamp script generates app-shell.json from the actual
/// Flutter output, avoiding a stale hand-maintained asset list.
const BUILD_VERSION = '__YABUS_BUILD_VERSION__';
const CACHE_NAME = 'yabus-' + (BUILD_VERSION.startsWith('__') ? 'dev' : BUILD_VERSION);

const APP_SHELL_MANIFEST_URL = '/app-shell.json';
const BASE_PRECACHE_URLS = [
  '/',
  '/index.html',
  APP_SHELL_MANIFEST_URL,
  '/manifest.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
];

const STATIC_ASSET_PATHS = new Set([
  '/flutter.js',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/main.dart.mjs',
  '/main.dart.wasm',
  '/manifest.json',
  '/favicon.png',
]);
const STATIC_ASSET_PREFIXES = [
  '/assets/',
  '/canvaskit/',
  '/icons/',
  '/splash/',
];

/// Paths that must always bypass the cache (network-only).
const NETWORK_ONLY_PATHS = [
  '/sw.js',
  '/firebase-messaging-sw.js',
  '/flutter_service_worker.js',
];

/// Paths that should prefer the network but still fall back to cache when
/// the app starts offline.
const NETWORK_FIRST_PATHS = [
  '/version.json',
];

function isStaticAsset(pathname) {
  return (
    STATIC_ASSET_PATHS.has(pathname) ||
    STATIC_ASSET_PREFIXES.some((prefix) => pathname.startsWith(prefix))
  );
}

async function appShellUrls() {
  try {
    const response = await fetch(APP_SHELL_MANIFEST_URL, { cache: 'reload' });
    if (!response.ok) {
      return [];
    }
    const urls = await response.json();
    return Array.isArray(urls)
      ? urls.filter((url) => typeof url === 'string' && url.startsWith('/'))
      : [];
  } catch (error) {
    console.warn('[YABus SW] app shell manifest unavailable', error);
    return [];
  }
}

async function precache(cache) {
  const urls = new Set([...BASE_PRECACHE_URLS, ...(await appShellUrls())]);
  await Promise.all(
    [...urls].map((url) =>
      cache.add(new Request(url, { cache: 'reload' })).catch((error) => {
        // A missing optional renderer artifact must not strand users on an
        // older service worker.
        console.warn('[YABus SW] precache failed for', url, error);
      }),
    ),
  );
}

// ── Install ────────────────────────────────────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then(precache));
  self.skipWaiting();
});

// ── Activate ───────────────────────────────────────────────────
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith('yabus-') && key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ),
    ),
  );
  self.clients.claim();
});

// ── Fetch ──────────────────────────────────────────────────────
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // Leave cross-origin requests (CDN scripts, analytics, external APIs) to
  // the browser: caching them here would freeze them across deployments.
  if (url.origin !== self.location.origin) return;

  // Network-only: service worker scripts must never be cached
  if (NETWORK_ONLY_PATHS.some((p) => url.pathname === p)) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Network-first with cache fallback for version.json so offline startup
  // can still read the previously fetched app metadata.
  if (NETWORK_FIRST_PATHS.some((p) => url.pathname === p)) {
    const cacheKey = `${url.origin}${url.pathname}`;
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(cacheKey, clone));
          }
          return response;
        })
        .catch(() => caches.match(cacheKey)),
    );
    return;
  }

  // Cache-first only for known Flutter build assets. Navigations always reach
  // the network first so direct links pick up new deployments.
  if (event.request.mode !== 'navigate' && isStaticAsset(url.pathname)) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        // `no-cache` revalidates with the origin so the browser HTTP cache
        // cannot repopulate a fresh deployment's cache with stale assets.
        return fetch(url.href, { cache: 'no-cache', credentials: 'same-origin' })
          .then((response) => {
            if (response && response.status === 200) {
              const clone = response.clone();
              caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
            }
            return response;
          })
          .catch(() => caches.match(event.request));
      }),
    );
    return;
  }

  // Do not cache arbitrary same-origin responses. Offline direct links fall
  // back to the app shell, which Flutter then resolves with its route parser.
  event.respondWith(
    fetch(event.request).catch(() =>
      event.request.mode === 'navigate'
        ? caches.match('/index.html')
        : caches.match(event.request),
    ),
  );
});
