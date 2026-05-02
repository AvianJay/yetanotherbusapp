/// YABus Service Worker – cache-first for static assets, network-first for API.
const CACHE_NAME = 'yabus-v1';

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

const NETWORK_FIRST_HOSTS = [
  'localhost',
  '127.0.0.1',
];

// ── Install ────────────────────────────────────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)),
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
  const url = new URL(event.request.url);

  // Only handle same-origin or known API origins
  if (event.request.method !== 'GET') return;

  // Cache-first for static assets by extension
  const isStaticAsset = CACHE_FIRST_EXTENSIONS.some(
    (ext) => url.pathname.endsWith(ext),
  );

  if (isStaticAsset) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request).then((response) => {
          if (response && response.status === 200) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        }).catch(() => caches.match(event.request));
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
