const http = require('node:http');
const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { URL } = require('node:url');

const PORT = Number(process.env.PORT || 8797);
const ROOT = __dirname;
const REPO_ROOT = path.resolve(ROOT, '..');
const PUBLIC_ROOT = path.join(ROOT, 'public');
const DATA_ROOT = path.join(ROOT, 'data');
const STATE_PATH = path.join(DATA_ROOT, 'state.json');
const INGEST_ASSET_ROOT = path.join(DATA_ROOT, 'assets');
const MODELS_ROOT = path.join(REPO_ROOT, 'models');
const ARCHIVE_CACHE = new Map();
const ENCRYPTION_ENVELOPE_MAGIC = Buffer.from('VINOENC1', 'utf8');
const BUNDLE_ARCHIVE_MAGIC = Buffer.from('VINOAR01', 'utf8');
const ENCRYPTION_ALGORITHM = 'aes-256-gcm';

function isoNow() {
  return new Date().toISOString();
}

function plusDays(days) {
  return new Date(Date.now() + Number(days || 0) * 24 * 60 * 60 * 1000).toISOString();
}

function shortHash(value) {
  return crypto.createHash('sha1').update(String(value)).digest('hex').slice(0, 12);
}

function slugify(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'model';
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

function fail(statusCode, code, message) {
  const error = new Error(message || code);
  error.statusCode = statusCode;
  error.code = code;
  throw error;
}

function normalizePathname(requestUrl) {
  return new URL(requestUrl, `http://127.0.0.1:${PORT}`).pathname;
}

async function ensureDirs() {
  await fs.mkdir(DATA_ROOT, { recursive: true });
  await fs.mkdir(INGEST_ASSET_ROOT, { recursive: true });
}

async function readBody(req, limitBytes = 200 * 1024 * 1024) {
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

function getSessionFromToken(state, token) {
  if (!token) {
    return null;
  }
  const session = state.sessions.find((item) => item.accessToken === token);
  if (!session || new Date(session.expiresAt).getTime() <= Date.now()) {
    return null;
  }
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
  if (!fsSync.existsSync(MODELS_ROOT)) {
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
    users: [
      {
        userId: 'user-admin-001',
        email: 'admin',
        password: 'meiyoumima',
        displayName: 'Platform Admin',
        organizationId: 'org-platform-001',
        organizationName: 'Vino Platform',
        role: 'super_admin',
        status: 'active',
      },
      {
        userId: 'user-buyer-001',
        email: 'buyer@vino.cc',
        password: 'demo123',
        displayName: 'Buyer Admin',
        organizationId: 'org-demo-001',
        organizationName: 'Vino Demo Factory',
        role: 'buyer_admin',
        status: 'active',
      },
      {
        userId: 'user-demo-001',
        email: 'demo@vino.cc',
        password: 'demo123',
        displayName: 'Demo Operator',
        organizationId: 'org-demo-001',
        organizationName: 'Vino Demo Factory',
        role: 'buyer_operator',
        status: 'active',
      },
      {
        userId: 'user-dev-001',
        email: 'developer@vino.cc',
        password: 'demo123',
        displayName: 'Model Developer',
        organizationId: 'org-dev-001',
        organizationName: 'Vino Model Lab',
        role: 'developer_admin',
        status: 'active',
      },
      {
        userId: 'user-ops-001',
        email: 'ops@vino.cc',
        password: 'demo123',
        displayName: 'Platform Ops',
        organizationId: 'org-platform-001',
        organizationName: 'Vino Platform',
        role: 'platform_ops',
        status: 'active',
      },
      {
        userId: 'user-reviewer-001',
        email: 'reviewer@vino.cc',
        password: 'demo123',
        displayName: 'Model Reviewer',
        organizationId: 'org-platform-001',
        organizationName: 'Vino Platform',
        role: 'reviewer',
        status: 'active',
      },
      {
        userId: 'user-finance-001',
        email: 'finance@vino.cc',
        password: 'demo123',
        displayName: 'Finance Admin',
        organizationId: 'org-platform-001',
        organizationName: 'Vino Platform',
        role: 'finance',
        status: 'active',
      },
    ],
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
  if (firstModel && !state.entitlements.some((item) => item.organizationId === 'org-demo-001' && item.modelId === firstModel.modelId)) {
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
  await writeState(state);
  return state;
}

async function writeState(state) {
  await ensureDirs();
  const tempPath = `${STATE_PATH}.${process.pid}.${Date.now()}.${crypto.randomUUID()}.tmp`;
  await fs.writeFile(tempPath, JSON.stringify(state, null, 2));
  await fs.rename(tempPath, STATE_PATH);
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

async function collectArchiveEntries(rootPath, basePath = rootPath) {
  const stat = await fs.stat(rootPath);
  if (stat.isFile()) {
    return [{ relativePath: path.basename(rootPath), bytes: await fs.readFile(rootPath) }];
  }

  const entries = [];
  const children = await fs.readdir(rootPath, { withFileTypes: true });
  for (const child of [...children].sort((a, b) => a.name.localeCompare(b.name))) {
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
  const header = Buffer.alloc(BUNDLE_ARCHIVE_MAGIC.length + 4 + 4);
  BUNDLE_ARCHIVE_MAGIC.copy(header, 0);
  header.writeUInt32LE(1, BUNDLE_ARCHIVE_MAGIC.length);
  header.writeUInt32LE(entries.length, BUNDLE_ARCHIVE_MAGIC.length + 4);
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

function hashHex(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function getModelArtifact(build) {
  const cacheKey = `${build.modelBuildId}:${build.sourcePath}`;
  const cached = ARCHIVE_CACHE.get(cacheKey);
  if (cached) {
    return cached;
  }

  const sourceAbsolute = path.join(REPO_ROOT, build.sourcePath);
  const stats = await fs.stat(sourceAbsolute);
  const bytes = stats.isDirectory() || build.transportFormat === 'bundle-archive'
    ? buildBundleArchive(await collectArchiveEntries(sourceAbsolute))
    : await fs.readFile(sourceAbsolute);
  const artifact = {
    bytes,
    sha256: hashHex(bytes),
    byteCount: bytes.length,
  };
  ARCHIVE_CACHE.set(cacheKey, artifact);
  return artifact;
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
  const accessToken = crypto.randomUUID().replace(/-/g, '');
  const organization = state.organizations.find((item) => item.organizationId === user.organizationId);
  const session = {
    accessToken,
    tokenType: 'Bearer',
    expiresAt: plusDays(7),
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
  };
  state.sessions = state.sessions.filter((item) => item.userId !== user.userId || item.deviceId !== session.deviceId);
  state.sessions.push(session);
  return session;
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
  if (!filePath.startsWith(PUBLIC_ROOT) || !fsSync.existsSync(filePath)) {
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

async function handleLogin(state, req, res) {
  const body = parseJsonBuffer(await readBody(req));
  const loginId = String(body.email || body.account || body.username || '').trim().toLowerCase();
  const user = state.users.find((item) => item.email.toLowerCase() === loginId && item.password === body.password && item.status !== 'disabled');
  if (!user) {
    sendJson(res, 401, { error: { code: 'invalid_credentials', message: 'invalid credentials' } });
    return;
  }
  const session = createSession(state, user, body);
  upsertDevice(state, session, session.deviceId, session.deviceName, session.platform);
  audit(state, session, 'auth.login', 'user', user.userId, { platform: session.platform });
  await writeState(state);
  sendJson(res, 200, {
    accessToken: session.accessToken,
    tokenType: session.tokenType,
    expiresAt: session.expiresAt,
    user: {
      ...publicUser(user),
      roleLabel: roleLabel(user.role),
    },
    permissions: permissionsForRole(user.role),
  });
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
  const state = await readState();

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Idempotency-Key',
      'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
    });
    res.end();
    return;
  }

  if (await serveStatic(req, res)) {
    return;
  }

  if (req.method === 'GET' && (pathname === '/api/platform/v1/health' || pathname === '/api/cloud/v1/health')) {
    sendJson(res, 200, { service: 'vino_platform', status: 'ok', now: isoNow() });
    return;
  }

  if (req.method === 'POST' && (pathname === '/api/platform/v1/auth/login' || pathname === '/api/cloud/v1/auth/login')) {
    await handleLogin(state, req, res);
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
        password: String(body.password || 'demo123'),
        displayName,
        organizationId,
        organizationName: organization.name,
        role: body.role || 'buyer_operator',
        status: body.status || 'active',
      };
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
        user.password = String(body.password);
      }
      audit(state, actor, 'user.update', 'user', user.userId, {});
    }
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
    let sku = body.skuId ? state.modelSkus.find((item) => item.skuId === body.skuId) : null;
    if (!sku) {
      sku = {
        skuId: `sku-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
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

  if (req.method === 'POST' && pathname === '/api/platform/v1/orders') {
    const session = requireAnyRole(state, req, ['buyer_admin', 'super_admin', 'platform_ops', 'admin']);
    const body = parseJsonBuffer(await readBody(req));
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

  if (req.method === 'POST' && /^\/api\/platform\/v1\/admin\/orders\/[^/]+\/confirm-payment$/.test(pathname)) {
    const actor = requireAnyRole(state, req, ['super_admin', 'admin', 'platform_ops', 'finance']);
    const body = parseJsonBuffer(await readBody(req));
    const orderId = pathname.split('/')[6];
    const order = state.orders.find((item) => item.orderId === orderId);
    if (!order) {
      fail(404, 'order_not_found', 'order not found');
    }
    if (['paid', 'delivering', 'completed'].includes(order.status)) {
      sendJson(res, 200, { ok: true, order, entitlements: state.entitlements.filter((item) => item.sourceOrderItemId && order.items.some((oi) => oi.orderItemId === item.sourceOrderItemId)) });
      return;
    }
    order.status = 'paid';
    order.paidAt = isoNow();
    order.updatedAt = isoNow();
    const payment = {
      paymentId: `pay-${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`,
      orderId,
      provider: body.provider || 'manual',
      status: 'succeeded',
      amount: order.totalAmount,
      providerTradeNo: body.providerTradeNo || `manual-${shortHash(orderId)}`,
      idempotencyKey: req.headers['idempotency-key'] || body.idempotencyKey || `manual-${orderId}`,
      createdAt: isoNow(),
    };
    state.payments.push(payment);
    const entitlements = order.items.map((item) => createEntitlementFromOrderItem(state, order, item, actor));
    const settlements = createSettlementEntriesForOrder(state, order, actor);
    audit(state, actor, 'order.confirm_payment', 'order', orderId, { paymentId: payment.paymentId });
    await writeState(state);
    sendJson(res, 200, { ok: true, order, payment, entitlements, settlements });
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
      || (assignedToType === 'user' ? state.users.find((item) => item.userId === assignedToId)?.organizationId : assignedToId)
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
    sendJson(res, 200, { ok: true, model, review });
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
    upsertDevice(state, session, deviceId, body.deviceName || session.deviceName, session.platform);
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
      downloadURL: `http://${req.headers.host}/api/cloud/v1/download/${ticket.ticketId}`,
    });
    return;
  }

  if (req.method === 'GET' && /^\/api\/cloud\/v1\/download\/[^/]+$/.test(pathname)) {
    const ticketId = pathname.split('/').pop();
    const ticket = state.tickets.find((item) => item.ticketId === ticketId);
    if (!ticket || ticket.status === 'revoked' || new Date(ticket.expiresAt).getTime() <= Date.now()) {
      fail(404, 'download_ticket_expired', 'download ticket expired');
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
    sendBuffer(res, 200, ticket.isEncrypted ? buildEncryptedEnvelope(artifact.bytes, ticket) : artifact.bytes);
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
    upsertDevice(state, session, deviceId, body.deviceName || session.deviceName, session.platform);
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

  sendJson(res, 404, { error: { code: 'not_found', message: 'route not found' } });
}

const server = http.createServer((req, res) => {
  handleRoute(req, res).catch((error) => {
    const statusCode = error.statusCode || 500;
    if (statusCode >= 500) {
      console.error(error);
    }
    sendJson(res, statusCode, {
      error: {
        code: error.code || 'internal_error',
        message: error.message || 'internal error',
      },
    });
  });
});

server.listen(PORT, () => {
  console.log(`vino_platform listening on http://127.0.0.1:${PORT}`);
});
