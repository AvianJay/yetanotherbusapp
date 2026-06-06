import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';

const port = Number.parseInt(process.env.PORT ?? '4173', 10);
const host = process.env.HOST ?? '0.0.0.0';
const webRoot = resolve(process.env.WEB_ROOT ?? 'build/web');
const upstreamApi = (process.env.YABUS_UPSTREAM_API ?? 'https://bus.avianjay.sbs').replace(/\/+$/, '');
const publicBaseUrl = (process.env.PUBLIC_BASE_URL ?? `http://localhost:${port}`).replace(/\/+$/, '');
const appleTeamId = process.env.APPLE_TEAM_ID ?? '2V25DVST23';
const iosBundleId = process.env.IOS_APP_BUNDLE_ID ?? 'tw.avianjay.taiwanbus.flutter';
const appClipBundleId = process.env.APP_CLIP_BUNDLE_ID ?? `${iosBundleId}.Clip`;

const mimeTypes = new Map([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.mjs', 'text/javascript; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.wasm', 'application/wasm'],
  ['.png', 'image/png'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.gif', 'image/gif'],
  ['.svg', 'image/svg+xml'],
  ['.ico', 'image/x-icon'],
  ['.webp', 'image/webp'],
  ['.ttf', 'font/ttf'],
  ['.otf', 'font/otf'],
  ['.woff', 'font/woff'],
  ['.woff2', 'font/woff2'],
]);

function send(res, statusCode, body, headers = {}) {
  res.writeHead(statusCode, headers);
  res.end(body);
}

function appleAssociation() {
  const appId = `${appleTeamId}.${iosBundleId}`;
  const clipId = `${appleTeamId}.${appClipBundleId}`;
  return {
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
  };
}

async function proxyApi(req, res, requestUrl) {
  const target = new URL(`${requestUrl.pathname}${requestUrl.search}`, upstreamApi);
  const headers = new Headers(req.headers);
  headers.set('host', target.host);
  headers.delete('connection');
  headers.delete('content-length');
  headers.delete('accept-encoding');

  const response = await fetch(target, {
    method: req.method,
    headers,
    body: req.method === 'GET' || req.method === 'HEAD' ? undefined : req,
    duplex: 'half',
  });

  const responseHeaders = Object.fromEntries(response.headers.entries());
  responseHeaders['access-control-allow-origin'] = '*';
  responseHeaders['cache-control'] ??= 'no-store';
  responseHeaders['content-encoding'] && delete responseHeaders['content-encoding'];
  responseHeaders['content-length'] && delete responseHeaders['content-length'];
  res.writeHead(response.status, responseHeaders);
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  const body = Buffer.from(await response.arrayBuffer());
  res.end(body);
}

async function serveStatic(req, res, requestUrl) {
  let pathname;
  try {
    pathname = decodeURIComponent(requestUrl.pathname);
  } catch {
    send(res, 400, 'Bad request');
    return;
  }

  if (pathname === '/apple-app-site-association' || pathname === '/.well-known/apple-app-site-association') {
    send(res, 200, JSON.stringify(appleAssociation(), null, 2), {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    });
    return;
  }

  if (pathname === '/.well-known/appclip') {
    send(res, 200, JSON.stringify({
      invocationURL: `${publicBaseUrl}/route/`,
      appClipBundleId,
      appID: `${appleTeamId}.${appClipBundleId}`,
    }, null, 2), {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    });
    return;
  }

  const normalizedPath = normalize(pathname).replace(/^(\.\.[/\\])+/, '');
  let filePath = resolve(join(webRoot, normalizedPath));
  if (!filePath.startsWith(webRoot)) {
    send(res, 403, 'Forbidden');
    return;
  }

  if (existsSync(filePath) && statSync(filePath).isDirectory()) {
    filePath = join(filePath, 'index.html');
  }

  if (!existsSync(filePath)) {
    filePath = join(webRoot, 'index.html');
  }

  const extension = extname(filePath).toLowerCase();
  const contentType = mimeTypes.get(extension) ?? 'application/octet-stream';
  const immutable = /\.(?:js|wasm|png|jpg|jpeg|gif|svg|ico|webp|ttf|otf|woff2?)$/i.test(filePath);
  res.writeHead(200, {
    'content-type': contentType,
    'cache-control': immutable ? 'public, max-age=31536000, immutable' : 'no-cache',
  });
  createReadStream(filePath).pipe(res);
}

const server = createServer(async (req, res) => {
  try {
    const requestUrl = new URL(req.url ?? '/', publicBaseUrl);

    if (req.method === 'OPTIONS') {
      send(res, 204, '', {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET,HEAD,POST,PUT,PATCH,DELETE,OPTIONS',
        'access-control-allow-headers': req.headers['access-control-request-headers'] ?? '*',
      });
      return;
    }

    if (requestUrl.pathname.startsWith('/api/')) {
      await proxyApi(req, res, requestUrl);
      return;
    }

    await serveStatic(req, res, requestUrl);
  } catch (error) {
    console.error(error);
    send(res, 502, `Server error: ${error instanceof Error ? error.message : String(error)}`);
  }
});

server.listen(port, host, async () => {
  const versionPath = join(webRoot, 'version.json');
  let version = 'unknown';
  try {
    version = await readFile(versionPath, 'utf8');
  } catch {
    // The app can still run without version.json.
  }
  console.log(`YABus web server listening on http://localhost:${port}`);
  console.log(`Serving ${webRoot}`);
  console.log(`Proxying /api to ${upstreamApi}`);
  console.log(`Apple app/site association: ${appleTeamId}.${iosBundleId}, ${appleTeamId}.${appClipBundleId}`);
  if (version !== 'unknown') {
    console.log(`version.json: ${version.trim()}`);
  }
});
