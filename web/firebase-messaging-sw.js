importScripts(
  'https://www.gstatic.com/firebasejs/12.12.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/12.12.0/firebase-messaging-compat.js',
);

const DEFAULT_APP_BASE_URL = 'https://busapp.avianjay.sbs';
const DEFAULT_FIREBASE_WEB_CONFIG = Object.freeze({
  apiKey: 'AIzaSyAMzgL6WxQarMcuXYrrqOHZsxUFVytkcuM',
  authDomain: 'yabus-111c1.firebaseapp.com',
  projectId: 'yabus-111c1',
  storageBucket: 'yabus-111c1.firebasestorage.app',
  messagingSenderId: '1011547280811',
  appId: '1:1011547280811:web:7e1e0c0a1baa160df7aeee',
  measurementId: 'G-RB7WBXXRQN',
});

let messagingReadyPromise = null;

function resolveApiBaseUrl() {
  const host = (self.location && self.location.hostname || '').toLowerCase();
  if (host === 'localhost' || host === '127.0.0.1') {
    return 'http://127.0.0.1:8000';
  }
  if (host === 'busapp.avianjay.sbs') {
    return 'https://bus.avianjay.sbs';
  }
  return 'https://bus.avianjay.sbs';
}

function announcementLink(config, data) {
  const appBaseUrl =
    (config && config.app_base_url) || DEFAULT_APP_BASE_URL;
  const announcementId = encodeURIComponent(data.announcement_id || '');
  return (
    data.link ||
    `${appBaseUrl}/announcement/${announcementId}`
  );
}

function normalizeString(value) {
  if (typeof value === 'string') {
    return value.trim();
  }
  return `${value ?? ''}`.trim();
}

function buildRuntimeConfig(config) {
  const runtimeConfig =
    config && typeof config === 'object' ? config : {};
  const webConfig =
    runtimeConfig.web && typeof runtimeConfig.web === 'object'
      ? runtimeConfig.web
      : {};

  return {
    web_enabled: runtimeConfig.web_enabled !== false,
    app_base_url:
      normalizeString(runtimeConfig.app_base_url) || DEFAULT_APP_BASE_URL,
    web: {
      ...DEFAULT_FIREBASE_WEB_CONFIG,
      apiKey:
        normalizeString(webConfig.apiKey) ||
        DEFAULT_FIREBASE_WEB_CONFIG.apiKey,
      authDomain:
        normalizeString(webConfig.authDomain) ||
        DEFAULT_FIREBASE_WEB_CONFIG.authDomain,
      projectId:
        normalizeString(webConfig.projectId) ||
        DEFAULT_FIREBASE_WEB_CONFIG.projectId,
      storageBucket:
        normalizeString(webConfig.storageBucket) ||
        DEFAULT_FIREBASE_WEB_CONFIG.storageBucket,
      messagingSenderId:
        normalizeString(webConfig.messagingSenderId) ||
        DEFAULT_FIREBASE_WEB_CONFIG.messagingSenderId,
      appId:
        normalizeString(webConfig.appId) ||
        DEFAULT_FIREBASE_WEB_CONFIG.appId,
      measurementId:
        normalizeString(webConfig.measurementId) ||
        DEFAULT_FIREBASE_WEB_CONFIG.measurementId,
      vapidKey: normalizeString(webConfig.vapidKey),
    },
  };
}

function ensureMessaging() {
  if (messagingReadyPromise) {
    return messagingReadyPromise;
  }

  messagingReadyPromise = fetch(`${resolveApiBaseUrl()}/api/v1/push/public-config`, {
    cache: 'no-store',
  })
    .then((response) => (response.ok ? response.json() : null))
    .catch(() => null)
    .then((config) => {
      const runtimeConfig = buildRuntimeConfig(config);
      if (!runtimeConfig.web_enabled) {
        return null;
      }

      if (!firebase.apps.length) {
        firebase.initializeApp({
          apiKey: runtimeConfig.web.apiKey,
          authDomain: runtimeConfig.web.authDomain,
          projectId: runtimeConfig.web.projectId,
          storageBucket: runtimeConfig.web.storageBucket,
          messagingSenderId: runtimeConfig.web.messagingSenderId,
          appId: runtimeConfig.web.appId,
          measurementId: runtimeConfig.web.measurementId,
        });
      }

      const messaging = firebase.messaging();
      messaging.onBackgroundMessage((payload) => {
        const notification = payload.notification || {};
        const data = payload.data || {};
        const title = notification.title || data.title || 'YABus';
        const body = notification.body || data.content || '';
        const link = announcementLink(runtimeConfig, data);
        const icon =
          `${runtimeConfig.app_base_url || DEFAULT_APP_BASE_URL}/icons/Icon-192.png`;
        self.registration.showNotification(title, {
          body,
          icon,
          data: {
            announcementId: data.announcement_id || '',
            link,
          },
        });
      });
      return runtimeConfig;
    });

  return messagingReadyPromise;
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const link = data.link;
  if (!link) {
    return;
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (windowClients) => {
        for (const client of windowClients) {
          if ('focus' in client) {
            client.navigate(link);
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow(link);
        }
        return undefined;
      },
    ),
  );
});

ensureMessaging();
