# vino-edge-worker

Cloudflare Worker for putting a Cloudflare edge layer in front of `vino_platform`.

This Worker is intentionally thin:

- Proxies API traffic to the ECS origin.
- Does not cache authenticated requests.
- Does not cache `/api/*` by default.
- Can cache explicit static prefixes such as `/assets/`, `/cdn/`, and `/models/`.
- Keeps large model delivery outside Worker business logic.

## Setup

```sh
cd cloudflare/vino-edge-worker
npm install
copy wrangler.toml.example wrangler.toml
```

Edit `wrangler.toml`:

```toml
[vars]
ORIGIN_BASE_URL = "https://origin.example.com"
CACHE_PATH_PREFIXES = "/assets/,/cdn/,/models/"
CACHE_DOWNLOAD_TICKETS = "false"
EDGE_CACHE_TTL_SECONDS = "604800"
```

Then:

```sh
npx wrangler login
npx wrangler deploy
```

Bind it to a route in Cloudflare, for example:

```txt
api.example.com/*
```

## Health Check

```sh
curl https://api.example.com/__edge/health
```

Expected:

```json
{"service":"vino-edge-worker","status":"ok","originConfigured":true}
```

## Cache Policy

Keep `CACHE_DOWNLOAD_TICKETS=false` for the current platform implementation.
Current download tickets generate short-lived, device-bound artifacts, so edge
caching those URLs has low reuse and can complicate entitlement semantics.

When model artifacts are moved to object storage/CDN, expose stable artifact
paths such as `/cdn/models/<modelBuildId>/<artifact>` and cache those paths.
