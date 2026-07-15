/// YABus Service Worker – versioned cache, cache-first for static assets,
/// network-first for API calls and navigations.
///
/// BUILD_VERSION is stamped at deploy time by scripts/stamp-web-build.mjs,
/// so every deployment ships a byte-different sw.js with its own cache name.
/// Installing the new worker precaches the new build; activating it deletes
/// every older cache, so clients switch to the new build atomically after
/// one reload. Without this, cache-first assets (main.dart.js has no content
/// hash in its name) would be served from cache forever.
const BUILD_VERSION = '__YABUS_BUILD_VERSION__';
const CACHE_NAME = 'yabus-' + (BUILD_VERSION.startsWith('__') ? 'dev' : BUILD_VERSION);

const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
];

const CACHE_FIRST_EXTENSIONS = [
  '.js', '.dart.js', '.wasm', '.json', '.png', '.jpg', '.jpeg',
  '.gif', '.webp', '.svg', '.css', '.ttf', '.woff2', '.html',
];

/// Paths that must always bypass the cache (network-only).
const NETWORK_ONLY_PATHS = [
  '/sw.js',
  '/firebase-messaging-sw.js',
];

/// Paths that should prefer the network but still fall back to cache when
/// the app starts offline.
const NETWORK_FIRST_PATHS = [
  '/version.json',
];

// ── Install ────────────────────────────────────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      // `reload` bypasses the HTTP cache so the precache really holds the
      // new deployment. Per-URL error handling keeps one missing file from
      // blocking the whole install (which would strand users on the old
      // service worker).
      Promise.all(
        PRECACHE_URLS.map((url) =>
          cache.add(new Request(url, { cache: 'reload' })).catch((err) => {
            console.warn('[YABus SW] precache failed for', url, err);
          }),
        ),
      ),
    ),
  );
  self.skipWaiting();
});

// ── Activate ───────────────────────────────────────────────────
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)),
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

  // Cache-first for static assets by extension. Navigations are excluded so
  // page loads always reach the network first and pick up new deployments.
  const isStaticAsset =
    event.request.mode !== 'navigate' &&
    CACHE_FIRST_EXTENSIONS.some((ext) => url.pathname.endsWith(ext));

  if (isStaticAsset) {
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

  // Network-first for everything else (API calls, HTML navigation)
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        if (response && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(event.request)),
  );
});
