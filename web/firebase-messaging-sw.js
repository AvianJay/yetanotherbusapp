importScripts(
  'https://www.gstatic.com/firebasejs/12.12.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/12.12.0/firebase-messaging-compat.js',
);

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
    (config && config.app_base_url) || 'https://busapp.avianjay.sbs';
  const announcementId = encodeURIComponent(data.announcement_id || '');
  return (
    data.link ||
    `${appBaseUrl}/announcement/${announcementId}`
  );
}

function ensureMessaging() {
  if (messagingReadyPromise) {
    return messagingReadyPromise;
  }

  messagingReadyPromise = fetch(`${resolveApiBaseUrl()}/api/v1/push/public-config`, {
    cache: 'no-store',
  })
    .then((response) => (response.ok ? response.json() : null))
    .then((config) => {
      if (!config || !config.web_enabled || !config.web) {
        return null;
      }

      if (!firebase.apps.length) {
        firebase.initializeApp({
          apiKey: config.web.apiKey,
          authDomain: config.web.authDomain,
          projectId: config.web.projectId,
          storageBucket: config.web.storageBucket,
          messagingSenderId: config.web.messagingSenderId,
          appId: config.web.appId,
          measurementId: config.web.measurementId,
        });
      }

      const messaging = firebase.messaging();
      messaging.onBackgroundMessage((payload) => {
        const notification = payload.notification || {};
        const data = payload.data || {};
        const title = notification.title || data.title || 'YABus';
        const body = notification.body || data.content || '';
        const link = announcementLink(config, data);
        const icon =
          `${config.app_base_url || 'https://busapp.avianjay.sbs'}/icons/Icon-192.png`;
        self.registration.showNotification(title, {
          body,
          icon,
          data: {
            announcementId: data.announcement_id || '',
            link,
          },
        });
      });
      return config;
    })
    .catch(() => null);

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
