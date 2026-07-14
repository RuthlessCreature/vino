const http = require('node:http');
const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { once } = require('node:events');
const { URL } = require('node:url');

const ROOT = __dirname;
const REPO_ROOT = path.resolve(ROOT, '..');
const HOST = process.env.HOST || '0.0.0.0';
const PORT = Number(process.env.PORT || 8797);
const PUBLIC_ROOT = path.resolve(process.env.VINO_PUBLIC_ROOT || path.join(ROOT, 'public'));
const DATA_ROOT = path.resolve(process.env.VINO_DATA_ROOT || path.join(ROOT, 'data'));
const STATE_PATH = path.resolve(process.env.VINO_STATE_PATH || path.join(DATA_ROOT, 'state.json'));
const INGEST_ASSET_ROOT = path.resolve(process.env.VINO_INGEST_ASSET_ROOT || path.join(DATA_ROOT, 'assets'));
const MODEL_UPLOAD_ROOT = path.resolve(process.env.VINO_MODEL_UPLOAD_ROOT || path.join(DATA_ROOT, 'model-builds'));
const ARTIFACT_CACHE_ROOT = path.resolve(process.env.VINO_ARTIFACT_CACHE_ROOT || path.join(DATA_ROOT, 'artifact-cache'));
const DOWNLOAD_WORK_ROOT = path.resolve(process.env.VINO_DOWNLOAD_WORK_ROOT || path.join(DATA_ROOT, 'download-work'));
const BACKUP_ROOT = path.resolve(process.env.VINO_BACKUP_ROOT || path.join(DATA_ROOT, 'backups'));
const MODELS_ROOT = path.resolve(process.env.VINO_MODELS_ROOT || path.join(REPO_ROOT, 'models'));
const SKIP_MODEL_DISCOVERY = process.env.VINO_SKIP_MODEL_DISCOVERY === '1';
const EXTERNAL_BASE_URL = String(process.env.VINO_EXTERNAL_BASE_URL || '').replace(/\/+$/, '');
const REQUEST_BODY_LIMIT_BYTES = parseByteSize(process.env.VINO_REQUEST_BODY_LIMIT || process.env.REQUEST_BODY_LIMIT || '200mb');
const SESSION_TTL_DAYS = Number(process.env.VINO_SESSION_TTL_DAYS || 7);
const SEED_DEMO_DATA = parseBoolean(process.env.VINO_SEED_DEMO_DATA, true);
const BOOTSTRAP_ADMIN_EMAIL = String(process.env.VINO_BOOTSTRAP_ADMIN_EMAIL || 'admin').trim().toLowerCase();
const BOOTSTRAP_ADMIN_PASSWORD = String(process.env.VINO_BOOTSTRAP_ADMIN_PASSWORD || '');
const RATE_LIMIT_ENABLED = parseBoolean(process.env.VINO_RATE_LIMIT_ENABLED, true);
const RATE_LIMIT_WINDOW_MS = parsePositiveInt(process.env.VINO_RATE_LIMIT_WINDOW_MS, 60 * 1000);
const RATE_LIMIT_MAX = parsePositiveInt(process.env.VINO_RATE_LIMIT_MAX, 600);
const RATE_LIMIT_AUTH_MAX = parsePositiveInt(process.env.VINO_RATE_LIMIT_AUTH_MAX, 30);
const MAINTENANCE_TICKET_RETENTION_DAYS = parsePositiveInt(process.env.VINO_TICKET_RETENTION_DAYS, 30);
const MAINTENANCE_DOWNLOAD_WORK_RETENTION_MINUTES = parsePositiveInt(process.env.VINO_DOWNLOAD_WORK_RETENTION_MINUTES, 60);
const MAINTENANCE_ARTIFACT_CACHE_RETENTION_DAYS = parsePositiveInt(process.env.VINO_ARTIFACT_CACHE_RETENTION_DAYS, 30);
const PASSWORD_HASH_ITERATIONS = 120000;
const ARCHIVE_CACHE = new Map();
const RATE_LIMIT_BUCKETS = new Map();
let STATE_OPERATION_LOCK = Promise.resolve();
let STATE_OPERATION_QUEUE_DEPTH = 0;
let STATE_OPERATION_LAST_ERROR_AT = null;
const ENCRYPTION_ENVELOPE_MAGIC = Buffer.from('VINOENC1', 'utf8');
const BUNDLE_ARCHIVE_MAGIC = Buffer.from('VINOAR01', 'utf8');
const ENCRYPTION_ALGORITHM = 'aes-256-gcm';

function parseByteSize(value) {
  const raw = String(value || '').trim().toLowerCase();
  const match = raw.match(/^(\d+(?:\.\d+)?)\s*(b|kb|mb|gb)?$/);
  if (!match) {
    return 200 * 1024 * 1024;
  }
  const number = Number(match[1]);
  const unit = match[2] || 'b';
  const multiplier = {
    b: 1,
    kb: 1024,
    mb: 1024 * 1024,
    gb: 1024 * 1024 * 1024,
  }[unit];
  return Math.floor(number * multiplier);
}

function parseBoolean(value, defaultValue = false) {
  if (value == null || value === '') {
    return defaultValue;
  }
  return ['1', 'true', 'yes', 'on'].includes(String(value).trim().toLowerCase());
}

function parsePositiveInt(value, defaultValue) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.floor(number) : defaultValue;
}

function parseNonNegativeInt(value, defaultValue) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.floor(number) : defaultValue;
}

function isoNow() {
  return new Date().toISOString();
}

function plusDays(days) {
  return new Date(Date.now() + Number(days || 0) * 24 * 60 * 60 * 1000).toISOString();
}

function plusMinutes(minutes) {
  return new Date(Date.now() + Number(minutes || 0) * 60 * 1000).toISOString();
}

function shortHash(value) {
  return crypto.createHash('sha1').update(String(value)).digest('hex').slice(0, 12);
}

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  return {
    passwordSalt: salt,
    passwordHash: crypto.pbkdf2Sync(String(password), salt, PASSWORD_HASH_ITERATIONS, 32, 'sha256').toString('hex'),
    passwordAlgorithm: `pbkdf2-sha256:${PASSWORD_HASH_ITERATIONS}`,
  };
}

function setUserPassword(user, password) {
  Object.assign(user, hashPassword(password));
  delete user.password;
}

function verifyPassword(user, password) {
  if (user.passwordHash && user.passwordSalt) {
    const expected = Buffer.from(user.passwordHash, 'hex');
    const actual = Buffer.from(hashPassword(password, user.passwordSalt).passwordHash, 'hex');
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  }
  return typeof user.password === 'string' && user.password === String(password);
}

function slugify(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'model';
}

function safeFileName(value, fallback = 'upload.bin') {
  const raw = path.basename(String(value || fallback)).replace(/[^a-zA-Z0-9._-]/g, '-');
  return raw || fallback;
}

function normalizeTimestamp(value) {
  if (value == null || value === '') {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function money(value) {
  const number = Number(value || 0);
  return Number.isFinite(number) ? Math.round(number * 100) / 100 : 0;
}

function publicUser(user) {
  return {
    userId: user.userId,
    email: user.email,
    displayName: user.displayName,
    organizationId: user.organizationId,
    organizationName: user.organizationName,
    role: user.role,
    status: user.status || 'active',
  };
}

function responseHeaders(res, headers = {}) {
  return {
    ...headers,
    'X-Request-Id': res.requestId || '',
    'Access-Control-Allow-Origin': '*',
  };
}

function payloadWithRequestId(res, payload) {
  if (!payload?.error) {
    return payload;
  }
  return {
    ...payload,
    error: {
      requestId: res.requestId,
      ...payload.error,
    },
  };
}

function sendJson(res, statusCode, payload) {
  const body = Buffer.from(JSON.stringify(payloadWithRequestId(res, payload), null, 2));
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': body.length,
    ...responseHeaders(res),
  });
  res.end(body);
}

function sendBuffer(res, statusCode, buffer, contentType = 'application/octet-stream') {
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Content-Length': buffer.length,
    ...responseHeaders(res),
  });
  res.end(buffer);
}

function sendError(res, statusCode, code, message, details) {
  sendJson(res, statusCode, {
    error: {
      code,
      message,
      ...(details ? { details } : {}),
    },
  });
}

function sendFile(res, statusCode, filePath, byteCount, contentType = 'application/octet-stream', onDone = null) {
  const stream = fsSync.createReadStream(filePath);
  let cleaned = false;
  const cleanup = () => {
    if (cleaned) {
      return;
    }
    cleaned = true;
    if (onDone) {
      onDone();
    }
  };
  stream.on('error', (error) => {
    cleanup();
    if (!res.headersSent) {
      sendJson(res, 500, { error: { code: 'file_stream_failed', message: error.message } });
    } else {
      res.destroy(error);
    }
  });
  stream.on('close', cleanup);
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Content-Length': byteCount,
    'Cache-Control': 'no-store',
    ...responseHeaders(res),
  });
  stream.pipe(res);
}

function fail(statusCode, code, message) {
  const error = new Error(message || code);
  error.statusCode = statusCode;
  error.code = code;
  throw error;
}

function normalizePathname(requestUrl) {
  return new URL(requestUrl, `http://127.0.0.1:${PORT}`).pathname;
}

function isPathInside(basePath, targetPath) {
  const relative = path.relative(basePath, targetPath);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function requestBaseUrl(req) {
  if (EXTERNAL_BASE_URL) {
    return EXTERNAL_BASE_URL;
  }
  const forwardedProto = String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim();
  const forwardedHost = String(req.headers['x-forwarded-host'] || '').split(',')[0].trim();
  const proto = forwardedProto || (req.socket.encrypted ? 'https' : 'http');
  const host = forwardedHost || req.headers.host || `127.0.0.1:${PORT}`;
  return `${proto}://${host}`;
}

function requestIdFromRequest(req) {
  const raw = String(req.headers['x-request-id'] || '').trim();
  const safe = raw.replace(/[^a-zA-Z0-9._:-]/g, '').slice(0, 96);
  return safe || crypto.randomUUID();
}

function clientIpFromRequest(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || req.socket.remoteAddress || 'unknown';
}

function rateLimitForPath(pathname) {
  if (/^\/api\/(platform|cloud)\/v1\/auth\/login$/.test(pathname)) {
    return { scope: 'auth', max: RATE_LIMIT_AUTH_MAX };
  }
  return { scope: 'global', max: RATE_LIMIT_MAX };
}

function pruneRateLimitBuckets(now) {
  if (RATE_LIMIT_BUCKETS.size < 5000) {
    return;
  }
  for (const [key, bucket] of RATE_LIMIT_BUCKETS) {
    if (now - bucket.windowStartedAt > RATE_LIMIT_WINDOW_MS * 2) {
      RATE_LIMIT_BUCKETS.delete(key);
    }
  }
}

function applyRateLimit(req, res, pathname) {
  if (!RATE_LIMIT_ENABLED || req.method === 'OPTIONS') {
    return true;
  }
  const { scope, max } = rateLimitForPath(pathname);
  if (!max) {
    return true;
  }
  const now = Date.now();
  pruneRateLimitBuckets(now);
  const key = `${scope}:${clientIpFromRequest(req)}`;
  const current = RATE_LIMIT_BUCKETS.get(key);
  const bucket = current && now - current.windowStartedAt < RATE_LIMIT_WINDOW_MS
    ? current
    : { windowStartedAt: now, count: 0 };
  bucket.count += 1;
  RATE_LIMIT_BUCKETS.set(key, bucket);

  const resetSeconds = Math.max(1, Math.ceil((bucket.windowStartedAt + RATE_LIMIT_WINDOW_MS - now) / 1000));
  const remaining = Math.max(0, max - bucket.count);
  res.setHeader('RateLimit-Limit', String(max));
  res.setHeader('RateLimit-Remaining', String(remaining));
  res.setHeader('RateLimit-Reset', String(resetSeconds));

  if (bucket.count <= max) {
    return true;
  }
  res.setHeader('Retry-After', String(resetSeconds));
  sendError(res, 429, 'rate_limited', 'too many requests', {
    scope,
    limit: max,
    windowMs: RATE_LIMIT_WINDOW_MS,
    retryAfterSeconds: resetSeconds,
  });
  return false;
}

async function ensureDirs() {
  await fs.mkdir(DATA_ROOT, { recursive: true });
  await fs.mkdir(INGEST_ASSET_ROOT, { recursive: true });
  await fs.mkdir(MODEL_UPLOAD_ROOT, { recursive: true });
  await fs.mkdir(ARTIFACT_CACHE_ROOT, { recursive: true });
  await fs.mkdir(DOWNLOAD_WORK_ROOT, { recursive: true });
}

async function readBody(req, limitBytes = REQUEST_BODY_LIMIT_BYTES) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > limitBytes) {
      fail(413, 'payload_too_large', 'payload too large');
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function parseJsonBuffer(buffer) {
  if (!buffer || buffer.length === 0) {
    return {};
  }
  return JSON.parse(buffer.toString('utf8'));
}

function authTokenFromRequest(req) {
  const raw = req.headers.authorization || '';
  return raw.startsWith('Bearer ') ? raw.slice('Bearer '.length).trim() : '';
}

function pruneSessions(state) {
  const now = Date.now();
  state.sessions = (state.sessions || []).filter((session) => {
    if (!session || session.revokedAt) {
      return false;
    }
    return new Date(session.expiresAt).getTime() > now;
  });
}

function getSessionFromToken(state, token) {
  if (!token) {
    return null;
  }
  const session = state.sessions.find((item) => item.accessToken === token);
  if (!session || session.revokedAt || new Date(session.expiresAt).getTime() <= Date.now()) {
    return null;
  }
  session.lastSeenAt = isoNow();
  return session;
}

function requireSession(state, req) {
  const session = getSessionFromToken(state, authTokenFromRequest(req));
  if (!session) {
    fail(401, 'unauthorized', 'unauthorized');
  }
  return session;
}

function requireAnyRole(state, req, roles) {
  const session = requireSession(state, req);
  if (!roles.includes(session.role)) {
    fail(403, 'forbidden', 'forbidden');
  }
  return session;
}

const ROLE_TABS = {
  super_admin: ['overview', 'market', 'developer', 'commerce', 'catalog', 'terminal', 'service', 'finance', 'ops'],
  admin: ['overview', 'market', 'developer', 'commerce', 'catalog', 'terminal', 'service', 'finance', 'ops'],
  platform_ops: ['overview', 'market', 'developer', 'commerce', 'catalog', 'terminal', 'service', 'ops'],
  reviewer: ['overview', 'developer', 'catalog'],
  finance: ['overview', 'finance'],
  buyer_admin: ['overview', 'market', 'commerce', 'terminal', 'service', 'finance'],
  buyer_operator: ['overview', 'market', 'terminal', 'service'],
  developer_admin: ['overview', 'developer', 'service', 'finance'],
};

function tabsForRole(role) {
  return ROLE_TABS[role] || ['overview'];
}

function roleLabel(role) {
  return {
    super_admin: '平台超级管理员',
    admin: '平台管理员',
    platform_ops: '平台运营',
    reviewer: '审核员',
    finance: '财务',
    buyer_admin: '采购管理员',
    buyer_operator: '现场操作员',
    developer_admin: '开发者',
  }[role] || role || '未知角色';
}

function isPlatformAdminRole(role) {
  return ['super_admin', 'admin', 'platform_ops'].includes(role);
}

function isAdminRole(role) {
  return isPlatformAdminRole(role);
}

function canUseMarketplaceRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator'].includes(role);
}

function canDeveloperSelfServiceRole(role) {
  return role === 'developer_admin';
}

function canReviewModelRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'reviewer'].includes(role);
}

function canCreateOrderRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'buyer_admin'].includes(role);
}

function canConfirmPaymentRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'finance'].includes(role);
}

function canRequestRefundRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'finance', 'buyer_admin'].includes(role);
}

function canCreateSupportTicketRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator', 'developer_admin'].includes(role);
}

function canCreateCustomRequestRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator'].includes(role);
}

function canSubmitCustomProposalRole(role) {
  return ['super_admin', 'admin', 'platform_ops', 'developer_admin'].includes(role);
}

function canRequestInvoiceRole(role) {
  return ['super_admin', 'admin', 'buyer_admin'].includes(role);
}

function canReviewFinanceRole(role) {
  return ['super_admin', 'admin', 'finance'].includes(role);
}

function canRequestWithdrawalRole(role) {
  return role === 'developer_admin';
}

function roleFeatures(role) {
  return {
    useMarketplace: canUseMarketplaceRole(role),
    developerSelfService: canDeveloperSelfServiceRole(role),
    reviewDevelopers: canReviewModelRole(role),
    reviewModels: canReviewModelRole(role),
    createOrders: canCreateOrderRole(role),
    confirmPayments: canConfirmPaymentRole(role),
    requestRefunds: canRequestRefundRole(role),
    manageEntitlements: isPlatformAdminRole(role),
    manageUsers: isPlatformAdminRole(role),
    manageSkus: isPlatformAdminRole(role),
    createSupportTickets: canCreateSupportTicketRole(role),
    manageSupportTickets: isPlatformAdminRole(role),
    createCustomRequests: canCreateCustomRequestRole(role),
    submitCustomProposals: canSubmitCustomProposalRole(role),
    requestInvoices: canRequestInvoiceRole(role),
    reviewInvoices: canReviewFinanceRole(role),
    requestWithdrawals: canRequestWithdrawalRole(role),
    reviewWithdrawals: canReviewFinanceRole(role),
    manageOps: isPlatformAdminRole(role),
    useTerminal: ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator'].includes(role),
  };
}

function permissionsForRole(role) {
  return {
    role,
    roleLabel: roleLabel(role),
    tabs: tabsForRole(role),
    isAdmin: isPlatformAdminRole(role),
    features: roleFeatures(role),
  };
}

function requireAdminSession(state, req) {
  const session = requireSession(state, req);
  if (!isPlatformAdminRole(session.role)) {
    fail(403, 'admin_required', 'admin access required');
  }
  return session;
}

function audit(state, actor, action, objectType, objectId, payload = {}) {
  state.auditLogs.push({
    auditId: `audit-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
    actorUserId: actor?.userId || null,
    actorType: actor ? 'user' : 'system',
    action,
    objectType,
    objectId,
    payload,
    createdAt: isoNow(),
  });
}

function notify(state, userId, title, body, kind = 'system') {
  const notification = {
    notificationId: `note-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
    userId,
    kind,
    title,
    body,
    readAt: null,
    createdAt: isoNow(),
  };
  state.notifications.push(notification);
  return notification;
}

function requiredString(body, key, label = key) {
  const value = String(body?.[key] || '').trim();
  if (!value) {
    fail(422, `${key}_required`, `${label} is required`);
  }
  return value;
}

async function discoverCoreMLBuilds() {
  if (SKIP_MODEL_DISCOVERY || !fsSync.existsSync(MODELS_ROOT)) {
    return [];
  }

  const priorityByFormat = { mlpackage: 3, mlmodel: 2, mlmodelc: 1 };
  const discovered = [];
  const queue = [MODELS_ROOT];

  while (queue.length > 0) {
    const current = queue.shift();
    const entries = await fs.readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      const absolute = path.join(current, entry.name);
      const extension = path.extname(entry.name).toLowerCase();
      const isModelBundle = entry.isDirectory() && (extension === '.mlpackage' || extension === '.mlmodelc');
      const isModelFile = entry.isFile() && extension === '.mlmodel';

      if (isModelBundle || isModelFile) {
        const stats = await fs.stat(absolute);
        const relative = path.relative(REPO_ROOT, absolute).split(path.sep).join('/');
        const baseName = path.basename(entry.name, extension);
        const slug = slugify(baseName);
        const sourceFormat = extension.slice(1);
        const modelId = `model-${shortHash(relative).slice(0, 10)}`;
        discovered.push({
          modelId,
          model: {
            modelId,
            developerId: 'dev-platform-seed',
            name: baseName || 'Imported Model',
            slug,
            category: 'cv',
            summary: `Imported CoreML model from ${relative}`,
            description: `Automatically discovered from repository path ${relative}.`,
            status: 'listed',
            tags: ['coreml', 'industrial', 'imported'],
            currentBuildId: `build-${slug}-${shortHash(`${relative}:${stats.mtimeMs}:${stats.size}`)}`,
            createdAt: isoNow(),
            updatedAt: isoNow(),
          },
          build: {
            modelBuildId: `build-${slug}-${shortHash(`${relative}:${stats.mtimeMs}:${stats.size}`)}`,
            modelId,
            version: '1.0.0',
            buildNumber: shortHash(`${relative}:${stats.mtimeMs}:${stats.size}`),
            platform: 'ios',
            sourcePath: relative,
            fileName: entry.name,
            sourceFormat,
            transportFormat: entry.isDirectory() ? 'bundle-archive' : 'raw-file',
            supportedPlatforms: ['ios'],
            isEncrypted: true,
            status: 'ready',
            byteCount: stats.size,
            sha256: '',
            createdAt: isoNow(),
          },
          priority: priorityByFormat[sourceFormat] || 0,
          dedupeKey: relative.replace(/\.(mlpackage|mlmodel|mlmodelc)$/i, ''),
        });
        continue;
      }

      if (entry.isDirectory()) {
        queue.push(absolute);
      }
    }
  }

  const deduped = new Map();
  for (const item of discovered) {
    const existing = deduped.get(item.dedupeKey);
    if (!existing || item.priority > existing.priority) {
      deduped.set(item.dedupeKey, item);
    }
  }
  return Array.from(deduped.values()).sort((left, right) => left.model.name.localeCompare(right.model.name));
}

function createSeedUser(user, password) {
  const seeded = { ...user };
  setUserPassword(seeded, password);
  return seeded;
}

function seedUsers() {
  if (!SEED_DEMO_DATA) {
    if (!BOOTSTRAP_ADMIN_PASSWORD) {
      return [];
    }
    return [
      createSeedUser({
        userId: 'user-admin-001',
        email: BOOTSTRAP_ADMIN_EMAIL || 'admin',
        displayName: 'Platform Admin',
        organizationId: 'org-platform-001',
        organizationName: 'Vino Platform',
        role: 'super_admin',
        status: 'active',
      }, BOOTSTRAP_ADMIN_PASSWORD),
    ];
  }

  return [
    createSeedUser({
      userId: 'user-admin-001',
      email: BOOTSTRAP_ADMIN_EMAIL || 'admin',
      displayName: 'Platform Admin',
      organizationId: 'org-platform-001',
      organizationName: 'Vino Platform',
      role: 'super_admin',
      status: 'active',
    }, BOOTSTRAP_ADMIN_PASSWORD || 'meiyoumima'),
    createSeedUser({
      userId: 'user-buyer-001',
      email: 'buyer@vino.cc',
      displayName: 'Buyer Admin',
      organizationId: 'org-demo-001',
      organizationName: 'Vino Demo Factory',
      role: 'buyer_admin',
      status: 'active',
    }, 'demo123'),
    createSeedUser({
      userId: 'user-demo-001',
      email: 'demo@vino.cc',
      displayName: 'Demo Operator',
      organizationId: 'org-demo-001',
      organizationName: 'Vino Demo Factory',
      role: 'buyer_operator',
      status: 'active',
    }, 'demo123'),
    createSeedUser({
      userId: 'user-dev-001',
      email: 'developer@vino.cc',
      displayName: 'Model Developer',
      organizationId: 'org-dev-001',
      organizationName: 'Vino Model Lab',
      role: 'developer_admin',
      status: 'active',
    }, 'demo123'),
    createSeedUser({
      userId: 'user-ops-001',
      email: 'ops@vino.cc',
      displayName: 'Platform Ops',
      organizationId: 'org-platform-001',
      organizationName: 'Vino Platform',
      role: 'platform_ops',
      status: 'active',
    }, 'demo123'),
    createSeedUser({
      userId: 'user-reviewer-001',
      email: 'reviewer@vino.cc',
      displayName: 'Model Reviewer',
      organizationId: 'org-platform-001',
      organizationName: 'Vino Platform',
      role: 'reviewer',
      status: 'active',
    }, 'demo123'),
    createSeedUser({
      userId: 'user-finance-001',
      email: 'finance@vino.cc',
      displayName: 'Finance Admin',
      organizationId: 'org-platform-001',
      organizationName: 'Vino Platform',
      role: 'finance',
      status: 'active',
    }, 'demo123'),
  ];
}

function seedState() {
  return {
    organizations: [
      {
        organizationId: 'org-demo-001',
        name: 'Vino Demo Factory',
        type: 'buyer',
        status: 'active',
        createdAt: isoNow(),
      },
      {
        organizationId: 'org-dev-001',
        name: 'Vino Model Lab',
        type: 'developer_company',
        status: 'active',
        createdAt: isoNow(),
      },
      {
        organizationId: 'org-platform-001',
        name: 'Vino Platform',
        type: 'internal',
        status: 'active',
        createdAt: isoNow(),
      },
    ],
    users: seedUsers(),
    developers: [
      {
        developerId: 'dev-platform-seed',
        organizationId: 'org-dev-001',
        displayName: 'Vino Model Lab',
        type: 'company',
        verificationStatus: 'approved',
        agreementSignedAt: isoNow(),
      },
    ],
    models: [],
    modelBuilds: [],
    modelSkus: [],
    orders: [],
    payments: [],
    entitlements: [],
    devices: [],
    deviceInvites: [],
    sessions: [],
    tickets: [],
    leases: [],
    reviews: [],
    modelReviews: [],
    favorites: [],
    supportTickets: [],
    customRequests: [],
    invoices: [],
    settlements: [],
    withdrawals: [],
    coupons: [],
    activities: [],
    notifications: [],
    categories: [
      { categoryId: 'cat-cv', name: '计算机视觉', slug: 'cv', status: 'active' },
      { categoryId: 'cat-ocr', name: 'OCR / 读码识别', slug: 'ocr', status: 'active' },
      { categoryId: 'cat-defect', name: '缺陷检测', slug: 'defect', status: 'active' },
      { categoryId: 'cat-safety', name: '现场安全', slug: 'safety', status: 'active' },
    ],
    platformSettings: {
      commissionRate: 0.12,
      defaultTrialDays: 7,
      defaultOfflineLeaseDays: 30,
      downloadTicketMinutes: 15,
      invoiceEnabled: true,
      manualPaymentEnabled: true,
    },
    auditLogs: [],
    ingests: {
      assets: [],
      results: [],
      logs: [],
      stats: [],
    },
  };
}

function mergeByKey(target, defaults, key) {
  const seen = new Set(target.map((item) => item[key]));
  for (const item of defaults) {
    if (!seen.has(item[key])) {
      target.push(item);
      seen.add(item[key]);
    }
  }
}

function ensureBaselineRecords(state) {
  const defaults = seedState();
  mergeByKey(state.organizations, defaults.organizations, 'organizationId');
  mergeByKey(state.users, defaults.users, 'userId');
  mergeByKey(state.developers, defaults.developers, 'developerId');
  mergeByKey(state.categories, defaults.categories, 'categoryId');
  state.platformSettings = {
    ...defaults.platformSettings,
    ...(state.platformSettings || {}),
  };
}

function migrateUserPasswords(state) {
  for (const user of state.users || []) {
    if (!user.passwordHash && typeof user.password === 'string') {
      setUserPassword(user, user.password);
      user.updatedAt = user.updatedAt || isoNow();
      continue;
    }
    if (user.passwordHash && Object.prototype.hasOwnProperty.call(user, 'password')) {
      delete user.password;
    }
  }
}

function normalizeState(state) {
  const normalized = { ...seedState(), ...state };
  normalized.organizations = Array.isArray(state.organizations) ? state.organizations : seedState().organizations;
  normalized.users = Array.isArray(state.users) ? state.users : seedState().users;
  normalized.developers = Array.isArray(state.developers) ? state.developers : seedState().developers;
  normalized.models = Array.isArray(state.models) ? state.models : [];
  normalized.modelBuilds = Array.isArray(state.modelBuilds) ? state.modelBuilds : [];
  normalized.modelSkus = Array.isArray(state.modelSkus) ? state.modelSkus : [];
  normalized.orders = Array.isArray(state.orders) ? state.orders : [];
  normalized.payments = Array.isArray(state.payments) ? state.payments : [];
  normalized.entitlements = Array.isArray(state.entitlements) ? state.entitlements : [];
  normalized.devices = Array.isArray(state.devices) ? state.devices : [];
  normalized.deviceInvites = Array.isArray(state.deviceInvites) ? state.deviceInvites : [];
  normalized.sessions = Array.isArray(state.sessions) ? state.sessions : [];
  normalized.tickets = Array.isArray(state.tickets) ? state.tickets : [];
  normalized.leases = Array.isArray(state.leases) ? state.leases : [];
  normalized.reviews = Array.isArray(state.reviews) ? state.reviews : [];
  normalized.modelReviews = Array.isArray(state.modelReviews) ? state.modelReviews : [];
  normalized.favorites = Array.isArray(state.favorites) ? state.favorites : [];
  normalized.supportTickets = Array.isArray(state.supportTickets) ? state.supportTickets : [];
  normalized.customRequests = Array.isArray(state.customRequests) ? state.customRequests : [];
  normalized.invoices = Array.isArray(state.invoices) ? state.invoices : [];
  normalized.settlements = Array.isArray(state.settlements) ? state.settlements : [];
  normalized.withdrawals = Array.isArray(state.withdrawals) ? state.withdrawals : [];
  normalized.coupons = Array.isArray(state.coupons) ? state.coupons : [];
  normalized.activities = Array.isArray(state.activities) ? state.activities : [];
  normalized.notifications = Array.isArray(state.notifications) ? state.notifications : [];
  normalized.categories = Array.isArray(state.categories) ? state.categories : seedState().categories;
  normalized.platformSettings = {
    ...seedState().platformSettings,
    ...(state.platformSettings || {}),
  };
  normalized.auditLogs = Array.isArray(state.auditLogs) ? state.auditLogs : [];
  normalized.ingests = {
    assets: Array.isArray(state.ingests?.assets) ? state.ingests.assets : [],
    results: Array.isArray(state.ingests?.results) ? state.ingests.results : [],
    logs: Array.isArray(state.ingests?.logs) ? state.ingests.logs : [],
    stats: Array.isArray(state.ingests?.stats) ? state.ingests.stats : [],
  };
  ensureBaselineRecords(normalized);
  migrateUserPasswords(normalized);
  pruneSessions(normalized);
  return normalized;
}

async function mergeDiscoveredModels(state) {
  const discovered = await discoverCoreMLBuilds();
  const modelById = new Map(state.models.map((item) => [item.modelId, item]));
  const buildById = new Map(state.modelBuilds.map((item) => [item.modelBuildId, item]));

  for (const item of discovered) {
    const existingModel = modelById.get(item.model.modelId);
    if (existingModel) {
      existingModel.name = existingModel.name || item.model.name;
      existingModel.currentBuildId = item.model.currentBuildId;
      existingModel.status = existingModel.status || 'listed';
      existingModel.tags = Array.from(new Set([...(existingModel.tags || []), ...item.model.tags]));
      existingModel.updatedAt = isoNow();
    } else {
      state.models.push(item.model);
      modelById.set(item.model.modelId, item.model);
    }

    const existingBuild = buildById.get(item.build.modelBuildId);
    if (existingBuild) {
      Object.assign(existingBuild, {
        sourcePath: item.build.sourcePath,
        fileName: item.build.fileName,
        sourceFormat: item.build.sourceFormat,
        transportFormat: item.build.transportFormat,
        isEncrypted: true,
        status: 'ready',
      });
    } else {
      state.modelBuilds.push(item.build);
      buildById.set(item.build.modelBuildId, item.build);
    }

    const skuId = `sku-${item.model.modelId}-annual`;
    if (!state.modelSkus.some((sku) => sku.skuId === skuId)) {
      state.modelSkus.push({
        skuId,
        modelId: item.model.modelId,
        buildId: item.build.modelBuildId,
        name: 'Annual device-bound license',
        licenseType: 'subscription',
        priceAmount: 9800,
        currency: 'CNY',
        durationDays: 365,
        maxDevices: 3,
        offlineLeaseDays: 30,
        status: 'active',
        createdAt: isoNow(),
      });
    }
  }

  const firstModel = state.models.find((model) => model.status === 'listed');
  const canSeedDemoEntitlement = SEED_DEMO_DATA
    && state.organizations.some((item) => item.organizationId === 'org-demo-001')
    && state.users.some((item) => item.userId === 'user-demo-001');
  if (canSeedDemoEntitlement && firstModel && !state.entitlements.some((item) => item.organizationId === 'org-demo-001' && item.modelId === firstModel.modelId)) {
    state.entitlements.push({
      entitlementId: `ent-${shortHash(`demo:${firstModel.modelId}`)}`,
      sourceOrderItemId: null,
      organizationId: 'org-demo-001',
      modelId: firstModel.modelId,
      modelSkuId: `sku-${firstModel.modelId}-annual`,
      assignedToType: 'user',
      assignedToId: 'user-demo-001',
      licenseId: `lic-${firstModel.modelId}-${shortHash('user-demo-001')}`,
      startsAt: isoNow(),
      endsAt: null,
      renewalMode: 'perpetual',
      renewalEndsAt: null,
      offlineLeaseDays: 30,
      maxDevices: 1,
      policyFlags: ['offline', 'device-bound'],
      deviceBindingRequired: true,
      status: 'active',
      createdAt: isoNow(),
      updatedAt: isoNow(),
    });
  }
}

async function readState() {
  await ensureDirs();
  let state;
  if (!fsSync.existsSync(STATE_PATH)) {
    state = seedState();
  } else {
    state = normalizeState(JSON.parse(await fs.readFile(STATE_PATH, 'utf8')));
  }
  await mergeDiscoveredModels(state);
  migrateUserPasswords(state);
  await writeState(state);
  return state;
}

async function writeState(state) {
  await ensureDirs();
  const tempPath = `${STATE_PATH}.${process.pid}.${Date.now()}.${crypto.randomUUID()}.tmp`;
  await fs.writeFile(tempPath, JSON.stringify(state, null, 2));
  await fs.rename(tempPath, STATE_PATH);
}

async function withStateLock(action) {
  STATE_OPERATION_QUEUE_DEPTH += 1;
  const previous = STATE_OPERATION_LOCK;
  let release;
  STATE_OPERATION_LOCK = new Promise((resolve) => {
    release = resolve;
  });
  await previous.catch(() => {});
  try {
    return await action();
  } catch (error) {
    STATE_OPERATION_LAST_ERROR_AT = isoNow();
    throw error;
  } finally {
    STATE_OPERATION_QUEUE_DEPTH = Math.max(0, STATE_OPERATION_QUEUE_DEPTH - 1);
    release();
  }
}

function getModel(state, modelId) {
  return state.models.find((model) => model.modelId === modelId);
}

function getBuildForModel(state, model) {
  return state.modelBuilds.find((build) => build.modelBuildId === model.currentBuildId)
    || state.modelBuilds.find((build) => build.modelId === model.modelId && build.status === 'ready');
}

function getSku(state, skuId) {
  return state.modelSkus.find((sku) => sku.skuId === skuId);
}

function getDeveloperForSession(state, session) {
  return state.developers.find((developer) => developer.organizationId === session.organizationId) || null;
}

function developerOwnsModel(state, session, modelId) {
  const developer = getDeveloperForSession(state, session);
  const model = getModel(state, modelId);
  return Boolean(developer && model && model.developerId === developer.developerId);
}

function stateDoctorIssue(issues, severity, code, message, objectType = null, objectId = null) {
  issues.push({
    severity,
    code,
    message,
    ...(objectType ? { objectType } : {}),
    ...(objectId ? { objectId } : {}),
  });
}

function indexById(items, key) {
  const map = new Map();
  for (const item of items || []) {
    const id = item?.[key];
    if (id) {
      map.set(id, item);
    }
  }
  return map;
}

function checkUniqueIds(issues, items, key, objectType) {
  const seen = new Set();
  for (const item of items || []) {
    const id = item?.[key];
    if (!id) {
      stateDoctorIssue(issues, 'error', 'missing_id', `${objectType} is missing ${key}`, objectType);
      continue;
    }
    if (seen.has(id)) {
      stateDoctorIssue(issues, 'error', 'duplicate_id', `${objectType} has duplicate ${key}: ${id}`, objectType, id);
    }
    seen.add(id);
  }
}

function checkReference(issues, map, id, code, message, objectType, objectId, severity = 'error') {
  if (id && !map.has(id)) {
    stateDoctorIssue(issues, severity, code, `${message}: ${id}`, objectType, objectId);
  }
}

function buildSourceAbsolutePath(build) {
  if (!build?.sourcePath) {
    return null;
  }
  return path.isAbsolute(build.sourcePath) ? build.sourcePath : path.join(REPO_ROOT, build.sourcePath);
}

function buildStateDoctor(state) {
  const issues = [];
  const now = Date.now();
  const organizations = indexById(state.organizations, 'organizationId');
  const users = indexById(state.users, 'userId');
  const developers = indexById(state.developers, 'developerId');
  const models = indexById(state.models, 'modelId');
  const builds = indexById(state.modelBuilds, 'modelBuildId');
  const skus = indexById(state.modelSkus, 'skuId');
  const orders = indexById(state.orders, 'orderId');
  const entitlements = indexById(state.entitlements, 'entitlementId');
  const devices = indexById(state.devices, 'deviceId');

  [
    ['organizations', state.organizations, 'organizationId'],
    ['users', state.users, 'userId'],
    ['developers', state.developers, 'developerId'],
    ['models', state.models, 'modelId'],
    ['modelBuilds', state.modelBuilds, 'modelBuildId'],
    ['modelSkus', state.modelSkus, 'skuId'],
    ['orders', state.orders, 'orderId'],
    ['payments', state.payments, 'paymentId'],
    ['entitlements', state.entitlements, 'entitlementId'],
    ['devices', state.devices, 'deviceId'],
    ['tickets', state.tickets, 'ticketId'],
    ['leases', state.leases, 'leaseId'],
    ['supportTickets', state.supportTickets, 'supportTicketId'],
    ['customRequests', state.customRequests, 'customRequestId'],
    ['invoices', state.invoices, 'invoiceId'],
    ['settlements', state.settlements, 'settlementId'],
    ['withdrawals', state.withdrawals, 'withdrawalId'],
    ['coupons', state.coupons, 'couponId'],
    ['activities', state.activities, 'activityId'],
  ].forEach(([objectType, items, key]) => checkUniqueIds(issues, items, key, objectType));

  const emails = new Set();
  for (const user of state.users) {
    if (user.email) {
      const email = user.email.toLowerCase();
      if (emails.has(email)) {
        stateDoctorIssue(issues, 'error', 'duplicate_email', `duplicate user email: ${email}`, 'user', user.userId);
      }
      emails.add(email);
    }
    if (Object.prototype.hasOwnProperty.call(user, 'password')) {
      stateDoctorIssue(issues, 'error', 'plain_password_present', 'user still has a plain password field', 'user', user.userId);
    }
    if (!user.passwordHash || !user.passwordSalt) {
      stateDoctorIssue(issues, 'error', 'password_hash_missing', 'user is missing password hash or salt', 'user', user.userId);
    }
    checkReference(issues, organizations, user.organizationId, 'organization_missing', 'user organization is missing', 'user', user.userId);
  }

  for (const developer of state.developers) {
    checkReference(issues, organizations, developer.organizationId, 'organization_missing', 'developer organization is missing', 'developer', developer.developerId);
  }

  for (const model of state.models) {
    checkReference(issues, developers, model.developerId, 'developer_missing', 'model developer is missing', 'model', model.modelId);
    checkReference(issues, builds, model.currentBuildId, 'build_missing', 'model current build is missing', 'model', model.modelId);
  }

  for (const build of state.modelBuilds) {
    checkReference(issues, models, build.modelId, 'model_missing', 'model build parent model is missing', 'modelBuild', build.modelBuildId);
    const sourceAbsolute = buildSourceAbsolutePath(build);
    if (!sourceAbsolute) {
      stateDoctorIssue(issues, 'error', 'source_path_missing', 'model build is missing sourcePath', 'modelBuild', build.modelBuildId);
    } else if (!fsSync.existsSync(sourceAbsolute)) {
      stateDoctorIssue(issues, 'error', 'source_file_missing', `model build source file is missing: ${sourceAbsolute}`, 'modelBuild', build.modelBuildId);
    }
  }

  for (const sku of state.modelSkus) {
    checkReference(issues, models, sku.modelId, 'model_missing', 'SKU model is missing', 'sku', sku.skuId);
    checkReference(issues, builds, sku.buildId, 'build_missing', 'SKU build is missing', 'sku', sku.skuId);
  }

  for (const order of state.orders) {
    checkReference(issues, organizations, order.buyerOrganizationId, 'organization_missing', 'order buyer organization is missing', 'order', order.orderId);
    checkReference(issues, users, order.buyerUserId, 'user_missing', 'order buyer user is missing', 'order', order.orderId);
    for (const item of order.items || []) {
      checkReference(issues, skus, item.skuId, 'sku_missing', 'order item SKU is missing', 'order', order.orderId);
      checkReference(issues, models, item.modelId, 'model_missing', 'order item model is missing', 'order', order.orderId);
    }
  }

  for (const payment of state.payments) {
    checkReference(issues, orders, payment.orderId, 'order_missing', 'payment order is missing', 'payment', payment.paymentId);
  }

  for (const entitlement of state.entitlements) {
    checkReference(issues, organizations, entitlement.organizationId, 'organization_missing', 'entitlement organization is missing', 'entitlement', entitlement.entitlementId);
    checkReference(issues, models, entitlement.modelId, 'model_missing', 'entitlement model is missing', 'entitlement', entitlement.entitlementId);
    if (entitlement.modelSkuId) {
      checkReference(issues, skus, entitlement.modelSkuId, 'sku_missing', 'entitlement SKU is missing', 'entitlement', entitlement.entitlementId);
    }
    if (entitlement.assignedToType === 'user') {
      checkReference(issues, users, entitlement.assignedToId, 'assigned_user_missing', 'entitlement assigned user is missing', 'entitlement', entitlement.entitlementId);
    } else if (entitlement.assignedToType === 'organization') {
      checkReference(issues, organizations, entitlement.assignedToId, 'assigned_organization_missing', 'entitlement assigned organization is missing', 'entitlement', entitlement.entitlementId);
    } else if (entitlement.assignedToType === 'device') {
      checkReference(issues, devices, entitlement.assignedToId, 'assigned_device_missing', 'entitlement assigned device is missing', 'entitlement', entitlement.entitlementId, 'warning');
    } else {
      stateDoctorIssue(issues, 'error', 'assigned_type_invalid', `invalid entitlement assignedToType: ${entitlement.assignedToType}`, 'entitlement', entitlement.entitlementId);
    }
  }

  for (const ticket of state.tickets) {
    checkReference(issues, entitlements, ticket.entitlementId, 'entitlement_missing', 'download ticket entitlement is missing', 'ticket', ticket.ticketId);
    checkReference(issues, users, ticket.userId, 'user_missing', 'download ticket user is missing', 'ticket', ticket.ticketId);
    checkReference(issues, organizations, ticket.organizationId, 'organization_missing', 'download ticket organization is missing', 'ticket', ticket.ticketId);
    checkReference(issues, models, ticket.modelId, 'model_missing', 'download ticket model is missing', 'ticket', ticket.ticketId);
    checkReference(issues, builds, ticket.modelBuildId, 'build_missing', 'download ticket build is missing', 'ticket', ticket.ticketId);
    if (ticket.status === 'issued' && new Date(ticket.expiresAt).getTime() <= now) {
      stateDoctorIssue(issues, 'warning', 'issued_ticket_expired', 'download ticket is issued but expired', 'ticket', ticket.ticketId);
    }
  }

  for (const lease of state.leases) {
    checkReference(issues, entitlements, lease.entitlementId, 'entitlement_missing', 'lease entitlement is missing', 'lease', lease.leaseId);
    checkReference(issues, users, lease.userId, 'user_missing', 'lease user is missing', 'lease', lease.leaseId);
    checkReference(issues, organizations, lease.organizationId, 'organization_missing', 'lease organization is missing', 'lease', lease.leaseId);
    checkReference(issues, models, lease.modelId, 'model_missing', 'lease model is missing', 'lease', lease.leaseId);
  }

  for (const supportTicket of state.supportTickets) {
    checkReference(issues, organizations, supportTicket.organizationId, 'organization_missing', 'support ticket organization is missing', 'supportTicket', supportTicket.supportTicketId);
    checkReference(issues, users, supportTicket.createdByUserId, 'user_missing', 'support ticket creator user is missing', 'supportTicket', supportTicket.supportTicketId);
    if (supportTicket.modelId) {
      checkReference(issues, models, supportTicket.modelId, 'model_missing', 'support ticket model is missing', 'supportTicket', supportTicket.supportTicketId, 'warning');
    }
  }

  for (const request of state.customRequests) {
    checkReference(issues, organizations, request.organizationId, 'organization_missing', 'custom request organization is missing', 'customRequest', request.customRequestId);
    checkReference(issues, users, request.buyerUserId, 'user_missing', 'custom request buyer user is missing', 'customRequest', request.customRequestId);
    for (const proposal of request.proposals || []) {
      checkReference(issues, developers, proposal.developerId, 'developer_missing', 'custom request proposal developer is missing', 'customRequest', request.customRequestId);
    }
  }

  for (const invoice of state.invoices) {
    checkReference(issues, orders, invoice.orderId, 'order_missing', 'invoice order is missing', 'invoice', invoice.invoiceId);
    checkReference(issues, organizations, invoice.organizationId, 'organization_missing', 'invoice organization is missing', 'invoice', invoice.invoiceId);
    checkReference(issues, users, invoice.requestedByUserId, 'user_missing', 'invoice requester user is missing', 'invoice', invoice.invoiceId);
  }

  for (const settlement of state.settlements) {
    checkReference(issues, orders, settlement.orderId, 'order_missing', 'settlement order is missing', 'settlement', settlement.settlementId);
    checkReference(issues, developers, settlement.developerId, 'developer_missing', 'settlement developer is missing', 'settlement', settlement.settlementId);
    checkReference(issues, models, settlement.modelId, 'model_missing', 'settlement model is missing', 'settlement', settlement.settlementId);
  }

  for (const withdrawal of state.withdrawals) {
    checkReference(issues, developers, withdrawal.developerId, 'developer_missing', 'withdrawal developer is missing', 'withdrawal', withdrawal.withdrawalId);
  }

  const errors = issues.filter((issue) => issue.severity === 'error');
  const warnings = issues.filter((issue) => issue.severity === 'warning');
  return {
    ok: errors.length === 0,
    status: errors.length > 0 ? 'error' : warnings.length > 0 ? 'warning' : 'ok',
    now: isoNow(),
    summary: {
      errors: errors.length,
      warnings: warnings.length,
      issues: issues.length,
    },
    issues,
  };
}

function canAccessSupportTicket(state, session, ticket) {
  if (!ticket || !canCreateSupportTicketRole(session.role)) {
    return false;
  }
  if (isPlatformAdminRole(session.role)) {
    return true;
  }
  if (ticket.organizationId === session.organizationId) {
    return true;
  }
  return session.role === 'developer_admin' && ticket.modelId && developerOwnsModel(state, session, ticket.modelId);
}

function publicModel(state, model) {
  const sku = state.modelSkus.find((item) => item.modelId === model.modelId && item.status === 'active');
  const reviews = state.modelReviews.filter((item) => item.modelId === model.modelId && item.status === 'published');
  const rating = reviews.length
    ? Math.round((reviews.reduce((sum, item) => sum + Number(item.rating || 0), 0) / reviews.length) * 10) / 10
    : null;
  return {
    ...model,
    sku: sku || null,
    rating,
    reviewCount: reviews.length,
    soldCount: state.orders.filter((order) => ['paid', 'delivering', 'completed'].includes(order.status) && order.items.some((item) => item.modelId === model.modelId)).length,
  };
}

function countItems(value) {
  return Array.isArray(value) ? value.length : 0;
}

function scopedSummary(data) {
  const orders = Array.isArray(data.orders) ? data.orders : [];
  return {
    organizations: countItems(data.organizations),
    users: countItems(data.users),
    developers: countItems(data.developers),
    models: countItems(data.models),
    skus: countItems(data.modelSkus),
    orders: countItems(data.orders),
    paidOrders: orders.filter((item) => ['paid', 'delivering', 'completed'].includes(item.status)).length,
    entitlements: countItems(data.entitlements),
    devices: countItems(data.devices),
    deviceInvites: countItems(data.deviceInvites),
    tickets: countItems(data.tickets),
    leases: countItems(data.leases),
    supportTickets: countItems(data.supportTickets),
    customRequests: countItems(data.customRequests),
    invoices: countItems(data.invoices),
    settlements: countItems(data.settlements),
    withdrawals: countItems(data.withdrawals),
    coupons: countItems(data.coupons),
    activities: countItems(data.activities),
    assets: countItems(data.recentAssets),
    results: countItems(data.recentResults),
  };
}

function finalizeScopedOverview(scoped) {
  scoped.summary = scopedSummary(scoped);
  return scoped;
}

function filterIngestsByOrganization(scoped, organizationId) {
  scoped.recentAssets = scoped.recentAssets.filter((item) => item.organizationId === organizationId);
  scoped.recentResults = scoped.recentResults.filter((item) => item.organizationId === organizationId);
  scoped.recentLogs = scoped.recentLogs.filter((item) => item.organizationId === organizationId);
  scoped.recentStats = scoped.recentStats.filter((item) => item.organizationId === organizationId);
}

function filterAuditLogsForRole(logs, role) {
  if (isPlatformAdminRole(role)) {
    return logs;
  }
  if (role === 'reviewer') {
    return logs.filter((log) => ['developer', 'model'].includes(log.objectType) || String(log.action).includes('review'));
  }
  if (role === 'finance') {
    return logs.filter((log) => ['order', 'payment', 'invoice', 'withdrawal', 'settlement'].includes(log.objectType));
  }
  return [];
}

function entitlementAppliesToSession(entitlement, session) {
  if (!entitlement || entitlement.organizationId !== session.organizationId || entitlement.status !== 'active') {
    return false;
  }
  if (entitlement.assignedToType === 'organization') {
    return entitlement.assignedToId === session.organizationId;
  }
  if (entitlement.assignedToType === 'user') {
    return entitlement.assignedToId === session.userId;
  }
  if (entitlement.assignedToType === 'device') {
    return entitlement.assignedToId === session.deviceId;
  }
  return false;
}

function isEntitlementRenewable(entitlement, now = Date.now()) {
  if (!entitlement || entitlement.status !== 'active') {
    return false;
  }
  const endsAt = entitlement.endsAt || entitlement.renewalEndsAt;
  if (!endsAt) {
    return true;
  }
  return new Date(endsAt).getTime() > now;
}

function findEntitlementForModel(state, session, modelId, options = {}) {
  const candidates = state.entitlements
    .filter((item) => item.modelId === modelId && entitlementAppliesToSession(item, session))
    .filter((item) => options.includeExpired || isEntitlementRenewable(item))
    .sort((left, right) => {
      const priority = { user: 3, device: 2, organization: 1 };
      return (priority[right.assignedToType] || 0) - (priority[left.assignedToType] || 0);
    });
  return candidates[0] || null;
}

function resolveLeaseExpiry(entitlement) {
  const hardEnd = normalizeTimestamp(entitlement.endsAt || entitlement.renewalEndsAt);
  const cycle = plusDays(entitlement.offlineLeaseDays || 30);
  if (!hardEnd) {
    return cycle;
  }
  return new Date(hardEnd).getTime() < new Date(cycle).getTime() ? hardEnd : cycle;
}

function findLease(state, entitlement, session, deviceId) {
  return state.leases.find((lease) =>
    lease.entitlementId === entitlement.entitlementId
    && lease.userId === session.userId
    && lease.deviceId === deviceId
  ) || null;
}

function upsertDevice(state, session, deviceId, deviceName, platform) {
  let device = state.devices.find((item) => item.deviceBindingId === deviceId && item.organizationId === session.organizationId);
  if (!device) {
    device = {
      deviceId: `device-${shortHash(`${session.organizationId}:${deviceId}`)}`,
      organizationId: session.organizationId,
      deviceBindingId: deviceId,
      name: deviceName || deviceId,
      platform: platform || 'unknown',
      status: 'active',
      lastSeenAt: isoNow(),
      createdAt: isoNow(),
    };
    state.devices.push(device);
  } else {
    device.name = deviceName || device.name;
    device.platform = platform || device.platform;
    device.lastSeenAt = isoNow();
  }
  return device;
}

function findDeviceByBinding(state, organizationId, deviceBindingId) {
  return state.devices.find((item) => item.organizationId === organizationId && item.deviceBindingId === deviceBindingId) || null;
}

function ensureDeviceCanUseEntitlement(state, entitlement, deviceId) {
  if (!entitlement) {
    fail(403, 'entitlement_not_found', 'model is not assigned to current user');
  }
  if (entitlement.assignedToType === 'device' && entitlement.assignedToId !== deviceId) {
    fail(403, 'device_mismatch', 'license is assigned to another device');
  }
  if (entitlement.deviceBindingRequired === false) {
    return;
  }
  const activeDeviceIds = new Set(
    state.leases
      .filter((lease) => lease.entitlementId === entitlement.entitlementId && lease.status === 'active')
      .map((lease) => lease.deviceId)
  );
  if (activeDeviceIds.has(deviceId)) {
    return;
  }
  const maxDevices = Number(entitlement.maxDevices || 1);
  if (activeDeviceIds.size >= maxDevices) {
    fail(403, 'device_limit_reached', 'license device limit reached');
  }
}

function upsertLease(state, entitlement, session, deviceId) {
  const leaseExpiresAt = resolveLeaseExpiry(entitlement);
  let lease = findLease(state, entitlement, session, deviceId);
  if (!lease) {
    lease = {
      leaseId: `lease-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      entitlementId: entitlement.entitlementId,
      organizationId: entitlement.organizationId,
      userId: session.userId,
      modelId: entitlement.modelId,
      deviceId,
      licenseId: entitlement.licenseId,
      leaseExpiresAt,
      policyFlags: entitlement.policyFlags || [],
      status: 'active',
      renewedAt: isoNow(),
      createdAt: isoNow(),
    };
    state.leases.push(lease);
  } else {
    lease.leaseExpiresAt = leaseExpiresAt;
    lease.policyFlags = entitlement.policyFlags || [];
    lease.status = 'active';
    lease.renewedAt = isoNow();
  }
  return lease;
}

function buildModelLicense(entitlement, lease, deviceId) {
  return {
    licenseId: entitlement.licenseId,
    leaseExpiresAt: lease?.leaseExpiresAt || resolveLeaseExpiry(entitlement),
    policyFlags: lease?.policyFlags || entitlement.policyFlags || [],
    deviceBindingRequired: entitlement.deviceBindingRequired !== false,
    deviceBindingId: deviceId || null,
    renewalMode: entitlement.renewalMode || 'perpetual',
    renewalEndsAt: entitlement.renewalEndsAt || entitlement.endsAt || null,
  };
}

async function writeStreamChunk(stream, chunk) {
  if (!chunk || chunk.length === 0) {
    return;
  }
  if (!stream.write(chunk)) {
    await once(stream, 'drain');
  }
}

async function finishWriteStream(stream) {
  stream.end();
  await once(stream, 'finish');
}

async function collectArchiveFileEntries(rootPath, basePath = rootPath) {
  const stat = await fs.stat(rootPath);
  if (stat.isFile()) {
    return [{
      relativePath: path.basename(rootPath),
      absolutePath: rootPath,
      byteCount: stat.size,
    }];
  }

  const entries = [];
  const children = await fs.readdir(rootPath, { withFileTypes: true });
  for (const child of [...children].sort((a, b) => a.name.localeCompare(b.name))) {
    const absolute = path.join(rootPath, child.name);
    if (child.isDirectory()) {
      entries.push(...await collectArchiveFileEntries(absolute, basePath));
    } else if (child.isFile()) {
      const childStat = await fs.stat(absolute);
      entries.push({
        relativePath: path.relative(basePath, absolute).split(path.sep).join('/'),
        absolutePath: absolute,
        byteCount: childStat.size,
      });
    }
  }
  return entries;
}

async function writeFileToArtifact(filePath, writer, hash) {
  let byteCount = 0;
  for await (const chunk of fsSync.createReadStream(filePath)) {
    hash.update(chunk);
    byteCount += chunk.length;
    await writeStreamChunk(writer, chunk);
  }
  return byteCount;
}

async function writeHashedPart(writer, hash, buffer) {
  hash.update(buffer);
  await writeStreamChunk(writer, buffer);
  return buffer.length;
}

async function writeBundleArchiveArtifact(rootPath, writer, hash) {
  const entries = await collectArchiveFileEntries(rootPath);
  const header = Buffer.alloc(BUNDLE_ARCHIVE_MAGIC.length + 4 + 4);
  BUNDLE_ARCHIVE_MAGIC.copy(header, 0);
  header.writeUInt32LE(1, BUNDLE_ARCHIVE_MAGIC.length);
  header.writeUInt32LE(entries.length, BUNDLE_ARCHIVE_MAGIC.length + 4);
  let byteCount = await writeHashedPart(writer, hash, header);
  for (const entry of entries) {
    const pathBuffer = Buffer.from(entry.relativePath, 'utf8');
    const entryHeader = Buffer.alloc(4 + 8);
    entryHeader.writeUInt32LE(pathBuffer.length, 0);
    entryHeader.writeBigUInt64LE(BigInt(entry.byteCount), 4);
    byteCount += await writeHashedPart(writer, hash, entryHeader);
    byteCount += await writeHashedPart(writer, hash, pathBuffer);
    byteCount += await writeFileToArtifact(entry.absolutePath, writer, hash);
  }
  return byteCount;
}

function hashHex(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function readCachedArtifact(cachePath, cacheKey) {
  try {
    const [metadataText] = await Promise.all([
      fs.readFile(`${cachePath}.json`, 'utf8'),
      fs.access(cachePath),
    ]);
    const metadata = JSON.parse(metadataText);
    if (metadata.cacheKey === cacheKey && metadata.cachePath === cachePath && metadata.byteCount >= 0 && metadata.sha256) {
      return metadata;
    }
  } catch {
    return null;
  }
  return null;
}

async function getModelArtifact(build) {
  await fs.mkdir(ARTIFACT_CACHE_ROOT, { recursive: true });
  const sourceAbsolute = path.isAbsolute(build.sourcePath)
    ? build.sourcePath
    : path.join(REPO_ROOT, build.sourcePath);
  const stats = await fs.stat(sourceAbsolute);
  const cacheKey = [
    build.modelBuildId,
    sourceAbsolute,
    build.transportFormat,
    stats.mtimeMs,
    stats.size,
  ].join(':');
  const cached = ARCHIVE_CACHE.get(cacheKey);
  if (cached && fsSync.existsSync(cached.cachePath)) {
    return cached;
  }

  const cacheName = `${safeFileName(build.modelBuildId, 'build')}-${shortHash(cacheKey)}.artifact`;
  const cachePath = path.join(ARTIFACT_CACHE_ROOT, cacheName);
  const metadata = await readCachedArtifact(cachePath, cacheKey);
  if (metadata) {
    ARCHIVE_CACHE.set(cacheKey, metadata);
    return metadata;
  }

  const tempPath = `${cachePath}.${process.pid}.${Date.now()}.tmp`;
  const writer = fsSync.createWriteStream(tempPath, { flags: 'wx' });
  const hash = crypto.createHash('sha256');
  let byteCount = 0;
  try {
    if (stats.isDirectory() || build.transportFormat === 'bundle-archive') {
      byteCount = await writeBundleArchiveArtifact(sourceAbsolute, writer, hash);
    } else {
      byteCount = await writeFileToArtifact(sourceAbsolute, writer, hash);
    }
    await finishWriteStream(writer);
    const artifact = {
      cacheKey,
      cachePath,
      sha256: hash.digest('hex'),
      byteCount,
      sourcePath: sourceAbsolute,
      createdAt: isoNow(),
    };
    await fs.rename(tempPath, cachePath);
    await fs.writeFile(`${cachePath}.json`, JSON.stringify(artifact, null, 2));
    ARCHIVE_CACHE.set(cacheKey, artifact);
    return artifact;
  } catch (error) {
    writer.destroy();
    await fs.rm(tempPath, { force: true }).catch(() => {});
    throw error;
  }
}

function deriveTicketKey(ticket) {
  return crypto.createHash('sha256')
    .update([
      ticket.ticketSecret || '',
      ticket.modelId || '',
      ticket.deviceId || '',
      ticket.modelBuildId || '',
    ].join(':'))
    .digest();
}

async function buildEncryptedEnvelopeFile(artifact, ticket) {
  await fs.mkdir(DOWNLOAD_WORK_ROOT, { recursive: true });
  const envelopePath = path.join(DOWNLOAD_WORK_ROOT, `${safeFileName(ticket.ticketId, 'ticket')}.vinoenc`);
  const tempPath = `${envelopePath}.${process.pid}.${Date.now()}.tmp`;
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ENCRYPTION_ALGORITHM, deriveTicketKey(ticket), iv);
  const tagLength = 16;
  const algorithmBuffer = Buffer.from(ENCRYPTION_ALGORITHM, 'utf8');
  const header = Buffer.alloc(ENCRYPTION_ENVELOPE_MAGIC.length + 4 + 4 + 4 + 4 + 8);
  let offset = 0;
  ENCRYPTION_ENVELOPE_MAGIC.copy(header, offset);
  offset += ENCRYPTION_ENVELOPE_MAGIC.length;
  header.writeUInt32LE(1, offset);
  offset += 4;
  header.writeUInt32LE(algorithmBuffer.length, offset);
  offset += 4;
  header.writeUInt32LE(iv.length, offset);
  offset += 4;
  header.writeUInt32LE(tagLength, offset);
  offset += 4;
  header.writeBigUInt64LE(BigInt(artifact.byteCount), offset);

  const tagOffset = header.length + algorithmBuffer.length + iv.length;
  const prelude = Buffer.concat([header, algorithmBuffer, iv, Buffer.alloc(tagLength)]);
  await fs.writeFile(tempPath, prelude, { flag: 'wx' });
  const writer = fsSync.createWriteStream(tempPath, { flags: 'a' });
  let ciphertextLength = 0;

  try {
    for await (const chunk of fsSync.createReadStream(artifact.cachePath)) {
      const encrypted = cipher.update(chunk);
      ciphertextLength += encrypted.length;
      await writeStreamChunk(writer, encrypted);
    }
    const final = cipher.final();
    ciphertextLength += final.length;
    await writeStreamChunk(writer, final);
    await finishWriteStream(writer);

    const file = await fs.open(tempPath, 'r+');
    try {
      const tag = cipher.getAuthTag();
      await file.write(tag, 0, tag.length, tagOffset);
    } finally {
      await file.close();
    }
    await fs.rename(tempPath, envelopePath);
    return {
      filePath: envelopePath,
      byteCount: prelude.length + ciphertextLength,
    };
  } catch (error) {
    writer.destroy();
    await fs.rm(tempPath, { force: true }).catch(() => {});
    throw error;
  }
}

async function terminalModelDescriptor(state, session, model, entitlement) {
  const build = getBuildForModel(state, model);
  if (!build) {
    return null;
  }
  const artifact = await getModelArtifact(build);
  build.sha256 = artifact.sha256;
  build.byteCount = artifact.byteCount;
  const lease = findLease(state, entitlement, session, session.deviceId || 'unknown-device');
  return {
    id: model.modelId,
    name: model.name,
    version: build.version,
    summary: model.summary || '',
    organizationId: entitlement.organizationId,
    modelBuildId: build.modelBuildId,
    fileName: build.fileName,
    sourceFormat: build.sourceFormat,
    transportFormat: build.transportFormat,
    sha256: artifact.sha256,
    byteCount: artifact.byteCount,
    isEncrypted: build.isEncrypted !== false,
    supportedPlatforms: build.supportedPlatforms || ['ios'],
    tags: model.tags || [],
    license: buildModelLicense(entitlement, lease, session.deviceId || null),
  };
}

async function listEntitledModels(state, session) {
  const descriptors = [];
  for (const model of state.models.filter((item) => item.status === 'listed' || item.status === 'approved')) {
    const entitlement = findEntitlementForModel(state, session, model.modelId);
    if (!entitlement) {
      continue;
    }
    const descriptor = await terminalModelDescriptor(state, session, model, entitlement);
    if (descriptor) {
      descriptors.push(descriptor);
    }
  }
  return descriptors;
}

function createSession(state, user, body) {
  const accessToken = crypto.randomBytes(32).toString('hex');
  const organization = state.organizations.find((item) => item.organizationId === user.organizationId);
  const session = {
    sessionId: `sess-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
    accessToken,
    tokenType: 'Bearer',
    expiresAt: plusDays(SESSION_TTL_DAYS),
    userId: user.userId,
    email: user.email,
    displayName: user.displayName,
    organizationId: user.organizationId,
    organizationName: user.organizationName || organization?.name || '',
    role: user.role,
    deviceId: body.deviceId || 'web-console',
    deviceName: body.deviceName || 'web-console',
    platform: body.platform || 'web',
    createdAt: isoNow(),
    lastSeenAt: isoNow(),
    revokedAt: null,
  };
  pruneSessions(state);
  state.sessions = state.sessions.filter((item) => item.userId !== user.userId || item.deviceId !== session.deviceId);
  state.sessions.push(session);
  return session;
}

function authSessionPayload(session, user) {
  return {
    accessToken: session.accessToken,
    tokenType: session.tokenType,
    expiresAt: session.expiresAt,
    user: {
      ...publicUser(user),
      roleLabel: roleLabel(user.role),
    },
    permissions: permissionsForRole(user.role),
  };
}

function normalizeInviteCode(raw) {
  return String(raw || '').trim().replace(/\s+/g, '').toUpperCase();
}

function createDeviceInviteCode(state) {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = crypto.randomBytes(5).toString('hex').toUpperCase();
    if (!state.deviceInvites.some((invite) => invite.code === code && invite.status === 'active')) {
      return code;
    }
  }
  fail(500, 'invite_code_unavailable', 'failed to allocate invite code');
}

function deviceInviteLinks(req, invite) {
  const baseURL = requestBaseUrl(req);
  const code = encodeURIComponent(invite.code);
  return {
    baseURL,
    claimURL: `${baseURL}/api/cloud/v1/device-invites/${code}/claim`,
    webProvisioningURL: `${baseURL}/provision?code=${code}`,
    deepLink: `vino://provision?baseURL=${encodeURIComponent(baseURL)}&code=${code}`,
  };
}

function publicDeviceInvite(req, invite) {
  return {
    inviteId: invite.inviteId,
    code: invite.code,
    organizationId: invite.organizationId,
    userId: invite.userId,
    status: invite.status,
    expiresAt: invite.expiresAt,
    claimedAt: invite.claimedAt || null,
    deviceId: invite.deviceId || null,
    deviceName: invite.deviceName || '',
    platform: invite.platform || '',
    note: invite.note || '',
    createdAt: invite.createdAt,
    ...deviceInviteLinks(req, invite),
  };
}

async function buildOverview(state) {
  const models = [];
  for (const model of state.models) {
    const build = getBuildForModel(state, model);
    const sku = state.modelSkus.find((item) => item.modelId === model.modelId);
    const entitlements = state.entitlements.filter((item) => item.modelId === model.modelId);
    models.push({
      ...model,
      currentBuild: build || null,
      sku: sku || null,
      assignmentCount: entitlements.length,
      activeAssignmentCount: entitlements.filter((item) => item.status === 'active').length,
    });
  }

  const entitlements = state.entitlements.map((entitlement) => {
    const model = getModel(state, entitlement.modelId);
    const user = state.users.find((item) => item.userId === entitlement.assignedToId);
    return {
      ...entitlement,
      modelName: model?.name || entitlement.modelId,
      assignedToLabel: entitlement.assignedToType === 'user'
        ? `${user?.displayName || entitlement.assignedToId} / ${user?.email || 'unknown'}`
        : entitlement.assignedToId,
      isRenewableNow: isEntitlementRenewable(entitlement),
    };
  });

  return {
    service: 'vino_platform',
    now: isoNow(),
    summary: {
      organizations: state.organizations.length,
      users: state.users.length,
      developers: state.developers.length,
      models: state.models.length,
      skus: state.modelSkus.length,
      orders: state.orders.length,
      paidOrders: state.orders.filter((item) => ['paid', 'delivering', 'completed'].includes(item.status)).length,
      entitlements: state.entitlements.length,
      devices: state.devices.length,
      deviceInvites: state.deviceInvites.length,
      tickets: state.tickets.length,
      leases: state.leases.length,
      supportTickets: state.supportTickets.length,
      customRequests: state.customRequests.length,
      invoices: state.invoices.length,
      settlements: state.settlements.length,
      withdrawals: state.withdrawals.length,
      coupons: state.coupons.length,
      activities: state.activities.length,
      assets: state.ingests.assets.length,
      results: state.ingests.results.length,
    },
    organizations: state.organizations,
    users: state.users.map((user) => ({
      ...publicUser(user),
      assignedModelCount: state.entitlements.filter((item) => item.assignedToType === 'user' && item.assignedToId === user.userId && item.status === 'active').length,
    })),
    developers: state.developers,
    models,
    modelSkus: state.modelSkus,
    orders: state.orders.slice().sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
    payments: state.payments.slice(-20).reverse(),
    entitlements: entitlements.sort((a, b) => String(b.updatedAt || b.createdAt).localeCompare(String(a.updatedAt || a.createdAt))),
    devices: state.devices.slice().sort((a, b) => String(b.lastSeenAt || '').localeCompare(String(a.lastSeenAt || ''))),
    deviceInvites: state.deviceInvites.slice(-30).reverse(),
    tickets: state.tickets.slice(-50).reverse(),
    leases: state.leases.slice(-30).reverse(),
    reviews: state.reviews.slice(-50).reverse(),
    modelReviews: state.modelReviews.slice(-50).reverse(),
    favorites: state.favorites.slice(-50).reverse(),
    supportTickets: state.supportTickets.slice().sort((a, b) => String(b.updatedAt || b.createdAt).localeCompare(String(a.updatedAt || a.createdAt))),
    customRequests: state.customRequests.slice().sort((a, b) => String(b.updatedAt || b.createdAt).localeCompare(String(a.updatedAt || a.createdAt))),
    invoices: state.invoices.slice().sort((a, b) => String(b.updatedAt || b.createdAt).localeCompare(String(a.updatedAt || a.createdAt))),
    settlements: state.settlements.slice().sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
    withdrawals: state.withdrawals.slice().sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))),
    coupons: state.coupons,
    activities: state.activities,
    categories: state.categories,
    platformSettings: state.platformSettings,
    notifications: state.notifications.slice(-50).reverse(),
    recentAssets: state.ingests.assets.slice(-10).reverse(),
    recentResults: state.ingests.results.slice(-10).reverse(),
    recentLogs: state.ingests.logs.slice(-10).reverse(),
    recentStats: state.ingests.stats.slice(-10).reverse(),
    auditLogs: state.auditLogs.slice(-50).reverse(),
  };
}

async function buildRoleOverview(state, session) {
  const overview = await buildOverview(state);
  const role = session.role;
  const ownOrganizationId = session.organizationId;
  const ownDeveloper = getDeveloperForSession(state, session);
  const ownDeveloperId = ownDeveloper?.developerId || null;
  const ownModelIds = new Set(state.models.filter((model) => model.developerId === ownDeveloperId).map((model) => model.modelId));

  const scoped = {
    ...overview,
    viewer: {
      ...publicUser({
        userId: session.userId,
        email: session.email,
        displayName: session.displayName,
        organizationId: session.organizationId,
        organizationName: session.organizationName,
        role: session.role,
        status: 'active',
      }),
      roleLabel: roleLabel(session.role),
    },
    permissions: {
      ...permissionsForRole(role),
    },
  };

  if (['super_admin', 'admin'].includes(role)) {
    return scoped;
  }

  if (role === 'platform_ops') {
    scoped.settlements = [];
    scoped.withdrawals = [];
    scoped.invoices = scoped.invoices.filter((invoice) => invoice.status !== 'issued');
    return finalizeScopedOverview(scoped);
  }

  if (role === 'reviewer') {
    scoped.organizations = scoped.organizations.filter((org) => org.type !== 'buyer');
    scoped.users = scoped.users.filter((user) => ['developer_admin', 'reviewer'].includes(user.role));
    scoped.orders = [];
    scoped.payments = [];
    scoped.entitlements = [];
    scoped.devices = [];
    scoped.deviceInvites = [];
    scoped.tickets = [];
    scoped.leases = [];
    scoped.supportTickets = [];
    scoped.customRequests = [];
    scoped.invoices = [];
    scoped.settlements = [];
    scoped.withdrawals = [];
    scoped.coupons = [];
    scoped.activities = [];
    scoped.recentAssets = [];
    scoped.recentResults = [];
    scoped.recentLogs = [];
    scoped.recentStats = [];
    scoped.auditLogs = filterAuditLogsForRole(scoped.auditLogs, role);
    scoped.notifications = scoped.notifications.filter((item) => item.userId === session.userId);
    return finalizeScopedOverview(scoped);
  }

  if (role === 'finance') {
    scoped.users = scoped.users.filter((user) => ['buyer_admin', 'developer_admin', 'finance'].includes(user.role));
    scoped.models = [];
    scoped.developers = [];
    scoped.entitlements = [];
    scoped.devices = [];
    scoped.deviceInvites = [];
    scoped.tickets = [];
    scoped.leases = [];
    scoped.supportTickets = [];
    scoped.customRequests = [];
    scoped.coupons = [];
    scoped.activities = [];
    scoped.reviews = [];
    scoped.modelReviews = [];
    scoped.favorites = [];
    scoped.recentAssets = [];
    scoped.recentResults = [];
    scoped.recentLogs = [];
    scoped.recentStats = [];
    scoped.auditLogs = filterAuditLogsForRole(scoped.auditLogs, role);
    scoped.notifications = scoped.notifications.filter((item) => item.userId === session.userId);
    return finalizeScopedOverview(scoped);
  }

  if (role === 'developer_admin') {
    scoped.organizations = scoped.organizations.filter((org) => org.organizationId === ownOrganizationId);
    scoped.users = scoped.users.filter((user) => user.organizationId === ownOrganizationId);
    scoped.developers = scoped.developers.filter((developer) => developer.organizationId === ownOrganizationId);
    scoped.models = scoped.models.filter((model) => ownModelIds.has(model.modelId));
    scoped.modelSkus = scoped.modelSkus.filter((sku) => ownModelIds.has(sku.modelId));
    scoped.orders = scoped.orders.filter((order) => order.items.some((item) => ownModelIds.has(item.modelId)));
    scoped.payments = [];
    scoped.entitlements = [];
    scoped.devices = [];
    scoped.deviceInvites = [];
    scoped.tickets = [];
    scoped.leases = [];
    scoped.supportTickets = scoped.supportTickets.filter((ticket) => canAccessSupportTicket(state, session, ticket));
    scoped.customRequests = scoped.customRequests.filter((request) => ['open', 'proposal_submitted'].includes(request.status));
    scoped.invoices = [];
    scoped.settlements = scoped.settlements.filter((settlement) => settlement.developerId === ownDeveloperId);
    scoped.withdrawals = scoped.withdrawals.filter((withdrawal) => withdrawal.developerId === ownDeveloperId);
    scoped.reviews = scoped.reviews.filter((review) => ownModelIds.has(review.subjectId));
    scoped.modelReviews = scoped.modelReviews.filter((review) => ownModelIds.has(review.modelId));
    scoped.favorites = [];
    scoped.coupons = [];
    scoped.activities = [];
    scoped.recentAssets = [];
    scoped.recentResults = [];
    scoped.recentLogs = [];
    scoped.recentStats = [];
    scoped.auditLogs = filterAuditLogsForRole(scoped.auditLogs, role);
    scoped.notifications = scoped.notifications.filter((item) => item.userId === session.userId);
    return finalizeScopedOverview(scoped);
  }

  if (role === 'buyer_admin' || role === 'buyer_operator') {
    scoped.organizations = scoped.organizations.filter((org) => org.organizationId === ownOrganizationId);
    scoped.users = scoped.users.filter((user) => user.organizationId === ownOrganizationId);
    scoped.developers = [];
    scoped.models = scoped.models.filter((model) => model.status === 'listed');
    scoped.modelSkus = scoped.modelSkus.filter((sku) => sku.status === 'active');
    scoped.orders = scoped.orders.filter((order) => order.buyerOrganizationId === ownOrganizationId);
    scoped.payments = scoped.payments.filter((payment) => scoped.orders.some((order) => order.orderId === payment.orderId));
    scoped.entitlements = scoped.entitlements.filter((entitlement) => entitlement.organizationId === ownOrganizationId);
    scoped.devices = scoped.devices.filter((device) => device.organizationId === ownOrganizationId);
    scoped.deviceInvites = scoped.deviceInvites.filter((invite) => invite.organizationId === ownOrganizationId);
    scoped.tickets = scoped.tickets.filter((ticket) => ticket.organizationId === ownOrganizationId);
    scoped.leases = scoped.leases.filter((lease) => lease.organizationId === ownOrganizationId);
    scoped.supportTickets = scoped.supportTickets.filter((ticket) => ticket.organizationId === ownOrganizationId);
    scoped.customRequests = scoped.customRequests.filter((request) => request.organizationId === ownOrganizationId);
    scoped.invoices = scoped.invoices.filter((invoice) => invoice.organizationId === ownOrganizationId);
    scoped.settlements = [];
    scoped.withdrawals = [];
    scoped.reviews = [];
    scoped.modelReviews = scoped.modelReviews.filter((review) => review.organizationId === ownOrganizationId);
    scoped.favorites = scoped.favorites.filter((favorite) => favorite.organizationId === ownOrganizationId);
    scoped.coupons = scoped.coupons.filter((coupon) => coupon.status === 'active');
    scoped.activities = scoped.activities.filter((activity) => activity.status === 'active');
    filterIngestsByOrganization(scoped, ownOrganizationId);
    scoped.auditLogs = [];
    scoped.notifications = scoped.notifications.filter((item) => item.userId === session.userId);
    if (role === 'buyer_operator') {
      scoped.orders = [];
      scoped.payments = [];
      scoped.invoices = [];
      scoped.entitlements = scoped.entitlements.filter((entitlement) => entitlement.assignedToType === 'user' && entitlement.assignedToId === session.userId);
    }
    return finalizeScopedOverview(scoped);
  }

  scoped.auditLogs = [];
  scoped.notifications = scoped.notifications.filter((item) => item.userId === session.userId);
  return finalizeScopedOverview(scoped);
}

async function serveStatic(req, res) {
  const pathname = normalizePathname(req.url);
  const filePath = pathname === '/'
    ? path.join(PUBLIC_ROOT, 'index.html')
    : path.join(PUBLIC_ROOT, pathname.replace(/^\/+/, ''));
  if (!isPathInside(PUBLIC_ROOT, filePath) || !fsSync.existsSync(filePath)) {
    return false;
  }
  const ext = path.extname(filePath);
  const contentType = ext === '.css'
    ? 'text/css; charset=utf-8'
    : ext === '.js'
      ? 'application/javascript; charset=utf-8'
      : 'text/html; charset=utf-8';
  sendBuffer(res, 200, await fs.readFile(filePath), contentType);
  return true;
}

async function checkReady() {
  await ensureDirs();
  const probePath = path.join(DATA_ROOT, `.ready-${process.pid}-${Date.now()}`);
  await fs.writeFile(probePath, 'ok');
  await fs.rm(probePath, { force: true });
  return {
    service: 'vino_platform',
    status: 'ok',
    now: isoNow(),
    dataRoot: DATA_ROOT,
    statePath: STATE_PATH,
    modelUploadRoot: MODEL_UPLOAD_ROOT,
    artifactCacheRoot: ARTIFACT_CACHE_ROOT,
    downloadWorkRoot: DOWNLOAD_WORK_ROOT,
    modelsRoot: MODELS_ROOT,
    modelsRootExists: fsSync.existsSync(MODELS_ROOT),
  };
}

async function fileSummary(filePath) {
  try {
    const stat = await fs.stat(filePath);
    return {
      path: filePath,
      exists: true,
      isDirectory: stat.isDirectory(),
      sizeBytes: stat.size,
      modifiedAt: stat.mtime.toISOString(),
    };
  } catch {
    return {
      path: filePath,
      exists: false,
    };
  }
}

async function directorySummary(directoryPath, { maxEntries = 5000, staleMs = 60 * 60 * 1000 } = {}) {
  const summary = {
    path: directoryPath,
    exists: false,
    fileCount: 0,
    directoryCount: 0,
    totalBytes: 0,
    scannedEntries: 0,
    truncated: false,
    staleFileCount: 0,
    newestModifiedAt: null,
    oldestModifiedAt: null,
  };
  if (!fsSync.existsSync(directoryPath)) {
    return summary;
  }
  summary.exists = true;
  const now = Date.now();
  const stack = [directoryPath];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (summary.scannedEntries >= maxEntries) {
        summary.truncated = true;
        return summary;
      }
      summary.scannedEntries += 1;
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) {
        summary.directoryCount += 1;
        stack.push(absolute);
        continue;
      }
      if (!entry.isFile()) {
        continue;
      }
      const stat = await fs.stat(absolute);
      const modifiedAt = stat.mtime.toISOString();
      summary.fileCount += 1;
      summary.totalBytes += stat.size;
      if (now - stat.mtimeMs > staleMs) {
        summary.staleFileCount += 1;
      }
      if (!summary.newestModifiedAt || modifiedAt > summary.newestModifiedAt) {
        summary.newestModifiedAt = modifiedAt;
      }
      if (!summary.oldestModifiedAt || modifiedAt < summary.oldestModifiedAt) {
        summary.oldestModifiedAt = modifiedAt;
      }
    }
  }
  return summary;
}

async function latestBackupSummary() {
  const summary = await directorySummary(BACKUP_ROOT, { maxEntries: 1000, staleMs: 7 * 24 * 60 * 60 * 1000 });
  if (!summary.exists) {
    return {
      ...summary,
      latest: null,
    };
  }
  const entries = await fs.readdir(BACKUP_ROOT, { withFileTypes: true }).catch(() => []);
  const backups = [];
  for (const entry of entries) {
    if (!entry.isFile() || !/^state-.+\.json\.gz$/.test(entry.name)) {
      continue;
    }
    const filePath = path.join(BACKUP_ROOT, entry.name);
    const stat = await fs.stat(filePath);
    backups.push({
      path: filePath,
      sizeBytes: stat.size,
      modifiedAt: stat.mtime.toISOString(),
    });
  }
  backups.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
  return {
    ...summary,
    backupCount: backups.length,
    latest: backups[0] || null,
  };
}

async function statfsSummary(directoryPath) {
  if (typeof fs.statfs !== 'function' || !fsSync.existsSync(directoryPath)) {
    return null;
  }
  try {
    const stat = await fs.statfs(directoryPath);
    return {
      path: directoryPath,
      blockSize: stat.bsize,
      totalBytes: Number(stat.blocks) * Number(stat.bsize),
      freeBytes: Number(stat.bfree) * Number(stat.bsize),
      availableBytes: Number(stat.bavail) * Number(stat.bsize),
    };
  } catch {
    return null;
  }
}

async function buildOpsStatus(state) {
  const now = Date.now();
  const stateFile = await fileSummary(STATE_PATH);
  const backups = await latestBackupSummary();
  const artifactCache = await directorySummary(ARTIFACT_CACHE_ROOT, { staleMs: 30 * 24 * 60 * 60 * 1000 });
  const downloadWork = await directorySummary(DOWNLOAD_WORK_ROOT, { staleMs: 60 * 60 * 1000 });
  const risks = [];
  const deployEnv = String(process.env.VINO_DEPLOY_ENV || process.env.NODE_ENV || 'development');
  const isProduction = deployEnv.toLowerCase() === 'production';

  if (!EXTERNAL_BASE_URL) {
    risks.push({ severity: isProduction ? 'high' : 'medium', code: 'external_base_url_missing', message: 'VINO_EXTERNAL_BASE_URL is not set.' });
  }
  if (isProduction && EXTERNAL_BASE_URL && !EXTERNAL_BASE_URL.startsWith('https://')) {
    risks.push({ severity: 'high', code: 'external_base_url_not_https', message: 'production external URL should use HTTPS.' });
  }
  if (SEED_DEMO_DATA) {
    risks.push({ severity: isProduction ? 'high' : 'low', code: 'demo_seed_enabled', message: 'demo seed data is enabled.' });
  }
  if (!backups.latest) {
    risks.push({ severity: 'medium', code: 'backup_missing', message: 'no state backup found.' });
  }
  if (downloadWork.fileCount > 0) {
    risks.push({ severity: downloadWork.staleFileCount > 0 ? 'medium' : 'low', code: 'download_work_not_empty', message: 'download work directory contains temporary files.' });
  }
  if (stateFile.exists && stateFile.sizeBytes > 50 * 1024 * 1024) {
    risks.push({ severity: 'medium', code: 'state_file_large', message: 'state.json is growing large for file-backed storage.' });
  }

  return {
    service: 'vino_platform',
    status: risks.some((risk) => risk.severity === 'high') ? 'risk' : 'ok',
    now: isoNow(),
    runtime: {
      pid: process.pid,
      nodeVersion: process.version,
      uptimeSeconds: Math.round(process.uptime()),
      memory: process.memoryUsage(),
      stateQueueDepth: STATE_OPERATION_QUEUE_DEPTH,
      stateLastErrorAt: STATE_OPERATION_LAST_ERROR_AT,
    },
    config: {
      deployEnv,
      host: HOST,
      port: PORT,
      externalBaseUrl: EXTERNAL_BASE_URL || null,
      seedDemoData: SEED_DEMO_DATA,
      skipModelDiscovery: SKIP_MODEL_DISCOVERY,
      requestBodyLimitBytes: REQUEST_BODY_LIMIT_BYTES,
      sessionTtlDays: SESSION_TTL_DAYS,
      rateLimit: {
        enabled: RATE_LIMIT_ENABLED,
        windowMs: RATE_LIMIT_WINDOW_MS,
        max: RATE_LIMIT_MAX,
        authMax: RATE_LIMIT_AUTH_MAX,
        buckets: RATE_LIMIT_BUCKETS.size,
      },
    },
    paths: {
      dataRoot: DATA_ROOT,
      statePath: STATE_PATH,
      modelsRoot: MODELS_ROOT,
      modelUploadRoot: MODEL_UPLOAD_ROOT,
      artifactCacheRoot: ARTIFACT_CACHE_ROOT,
      downloadWorkRoot: DOWNLOAD_WORK_ROOT,
      backupRoot: BACKUP_ROOT,
    },
    storage: {
      stateFile,
      dataRoot: await directorySummary(DATA_ROOT, { maxEntries: 10000, staleMs: 30 * 24 * 60 * 60 * 1000 }),
      artifactCache,
      downloadWork,
      backups,
      filesystem: await statfsSummary(DATA_ROOT),
    },
    collections: {
      organizations: state.organizations.length,
      users: state.users.length,
      sessions: state.sessions.length,
      activeSessions: state.sessions.filter((item) => !item.revokedAt && new Date(item.expiresAt).getTime() > now).length,
      models: state.models.length,
      modelBuilds: state.modelBuilds.length,
      modelSkus: state.modelSkus.length,
      orders: state.orders.length,
      entitlements: state.entitlements.length,
      tickets: state.tickets.length,
      issuedTickets: state.tickets.filter((item) => item.status === 'issued').length,
      usedTickets: state.tickets.filter((item) => item.status === 'used').length,
      expiredIssuedTickets: state.tickets.filter((item) => item.status === 'issued' && new Date(item.expiresAt).getTime() <= now).length,
      leases: state.leases.length,
      auditLogs: state.auditLogs.length,
      ingestAssets: state.ingests.assets.length,
      ingestResults: state.ingests.results.length,
    },
    risks,
  };
}

function maintenanceOptions(input = {}) {
  return {
    dryRun: input.dryRun === true,
    ticketRetentionDays: parseNonNegativeInt(input.ticketRetentionDays, MAINTENANCE_TICKET_RETENTION_DAYS),
    downloadWorkRetentionMinutes: parseNonNegativeInt(input.downloadWorkRetentionMinutes, MAINTENANCE_DOWNLOAD_WORK_RETENTION_MINUTES),
    artifactCacheRetentionDays: parseNonNegativeInt(input.artifactCacheRetentionDays, MAINTENANCE_ARTIFACT_CACHE_RETENTION_DAYS),
    cleanArtifactCache: input.cleanArtifactCache === true,
  };
}

function shouldRemoveTicket(ticket, now, retentionMs) {
  if (!ticket) {
    return true;
  }
  const expiresAt = new Date(ticket.expiresAt || 0).getTime();
  const usedAt = new Date(ticket.usedAt || 0).getTime();
  const revokedAt = new Date(ticket.revokedAt || 0).getTime();
  const createdAt = new Date(ticket.createdAt || 0).getTime();
  const inactive = ticket.status === 'used' || ticket.status === 'revoked' || expiresAt <= now;
  if (!inactive) {
    return false;
  }
  const terminalAt = ticket.status === 'used'
    ? (usedAt || createdAt)
    : ticket.status === 'revoked'
      ? (revokedAt || createdAt)
      : (expiresAt || createdAt);
  return terminalAt > 0 && terminalAt <= now - retentionMs;
}

function compactOperationalState(state, options) {
  const now = Date.now();
  const ticketRetentionMs = options.ticketRetentionDays * 24 * 60 * 60 * 1000;
  const sessionsBefore = state.sessions.length;
  const ticketsBefore = state.tickets.length;
  const activeSessions = state.sessions.filter((session) =>
    session && !session.revokedAt && new Date(session.expiresAt).getTime() > now
  );
  const keptTickets = state.tickets.filter((ticket) => !shouldRemoveTicket(ticket, now, ticketRetentionMs));

  if (!options.dryRun) {
    state.sessions = activeSessions;
    state.tickets = keptTickets;
  }

  return {
    sessionsBefore,
    sessionsAfter: activeSessions.length,
    sessionsRemoved: sessionsBefore - activeSessions.length,
    ticketsBefore,
    ticketsAfter: keptTickets.length,
    ticketsRemoved: ticketsBefore - keptTickets.length,
  };
}

async function cleanupDirectoryFiles(directoryPath, { olderThanMs, dryRun, maxEntries = 10000 } = {}) {
  const summary = {
    path: directoryPath,
    exists: fsSync.existsSync(directoryPath),
    scannedFiles: 0,
    removedFiles: 0,
    removedBytes: 0,
    truncated: false,
    errors: [],
  };
  if (!summary.exists) {
    return summary;
  }

  const cutoff = Date.now() - olderThanMs;
  const stack = [directoryPath];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = await fs.readdir(current, { withFileTypes: true });
    } catch (error) {
      summary.errors.push({ path: current, message: error.message });
      continue;
    }
    for (const entry of entries) {
      if (summary.scannedFiles >= maxEntries) {
        summary.truncated = true;
        return summary;
      }
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(absolute);
        continue;
      }
      if (!entry.isFile()) {
        continue;
      }
      summary.scannedFiles += 1;
      try {
        const stat = await fs.stat(absolute);
        if (stat.mtimeMs > cutoff) {
          continue;
        }
        summary.removedFiles += 1;
        summary.removedBytes += stat.size;
        if (!dryRun) {
          await fs.rm(absolute, { force: true });
        }
      } catch (error) {
        summary.errors.push({ path: absolute, message: error.message });
      }
    }
  }
  return summary;
}

async function runMaintenance(state, input = {}) {
  const options = maintenanceOptions(input);
  const stateCompaction = compactOperationalState(state, options);
  const downloadWorkCleanup = await cleanupDirectoryFiles(DOWNLOAD_WORK_ROOT, {
    olderThanMs: options.downloadWorkRetentionMinutes * 60 * 1000,
    dryRun: options.dryRun,
  });
  const artifactCacheCleanup = options.cleanArtifactCache
    ? await cleanupDirectoryFiles(ARTIFACT_CACHE_ROOT, {
      olderThanMs: options.artifactCacheRetentionDays * 24 * 60 * 60 * 1000,
      dryRun: options.dryRun,
    })
    : null;

  return {
    ok: true,
    dryRun: options.dryRun,
    options,
    state: stateCompaction,
    files: {
      downloadWork: downloadWorkCleanup,
      artifactCache: artifactCacheCleanup,
    },
    changed: stateCompaction.sessionsRemoved > 0
      || stateCompaction.ticketsRemoved > 0
      || downloadWorkCleanup.removedFiles > 0
      || (artifactCacheCleanup?.removedFiles || 0) > 0,
  };
}

function createEntitlementFromOrderItem(state, order, item, actor) {
  const sku = getSku(state, item.skuId);
  if (!sku) {
    fail(404, 'sku_not_found', 'sku not found');
  }
  const endsAt = sku.licenseType === 'perpetual' ? null : plusDays(sku.durationDays || 365);
  const entitlement = {
    entitlementId: `ent-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
    sourceOrderItemId: item.orderItemId,
    organizationId: order.buyerOrganizationId,
    modelId: sku.modelId,
    modelSkuId: sku.skuId,
    assignedToType: 'organization',
    assignedToId: order.buyerOrganizationId,
    licenseId: `lic-${sku.modelId}-${shortHash(order.orderId)}`,
    startsAt: isoNow(),
    endsAt,
    renewalMode: endsAt ? 'fixed' : 'perpetual',
    renewalEndsAt: endsAt,
    offlineLeaseDays: sku.offlineLeaseDays || 30,
    maxDevices: sku.maxDevices || 1,
    policyFlags: ['offline', 'device-bound'],
    deviceBindingRequired: true,
    status: 'active',
    createdAt: isoNow(),
    updatedAt: isoNow(),
  };
  state.entitlements.push(entitlement);
  audit(state, actor, 'entitlement.create_from_order', 'entitlement', entitlement.entitlementId, { orderId: order.orderId });
  return entitlement;
}

function createTrialEntitlement(state, session, model, days) {
  const existing = state.entitlements.find((item) =>
    item.organizationId === session.organizationId
    && item.modelId === model.modelId
    && item.assignedToType === 'user'
    && item.assignedToId === session.userId
    && item.policyFlags?.includes('trial')
    && item.status === 'active'
  );
  if (existing) {
    return existing;
  }
  const endsAt = plusDays(days || state.platformSettings.defaultTrialDays || 7);
  const entitlement = {
    entitlementId: `ent-trial-${crypto.randomUUID().replace(/-/g, '').slice(0, 10)}`,
    sourceOrderItemId: null,
    organizationId: session.organizationId,
    modelId: model.modelId,
    modelSkuId: null,
    assignedToType: 'user',
    assignedToId: session.userId,
    licenseId: `trial-${model.modelId}-${shortHash(session.userId)}`,
    startsAt: isoNow(),
    endsAt,
    renewalMode: 'fixed',
    renewalEndsAt: endsAt,
    offlineLeaseDays: Math.min(Number(state.platformSettings.defaultTrialDays || 7), 7),
    maxDevices: 1,
    policyFlags: ['offline', 'device-bound', 'trial'],
    deviceBindingRequired: true,
    status: 'active',
    createdAt: isoNow(),
    updatedAt: isoNow(),
  };
  state.entitlements.push(entitlement);
  return entitlement;
}

function ensureDefaultSkuForModel(state, model, actor) {
  let sku = state.modelSkus.find((item) => item.modelId === model.modelId && item.status === 'active');
  if (sku) {
    return sku;
  }
  sku = {
    skuId: `sku-${model.modelId}-annual`,
    modelId: model.modelId,
    buildId: model.currentBuildId || null,
    name: 'Annual device-bound license',
    licenseType: 'subscription',
    priceAmount: 9800,
    currency: 'CNY',
    durationDays: 365,
    maxDevices: 3,
    offlineLeaseDays: state.platformSettings.defaultOfflineLeaseDays || 30,
    status: 'active',
    createdAt: isoNow(),
    updatedAt: isoNow(),
  };
  state.modelSkus.push(sku);
  audit(state, actor, 'sku.default_create', 'model_sku', sku.skuId, { modelId: model.modelId });
  return sku;
}

function buildAccessScopeForOrder(state, session, order) {
  if (!order) {
    return false;
  }
  if (['super_admin', 'admin', 'platform_ops', 'finance'].includes(session.role)) {
    return true;
  }
  if (['buyer_admin', 'buyer_operator'].includes(session.role)) {
    return order.buyerOrganizationId === session.organizationId;
  }
  if (session.role === 'developer_admin') {
    const developer = getDeveloperForSession(state, session);
    if (!developer) {
      return false;
    }
    const ownModelIds = new Set(state.models.filter((model) => model.developerId === developer.developerId).map((model) => model.modelId));
    return order.items.some((item) => ownModelIds.has(item.modelId));
  }
  return false;
}

function ensureOrderPaymentSucceeded(state, order, actor, paymentPayload = {}) {
  if (['paid', 'delivering', 'completed'].includes(order.status)) {
    return {
      order,
      payment: state.payments.find((item) => item.orderId === order.orderId && item.status === 'succeeded') || null,
      entitlements: state.entitlements.filter((item) => item.sourceOrderItemId && order.items.some((oi) => oi.orderItemId === item.sourceOrderItemId)),
      settlements: state.settlements.filter((item) => item.orderId === order.orderId),
    };
  }
  order.status = 'paid';
  order.paidAt = isoNow();
  order.updatedAt = isoNow();
  const payment = {
    paymentId: paymentPayload.paymentId || `pay-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
    orderId: order.orderId,
    provider: paymentPayload.provider || 'manual',
    status: 'succeeded',
    amount: money(paymentPayload.amount ?? order.totalAmount),
    providerTradeNo: paymentPayload.providerTradeNo || `manual-${shortHash(order.orderId)}`,
    idempotencyKey: paymentPayload.idempotencyKey || `manual-${order.orderId}`,
    rawPayload: paymentPayload.rawPayload || undefined,
    createdAt: isoNow(),
  };
  state.payments.push(payment);
  const entitlements = order.items.map((item) => createEntitlementFromOrderItem(state, order, item, actor));
  const settlements = createSettlementEntriesForOrder(state, order, actor);
  audit(state, actor, 'order.confirm_payment', 'order', order.orderId, { paymentId: payment.paymentId });
  return { order, payment, entitlements, settlements };
}

async function createUploadedBuild(state, session, model, body) {
  const fileName = safeFileName(requiredString(body, 'fileName'));
  const contentBase64 = requiredString(body, 'contentBase64', 'contentBase64');
  const bytes = Buffer.from(contentBase64, 'base64');
  if (bytes.length === 0) {
    fail(422, 'empty_model_file', 'model file is empty');
  }
  const extension = path.extname(fileName).toLowerCase();
  const allowedExtensions = new Set(['.mlmodel', '.mlpackage', '.mlmodelc', '.zip', '.bin']);
  if (!allowedExtensions.has(extension)) {
    fail(422, 'unsupported_model_format', 'model file must be CoreML or an archived bundle');
  }
  const uploadId = crypto.randomUUID().replace(/-/g, '').slice(0, 12);
  const storedName = `${model.modelId}-${uploadId}-${fileName}`;
  const storedPath = path.join(MODEL_UPLOAD_ROOT, storedName);
  await fs.writeFile(storedPath, bytes);
  const sourceFormat = String(body.sourceFormat || extension.replace('.', '') || 'binary').replace(/[^a-zA-Z0-9_-]/g, '');
  const build = {
    modelBuildId: `build-${uploadId}`,
    modelId: model.modelId,
    version: String(body.version || model.version || '1.0.0'),
    buildNumber: String(body.buildNumber || shortHash(`${storedName}:${bytes.length}`)),
    platform: body.platform || 'ios',
    sourcePath: path.relative(REPO_ROOT, storedPath).split(path.sep).join('/'),
    objectKey: path.relative(DATA_ROOT, storedPath).split(path.sep).join('/'),
    fileName,
    sourceFormat,
    transportFormat: body.transportFormat || (extension === '.mlpackage' || extension === '.mlmodelc' ? 'bundle-archive' : 'raw-file'),
    supportedPlatforms: Array.isArray(body.supportedPlatforms) ? body.supportedPlatforms : ['ios'],
    isEncrypted: body.isEncrypted !== false,
    status: 'ready',
    byteCount: bytes.length,
    sha256: hashHex(bytes),
    createdAt: isoNow(),
  };
  state.modelBuilds.push(build);
  model.currentBuildId = build.modelBuildId;
  model.status = ['listed', 'in_review'].includes(model.status) ? 'in_review' : (model.status || 'draft');
  model.updatedAt = isoNow();
  audit(state, session, 'model_build.upload', 'model_build', build.modelBuildId, { modelId: model.modelId, byteCount: build.byteCount });
  return build;
}

function createSettlementEntriesForOrder(state, order, actor) {
  const created = [];
  for (const item of order.items || []) {
    const model = getModel(state, item.modelId);
    const developer = model ? state.developers.find((dev) => dev.developerId === model.developerId) : null;
    if (!developer) {
      continue;
    }
    const grossAmount = money(item.unitPrice * item.quantity);
    const commissionRate = Number(state.platformSettings.commissionRate || 0.12);
    const commissionAmount = money(grossAmount * commissionRate);
    const payableAmount = money(grossAmount - commissionAmount);
    const existing = state.settlements.find((settlement) => settlement.orderItemId === item.orderItemId);
    if (existing) {
      created.push(existing);
      continue;
    }
    const settlement = {
      settlementId: `set-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      developerId: developer.developerId,
      organizationId: developer.organizationId,
      orderId: order.orderId,
      orderItemId: item.orderItemId,
      modelId: item.modelId,
      grossAmount,
      commissionRate,
      commissionAmount,
      payableAmount,
      currency: order.currency || 'CNY',
      status: 'pending',
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    state.settlements.push(settlement);
    created.push(settlement);
    audit(state, actor, 'settlement.create', 'settlement', settlement.settlementId, { orderId: order.orderId });
  }
  return created;
}

function revokeOrderEntitlements(state, order, actor, reason) {
  const revoked = [];
  const itemIds = new Set((order.items || []).map((item) => item.orderItemId));
  for (const entitlement of state.entitlements) {
    if (entitlement.sourceOrderItemId && itemIds.has(entitlement.sourceOrderItemId) && entitlement.status === 'active') {
      entitlement.status = 'revoked';
      entitlement.updatedAt = isoNow();
      revoked.push(entitlement);
      audit(state, actor, 'entitlement.revoke_for_refund', 'entitlement', entitlement.entitlementId, { orderId: order.orderId, reason });
    }
  }
  return revoked;
}

async function handleCreateDeviceInvite(state, req, res) {
  const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin']);
  const body = parseJsonBuffer(await readBody(req));
  const organizationId = isPlatformAdminRole(actor.role)
    ? String(body.organizationId || actor.organizationId || '').trim()
    : actor.organizationId;
  const organization = state.organizations.find((item) => item.organizationId === organizationId);
  if (!organization) {
    fail(404, 'organization_not_found', 'organization not found');
  }

  const requestedUser = String(body.userId || body.email || '').trim().toLowerCase();
  const user = requestedUser
    ? state.users.find((item) =>
      item.userId === requestedUser
      || String(item.email || '').toLowerCase() === requestedUser
    )
    : state.users.find((item) => item.userId === actor.userId);
  if (!user || user.organizationId !== organizationId || user.status === 'disabled') {
    fail(404, 'invite_user_not_found', 'invite user not found');
  }

  const ttlMinutes = Math.min(parsePositiveInt(body.ttlMinutes, 10), 24 * 60);
  const invite = {
    inviteId: `invite-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
    code: createDeviceInviteCode(state),
    organizationId,
    organizationName: organization.name,
    userId: user.userId,
    email: user.email,
    displayName: user.displayName,
    createdBy: actor.userId,
    status: 'active',
    expiresAt: plusMinutes(ttlMinutes),
    claimedAt: null,
    claimedBySessionId: null,
    deviceId: null,
    deviceName: '',
    platform: body.platform || 'iOS',
    note: String(body.note || '').trim(),
    createdAt: isoNow(),
    updatedAt: isoNow(),
  };
  state.deviceInvites.push(invite);
  audit(state, actor, 'device_invite.create', 'device_invite', invite.inviteId, {
    organizationId,
    userId: user.userId,
    expiresAt: invite.expiresAt,
  });
  await writeState(state);
  sendJson(res, 201, { invite: publicDeviceInvite(req, invite) });
}

async function handleClaimDeviceInvite(state, req, res, codeFromPath) {
  const body = parseJsonBuffer(await readBody(req));
  const code = normalizeInviteCode(codeFromPath || body.code);
  if (!code) {
    fail(422, 'invite_code_required', 'invite code is required');
  }
  const invite = state.deviceInvites.find((item) => item.code === code);
  if (!invite || invite.status !== 'active') {
    fail(404, 'invite_not_found', 'device invite not found');
  }
  if (new Date(invite.expiresAt).getTime() <= Date.now()) {
    invite.status = 'expired';
    invite.updatedAt = isoNow();
    await writeState(state);
    fail(410, 'invite_expired', 'device invite expired');
  }

  const user = state.users.find((item) => item.userId === invite.userId && item.status !== 'disabled');
  if (!user) {
    fail(404, 'invite_user_not_found', 'invite user not found');
  }

  const session = createSession(state, user, {
    deviceId: requiredString(body, 'deviceId', 'deviceId'),
    deviceName: String(body.deviceName || body.deviceId || '').trim(),
    platform: String(body.platform || invite.platform || 'iOS').trim(),
  });
  const device = upsertDevice(state, session, session.deviceId, session.deviceName, session.platform);
  invite.status = 'claimed';
  invite.claimedAt = isoNow();
  invite.claimedBySessionId = session.sessionId;
  invite.deviceId = device.deviceBindingId;
  invite.deviceName = device.name;
  invite.platform = device.platform;
  invite.updatedAt = isoNow();
  audit(state, session, 'device_invite.claim', 'device_invite', invite.inviteId, {
    organizationId: invite.organizationId,
    deviceId: device.deviceBindingId,
    platform: device.platform,
  });
  await writeState(state);
  sendJson(res, 200, {
    ...authSessionPayload(session, user),
    provisioning: {
      organizationId: invite.organizationId,
      organizationName: invite.organizationName,
      deviceId: device.deviceBindingId,
      deviceName: device.name,
      platform: device.platform,
      cloudBaseURL: requestBaseUrl(req),
    },
  });
}

async function handleLogin(state, req, res) {
  const body = parseJsonBuffer(await readBody(req));
  const loginId = String(body.email || body.account || body.username || '').trim().toLowerCase();
  const password = String(body.password || '').trim();
  const user = state.users.find((item) => item.email.toLowerCase() === loginId && item.status !== 'disabled' && verifyPassword(item, password));
  if (!user) {
    sendJson(res, 401, { error: { code: 'invalid_credentials', message: 'invalid credentials' } });
    return;
  }
  const session = createSession(state, user, body);
  upsertDevice(state, session, session.deviceId, session.deviceName, session.platform);
  audit(state, session, 'auth.login', 'user', user.userId, { platform: session.platform });
  await writeState(state);
  sendJson(res, 200, authSessionPayload(session, user));
}

async function handleLogout(state, req, res) {
  const token = authTokenFromRequest(req);
  const session = getSessionFromToken(state, token);
  if (session) {
    session.revokedAt = isoNow();
    audit(state, session, 'auth.logout', 'session', session.sessionId || session.accessToken, { platform: session.platform });
    await writeState(state);
  }
  sendJson(res, 200, { ok: true });
}

async function handleIngest(state, req, res, kind) {
  const body = parseJsonBuffer(await readBody(req));
  const id = body.idempotencyKey || body[`${kind}Id`] || `${kind}-${crypto.randomUUID()}`;
  const collectionName = kind === 'asset' ? 'assets' : `${kind}s`;
  const collection = state.ingests[collectionName];
  const idField = `${kind}Id`;
  const existing = collection.find((item) => item[idField] === id);
  if (existing) {
    sendJson(res, 200, existing);
    return;
  }

  let record;
  if (kind === 'asset') {
    const extension = path.extname(body.fileName || '').replace(/[^a-zA-Z0-9.]/g, '');
    const safeFileName = `${id}${extension}`;
    const filePath = path.join(INGEST_ASSET_ROOT, safeFileName);
    const bytes = Buffer.from(String(body.contentBase64 || ''), 'base64');
    await fs.writeFile(filePath, bytes);
    record = {
      assetId: id,
      organizationId: body.organizationId || '',
      deviceId: body.deviceId || 'unknown-device',
      deviceName: body.deviceName || '',
      fileName: body.fileName || safeFileName,
      category: body.category || 'binary',
      byteCount: bytes.length,
      productUUID: body.productUUID || '',
      pointIndex: Number(body.pointIndex || 0),
      jobId: body.jobId || '',
      capturedAt: body.capturedAt || isoNow(),
      storedPath: filePath,
      createdAt: isoNow(),
    };
  } else {
    record = {
      [idField]: id,
      organizationId: body.organizationId || '',
      deviceId: body.deviceId || 'unknown-device',
      deviceName: body.deviceName || '',
      resultType: body.resultType || body.type || kind,
      level: body.level || undefined,
      category: body.category || undefined,
      payload: body.payload || body,
      productUUID: body.productUUID || '',
      pointIndex: Number(body.pointIndex || 0),
      jobId: body.jobId || '',
      capturedAt: body.capturedAt || body.timestamp || isoNow(),
      createdAt: isoNow(),
    };
  }
  collection.push(record);
  await writeState(state);
  sendJson(res, 200, record);
}

async function handleRoute(req, res) {
  const pathname = normalizePathname(req.url);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'X-Request-Id': res.requestId || '',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key',
      'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
    });
    res.end();
    return;
  }

  if (!applyRateLimit(req, res, pathname)) {
    return;
  }

  if (req.method === 'GET' && pathname === '/healthz') {
    sendJson(res, 200, { service: 'vino_platform', status: 'ok', now: isoNow() });
    return;
  }

  if (req.method === 'GET' && (pathname === '/readyz' || pathname === '/api/platform/v1/health' || pathname === '/api/cloud/v1/health')) {
    sendJson(res, 200, await checkReady());
    return;
  }

  if (await serveStatic(req, res)) {
    return;
  }

  return withStateLock(() => handleStateRoute(req, res, pathname));
}

async function handleStateRoute(req, res, pathname) {
  const state = await readState();

  if (req.method === 'POST' && (pathname === '/api/platform/v1/auth/login' || pathname === '/api/cloud/v1/auth/login')) {
    await handleLogin(state, req, res);
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/platform/v1/auth/logout' || pathname === '/api/cloud/v1/auth/logout')) {
    await handleLogout(state, req, res);
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/device-invites') {
    await handleCreateDeviceInvite(state, req, res);
    return;
  }

  if (req.method === 'POST' && /^\/api\/(platform|cloud)\/v1\/device-invites\/[^/]+\/claim$/.test(pathname)) {
    await handleClaimDeviceInvite(state, req, res, decodeURIComponent(pathname.split('/')[5] || ''));
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/me') {
    const session = requireSession(state, req);
    const user = state.users.find((item) => item.userId === session.userId);
    sendJson(res, 200, {
      session,
      user: {
        ...publicUser(user),
        roleLabel: roleLabel(user?.role),
      },
      permissions: permissionsForRole(user?.role),
    });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/dashboard/overview') {
    const session = requireSession(state, req);
    sendJson(res, 200, await buildRoleOverview(state, session));
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/admin/ops/status') {
    requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    sendJson(res, 200, await buildOpsStatus(state));
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/admin/ops/doctor') {
    requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    sendJson(res, 200, buildStateDoctor(state));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/ops/maintenance') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const result = await runMaintenance(state, body);
    if (!result.dryRun && result.changed) {
      audit(state, actor, 'ops.maintenance', 'ops', 'maintenance', result);
      await writeState(state);
    }
    sendJson(res, 200, result);
    return;
  }

  if (req.method === 'GET' && /^\/api\/platform\/v1\/organizations\/[^/]+$/.test(pathname)) {
    const session = requireSession(state, req);
    const organizationId = pathname.split('/')[5];
    if (!isPlatformAdminRole(session.role) && session.organizationId !== organizationId) {
      fail(403, 'forbidden', 'forbidden');
    }
    const organization = state.organizations.find((item) => item.organizationId === organizationId);
    if (!organization) {
      fail(404, 'organization_not_found', 'organization not found');
    }
    sendJson(res, 200, { organization });
    return;
  }

  if (req.method === 'GET' && /^\/api\/platform\/v1\/organizations\/[^/]+\/users$/.test(pathname)) {
    const session = requireSession(state, req);
    const organizationId = pathname.split('/')[5];
    if (!isPlatformAdminRole(session.role) && session.organizationId !== organizationId) {
      fail(403, 'forbidden', 'forbidden');
    }
    sendJson(res, 200, {
      users: state.users.filter((user) => user.organizationId === organizationId).map(publicUser),
    });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/organizations\/[^/]+\/users$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin']);
    const organizationId = pathname.split('/')[5];
    if (!isPlatformAdminRole(actor.role) && actor.organizationId !== organizationId) {
      fail(403, 'forbidden', 'forbidden');
    }
    const body = parseJsonBuffer(await readBody(req));
    body.organizationId = organizationId;
    const organization = state.organizations.find((item) => item.organizationId === organizationId);
    if (!organization) {
      fail(404, 'organization_not_found', 'organization not found');
    }
    const email = requiredString(body, 'email').toLowerCase();
    const duplicate = state.users.find((item) => item.email === email);
    if (duplicate) {
      fail(409, 'email_exists', 'email already exists');
    }
    const user = {
      userId: `user-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      email,
      displayName: requiredString(body, 'displayName'),
      organizationId,
      organizationName: organization.name,
      role: body.role || 'buyer_operator',
      status: body.status || 'active',
    };
    setUserPassword(user, body.password || 'demo123');
    state.users.push(user);
    audit(state, actor, 'user.create', 'user', user.userId, { organizationId });
    await writeState(state);
    sendJson(res, 201, { ok: true, user: publicUser(user) });
    return;
  }

  if (req.method === 'GET' && (pathname === '/api/platform/v1/admin/overview' || pathname === '/api/cloud/v1/admin/overview' || pathname === '/api/cloud/v1/overview')) {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    sendJson(res, 200, await buildRoleOverview(state, session));
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/models') {
    requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator']);
    sendJson(res, 200, { models: state.models.filter((model) => model.status === 'listed') });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/model-skus') {
    requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator']);
    sendJson(res, 200, { modelSkus: state.modelSkus.filter((sku) => sku.status === 'active') });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/marketplace/search') {
    requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator']);
    const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
    const query = String(url.searchParams.get('q') || '').trim().toLowerCase();
    const category = String(url.searchParams.get('category') || '').trim();
    const models = state.models
      .filter((model) => model.status === 'listed')
      .filter((model) => !query || [model.name, model.summary, model.description, ...(model.tags || [])].join(' ').toLowerCase().includes(query))
      .filter((model) => !category || model.category === category || (model.tags || []).includes(category))
      .map((model) => publicModel(state, model));
    sendJson(res, 200, { models, categories: state.categories });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/models\/[^/]+\/favorite$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator']);
    const modelId = pathname.split('/')[5];
    const model = getModel(state, modelId);
    if (!model || model.status !== 'listed') {
      fail(404, 'model_not_found', 'model not found');
    }
    let favorite = state.favorites.find((item) => item.userId === session.userId && item.modelId === modelId);
    if (!favorite) {
      favorite = {
        favoriteId: `fav-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        userId: session.userId,
        organizationId: session.organizationId,
        modelId,
        createdAt: isoNow(),
      };
      state.favorites.push(favorite);
      audit(state, session, 'model.favorite', 'model', modelId, {});
    }
    await writeState(state);
    sendJson(res, 200, { ok: true, favorite });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/models\/[^/]+\/reviews$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator']);
    const modelId = pathname.split('/')[5];
    const body = parseJsonBuffer(await readBody(req));
    const model = getModel(state, modelId);
    if (!model || model.status !== 'listed') {
      fail(404, 'model_not_found', 'model not found');
    }
    const review = {
      modelReviewId: `mr-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      modelId,
      userId: session.userId,
      organizationId: session.organizationId,
      rating: Math.max(1, Math.min(5, Number(body.rating || 5))),
      title: String(body.title || '').trim() || '使用评价',
      body: String(body.body || '').trim(),
      status: 'published',
      createdAt: isoNow(),
    };
    state.modelReviews.push(review);
    audit(state, session, 'model.review.create', 'model', modelId, { rating: review.rating });
    await writeState(state);
    sendJson(res, 201, { ok: true, review });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/models\/[^/]+\/trial-request$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator']);
    const modelId = pathname.split('/')[5];
    const model = getModel(state, modelId);
    if (!model || model.status !== 'listed') {
      fail(404, 'model_not_found', 'model not found');
    }
    const entitlement = createTrialEntitlement(state, session, model, state.platformSettings.defaultTrialDays);
    notify(state, session.userId, '试用授权已开通', `${model.name} 已加入你的可用模型`, 'trial');
    audit(state, session, 'trial.grant', 'entitlement', entitlement.entitlementId, { modelId });
    await writeState(state);
    sendJson(res, 200, { ok: true, entitlement });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/developers') {
    const session = requireAnyRole(state, req, ['developer_admin', 'super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const organizationId = isPlatformAdminRole(session.role) && body.organizationId ? body.organizationId : session.organizationId;
    let developer = state.developers.find((item) => item.organizationId === organizationId);
    if (!developer) {
      developer = {
        developerId: `dev-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        organizationId,
        createdAt: isoNow(),
      };
      state.developers.push(developer);
    }
    Object.assign(developer, {
      displayName: body.displayName || developer.displayName || session.organizationName,
      type: body.type || developer.type || 'company',
      verificationStatus: body.submit ? 'submitted' : developer.verificationStatus || 'draft',
      agreementSignedAt: body.agreementSigned ? isoNow() : developer.agreementSignedAt || null,
      updatedAt: isoNow(),
    });
    audit(state, session, 'developer.upsert', 'developer', developer.developerId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, developer });
    return;
  }

  if (req.method === 'GET' && /^\/api\/platform\/v1\/developers\/[^/]+$/.test(pathname)) {
    const session = requireSession(state, req);
    const developerId = pathname.split('/')[5];
    const developer = state.developers.find((item) => item.developerId === developerId);
    if (!developer) {
      fail(404, 'developer_not_found', 'developer not found');
    }
    if (!isPlatformAdminRole(session.role) && session.role !== 'reviewer' && developer.organizationId !== session.organizationId) {
      fail(403, 'forbidden', 'forbidden');
    }
    sendJson(res, 200, { developer });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/developers\/[^/]+\/qualifications$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['developer_admin', 'super_admin', 'admin', 'platform_ops', 'reviewer']);
    const developerId = pathname.split('/')[5];
    const body = parseJsonBuffer(await readBody(req));
    const developer = state.developers.find((item) => item.developerId === developerId);
    if (!developer) {
      fail(404, 'developer_not_found', 'developer not found');
    }
    if (!isPlatformAdminRole(session.role) && session.role !== 'reviewer' && developer.organizationId !== session.organizationId) {
      fail(403, 'forbidden', 'forbidden');
    }
    const qualification = {
      qualificationId: `qual-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      kind: body.kind || 'copyright',
      fileName: safeFileName(body.fileName || `${body.kind || 'qualification'}.txt`),
      note: body.note || '',
      status: isPlatformAdminRole(session.role) || session.role === 'reviewer' ? (body.status || 'approved') : 'pending',
      reviewerId: isPlatformAdminRole(session.role) || session.role === 'reviewer' ? session.userId : null,
      createdAt: isoNow(),
    };
    developer.qualifications = Array.isArray(developer.qualifications) ? developer.qualifications : [];
    developer.qualifications.push(qualification);
    developer.updatedAt = isoNow();
    audit(state, session, 'developer.qualification.add', 'developer', developer.developerId, { kind: qualification.kind });
    await writeState(state);
    sendJson(res, 201, { ok: true, developer, qualification });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/developer/profile') {
    const session = requireAnyRole(state, req, ['developer_admin']);
    const body = parseJsonBuffer(await readBody(req));
    let developer = getDeveloperForSession(state, session);
    if (!developer) {
      developer = {
        developerId: `dev-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        organizationId: session.organizationId,
        createdAt: isoNow(),
      };
      state.developers.push(developer);
    }
    Object.assign(developer, {
      displayName: body.displayName || developer.displayName || session.organizationName,
      type: body.type || developer.type || 'company',
      verificationStatus: body.submit ? 'submitted' : developer.verificationStatus || 'draft',
      agreementSignedAt: body.agreementSigned ? isoNow() : developer.agreementSignedAt || null,
      qualifications: Array.isArray(body.qualifications) ? body.qualifications : developer.qualifications || [],
      updatedAt: isoNow(),
    });
    audit(state, session, 'developer.profile.upsert', 'developer', developer.developerId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, developer });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/developer/models') {
    const session = requireAnyRole(state, req, ['developer_admin']);
    const body = parseJsonBuffer(await readBody(req));
    let developer = getDeveloperForSession(state, session);
    if (!developer) {
      developer = {
        developerId: `dev-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        organizationId: session.organizationId,
        displayName: session.organizationName,
        type: 'company',
        verificationStatus: 'draft',
        createdAt: isoNow(),
      };
      state.developers.push(developer);
    }
    const name = requiredString(body, 'name');
    let model = body.modelId ? state.models.find((item) => item.modelId === body.modelId) : null;
    if (model && model.developerId !== developer.developerId) {
      fail(403, 'forbidden', 'forbidden');
    }
    if (!model) {
      model = {
        modelId: `model-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        developerId: developer.developerId,
        createdAt: isoNow(),
      };
      state.models.push(model);
    }
    Object.assign(model, {
      name,
      slug: slugify(body.slug || name),
      category: body.category || 'cv',
      summary: body.summary || '',
      description: body.description || '',
      status: model.status || 'draft',
      tags: Array.isArray(body.tags) ? body.tags : String(body.tags || '').split(',').map((item) => item.trim()).filter(Boolean),
      currentBuildId: body.currentBuildId || model.currentBuildId || null,
      updatedAt: isoNow(),
    });
    audit(state, session, 'developer.model.upsert', 'model', model.modelId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, model });
    return;
  }

  if (req.method === 'PATCH' && /^\/api\/platform\/v1\/developer\/models\/[^/]+$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['developer_admin']);
    const modelId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    if (!developerOwnsModel(state, session, modelId)) {
      fail(403, 'forbidden', 'forbidden');
    }
    if (body.name) model.name = String(body.name).trim();
    if (body.slug || body.name) model.slug = slugify(body.slug || model.name);
    if (body.category) model.category = body.category;
    if (body.summary !== undefined) model.summary = String(body.summary || '');
    if (body.description !== undefined) model.description = String(body.description || '');
    if (body.tags !== undefined) {
      model.tags = Array.isArray(body.tags) ? body.tags : String(body.tags || '').split(',').map((item) => item.trim()).filter(Boolean);
    }
    if (['listed', 'approved'].includes(model.status)) {
      model.status = 'in_review';
    }
    model.updatedAt = isoNow();
    audit(state, session, 'developer.model.update', 'model', model.modelId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, model });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/developer\/models\/[^/]+\/builds$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['developer_admin']);
    const modelId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    if (!developerOwnsModel(state, session, modelId)) {
      fail(403, 'forbidden', 'forbidden');
    }
    const build = await createUploadedBuild(state, session, model, body);
    await writeState(state);
    sendJson(res, 201, { ok: true, model, build });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/developer\/models\/[^/]+\/submit-review$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['developer_admin']);
    const modelId = pathname.split('/')[6];
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    if (!developerOwnsModel(state, session, modelId)) {
      fail(403, 'forbidden', 'forbidden');
    }
    model.status = 'in_review';
    model.updatedAt = isoNow();
    const review = {
      reviewId: `review-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      subjectType: 'model',
      subjectId: modelId,
      status: 'pending',
      reviewerId: null,
      decisionNote: '',
      createdAt: isoNow(),
    };
    state.reviews.push(review);
    audit(state, session, 'model.submit_review', 'model', modelId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, model, review });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/developers\/[^/]+\/review$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'reviewer']);
    const developerId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const developer = state.developers.find((item) => item.developerId === developerId);
    if (!developer) {
      fail(404, 'developer_not_found', 'developer not found');
    }
    developer.verificationStatus = body.decision === 'reject' ? 'rejected' : 'approved';
    developer.reviewNote = body.note || '';
    developer.updatedAt = isoNow();
    audit(state, actor, 'developer.review', 'developer', developerId, { status: developer.verificationStatus });
    await writeState(state);
    sendJson(res, 200, { ok: true, developer });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/users') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const email = requiredString(body, 'email').toLowerCase();
    const displayName = requiredString(body, 'displayName');
    const organizationId = String(body.organizationId || 'org-demo-001').trim();
    const organization = state.organizations.find((item) => item.organizationId === organizationId);
    if (!organization) {
      fail(404, 'organization_not_found', 'organization not found');
    }
    let user = body.userId ? state.users.find((item) => item.userId === body.userId) : null;
    const duplicate = state.users.find((item) => item.email === email && item.userId !== user?.userId);
    if (duplicate) {
      fail(409, 'email_exists', 'email already exists');
    }
    if (!user) {
      user = {
        userId: `user-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        email,
        displayName,
        organizationId,
        organizationName: organization.name,
        role: body.role || 'buyer_operator',
        status: body.status || 'active',
      };
      setUserPassword(user, body.password || 'demo123');
      state.users.push(user);
      audit(state, actor, 'user.create', 'user', user.userId, {});
    } else {
      user.email = email;
      user.displayName = displayName;
      user.organizationId = organizationId;
      user.organizationName = organization.name;
      user.role = body.role || user.role;
      user.status = body.status || user.status || 'active';
      if (body.password) {
        setUserPassword(user, body.password);
      }
      audit(state, actor, 'user.update', 'user', user.userId, {});
    }
    await writeState(state);
    sendJson(res, 200, { ok: true, user: publicUser(user) });
    return;
  }

  if (req.method === 'PATCH' && /^\/api\/platform\/v1\/users\/[^/]+$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin']);
    const userId = pathname.split('/')[5];
    const body = parseJsonBuffer(await readBody(req));
    const user = state.users.find((item) => item.userId === userId);
    if (!user) {
      fail(404, 'user_not_found', 'user not found');
    }
    if (!isPlatformAdminRole(actor.role) && actor.organizationId !== user.organizationId) {
      fail(403, 'forbidden', 'forbidden');
    }
    if (body.email) {
      const email = String(body.email).trim().toLowerCase();
      const duplicate = state.users.find((item) => item.email === email && item.userId !== user.userId);
      if (duplicate) {
        fail(409, 'email_exists', 'email already exists');
      }
      user.email = email;
    }
    if (body.displayName !== undefined) user.displayName = String(body.displayName || user.displayName);
    if (body.password) setUserPassword(user, body.password);
    if (body.role && (isPlatformAdminRole(actor.role) || !['super_admin', 'admin', 'platform_ops', 'reviewer', 'finance'].includes(body.role))) {
      user.role = body.role;
    }
    if (body.status) user.status = body.status;
    user.updatedAt = isoNow();
    audit(state, actor, 'user.update', 'user', user.userId, { status: user.status, role: user.role });
    await writeState(state);
    sendJson(res, 200, { ok: true, user: publicUser(user) });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/model-skus') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = requiredString(body, 'modelId');
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    let sku = body.skuId
      ? state.modelSkus.find((item) => item.skuId === body.skuId)
      : body.defaultSku
        ? state.modelSkus.find((item) => item.skuId === `sku-${modelId}-annual` || item.modelId === modelId)
        : null;
    if (!sku) {
      sku = {
        skuId: body.defaultSku ? `sku-${modelId}-annual` : `sku-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        createdAt: isoNow(),
      };
      state.modelSkus.push(sku);
    }
    Object.assign(sku, {
      modelId,
      buildId: body.buildId || model.currentBuildId,
      name: body.name || 'Standard license',
      licenseType: body.licenseType || 'subscription',
      priceAmount: money(body.priceAmount || 0),
      currency: body.currency || 'CNY',
      durationDays: Number(body.durationDays || 365),
      maxDevices: Number(body.maxDevices || 1),
      offlineLeaseDays: Number(body.offlineLeaseDays || 30),
      status: body.status || 'active',
      updatedAt: isoNow(),
    });
    audit(state, actor, 'sku.upsert', 'model_sku', sku.skuId, { modelId });
    await writeState(state);
    sendJson(res, 200, { ok: true, sku });
    return;
  }

  if (req.method === 'GET' && /^\/api\/platform\/v1\/model-skus\/[^/]+$/.test(pathname)) {
    requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator', 'developer_admin']);
    const skuId = pathname.split('/')[5];
    const sku = getSku(state, skuId);
    if (!sku) {
      fail(404, 'sku_not_found', 'sku not found');
    }
    const model = getModel(state, sku.modelId);
    sendJson(res, 200, { sku, model: model ? publicModel(state, model) : null });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/orders') {
    const session = requireAnyRole(state, req, ['buyer_admin', 'super_admin', 'platform_ops', 'admin']);
    const body = parseJsonBuffer(await readBody(req));
    const idempotencyKey = String(req.headers['idempotency-key'] || body.idempotencyKey || '').trim();
    if (idempotencyKey) {
      const existing = state.orders.find((item) => item.idempotencyKey === idempotencyKey && item.buyerUserId === session.userId);
      if (existing) {
        sendJson(res, 200, { ok: true, order: existing, replayed: true });
        return;
      }
    }
    const buyerOrganizationId = isPlatformAdminRole(session.role)
      ? body.buyerOrganizationId || state.organizations.find((item) => item.type === 'buyer')?.organizationId || session.organizationId
      : session.organizationId;
    const buyerOrganization = state.organizations.find((item) => item.organizationId === buyerOrganizationId);
    if (!buyerOrganization || buyerOrganization.type !== 'buyer') {
      fail(422, 'buyer_organization_required', 'buyer organization is required');
    }
    const items = Array.isArray(body.items) ? body.items : [{ skuId: body.skuId, quantity: body.quantity || 1 }];
    const orderItems = items.map((item) => {
      const sku = getSku(state, requiredString(item, 'skuId'));
      if (!sku) {
        fail(404, 'sku_not_found', 'sku not found');
      }
      return {
        orderItemId: `oi-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        skuId: sku.skuId,
        modelId: sku.modelId,
        quantity: Number(item.quantity || 1),
        unitPrice: money(sku.priceAmount),
        entitlementPolicySnapshot: {
          licenseType: sku.licenseType,
          durationDays: sku.durationDays,
          maxDevices: sku.maxDevices,
          offlineLeaseDays: sku.offlineLeaseDays,
        },
      };
    });
    const subtotalAmount = orderItems.reduce((sum, item) => sum + item.unitPrice * item.quantity, 0);
    const couponCode = String(body.couponCode || '').trim().toUpperCase();
    const coupon = couponCode
      ? state.coupons.find((item) => item.code === couponCode && item.status === 'active')
      : null;
    const discountAmount = coupon
      ? Math.min(
        coupon.discountType === 'percent'
          ? subtotalAmount * (Number(coupon.discountValue || 0) / 100)
          : Number(coupon.discountValue || 0),
        subtotalAmount
      )
      : 0;
    const totalAmount = Math.max(0, subtotalAmount - discountAmount);
    const order = {
      orderId: `order-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      buyerOrganizationId,
      buyerUserId: session.userId,
      status: 'pending_payment',
      subtotalAmount: money(subtotalAmount),
      discountAmount: money(discountAmount),
      couponCode: coupon?.code || null,
      totalAmount: money(totalAmount),
      currency: body.currency || 'CNY',
      paymentMode: body.paymentMode || 'offline_transfer',
      idempotencyKey: idempotencyKey || null,
      items: orderItems,
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    if (coupon) {
      coupon.usedCount = Number(coupon.usedCount || 0) + 1;
    }
    state.orders.push(order);
    audit(state, session, 'order.create', 'order', order.orderId, { totalAmount: order.totalAmount });
    await writeState(state);
    sendJson(res, 201, { ok: true, order });
    return;
  }

  if (req.method === 'GET' && /^\/api\/platform\/v1\/orders\/[^/]+$/.test(pathname)) {
    const session = requireSession(state, req);
    const orderId = pathname.split('/')[5];
    const order = state.orders.find((item) => item.orderId === orderId);
    if (!order) {
      fail(404, 'order_not_found', 'order not found');
    }
    if (!buildAccessScopeForOrder(state, session, order)) {
      fail(403, 'forbidden', 'forbidden');
    }
    sendJson(res, 200, {
      order,
      payments: state.payments.filter((payment) => payment.orderId === order.orderId),
      entitlements: state.entitlements.filter((item) => item.sourceOrderItemId && order.items.some((oi) => oi.orderItemId === item.sourceOrderItemId)),
      settlements: state.settlements.filter((settlement) => settlement.orderId === order.orderId),
    });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/orders\/[^/]+\/confirm-payment$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'finance']);
    const body = parseJsonBuffer(await readBody(req));
    const orderId = pathname.split('/')[6];
    const order = state.orders.find((item) => item.orderId === orderId);
    if (!order) {
      fail(404, 'order_not_found', 'order not found');
    }
    const idempotencyKey = String(req.headers['idempotency-key'] || body.idempotencyKey || `manual-${orderId}`).trim();
    const existingPayment = state.payments.find((payment) => payment.idempotencyKey === idempotencyKey);
    if (existingPayment) {
      sendJson(res, 200, {
        ok: true,
        order,
        payment: existingPayment,
        entitlements: state.entitlements.filter((item) => item.sourceOrderItemId && order.items.some((oi) => oi.orderItemId === item.sourceOrderItemId)),
        settlements: state.settlements.filter((settlement) => settlement.orderId === orderId),
        replayed: true,
      });
      return;
    }
    const result = ensureOrderPaymentSucceeded(state, order, actor, {
      provider: body.provider || 'manual',
      providerTradeNo: body.providerTradeNo || `manual-${shortHash(orderId)}`,
      idempotencyKey,
      amount: order.totalAmount,
    });
    await writeState(state);
    sendJson(res, 200, { ok: true, ...result });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/payments\/webhooks\/[^/]+$/.test(pathname)) {
    const body = parseJsonBuffer(await readBody(req));
    const provider = pathname.split('/')[6];
    const idempotencyKey = String(req.headers['idempotency-key'] || body.idempotencyKey || body.providerTradeNo || '').trim();
    if (!idempotencyKey) {
      fail(422, 'idempotency_key_required', 'payment webhook requires idempotency key');
    }
    const existingPayment = state.payments.find((payment) => payment.idempotencyKey === idempotencyKey);
    if (existingPayment) {
      sendJson(res, 200, { ok: true, payment: existingPayment, replayed: true });
      return;
    }
    const order = state.orders.find((item) => item.orderId === body.orderId);
    if (!order) {
      fail(404, 'order_not_found', 'order not found');
    }
    if (!['succeeded', 'success', 'paid'].includes(String(body.status || '').toLowerCase())) {
      const payment = {
        paymentId: `pay-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        orderId: order.orderId,
        provider,
        status: 'failed',
        amount: money(body.amount || order.totalAmount),
        providerTradeNo: body.providerTradeNo || idempotencyKey,
        idempotencyKey,
        rawPayload: body,
        createdAt: isoNow(),
      };
      state.payments.push(payment);
      audit(state, null, 'payment.webhook_failed', 'payment', payment.paymentId, { orderId: order.orderId });
      await writeState(state);
      sendJson(res, 200, { ok: true, payment });
      return;
    }
    const result = ensureOrderPaymentSucceeded(state, order, null, {
      provider,
      providerTradeNo: body.providerTradeNo || idempotencyKey,
      idempotencyKey,
      amount: body.amount || order.totalAmount,
      rawPayload: body,
    });
    audit(state, null, 'payment.webhook_succeeded', 'order', order.orderId, { provider });
    await writeState(state);
    sendJson(res, 200, { ok: true, ...result });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/orders\/[^/]+\/refund$/.test(pathname)) {
    const session = requireSession(state, req);
    if (!canRequestRefundRole(session.role)) {
      fail(403, 'forbidden', 'forbidden');
    }
    const body = parseJsonBuffer(await readBody(req));
    const orderId = pathname.split('/')[5];
    const order = state.orders.find((item) => item.orderId === orderId);
    if (!order) {
      fail(404, 'order_not_found', 'order not found');
    }
    const isOwner = order.buyerUserId === session.userId || order.buyerOrganizationId === session.organizationId;
    if (!isOwner && !canConfirmPaymentRole(session.role)) {
      fail(403, 'forbidden', 'forbidden');
    }
    const autoApprove = canConfirmPaymentRole(session.role) && body.autoApprove !== false;
    order.status = autoApprove ? 'refunded' : 'after_sale';
    order.refundReason = body.reason || 'refund requested';
    order.refundRequestedAt = isoNow();
    order.updatedAt = isoNow();
    const revoked = order.status === 'refunded' ? revokeOrderEntitlements(state, order, session, order.refundReason) : [];
    state.payments
      .filter((payment) => payment.orderId === orderId)
      .forEach((payment) => {
        payment.status = order.status === 'refunded' ? 'refunded' : payment.status;
      });
    state.settlements
      .filter((settlement) => settlement.orderId === orderId)
      .forEach((settlement) => {
        settlement.status = order.status === 'refunded' ? 'canceled' : settlement.status;
        settlement.updatedAt = isoNow();
      });
    audit(state, session, 'order.refund_request', 'order', orderId, { status: order.status });
    await writeState(state);
    sendJson(res, 200, { ok: true, order, revoked });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/entitlements') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = requiredString(body, 'modelId');
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    const assignedToType = ['organization', 'user', 'device'].includes(body.assignedToType) ? body.assignedToType : 'user';
    const assignedToId = requiredString(body, 'assignedToId');
    const organizationId = body.organizationId
      || (assignedToType === 'user'
        ? state.users.find((item) => item.userId === assignedToId)?.organizationId
        : assignedToType === 'device'
          ? state.devices.find((item) => item.deviceBindingId === assignedToId || item.deviceId === assignedToId)?.organizationId
          : assignedToId)
      || 'org-demo-001';
    let entitlement = body.entitlementId ? state.entitlements.find((item) => item.entitlementId === body.entitlementId) : null;
    if (!entitlement) {
      entitlement = {
        entitlementId: `ent-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        createdAt: isoNow(),
      };
      state.entitlements.push(entitlement);
    }
    const renewalMode = body.renewalMode === 'fixed' ? 'fixed' : 'perpetual';
    const renewalEndsAt = renewalMode === 'fixed' ? normalizeTimestamp(body.renewalEndsAt) : null;
    Object.assign(entitlement, {
      sourceOrderItemId: body.sourceOrderItemId || entitlement.sourceOrderItemId || null,
      organizationId,
      modelId,
      modelSkuId: body.modelSkuId || `sku-${modelId}-annual`,
      assignedToType,
      assignedToId,
      licenseId: body.licenseId || entitlement.licenseId || `lic-${modelId}-${shortHash(assignedToId)}`,
      startsAt: normalizeTimestamp(body.startsAt) || entitlement.startsAt || isoNow(),
      endsAt: renewalEndsAt,
      renewalMode,
      renewalEndsAt,
      offlineLeaseDays: Number(body.offlineLeaseDays || entitlement.offlineLeaseDays || 30),
      maxDevices: Number(body.maxDevices || entitlement.maxDevices || 1),
      policyFlags: Array.isArray(body.policyFlags) ? body.policyFlags : ['offline', 'device-bound'],
      deviceBindingRequired: body.deviceBindingRequired !== false,
      status: body.status || 'active',
      updatedAt: isoNow(),
    });
    audit(state, actor, 'entitlement.upsert', 'entitlement', entitlement.entitlementId, { modelId });
    await writeState(state);
    sendJson(res, 200, { ok: true, entitlement });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/entitlements\/[^/]+\/revoke$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const entitlementId = pathname.split('/')[6];
    const entitlement = state.entitlements.find((item) => item.entitlementId === entitlementId);
    if (!entitlement) {
      fail(404, 'entitlement_not_found', 'entitlement not found');
    }
    entitlement.status = 'revoked';
    entitlement.updatedAt = isoNow();
    state.leases.filter((lease) => lease.entitlementId === entitlementId).forEach((lease) => {
      lease.status = 'revoked';
    });
    audit(state, actor, 'entitlement.revoke', 'entitlement', entitlementId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, entitlement });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/entitlements\/[^/]+\/assign$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const entitlementId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const entitlement = state.entitlements.find((item) => item.entitlementId === entitlementId);
    if (!entitlement) {
      fail(404, 'entitlement_not_found', 'entitlement not found');
    }
    const assignedToType = ['organization', 'user', 'device'].includes(body.assignedToType) ? body.assignedToType : entitlement.assignedToType;
    const assignedToId = requiredString(body, 'assignedToId');
    let organizationId = body.organizationId || entitlement.organizationId;
    if (assignedToType === 'user') {
      const user = state.users.find((item) => item.userId === assignedToId);
      if (!user) {
        fail(404, 'user_not_found', 'user not found');
      }
      organizationId = user.organizationId;
    }
    if (assignedToType === 'organization' && !state.organizations.some((item) => item.organizationId === assignedToId)) {
      fail(404, 'organization_not_found', 'organization not found');
    }
    entitlement.assignedToType = assignedToType;
    entitlement.assignedToId = assignedToId;
    entitlement.organizationId = organizationId;
    entitlement.updatedAt = isoNow();
    audit(state, actor, 'entitlement.assign', 'entitlement', entitlementId, { assignedToType, assignedToId });
    await writeState(state);
    sendJson(res, 200, { ok: true, entitlement });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/admin/entitlements') {
    requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    sendJson(res, 200, { entitlements: (await buildOverview(state)).entitlements });
    return;
  }

  if (req.method === 'POST' && /^\/api\/cloud\/v1\/admin\/entitlements\/[^/]+\/delete$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const entitlementId = pathname.split('/')[6];
    const entitlement = state.entitlements.find((item) => item.entitlementId === entitlementId);
    if (!entitlement) {
      fail(404, 'entitlement_not_found', 'entitlement not found');
    }
    entitlement.status = 'revoked';
    entitlement.updatedAt = isoNow();
    audit(state, actor, 'entitlement.revoke', 'entitlement', entitlementId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/models\/[^/]+\/review$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'reviewer']);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = pathname.split('/')[6];
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    model.status = body.decision === 'reject' ? 'rejected' : body.status || 'listed';
    model.reviewNote = body.note || '';
    model.updatedAt = isoNow();
    const sku = model.status === 'listed' ? ensureDefaultSkuForModel(state, model, actor) : null;
    const review = {
      reviewId: `review-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      subjectType: 'model',
      subjectId: modelId,
      status: model.status === 'rejected' ? 'rejected' : 'approved',
      reviewerId: actor.userId,
      decisionNote: body.note || '',
      createdAt: isoNow(),
    };
    state.reviews.push(review);
    audit(state, actor, 'model.review', 'model', modelId, { status: model.status });
    await writeState(state);
    sendJson(res, 200, { ok: true, model, review, sku });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/models\/[^/]+\/publish$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'reviewer']);
    const modelId = pathname.split('/')[6];
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    model.status = 'listed';
    model.updatedAt = isoNow();
    const sku = ensureDefaultSkuForModel(state, model, actor);
    audit(state, actor, 'model.publish', 'model', modelId, { skuId: sku.skuId });
    await writeState(state);
    sendJson(res, 200, { ok: true, model, sku });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/models\/[^/]+\/delist$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'reviewer']);
    const modelId = pathname.split('/')[6];
    const model = getModel(state, modelId);
    if (!model) {
      fail(404, 'model_not_found', 'model not found');
    }
    model.status = 'delisted';
    model.delistReason = parseJsonBuffer(await readBody(req)).reason || '';
    model.updatedAt = isoNow();
    audit(state, actor, 'model.delist', 'model', modelId, { reason: model.delistReason });
    await writeState(state);
    sendJson(res, 200, { ok: true, model });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/platform/v1/devices') {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator']);
    const devices = isPlatformAdminRole(session.role)
      ? state.devices
      : state.devices.filter((device) => device.organizationId === session.organizationId);
    sendJson(res, 200, { devices });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/devices\/[^/]+\/block$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const deviceId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const device = state.devices.find((item) => item.deviceId === deviceId || item.deviceBindingId === deviceId);
    if (!device) {
      fail(404, 'device_not_found', 'device not found');
    }
    device.status = body.block === false ? 'active' : 'blocked';
    device.blockReason = body.reason || device.blockReason || '';
    device.updatedAt = isoNow();
    if (device.status === 'blocked') {
      state.leases
        .filter((lease) => lease.deviceId === device.deviceBindingId || lease.deviceId === device.deviceId)
        .forEach((lease) => {
          lease.status = 'revoked';
        });
    }
    audit(state, actor, device.status === 'blocked' ? 'device.block' : 'device.unblock', 'device', device.deviceId, { reason: device.blockReason });
    await writeState(state);
    sendJson(res, 200, { ok: true, device });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/support/tickets') {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator', 'developer_admin']);
    const body = parseJsonBuffer(await readBody(req));
    const ticket = {
      supportTicketId: `st-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      organizationId: session.organizationId,
      userId: session.userId,
      modelId: body.modelId || null,
      orderId: body.orderId || null,
      title: requiredString(body, 'title'),
      category: body.category || 'technical',
      priority: body.priority || 'normal',
      status: 'open',
      messages: [
        {
          messageId: `msg-${crypto.randomUUID().replace(/-/g, '').slice(0, 10)}`,
          actorUserId: session.userId,
          body: String(body.body || ''),
          createdAt: isoNow(),
        },
      ],
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    state.supportTickets.push(ticket);
    audit(state, session, 'support.create', 'support_ticket', ticket.supportTicketId, {});
    await writeState(state);
    sendJson(res, 201, { ok: true, ticket });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/support\/tickets\/[^/]+\/reply$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator', 'developer_admin']);
    const ticketId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const ticket = state.supportTickets.find((item) => item.supportTicketId === ticketId);
    if (!ticket) {
      fail(404, 'support_ticket_not_found', 'support ticket not found');
    }
    if (!canAccessSupportTicket(state, session, ticket)) {
      fail(403, 'forbidden', 'forbidden');
    }
    ticket.messages.push({
      messageId: `msg-${crypto.randomUUID().replace(/-/g, '').slice(0, 10)}`,
      actorUserId: session.userId,
      body: String(body.body || ''),
      createdAt: isoNow(),
    });
    ticket.status = body.status || (isPlatformAdminRole(session.role) ? 'waiting_customer' : 'waiting_support');
    ticket.updatedAt = isoNow();
    audit(state, session, 'support.reply', 'support_ticket', ticketId, { status: ticket.status });
    await writeState(state);
    sendJson(res, 200, { ok: true, ticket });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/custom-requests') {
    const session = requireAnyRole(state, req, ['buyer_admin', 'buyer_operator', 'super_admin', 'platform_ops', 'admin']);
    const body = parseJsonBuffer(await readBody(req));
    const request = {
      customRequestId: `cr-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      organizationId: session.organizationId,
      userId: session.userId,
      title: requiredString(body, 'title'),
      scenario: body.scenario || '',
      budgetAmount: money(body.budgetAmount || 0),
      currency: body.currency || 'CNY',
      dueAt: normalizeTimestamp(body.dueAt),
      status: 'open',
      proposals: [],
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    state.customRequests.push(request);
    audit(state, session, 'custom_request.create', 'custom_request', request.customRequestId, {});
    await writeState(state);
    sendJson(res, 201, { ok: true, request });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/custom-requests\/[^/]+\/proposal$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['developer_admin', 'super_admin', 'platform_ops', 'admin']);
    const requestId = pathname.split('/')[5];
    const body = parseJsonBuffer(await readBody(req));
    const request = state.customRequests.find((item) => item.customRequestId === requestId);
    if (!request) {
      fail(404, 'custom_request_not_found', 'custom request not found');
    }
    const developer = getDeveloperForSession(state, session) || (isPlatformAdminRole(session.role) ? state.developers[0] : null);
    if (!developer) {
      fail(404, 'developer_not_found', 'developer not found');
    }
    const proposal = {
      proposalId: `prop-${crypto.randomUUID().replace(/-/g, '').slice(0, 10)}`,
      developerId: developer.developerId,
      quoteAmount: money(body.quoteAmount || 0),
      currency: body.currency || request.currency || 'CNY',
      body: String(body.body || ''),
      status: 'submitted',
      createdAt: isoNow(),
    };
    request.proposals.push(proposal);
    request.status = 'proposal_submitted';
    request.updatedAt = isoNow();
    audit(state, session, 'custom_request.proposal', 'custom_request', requestId, { proposalId: proposal.proposalId });
    await writeState(state);
    sendJson(res, 200, { ok: true, request, proposal });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/custom-requests\/[^/]+\/proposals\/[^/]+\/accept$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['buyer_admin', 'super_admin', 'platform_ops', 'admin']);
    const parts = pathname.split('/');
    const requestId = parts[5];
    const proposalId = parts[7];
    const request = state.customRequests.find((item) => item.customRequestId === requestId);
    if (!request) {
      fail(404, 'custom_request_not_found', 'custom request not found');
    }
    if (!isPlatformAdminRole(session.role) && request.organizationId !== session.organizationId) {
      fail(403, 'forbidden', 'forbidden');
    }
    const proposal = request.proposals.find((item) => item.proposalId === proposalId);
    if (!proposal) {
      fail(404, 'proposal_not_found', 'proposal not found');
    }
    request.proposals.forEach((item) => {
      item.status = item.proposalId === proposalId ? 'accepted' : 'declined';
    });
    request.status = 'in_delivery';
    request.acceptedProposalId = proposalId;
    request.updatedAt = isoNow();
    audit(state, session, 'custom_request.accept_proposal', 'custom_request', requestId, { proposalId });
    await writeState(state);
    sendJson(res, 200, { ok: true, request, proposal });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/invoices') {
    const session = requireAnyRole(state, req, ['buyer_admin', 'super_admin', 'admin']);
    const body = parseJsonBuffer(await readBody(req));
    const order = state.orders.find((item) => item.orderId === body.orderId);
    if (!order) {
      fail(404, 'order_not_found', 'order not found');
    }
    if (order.buyerOrganizationId !== session.organizationId && !isPlatformAdminRole(session.role)) {
      fail(403, 'forbidden', 'forbidden');
    }
    const invoice = {
      invoiceId: `inv-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      orderId: order.orderId,
      organizationId: order.buyerOrganizationId,
      applicantUserId: session.userId,
      invoiceType: body.invoiceType || 'vat_normal',
      title: requiredString(body, 'title'),
      taxNumber: body.taxNumber || '',
      amount: money(body.amount || order.totalAmount),
      currency: order.currency || 'CNY',
      deliveryEmail: body.deliveryEmail || '',
      status: 'pending',
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    state.invoices.push(invoice);
    audit(state, session, 'invoice.request', 'invoice', invoice.invoiceId, { orderId: order.orderId });
    await writeState(state);
    sendJson(res, 201, { ok: true, invoice });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/invoices\/[^/]+\/review$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'finance']);
    const invoiceId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const invoice = state.invoices.find((item) => item.invoiceId === invoiceId);
    if (!invoice) {
      fail(404, 'invoice_not_found', 'invoice not found');
    }
    invoice.status = body.decision === 'reject' ? 'rejected' : body.status || 'issued';
    invoice.invoiceNo = body.invoiceNo || invoice.invoiceNo || `FP-${shortHash(invoiceId).toUpperCase()}`;
    invoice.reviewNote = body.note || '';
    invoice.updatedAt = isoNow();
    audit(state, actor, 'invoice.review', 'invoice', invoiceId, { status: invoice.status });
    await writeState(state);
    sendJson(res, 200, { ok: true, invoice });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/developer/withdrawals') {
    const session = requireAnyRole(state, req, ['developer_admin']);
    const body = parseJsonBuffer(await readBody(req));
    const developer = getDeveloperForSession(state, session);
    if (!developer) {
      fail(404, 'developer_not_found', 'developer not found');
    }
    const payable = state.settlements
      .filter((item) => item.developerId === developer.developerId && item.status === 'pending')
      .reduce((sum, item) => sum + Number(item.payableAmount || 0), 0);
    const amount = money(body.amount || payable);
    if (amount <= 0 || amount > payable) {
      fail(422, 'invalid_withdrawal_amount', 'invalid withdrawal amount');
    }
    const withdrawal = {
      withdrawalId: `wd-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      developerId: developer.developerId,
      organizationId: developer.organizationId,
      amount,
      currency: body.currency || 'CNY',
      accountName: body.accountName || developer.displayName,
      accountNo: body.accountNo || '',
      status: 'pending',
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    state.withdrawals.push(withdrawal);
    audit(state, session, 'withdrawal.request', 'withdrawal', withdrawal.withdrawalId, { amount });
    await writeState(state);
    sendJson(res, 201, { ok: true, withdrawal, payable });
    return;
  }

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/withdrawals\/[^/]+\/review$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'finance']);
    const withdrawalId = pathname.split('/')[6];
    const body = parseJsonBuffer(await readBody(req));
    const withdrawal = state.withdrawals.find((item) => item.withdrawalId === withdrawalId);
    if (!withdrawal) {
      fail(404, 'withdrawal_not_found', 'withdrawal not found');
    }
    withdrawal.status = body.decision === 'reject' ? 'rejected' : 'paid';
    withdrawal.reviewNote = body.note || '';
    withdrawal.updatedAt = isoNow();
    if (withdrawal.status === 'paid') {
      let remaining = withdrawal.amount;
      for (const settlement of state.settlements.filter((item) => item.developerId === withdrawal.developerId && item.status === 'pending')) {
        if (remaining <= 0) {
          break;
        }
        settlement.status = 'paid';
        settlement.withdrawalId = withdrawal.withdrawalId;
        settlement.updatedAt = isoNow();
        remaining -= Number(settlement.payableAmount || 0);
      }
    }
    audit(state, actor, 'withdrawal.review', 'withdrawal', withdrawalId, { status: withdrawal.status });
    await writeState(state);
    sendJson(res, 200, { ok: true, withdrawal });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/coupons') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const coupon = {
      couponId: body.couponId || `cp-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      code: requiredString(body, 'code').toUpperCase(),
      name: body.name || body.code,
      discountType: body.discountType || 'amount',
      discountValue: money(body.discountValue || 0),
      startsAt: normalizeTimestamp(body.startsAt) || isoNow(),
      endsAt: normalizeTimestamp(body.endsAt),
      usageLimit: Number(body.usageLimit || 0),
      status: body.status || 'active',
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    const existingIndex = state.coupons.findIndex((item) => item.couponId === coupon.couponId || item.code === coupon.code);
    if (existingIndex >= 0) {
      state.coupons[existingIndex] = { ...state.coupons[existingIndex], ...coupon, createdAt: state.coupons[existingIndex].createdAt };
    } else {
      state.coupons.push(coupon);
    }
    audit(state, actor, 'coupon.upsert', 'coupon', coupon.couponId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, coupon });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/activities') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const activity = {
      activityId: body.activityId || `act-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      title: requiredString(body, 'title'),
      description: body.description || '',
      placement: body.placement || 'home',
      startsAt: normalizeTimestamp(body.startsAt) || isoNow(),
      endsAt: normalizeTimestamp(body.endsAt),
      status: body.status || 'active',
      createdAt: isoNow(),
      updatedAt: isoNow(),
    };
    const existingIndex = state.activities.findIndex((item) => item.activityId === activity.activityId);
    if (existingIndex >= 0) {
      state.activities[existingIndex] = { ...state.activities[existingIndex], ...activity, createdAt: state.activities[existingIndex].createdAt };
    } else {
      state.activities.push(activity);
    }
    audit(state, actor, 'activity.upsert', 'activity', activity.activityId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, activity });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/categories') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    const category = {
      categoryId: body.categoryId || `cat-${slugify(body.name || body.slug)}`,
      name: requiredString(body, 'name'),
      slug: slugify(body.slug || body.name),
      status: body.status || 'active',
      updatedAt: isoNow(),
    };
    const existingIndex = state.categories.findIndex((item) => item.categoryId === category.categoryId || item.slug === category.slug);
    if (existingIndex >= 0) {
      state.categories[existingIndex] = { ...state.categories[existingIndex], ...category };
    } else {
      state.categories.push({ ...category, createdAt: isoNow() });
    }
    audit(state, actor, 'category.upsert', 'category', category.categoryId, {});
    await writeState(state);
    sendJson(res, 200, { ok: true, category });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/platform/v1/admin/settings') {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const body = parseJsonBuffer(await readBody(req));
    state.platformSettings = {
      ...state.platformSettings,
      ...Object.fromEntries(Object.entries(body).filter(([, value]) => value !== undefined)),
    };
    audit(state, actor, 'settings.update', 'platform_settings', 'default', body);
    await writeState(state);
    sendJson(res, 200, { ok: true, platformSettings: state.platformSettings });
    return;
  }

  if (req.method === 'GET' && (pathname === '/api/cloud/v1/models' || pathname === '/api/platform/v1/terminal/models')) {
    const session = requireSession(state, req);
    const models = await listEntitledModels(state, session);
    await writeState(state);
    sendJson(res, 200, { models, syncedAt: isoNow() });
    return;
  }

  if (req.method === 'POST' && /^\/api\/cloud\/v1\/models\/[^/]+\/download-ticket$/.test(pathname)) {
    const session = requireSession(state, req);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = pathname.split('/')[5];
    const model = getModel(state, modelId);
    if (!model || !['listed', 'approved'].includes(model.status)) {
      fail(404, 'model_not_found', 'model not found');
    }
    const entitlement = findEntitlementForModel(state, session, modelId, { includeExpired: true });
    if (!entitlement) {
      fail(403, 'entitlement_not_found', 'model is not assigned to current user');
    }
    if (!isEntitlementRenewable(entitlement)) {
      fail(403, 'entitlement_expired', 'entitlement renewal window has ended');
    }
    const build = getBuildForModel(state, model);
    if (!build) {
      fail(404, 'model_build_not_found', 'model build not found');
    }
    const artifact = await getModelArtifact(build);
    build.sha256 = artifact.sha256;
    build.byteCount = artifact.byteCount;
    const deviceId = String(body.deviceId || session.deviceId || 'unknown-device');
    const device = upsertDevice(state, session, deviceId, body.deviceName || session.deviceName, session.platform);
    if (device.status === 'blocked') {
      fail(403, 'device_blocked', 'device is blocked');
    }
    ensureDeviceCanUseEntitlement(state, entitlement, deviceId);
    const lease = upsertLease(state, entitlement, session, deviceId);
    const ticket = {
      ticketId: crypto.randomUUID().replace(/-/g, ''),
      entitlementId: entitlement.entitlementId,
      userId: session.userId,
      modelId,
      organizationId: session.organizationId,
      deviceId,
      expiresAt: new Date(Date.now() + Number(state.platformSettings.downloadTicketMinutes || 15) * 60 * 1000).toISOString(),
      fileName: build.fileName,
      sourceFormat: build.sourceFormat,
      transportFormat: build.transportFormat,
      sha256: artifact.sha256,
      byteCount: artifact.byteCount,
      modelBuildId: build.modelBuildId,
      isEncrypted: build.isEncrypted !== false,
      ticketSecret: crypto.randomBytes(32).toString('hex'),
      status: 'issued',
      createdAt: isoNow(),
      license: buildModelLicense(entitlement, lease, deviceId),
    };
    state.tickets.push(ticket);
    audit(state, session, 'download_ticket.issue', 'download_ticket', ticket.ticketId, { modelId });
    await writeState(state);
    sendJson(res, 200, {
      ticketId: ticket.ticketId,
      modelId: ticket.modelId,
      organizationId: ticket.organizationId,
      deviceId: ticket.deviceId,
      expiresAt: ticket.expiresAt,
      fileName: ticket.fileName,
      sourceFormat: ticket.sourceFormat,
      transportFormat: ticket.transportFormat,
      sha256: ticket.sha256,
      byteCount: ticket.byteCount,
      modelBuildId: ticket.modelBuildId,
      isEncrypted: ticket.isEncrypted,
      license: ticket.license,
      encryption: ticket.isEncrypted ? {
        envelope: 'vino-aesgcm-v1',
        algorithm: ENCRYPTION_ALGORITHM,
        keyDerivation: 'sha256(ticketSecret:modelId:deviceId:modelBuildId)',
        ticketSecret: ticket.ticketSecret,
      } : null,
      downloadURL: `${requestBaseUrl(req)}/api/cloud/v1/download/${ticket.ticketId}`,
    });
    return;
  }

  if (req.method === 'GET' && /^\/api\/cloud\/v1\/download\/[^/]+$/.test(pathname)) {
    const ticketId = pathname.split('/').pop();
    const ticket = state.tickets.find((item) => item.ticketId === ticketId);
    if (!ticket || ticket.status === 'revoked' || new Date(ticket.expiresAt).getTime() <= Date.now()) {
      fail(404, 'download_ticket_expired', 'download ticket expired');
    }
    const device = findDeviceByBinding(state, ticket.organizationId, ticket.deviceId);
    if (device?.status === 'blocked') {
      fail(403, 'device_blocked', 'device is blocked');
    }
    const model = getModel(state, ticket.modelId);
    const build = model ? getBuildForModel(state, model) : null;
    if (!model || !build) {
      fail(404, 'model_not_found', 'model not found');
    }
    const artifact = await getModelArtifact(build);
    ticket.status = 'used';
    ticket.usedAt = isoNow();
    audit(state, null, 'download_ticket.used', 'download_ticket', ticket.ticketId, { modelId: ticket.modelId });
    await writeState(state);
    if (ticket.isEncrypted) {
      const envelope = await buildEncryptedEnvelopeFile(artifact, ticket);
      sendFile(res, 200, envelope.filePath, envelope.byteCount, 'application/octet-stream', () => {
        fs.rm(envelope.filePath, { force: true }).catch(() => {});
      });
    } else {
      sendFile(res, 200, artifact.cachePath, artifact.byteCount);
    }
    return;
  }

  if (req.method === 'POST' && pathname === '/api/cloud/v1/licenses/lease/renew') {
    const session = requireSession(state, req);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = requiredString(body, 'modelId');
    const entitlement = findEntitlementForModel(state, session, modelId, { includeExpired: true });
    if (!entitlement) {
      fail(404, 'license_not_found', 'license not found for current user');
    }
    if (!isEntitlementRenewable(entitlement)) {
      fail(403, 'entitlement_expired', 'entitlement renewal window has ended');
    }
    const deviceId = body.deviceId || session.deviceId || 'unknown-device';
    const device = upsertDevice(state, session, deviceId, body.deviceName || session.deviceName, session.platform);
    if (device.status === 'blocked') {
      fail(403, 'device_blocked', 'device is blocked');
    }
    ensureDeviceCanUseEntitlement(state, entitlement, deviceId);
    const lease = upsertLease(state, entitlement, session, deviceId);
    audit(state, session, 'lease.renew', 'offline_lease', lease.leaseId, { modelId });
    await writeState(state);
    sendJson(res, 200, {
      modelId,
      licenseId: lease.licenseId,
      leaseExpiresAt: lease.leaseExpiresAt,
      policyFlags: lease.policyFlags,
      deviceBindingId: lease.deviceId,
    });
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/asset' || pathname === '/api/platform/v1/ingest/asset')) {
    await handleIngest(state, req, res, 'asset');
    return;
  }

  if (req.method === 'GET' && /^\/api\/platform\/v1\/admin\/ingest\/(assets|results|logs|stats)$/.test(pathname)) {
    const session = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops']);
    const collectionName = pathname.split('/').pop();
    sendJson(res, 200, { [collectionName]: state.ingests[collectionName] || [], viewer: publicUser(session) });
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/result' || pathname === '/api/platform/v1/ingest/result' || pathname === '/uploadData')) {
    await handleIngest(state, req, res, 'result');
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/log' || pathname === '/api/platform/v1/ingest/log' || pathname === '/uploadLog')) {
    await handleIngest(state, req, res, 'log');
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/stat' || pathname === '/api/platform/v1/ingest/stat' || pathname === '/uploadStat')) {
    await handleIngest(state, req, res, 'stat');
    return;
  }

  sendError(res, 404, 'not_found', 'route not found');
}

const server = http.createServer((req, res) => {
  res.requestId = requestIdFromRequest(req);
  handleRoute(req, res).catch((error) => {
    const statusCode = error.statusCode || 500;
    if (statusCode >= 500) {
      console.error(`[${res.requestId}]`, error);
    }
    sendError(res, statusCode, error.code || 'internal_error', error.message || 'internal error', error.details);
  });
});

server.listen(PORT, HOST, () => {
  console.log(`vino_platform listening on http://${HOST}:${PORT}`);
  console.log(`vino_platform data root: ${DATA_ROOT}`);
  console.log(`vino_platform models root: ${MODELS_ROOT}`);
  console.log(`vino_platform rate limit: ${RATE_LIMIT_ENABLED ? `${RATE_LIMIT_MAX}/${RATE_LIMIT_WINDOW_MS}ms` : 'disabled'}`);
});
