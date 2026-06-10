const DEFAULT_PUBLIC_BASE_URL = 'https://busapp.avianjay.sbs';
const DEFAULT_APPLE_TEAM_ID = '2V25DVST23';
const DEFAULT_IOS_BUNDLE_ID = 'tw.avianjay.taiwanbus.flutter';
const DEFAULT_APP_CLIP_BUNDLE_ID = `${DEFAULT_IOS_BUNDLE_ID}.Clip`;

function trimTrailingSlash(value, fallback) {
  const normalized = `${value ?? ''}`.trim();
  const base = normalized || fallback;
  return base.replace(/\/+$/, '');
}

function jsonResponse(payload, init = {}) {
  const headers = new Headers(init.headers);
  if (!headers.has('content-type')) {
    headers.set('content-type', 'application/json; charset=utf-8');
  }
  if (!headers.has('cache-control')) {
    headers.set('cache-control', 'no-store');
  }
  return new Response(JSON.stringify(payload, null, 2), {
    ...init,
    headers,
  });
}

function buildPublicBaseUrl(request, env) {
  return trimTrailingSlash(env.PUBLIC_BASE_URL, new URL(request.url).origin);
}

function buildAppleAssociation(env) {
  const appleTeamId =
    `${env.APPLE_TEAM_ID ?? DEFAULT_APPLE_TEAM_ID}`.trim() ||
    DEFAULT_APPLE_TEAM_ID;
  const iosBundleId =
    `${env.IOS_APP_BUNDLE_ID ?? DEFAULT_IOS_BUNDLE_ID}`.trim() ||
    DEFAULT_IOS_BUNDLE_ID;
  const appClipBundleId =
    `${env.APP_CLIP_BUNDLE_ID ?? `${iosBundleId}.Clip`}`.trim() ||
    DEFAULT_APP_CLIP_BUNDLE_ID;
  const appId = `${appleTeamId}.${iosBundleId}`;
  const clipId = `${appleTeamId}.${appClipBundleId}`;

  return {
    appId,
    clipId,
    appClipBundleId,
    payload: {
      applinks: {
        details: [
          {
            appIDs: [appId],
            components: [
              { '/': '/route/*', comment: 'YABus route detail links' },
              { '/': '/search', comment: 'YABus search' },
              { '/': '/nearby', comment: 'YABus nearby' },
              { '/': '/favorites', comment: 'YABus favorites' },
              { '/': '/announcement/*', comment: 'YABus announcements' },
            ],
          },
        ],
      },
      appclips: {
        apps: [clipId],
      },
      webcredentials: {
        apps: [appId],
      },
    },
  };
}

async function serveStatic(request, env) {
  return env.ASSETS.fetch(request);
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods':
            'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS',
          'access-control-allow-headers':
            request.headers.get('access-control-request-headers') ?? '*',
        },
      });
    }

    const url = new URL(request.url);
    const appleAssociation = buildAppleAssociation(env);
    const publicBaseUrl = buildPublicBaseUrl(request, env);

    if (
      url.pathname === '/apple-app-site-association' ||
      url.pathname === '/.well-known/apple-app-site-association'
    ) {
      return jsonResponse(appleAssociation.payload);
    }

    if (url.pathname === '/.well-known/appclip') {
      return jsonResponse({
        invocationURL: `${publicBaseUrl}/route/`,
        appClipBundleId: appleAssociation.appClipBundleId,
        appID: appleAssociation.clipId,
      });
    }

    return serveStatic(request, env);
  },
};
