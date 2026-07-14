const DEFAULT_CACHE_PREFIXES = ['/assets/', '/cdn/', '/models/'];

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === '/__edge/health') {
      return json({
        service: 'vino-edge-worker',
        status: 'ok',
        now: new Date().toISOString(),
        originConfigured: Boolean(env.ORIGIN_BASE_URL),
      });
    }

    if (!env.ORIGIN_BASE_URL) {
      return json({ error: 'ORIGIN_BASE_URL is not configured' }, 500);
    }

    const targetURL = buildOriginURL(request, env.ORIGIN_BASE_URL);
    const cacheable = isCacheableRequest(request, url, env);

    if (!cacheable) {
      return fetchOrigin(request, targetURL, { bypassCache: true });
    }

    const cache = caches.default;
    const cacheKey = new Request(url.toString(), { method: 'GET' });
    const cached = await cache.match(cacheKey);
    if (cached) {
      return withEdgeHeader(cached, 'HIT');
    }

    const response = await fetchOrigin(request, targetURL, { bypassCache: false });
    const cacheCandidate = makeCacheCandidate(response, env);
    if (cacheCandidate) {
      ctx.waitUntil(cache.put(cacheKey, cacheCandidate.clone()));
      return withEdgeHeader(cacheCandidate, 'MISS');
    }

    return withEdgeHeader(response, 'BYPASS');
  },
};

function json(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function buildOriginURL(request, originBaseURL) {
  const requestURL = new URL(request.url);
  const origin = new URL(originBaseURL);
  return new URL(`${requestURL.pathname}${requestURL.search}`, origin);
}

function isCacheableRequest(request, url, env) {
  if (request.method !== 'GET') {
    return false;
  }
  if (request.headers.has('authorization')) {
    return false;
  }
  if (url.pathname.startsWith('/api/')) {
    return env.CACHE_DOWNLOAD_TICKETS === 'true'
      && url.pathname.startsWith('/api/cloud/v1/download/');
  }
  return cachePrefixes(env).some((prefix) => url.pathname.startsWith(prefix));
}

function cachePrefixes(env) {
  const raw = String(env.CACHE_PATH_PREFIXES || '').trim();
  if (!raw) {
    return DEFAULT_CACHE_PREFIXES;
  }
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

async function fetchOrigin(request, targetURL, { bypassCache }) {
  const headers = new Headers(request.headers);
  headers.set('x-forwarded-host', new URL(request.url).host);
  headers.set('x-forwarded-proto', 'https');
  headers.delete('cf-connecting-ip');
  headers.delete('cf-ipcountry');
  headers.delete('cf-ray');
  headers.delete('cf-visitor');

  const init = {
    method: request.method,
    headers,
    body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
    redirect: 'manual',
    cf: bypassCache
      ? { cacheTtl: 0, cacheEverything: false }
      : { cacheEverything: true },
  };

  return fetch(targetURL.toString(), init);
}

function makeCacheCandidate(response, env) {
  if (!response || response.status !== 200) {
    return null;
  }
  const cacheControl = response.headers.get('cache-control') || '';
  if (/no-store|private/i.test(cacheControl)) {
    return null;
  }

  const ttl = Number(env.EDGE_CACHE_TTL_SECONDS || 604800);
  const headers = new Headers(response.headers);
  headers.set('cache-control', `public, max-age=${Math.max(60, ttl)}`);
  headers.set('x-vino-edge-cacheable', 'true');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function withEdgeHeader(response, value) {
  const headers = new Headers(response.headers);
  headers.set('x-vino-edge-cache', value);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
