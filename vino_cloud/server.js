const http = require('node:http');
const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { URL } = require('node:url');

const PORT = Number(process.env.PORT || 8787);
const ROOT = __dirname;
const REPO_ROOT = path.resolve(ROOT, '..');
const DATA_ROOT = path.join(ROOT, 'data');
const PUBLIC_ROOT = path.join(ROOT, 'public');
const STATE_PATH = path.join(DATA_ROOT, 'state.json');
const INGEST_ASSET_ROOT = path.join(DATA_ROOT, 'assets');
const MODELS_ROOT = path.join(REPO_ROOT, 'models');
const ARCHIVE_CACHE = new Map();
const ENCRYPTION_ENVELOPE_MAGIC = Buffer.from('VINOENC1', 'utf8');
const ENCRYPTION_ALGORITHM = 'aes-256-gcm';

function isoNow() {
  return new Date().toISOString();
}

function slugify(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'model';
}

function shortHash(value) {
  return crypto.createHash('sha1').update(String(value)).digest('hex').slice(0, 12);
}

function plusDays(days) {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
}

function normalizeTimestamp(value) {
  if (value == null || value === '') {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function firstUserInOrganization(users, organizationId) {
  return users.find((user) => user.organizationId === organizationId) || null;
}

function normalizeUserRecord(user, index) {
  const normalized = { ...user };
  normalized.userId = normalized.userId || `user-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`;
  normalized.email = String(normalized.email || '').trim().toLowerCase();
  normalized.password = String(normalized.password || 'demo123');
  normalized.displayName = String(normalized.displayName || normalized.email || `User ${index + 1}`);
  normalized.organizationId = String(normalized.organizationId || 'org-demo-001');
  normalized.organizationName = String(normalized.organizationName || 'Vino Demo Factory');
  normalized.role = normalized.role === 'admin' ? 'admin' : index === 0 ? 'admin' : 'member';
  return normalized;
}

function ensureBuiltinAdminUser(users) {
  const adminEmail = 'admin';
  const existing = users.find((user) => user.email === adminEmail);
  if (existing) {
    existing.password = 'meiyoumima';
    existing.displayName = 'Cloud Admin';
    existing.organizationId = existing.organizationId || 'org-demo-001';
    existing.organizationName = existing.organizationName || 'Vino Demo Factory';
    existing.role = 'admin';
    return;
  }

  users.push({
    userId: 'user-admin-001',
    email: adminEmail,
    password: 'meiyoumima',
    displayName: 'Cloud Admin',
    organizationId: 'org-demo-001',
    organizationName: 'Vino Demo Factory',
    role: 'admin',
  });
}

function normalizeEntitlementRecord(item, users) {
  const organizationId = String(
    item.organizationId
    || users.find((user) => user.userId === item.userId)?.organizationId
    || 'org-demo-001'
  );
  const fallbackUser = firstUserInOrganization(users, organizationId);
  let assignedToType = item.assignedToType === 'organization' || item.assignedToType === 'user'
    ? item.assignedToType
    : (item.userId || item.assignedToId || fallbackUser ? 'user' : 'organization');
  let assignedToId = String(
    item.assignedToId
    || item.userId
    || (assignedToType === 'user' ? fallbackUser?.userId || '' : organizationId)
  );
  if (assignedToType === 'user' && !users.some((user) => user.userId === assignedToId)) {
    assignedToType = 'organization';
    assignedToId = organizationId;
  }

  const renewalMode = item.renewalMode === 'fixed' || item.renewalEndsAt ? 'fixed' : 'perpetual';
  const renewalEndsAt = renewalMode === 'fixed'
    ? normalizeTimestamp(item.renewalEndsAt || item.leaseExpiresAt || item.contractEndsAt)
    : null;
  const createdAt = normalizeTimestamp(item.createdAt) || isoNow();
  const updatedAt = normalizeTimestamp(item.updatedAt) || createdAt;

  return {
    entitlementId: String(
      item.entitlementId
      || `ent-${shortHash(`${organizationId}:${item.modelId}:${assignedToType}:${assignedToId}:${item.licenseId || ''}`)}`
    ),
    organizationId,
    modelId: String(item.modelId || ''),
    assignedToType,
    assignedToId,
    licenseId: String(item.licenseId || `lic-${item.modelId || 'model'}-${shortHash(`${assignedToType}:${assignedToId}`)}`),
    renewalMode,
    renewalEndsAt,
    leaseDays: Number(item.leaseDays || 14),
    policyFlags: Array.isArray(item.policyFlags) ? item.policyFlags : ['offline', 'device-bound'],
    deviceBindingRequired: item.deviceBindingRequired !== false,
    isActive: item.isActive !== false,
    createdAt,
    updatedAt,
  };
}

function dedupeEntitlements(entitlements) {
  const deduped = new Map();
  const sorted = [...entitlements].sort((left, right) =>
    String(right.updatedAt || right.createdAt || '').localeCompare(String(left.updatedAt || left.createdAt || ''))
  );

  for (const entitlement of sorted) {
    const key = [entitlement.modelId, entitlement.assignedToType, entitlement.assignedToId].join(':');
    if (!deduped.has(key)) {
      deduped.set(key, entitlement);
    }
  }

  return Array.from(deduped.values());
}

function normalizeLeaseRecord(lease, entitlements) {
  const matchedEntitlement = entitlements.find((item) =>
    (lease.entitlementId && item.entitlementId === lease.entitlementId)
    || (
      item.organizationId === lease.organizationId
      && item.modelId === lease.modelId
      && item.licenseId === lease.licenseId
    )
  );
  return {
    entitlementId: lease.entitlementId || matchedEntitlement?.entitlementId || null,
    organizationId: lease.organizationId || matchedEntitlement?.organizationId || 'org-demo-001',
    userId: lease.userId || (matchedEntitlement?.assignedToType === 'user' ? matchedEntitlement.assignedToId : null),
    modelId: lease.modelId || matchedEntitlement?.modelId || '',
    deviceId: lease.deviceId || 'unknown-device',
    licenseId: lease.licenseId || matchedEntitlement?.licenseId || 'lic-unknown',
    leaseExpiresAt: normalizeTimestamp(lease.leaseExpiresAt),
    policyFlags: Array.isArray(lease.policyFlags) ? lease.policyFlags : [],
    renewedAt: normalizeTimestamp(lease.renewedAt || lease.createdAt) || isoNow(),
  };
}

function sendJson(res, statusCode, payload) {
  const body = Buffer.from(JSON.stringify(payload, null, 2));
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': body.length,
    'Access-Control-Allow-Origin': '*',
  });
  res.end(body);
}

function sendBuffer(res, statusCode, buffer, contentType = 'application/octet-stream') {
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Content-Length': buffer.length,
    'Access-Control-Allow-Origin': '*',
  });
  res.end(buffer);
}

function notFound(res) {
  sendJson(res, 404, { error: 'route not found' });
}

function normalizePathname(requestUrl) {
  const url = new URL(requestUrl, `http://127.0.0.1:${PORT}`);
  return url.pathname;
}

async function ensureDirs() {
  await fs.mkdir(DATA_ROOT, { recursive: true });
  await fs.mkdir(INGEST_ASSET_ROOT, { recursive: true });
}

async function discoverCoreMLModels() {
  if (!fsSync.existsSync(MODELS_ROOT)) {
    return [];
  }

  const priorityByFormat = {
    mlpackage: 3,
    mlmodel: 2,
    mlmodelc: 1,
  };
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
        const relative = path.relative(REPO_ROOT, absolute).split(path.sep).join('/');
        const stats = await fs.stat(absolute);
        const baseName = path.basename(entry.name, extension);
        const modelSlug = slugify(baseName);
        const buildHash = shortHash(`${relative}:${stats.mtimeMs}:${stats.size}`);
        discovered.push({
          id: `${modelSlug}-${shortHash(relative).slice(0, 8)}`,
          name: baseName || 'Imported Model',
          version: '1.0.0',
          summary: `自动发现的 CoreML 模型：${relative}`,
          organizationId: 'org-demo-001',
          modelBuildId: `build-${modelSlug}-${buildHash}`,
          sourcePath: relative,
          fileName: entry.name,
          sourceFormat: extension.slice(1),
          transportFormat: entry.isDirectory() ? 'bundle-archive' : 'raw-file',
          supportedPlatforms: ['ios'],
          tags: ['imported', 'coreml'],
          isEncrypted: true,
        });
        continue;
      }

      if (entry.isDirectory()) {
        queue.push(absolute);
      }
    }
  }

  const deduped = new Map();
  for (const model of discovered) {
    const dedupKey = model.sourcePath.replace(/\.(mlpackage|mlmodel|mlmodelc)$/i, '');
    const existing = deduped.get(dedupKey);
    if (!existing || (priorityByFormat[model.sourceFormat] || 0) > (priorityByFormat[existing.sourceFormat] || 0)) {
      deduped.set(dedupKey, model);
    }
  }

  return Array.from(deduped.values()).sort((left, right) => left.name.localeCompare(right.name));
}

function seedState() {
  return {
    users: [
      {
        userId: 'user-demo-001',
        email: 'demo@vino.cc',
        password: 'demo123',
        displayName: 'Demo Operator',
        organizationId: 'org-demo-001',
        organizationName: 'Vino Demo Factory',
        role: 'admin',
      },
      {
        userId: 'user-admin-001',
        email: 'admin',
        password: 'meiyoumima',
        displayName: 'Cloud Admin',
        organizationId: 'org-demo-001',
        organizationName: 'Vino Demo Factory',
        role: 'admin',
      },
    ],
    models: [
      {
        id: 'yolov8n-demo',
        name: 'YOLOv8n Demo',
        version: '1.0.0',
        summary: '演示用通用检测模型，适合走通 iPhone 下载与租约链路。',
        organizationId: 'org-demo-001',
        modelBuildId: 'build-yolov8n-20260407',
        sourcePath: 'models/yolov8n.mlpackage',
        fileName: 'yolov8n.mlpackage',
        sourceFormat: 'mlpackage',
        transportFormat: 'bundle-archive',
        supportedPlatforms: ['ios'],
        tags: ['demo', 'coreml', 'industrial'],
        isEncrypted: true,
      },
    ],
    entitlements: [
      {
        entitlementId: 'ent-demo-yolov8n',
        organizationId: 'org-demo-001',
        modelId: 'yolov8n-demo',
        assignedToType: 'user',
        assignedToId: 'user-demo-001',
        licenseId: 'lic-demo-yolov8n',
        renewalMode: 'perpetual',
        renewalEndsAt: null,
        policyFlags: ['offline', 'device-bound'],
        deviceBindingRequired: true,
        isActive: true,
        createdAt: isoNow(),
        updatedAt: isoNow(),
      },
    ],
    sessions: [],
    tickets: [],
    leases: [],
    ingests: {
      assets: [],
      results: [],
      logs: [],
      stats: [],
    },
  };
}

function normalizeState(state) {
  const normalized = { ...state };
  normalized.users = Array.isArray(state.users)
    ? state.users.map((user, index) => normalizeUserRecord(user, index))
    : [];
  ensureBuiltinAdminUser(normalized.users);
  if (normalized.users.length > 0 && !normalized.users.some((user) => user.role === 'admin')) {
    normalized.users[0].role = 'admin';
  }
  normalized.models = Array.isArray(state.models) ? state.models.map((model) => ({
    ...model,
    isEncrypted: model.id === 'yolov8n-demo' ? true : Boolean(model.isEncrypted),
  })) : [];
  normalized.entitlements = Array.isArray(state.entitlements)
    ? state.entitlements
      .map((item) => normalizeEntitlementRecord(item, normalized.users))
      .filter((item) => item.modelId)
    : [];
  normalized.entitlements = dedupeEntitlements(normalized.entitlements);
  normalized.sessions = Array.isArray(state.sessions) ? state.sessions : [];
  normalized.tickets = Array.isArray(state.tickets) ? state.tickets : [];
  normalized.leases = Array.isArray(state.leases)
    ? state.leases.map((lease) => normalizeLeaseRecord(lease, normalized.entitlements))
    : [];
  normalized.ingests = {
    assets: Array.isArray(state.ingests?.assets) ? state.ingests.assets : [],
    results: Array.isArray(state.ingests?.results) ? state.ingests.results : [],
    logs: Array.isArray(state.ingests?.logs) ? state.ingests.logs : [],
    stats: Array.isArray(state.ingests?.stats) ? state.ingests.stats : [],
  };
  return normalized;
}

async function readState() {
  await ensureDirs();
  if (!fsSync.existsSync(STATE_PATH)) {
    const initial = seedState();
    await writeState(initial);
    return initial;
  }
  const raw = await fs.readFile(STATE_PATH, 'utf8');
  const parsed = JSON.parse(raw);
  const normalized = normalizeState(parsed);
  const discoveredModels = await discoverCoreMLModels();
  const discoveredByPath = new Map(discoveredModels.map((model) => [model.sourcePath, model]));
  const mergedModels = [];
  const seenPaths = new Set();

  for (const model of normalized.models) {
    const discovered = discoveredByPath.get(model.sourcePath);
    if (discovered) {
      mergedModels.push({
        ...model,
        ...discovered,
        tags: Array.from(new Set([...(model.tags || []), ...(discovered.tags || [])])),
        isEncrypted: true,
      });
      seenPaths.add(model.sourcePath);
    } else {
      mergedModels.push(model);
    }
  }

  for (const model of discoveredModels) {
    if (!seenPaths.has(model.sourcePath)) {
      mergedModels.push(model);
    }
  }

  normalized.models = mergedModels;
  const knownModelIDs = new Set(normalized.models.map((model) => model.id));
  normalized.entitlements = normalized.entitlements.filter((item) => knownModelIDs.has(item.modelId));
  normalized.leases = normalized.leases.filter((item) => knownModelIDs.has(item.modelId));
  normalized.tickets = normalized.tickets.filter((item) => knownModelIDs.has(item.modelId));
  if (JSON.stringify(normalized) !== JSON.stringify(parsed)) {
    await writeState(normalized);
  }
  return normalized;
}

async function writeState(state) {
  await ensureDirs();
  const tempPath = `${STATE_PATH}.${process.pid}.${Date.now()}.${crypto.randomUUID()}.tmp`;
  await fs.writeFile(tempPath, JSON.stringify(state, null, 2));
  await fs.rename(tempPath, STATE_PATH);
}

async function readBody(req, limitBytes = 200 * 1024 * 1024) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > limitBytes) {
      throw new Error('payload too large');
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
  if (!raw.startsWith('Bearer ')) {
    return '';
  }
  return raw.slice('Bearer '.length).trim();
}

function getSessionFromToken(state, token) {
  if (!token) {
    return null;
  }
  const session = state.sessions.find((item) => item.accessToken === token);
  if (!session) {
    return null;
  }
  if (new Date(session.expiresAt).getTime() <= Date.now()) {
    return null;
  }
  return session;
}

function requireSession(state, req) {
  const session = getSessionFromToken(state, authTokenFromRequest(req));
  if (!session) {
    const error = new Error('unauthorized');
    error.statusCode = 401;
    throw error;
  }
  return session;
}

function requireAdminSession(state, req) {
  const session = requireSession(state, req);
  const user = state.users.find((item) => item.userId === session.userId);
  const role = session.role || user?.role;
  if (role !== 'admin') {
    const error = new Error('admin access required');
    error.statusCode = 403;
    throw error;
  }
  return session;
}

function hashHex(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
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

function buildEncryptedEnvelope(plaintext, ticket) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ENCRYPTION_ALGORITHM, deriveTicketKey(ticket), iv);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
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
  header.writeUInt32LE(tag.length, offset);
  offset += 4;
  header.writeBigUInt64LE(BigInt(ciphertext.length), offset);

  return Buffer.concat([header, algorithmBuffer, iv, tag, ciphertext]);
}

async function collectArchiveEntries(rootPath, basePath = rootPath) {
  const stat = await fs.stat(rootPath);
  if (stat.isFile()) {
    return [
      {
        relativePath: path.basename(rootPath),
        bytes: await fs.readFile(rootPath),
      },
    ];
  }

  const entries = [];
  const children = await fs.readdir(rootPath, { withFileTypes: true });
  const sorted = [...children].sort((a, b) => a.name.localeCompare(b.name));
  for (const child of sorted) {
    const absolute = path.join(rootPath, child.name);
    if (child.isDirectory()) {
      entries.push(...await collectArchiveEntries(absolute, basePath));
    } else if (child.isFile()) {
      entries.push({
        relativePath: path.relative(basePath, absolute).split(path.sep).join('/'),
        bytes: await fs.readFile(absolute),
      });
    }
  }
  return entries;
}

function buildBundleArchive(entries) {
  const magic = Buffer.from('VINOAR01', 'utf8');
  const header = Buffer.alloc(magic.length + 4 + 4);
  magic.copy(header, 0);
  header.writeUInt32LE(1, magic.length);
  header.writeUInt32LE(entries.length, magic.length + 4);

  const parts = [header];
  for (const entry of entries) {
    const pathBuffer = Buffer.from(entry.relativePath, 'utf8');
    const entryHeader = Buffer.alloc(4 + 8);
    entryHeader.writeUInt32LE(pathBuffer.length, 0);
    entryHeader.writeBigUInt64LE(BigInt(entry.bytes.length), 4);
    parts.push(entryHeader, pathBuffer, entry.bytes);
  }
  return Buffer.concat(parts);
}

async function getModelArtifact(model) {
  const cacheKey = `${model.id}:${model.modelBuildId}`;
  const cached = ARCHIVE_CACHE.get(cacheKey);
  if (cached) {
    return cached;
  }

  const sourceAbsolute = path.join(REPO_ROOT, model.sourcePath);
  const stats = await fs.stat(sourceAbsolute);
  let bytes;
  if (stats.isDirectory() || model.transportFormat === 'bundle-archive') {
    const entries = await collectArchiveEntries(sourceAbsolute);
    bytes = buildBundleArchive(entries);
  } else {
    bytes = await fs.readFile(sourceAbsolute);
  }

  const artifact = {
    bytes,
    sha256: hashHex(bytes),
    byteCount: bytes.length,
  };
  ARCHIVE_CACHE.set(cacheKey, artifact);
  return artifact;
}

function entitlementAppliesToSession(entitlement, session) {
  if (!entitlement || entitlement.organizationId !== session.organizationId || entitlement.isActive === false) {
    return false;
  }
  if (entitlement.assignedToType === 'user') {
    return entitlement.assignedToId === session.userId;
  }
  return entitlement.assignedToId === session.organizationId;
}

function isEntitlementRenewable(entitlement, now = Date.now()) {
  if (!entitlement || entitlement.isActive === false) {
    return false;
  }
  if (entitlement.renewalMode !== 'fixed') {
    return true;
  }
  if (!entitlement.renewalEndsAt) {
    return false;
  }
  return new Date(entitlement.renewalEndsAt).getTime() > now;
}

function resolveEntitlementLeaseExpiry(entitlement) {
  return entitlement.renewalMode === 'fixed' ? entitlement.renewalEndsAt || null : null;
}

function entitlementPriority(entitlement) {
  return entitlement.assignedToType === 'user' ? 2 : 1;
}

function sortEntitlements(left, right) {
  const priorityDelta = entitlementPriority(right) - entitlementPriority(left);
  if (priorityDelta !== 0) {
    return priorityDelta;
  }
  return String(right.updatedAt || '').localeCompare(String(left.updatedAt || ''));
}

function findEntitlementForModel(state, session, modelId, options = {}) {
  const includeExpired = Boolean(options.includeExpired);
  const candidates = state.entitlements
    .filter((item) => item.modelId === modelId && entitlementAppliesToSession(item, session))
    .filter((item) => includeExpired || isEntitlementRenewable(item))
    .sort(sortEntitlements);
  return candidates[0] || null;
}

function findLease(state, entitlement, session, deviceId) {
  return state.leases.find((lease) =>
    (lease.entitlementId === entitlement.entitlementId
      || (
        !lease.entitlementId
        && lease.organizationId === entitlement.organizationId
        && lease.modelId === entitlement.modelId
        && lease.licenseId === entitlement.licenseId
      ))
    && lease.deviceId === deviceId
    && (lease.userId || null) === (session.userId || null)
  ) || null;
}

function upsertLease(state, entitlement, session, deviceId) {
  const leaseExpiresAt = resolveEntitlementLeaseExpiry(entitlement);
  const existing = findLease(state, entitlement, session, deviceId);
  if (existing) {
    existing.entitlementId = entitlement.entitlementId;
    existing.organizationId = entitlement.organizationId;
    existing.userId = session.userId || null;
    existing.modelId = entitlement.modelId;
    existing.deviceId = deviceId;
    existing.licenseId = entitlement.licenseId;
    existing.leaseExpiresAt = leaseExpiresAt;
    existing.policyFlags = entitlement.policyFlags || [];
    existing.renewedAt = isoNow();
    return existing;
  }

  const created = {
    entitlementId: entitlement.entitlementId,
    organizationId: entitlement.organizationId,
    userId: session.userId || null,
    modelId: entitlement.modelId,
    deviceId,
    licenseId: entitlement.licenseId,
    leaseExpiresAt,
    policyFlags: entitlement.policyFlags || [],
    renewedAt: isoNow(),
  };
  state.leases.push(created);
  return created;
}

function buildModelLicense(entitlement, lease, deviceId) {
  return {
    licenseId: entitlement.licenseId,
    leaseExpiresAt: lease ? lease.leaseExpiresAt : resolveEntitlementLeaseExpiry(entitlement),
    policyFlags: lease ? lease.policyFlags : entitlement.policyFlags || [],
    deviceBindingRequired: Boolean(entitlement.deviceBindingRequired),
    deviceBindingId: deviceId || null,
    renewalMode: entitlement.renewalMode,
    renewalEndsAt: entitlement.renewalEndsAt || null,
  };
}

async function listEntitledModels(state, session) {
  const models = state.models.filter((model) => model.organizationId === session.organizationId);
  const enriched = [];
  for (const model of models) {
    const entitlement = findEntitlementForModel(state, session, model.id);
    if (!entitlement) {
      continue;
    }
    const artifact = await getModelArtifact(model);
    const lease = findLease(state, entitlement, session, session.deviceId || 'unknown-device');
    enriched.push({
      id: model.id,
      name: model.name,
      version: model.version,
      summary: model.summary,
      organizationId: model.organizationId,
      modelBuildId: model.modelBuildId,
      fileName: model.fileName,
      sourceFormat: model.sourceFormat,
      transportFormat: model.transportFormat,
      sha256: artifact.sha256,
      byteCount: artifact.byteCount,
      isEncrypted: Boolean(model.isEncrypted),
      supportedPlatforms: model.supportedPlatforms,
      tags: model.tags,
      license: buildModelLicense(entitlement, lease, session.deviceId || null),
    });
  }
  return enriched;
}

function publicUser(user) {
  return {
    userId: user.userId,
    email: user.email,
    displayName: user.displayName,
    organizationId: user.organizationId,
    organizationName: user.organizationName,
    role: user.role,
  };
}

async function buildAdminOverview(state) {
  const models = await Promise.all(state.models.map(async (model) => {
    const artifact = await getModelArtifact(model);
    const entitlements = state.entitlements.filter((item) => item.modelId === model.id);
    return {
      id: model.id,
      name: model.name,
      version: model.version,
      summary: model.summary,
      organizationId: model.organizationId,
      modelBuildId: model.modelBuildId,
      fileName: model.fileName,
      sourceFormat: model.sourceFormat,
      transportFormat: model.transportFormat,
      sha256: artifact.sha256,
      byteCount: artifact.byteCount,
      isEncrypted: Boolean(model.isEncrypted),
      supportedPlatforms: model.supportedPlatforms,
      tags: model.tags,
      assignmentCount: entitlements.length,
      userAssignmentCount: entitlements.filter((item) => item.assignedToType === 'user').length,
      organizationAssignmentCount: entitlements.filter((item) => item.assignedToType === 'organization').length,
    };
  }));

  const entitlements = state.entitlements
    .map((entitlement) => {
      const user = state.users.find((item) => item.userId === entitlement.assignedToId);
      const model = state.models.find((item) => item.id === entitlement.modelId);
      return {
        ...entitlement,
        assignedToLabel: entitlement.assignedToType === 'user'
          ? `${user?.displayName || entitlement.assignedToId} · ${user?.email || 'unknown'}`
          : entitlement.organizationId,
        modelName: model?.name || entitlement.modelId,
        isRenewableNow: isEntitlementRenewable(entitlement),
        effectiveLeaseExpiresAt: resolveEntitlementLeaseExpiry(entitlement),
      };
    })
    .sort(sortEntitlements);

  const activeLeases = state.leases.filter((lease) => !lease.leaseExpiresAt || new Date(lease.leaseExpiresAt).getTime() > Date.now());

  return {
    service: 'vino_cloud',
    now: isoNow(),
    summary: {
      ...ingestSummary(state),
      entitlements: state.entitlements.length,
      perpetualEntitlements: state.entitlements.filter((item) => item.renewalMode !== 'fixed').length,
      fixedEntitlements: state.entitlements.filter((item) => item.renewalMode === 'fixed').length,
      activeLeases: activeLeases.length,
    },
    users: state.users.map((user) => ({
      ...publicUser(user),
      assignedModelCount: entitlements.filter((item) => item.assignedToType === 'user' && item.assignedToId === user.userId).length,
    })),
    models,
    entitlements,
    recentAssets: state.ingests.assets.slice(-10).reverse(),
    recentResults: state.ingests.results.slice(-10).reverse(),
    recentLogs: state.ingests.logs.slice(-10).reverse(),
    recentStats: state.ingests.stats.slice(-10).reverse(),
  };
}

async function serveStatic(req, res) {
  const pathname = normalizePathname(req.url);
  const filePath = pathname === '/'
    ? path.join(PUBLIC_ROOT, 'index.html')
    : path.join(PUBLIC_ROOT, pathname.replace(/^\/+/, ''));
  if (!filePath.startsWith(PUBLIC_ROOT) || !fsSync.existsSync(filePath)) {
    return false;
  }
  const ext = path.extname(filePath);
  const type = ext === '.css'
    ? 'text/css; charset=utf-8'
    : ext === '.js'
      ? 'application/javascript; charset=utf-8'
      : 'text/html; charset=utf-8';
  sendBuffer(res, 200, await fs.readFile(filePath), type);
  return true;
}

function ingestSummary(state) {
  return {
    users: state.users.length,
    activeSessions: state.sessions.filter((session) => new Date(session.expiresAt).getTime() > Date.now()).length,
    models: state.models.length,
    assets: state.ingests.assets.length,
    results: state.ingests.results.length,
    logs: state.ingests.logs.length,
    stats: state.ingests.stats.length,
  };
}

function fail(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  throw error;
}

function requiredString(body, key, label) {
  const value = String(body?.[key] || '').trim();
  if (!value) {
    fail(400, `${label} is required`);
  }
  return value;
}

async function handleRoute(req, res) {
  const pathname = normalizePathname(req.url);
  const state = await readState();

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    });
    res.end();
    return;
  }

  if (await serveStatic(req, res)) {
    return;
  }

  if (req.method === 'GET' && pathname === '/api/cloud/v1/health') {
    sendJson(res, 200, {
      service: 'vino_cloud',
      status: 'ok',
      now: isoNow(),
      summary: ingestSummary(state),
    });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/cloud/v1/overview') {
    requireAdminSession(state, req);
    sendJson(res, 200, await buildAdminOverview(state));
    return;
  }

  if (req.method === 'GET' && pathname === '/api/cloud/v1/admin/overview') {
    requireAdminSession(state, req);
    sendJson(res, 200, await buildAdminOverview(state));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/cloud/v1/admin/users') {
    requireAdminSession(state, req);
    const body = parseJsonBuffer(await readBody(req));
    const email = requiredString(body, 'email', 'email').toLowerCase();
    const displayName = requiredString(body, 'displayName', 'displayName');
    const organizationId = String(body.organizationId || 'org-demo-001').trim() || 'org-demo-001';
    const organizationName = String(body.organizationName || 'Vino Demo Factory').trim() || 'Vino Demo Factory';
    const role = body.role === 'admin' ? 'admin' : 'member';
    const existing = body.userId ? state.users.find((item) => item.userId === body.userId) : null;
    const duplicate = state.users.find((item) => item.email === email && item.userId !== existing?.userId);
    if (duplicate) {
      sendJson(res, 409, { error: 'email already exists' });
      return;
    }

    if (existing) {
      existing.email = email;
      existing.displayName = displayName;
      existing.organizationId = organizationId;
      existing.organizationName = organizationName;
      existing.role = role;
      if (body.password != null && String(body.password).trim()) {
        existing.password = String(body.password);
      }
      state.sessions = state.sessions.map((session) => (
        session.userId === existing.userId
          ? {
            ...session,
            email: existing.email,
            displayName: existing.displayName,
            organizationId: existing.organizationId,
            organizationName: existing.organizationName,
            role: existing.role,
          }
          : session
      ));
    } else {
      state.users.push({
        userId: `user-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        email,
        password: String(body.password || 'demo123'),
        displayName,
        organizationId,
        organizationName,
        role,
      });
    }

    await writeState(state);
    sendJson(res, 200, { ok: true, users: state.users.map(publicUser) });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/cloud/v1/admin/entitlements') {
    requireAdminSession(state, req);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = requiredString(body, 'modelId', 'modelId');
    const model = state.models.find((item) => item.id === modelId);
    if (!model) {
      sendJson(res, 404, { error: 'model not found' });
      return;
    }

    const assignedToType = body.assignedToType === 'organization' ? 'organization' : 'user';
    let assignedToId;
    if (assignedToType === 'user') {
      assignedToId = requiredString(body, 'assignedToId', 'assignedToId');
      const user = state.users.find((item) => item.userId === assignedToId);
      if (!user) {
        sendJson(res, 404, { error: 'user not found' });
        return;
      }
      if (user.organizationId !== model.organizationId) {
        sendJson(res, 400, { error: 'user organization mismatch' });
        return;
      }
    } else {
      assignedToId = model.organizationId;
    }

    const renewalMode = body.renewalMode === 'fixed' ? 'fixed' : 'perpetual';
    const renewalEndsAt = renewalMode === 'fixed' ? normalizeTimestamp(body.renewalEndsAt) : null;
    if (renewalMode === 'fixed' && !renewalEndsAt) {
      sendJson(res, 400, { error: 'renewalEndsAt is required for fixed mode' });
      return;
    }

    const duplicate = state.entitlements.find((item) =>
      item.modelId === modelId &&
      item.assignedToType === assignedToType &&
      item.assignedToId === assignedToId
    );

    let entitlement = body.entitlementId
      ? state.entitlements.find((item) => item.entitlementId === body.entitlementId)
      : null;

    if (entitlement && duplicate && duplicate.entitlementId !== entitlement.entitlementId) {
      sendJson(res, 409, { error: 'each user can only have one entitlement per model' });
      return;
    }

    if (!entitlement && duplicate) {
      entitlement = duplicate;
    }

    if (entitlement) {
      entitlement.modelId = modelId;
      entitlement.organizationId = model.organizationId;
      entitlement.assignedToType = assignedToType;
      entitlement.assignedToId = assignedToId;
      entitlement.licenseId = String(body.licenseId || entitlement.licenseId || `lic-${modelId}-${shortHash(`${assignedToType}:${assignedToId}`)}`);
      entitlement.renewalMode = renewalMode;
      entitlement.renewalEndsAt = renewalEndsAt;
      entitlement.deviceBindingRequired = body.deviceBindingRequired !== false;
      entitlement.policyFlags = Array.isArray(body.policyFlags) ? body.policyFlags : ['offline', 'device-bound'];
      entitlement.isActive = body.isActive !== false;
      entitlement.updatedAt = isoNow();
    } else {
      entitlement = {
        entitlementId: `ent-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
        organizationId: model.organizationId,
        modelId,
        assignedToType,
        assignedToId,
        licenseId: String(body.licenseId || `lic-${modelId}-${shortHash(`${assignedToType}:${assignedToId}`)}`),
        renewalMode,
        renewalEndsAt,
        leaseDays: 14,
        policyFlags: Array.isArray(body.policyFlags) ? body.policyFlags : ['offline', 'device-bound'],
        deviceBindingRequired: body.deviceBindingRequired !== false,
        isActive: body.isActive !== false,
        createdAt: isoNow(),
        updatedAt: isoNow(),
      };
      state.entitlements.push(entitlement);
    }

    await writeState(state);
    sendJson(res, 200, { ok: true, entitlement });
    return;
  }

  if (req.method === 'POST' && /^\/api\/cloud\/v1\/admin\/entitlements\/[^/]+\/delete$/.test(pathname)) {
    requireAdminSession(state, req);
    const entitlementId = pathname.split('/')[6];
    const before = state.entitlements.length;
    state.entitlements = state.entitlements.filter((item) => item.entitlementId !== entitlementId);
    state.leases = state.leases.filter((item) => item.entitlementId !== entitlementId);
    if (state.entitlements.length === before) {
      sendJson(res, 404, { error: 'entitlement not found' });
      return;
    }
    await writeState(state);
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/cloud/v1/auth/login') {
    const body = parseJsonBuffer(await readBody(req));
    const loginID = String(body.email || body.account || body.username || '').trim().toLowerCase();
    const user = state.users.find((item) => item.email === loginID && item.password === body.password);
    if (!user) {
      sendJson(res, 401, { error: 'invalid credentials' });
      return;
    }

    const accessToken = crypto.randomUUID().replace(/-/g, '');
    const session = {
      accessToken,
      tokenType: 'Bearer',
      expiresAt: plusDays(7),
      userId: user.userId,
      email: user.email,
      displayName: user.displayName,
      organizationId: user.organizationId,
      organizationName: user.organizationName,
      role: user.role,
      deviceId: body.deviceId || 'unknown-device',
      deviceName: body.deviceName || 'unknown-device',
      platform: body.platform || 'unknown',
    };
    state.sessions = state.sessions.filter((item) => item.userId !== user.userId || item.deviceId !== session.deviceId);
    state.sessions.push(session);
    await writeState(state);

    sendJson(res, 200, {
      accessToken: session.accessToken,
      tokenType: session.tokenType,
      expiresAt: session.expiresAt,
      user: {
        userId: user.userId,
        email: user.email,
        displayName: user.displayName,
        organizationId: user.organizationId,
        organizationName: user.organizationName,
        role: user.role,
      },
    });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/cloud/v1/models') {
    const session = requireSession(state, req);
    const models = await listEntitledModels(state, session);
    sendJson(res, 200, {
      models,
      syncedAt: isoNow(),
    });
    return;
  }

  if (req.method === 'POST' && /^\/api\/cloud\/v1\/models\/[^/]+\/download-ticket$/.test(pathname)) {
    const session = requireSession(state, req);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = pathname.split('/')[5];
    const model = state.models.find((item) => item.id === modelId && item.organizationId === session.organizationId);
    if (!model) {
      sendJson(res, 404, { error: 'model not found' });
      return;
    }

    const entitlement = findEntitlementForModel(state, session, modelId, { includeExpired: true });
    if (!entitlement) {
      sendJson(res, 403, { error: 'model is not assigned to current user' });
      return;
    }
    if (!isEntitlementRenewable(entitlement)) {
      sendJson(res, 403, { error: 'entitlement renewal window has ended' });
      return;
    }
    const artifact = await getModelArtifact(model);
    const deviceId = String(body.deviceId || session.deviceId || 'unknown-device');
    const lease = upsertLease(state, entitlement, session, deviceId);

    const ticket = {
      ticketId: crypto.randomUUID().replace(/-/g, ''),
      entitlementId: entitlement.entitlementId,
      userId: session.userId,
      modelId,
      organizationId: session.organizationId,
      deviceId,
      expiresAt: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      fileName: model.fileName,
      sourceFormat: model.sourceFormat,
      transportFormat: model.transportFormat,
      sha256: artifact.sha256,
      byteCount: artifact.byteCount,
      modelBuildId: model.modelBuildId,
      isEncrypted: Boolean(model.isEncrypted),
      ticketSecret: crypto.randomBytes(32).toString('hex'),
      license: buildModelLicense(entitlement, lease, deviceId),
    };
    state.tickets = state.tickets.filter((item) => item.ticketId !== ticket.ticketId);
    state.tickets.push(ticket);
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
      downloadURL: `http://${req.headers.host}/api/cloud/v1/download/${ticket.ticketId}`,
    });
    return;
  }

  if (req.method === 'GET' && /^\/api\/cloud\/v1\/download\/[^/]+$/.test(pathname)) {
    const ticketId = pathname.split('/').pop();
    const ticket = state.tickets.find((item) => item.ticketId === ticketId);
    if (!ticket || new Date(ticket.expiresAt).getTime() <= Date.now()) {
      sendJson(res, 404, { error: 'download ticket expired' });
      return;
    }

    const model = state.models.find((item) => item.id === ticket.modelId);
    if (!model) {
      sendJson(res, 404, { error: 'model not found' });
      return;
    }

    const artifact = await getModelArtifact(model);
    const body = ticket.isEncrypted ? buildEncryptedEnvelope(artifact.bytes, ticket) : artifact.bytes;
    sendBuffer(res, 200, body);
    return;
  }

  if (req.method === 'POST' && pathname === '/api/cloud/v1/licenses/lease/renew') {
    const session = requireSession(state, req);
    const body = parseJsonBuffer(await readBody(req));
    const modelId = requiredString(body, 'modelId', 'modelId');
    const entitlement = findEntitlementForModel(state, session, modelId, { includeExpired: true });
    if (!entitlement) {
      sendJson(res, 404, { error: 'license not found for current user' });
      return;
    }
    if (!isEntitlementRenewable(entitlement)) {
      sendJson(res, 403, { error: 'entitlement renewal window has ended' });
      return;
    }

    const lease = upsertLease(state, entitlement, session, body.deviceId || session.deviceId || 'unknown-device');
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

  if (req.method === 'GET' && pathname === '/api/cloud/v1/assets') {
    sendJson(res, 200, { assets: state.ingests.assets.slice().reverse() });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/cloud/v1/results') {
    sendJson(res, 200, { results: state.ingests.results.slice().reverse() });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/cloud/v1/logs') {
    sendJson(res, 200, { logs: state.ingests.logs.slice().reverse() });
    return;
  }

  if (req.method === 'GET' && pathname === '/api/cloud/v1/stats') {
    sendJson(res, 200, { stats: state.ingests.stats.slice().reverse() });
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/asset')) {
    const body = parseJsonBuffer(await readBody(req));
    const id = body.idempotencyKey || `asset-${crypto.randomUUID()}`;
    const existing = state.ingests.assets.find((item) => item.assetId === id);
    if (existing) {
      sendJson(res, 200, existing);
      return;
    }

    const extension = path.extname(body.fileName || '').replace(/[^a-zA-Z0-9.]/g, '');
    const safeFileName = `${id}${extension}`;
    const filePath = path.join(INGEST_ASSET_ROOT, safeFileName);
    const bytes = Buffer.from(String(body.contentBase64 || ''), 'base64');
    await fs.writeFile(filePath, bytes);

    const record = {
      assetId: id,
      deviceId: body.deviceId || 'unknown-device',
      deviceName: body.deviceName || '',
      fileName: body.fileName || safeFileName,
      category: body.category || 'binary',
      byteCount: bytes.length,
      capturedAt: body.capturedAt || isoNow(),
      productUUID: body.productUUID || '',
      pointIndex: Number(body.pointIndex || 0),
      jobId: body.jobId || '',
      storedPath: filePath,
      createdAt: isoNow(),
    };
    state.ingests.assets.push(record);
    await writeState(state);
    sendJson(res, 200, record);
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/result' || pathname === '/uploadData')) {
    const body = parseJsonBuffer(await readBody(req));
    const id = body.idempotencyKey || body.resultId || `result-${crypto.randomUUID()}`;
    const existing = state.ingests.results.find((item) => item.resultId === id);
    if (existing) {
      sendJson(res, 200, existing);
      return;
    }

    const record = {
      resultId: id,
      deviceId: body.deviceId || 'unknown-device',
      deviceName: body.deviceName || '',
      resultType: body.resultType || 'generic',
      capturedAt: body.capturedAt || body.timestamp || isoNow(),
      productUUID: body.productUUID || '',
      pointIndex: Number(body.pointIndex || 0),
      jobId: body.jobId || '',
      payload: body.payload || body,
      createdAt: isoNow(),
    };
    state.ingests.results.push(record);
    await writeState(state);
    sendJson(res, 200, record);
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/log' || pathname === '/uploadLog')) {
    const body = parseJsonBuffer(await readBody(req));
    const id = body.idempotencyKey || body.logId || `log-${crypto.randomUUID()}`;
    const existing = state.ingests.logs.find((item) => item.logId === id);
    if (existing) {
      sendJson(res, 200, existing);
      return;
    }

    const record = {
      logId: id,
      deviceId: body.deviceId || 'unknown-device',
      level: body.level || 'info',
      category: body.category || 'general',
      message: body.message || body.msg || 'log',
      capturedAt: body.capturedAt || body.timestamp || isoNow(),
      payload: body,
      createdAt: isoNow(),
    };
    state.ingests.logs.push(record);
    await writeState(state);
    sendJson(res, 200, record);
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/cloud/v1/ingest/stat' || pathname === '/uploadStat')) {
    const body = parseJsonBuffer(await readBody(req));
    const id = body.idempotencyKey || body.statId || `stat-${crypto.randomUUID()}`;
    const existing = state.ingests.stats.find((item) => item.statId === id);
    if (existing) {
      sendJson(res, 200, existing);
      return;
    }

    const record = {
      statId: id,
      deviceId: body.deviceId || 'unknown-device',
      metric: body.metric || body.name || 'generic',
      value: body.value ?? body.statValue ?? '',
      capturedAt: body.capturedAt || body.timestamp || isoNow(),
      payload: body,
      createdAt: isoNow(),
    };
    state.ingests.stats.push(record);
    await writeState(state);
    sendJson(res, 200, record);
    return;
  }

  notFound(res);
}

const server = http.createServer(async (req, res) => {
  try {
    await handleRoute(req, res);
  } catch (error) {
    const statusCode = error && error.statusCode ? error.statusCode : 500;
    sendJson(res, statusCode, { error: error.message || 'internal server error' });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`vino_cloud listening on http://0.0.0.0:${PORT}`);
});
