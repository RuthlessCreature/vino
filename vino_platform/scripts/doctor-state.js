const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const repoRoot = path.resolve(root, '..');
const dataRoot = path.resolve(process.env.VINO_DATA_ROOT || path.join(root, 'data'));
const statePath = path.resolve(process.env.VINO_STATE_PATH || path.join(dataRoot, 'state.json'));

function issue(issues, severity, code, message, objectType = null, objectId = null) {
  issues.push({
    severity,
    code,
    message,
    ...(objectType ? { objectType } : {}),
    ...(objectId ? { objectId } : {}),
  });
}

function array(value) {
  return Array.isArray(value) ? value : [];
}

function indexBy(items, key) {
  const map = new Map();
  for (const item of array(items)) {
    if (item?.[key]) {
      map.set(item[key], item);
    }
  }
  return map;
}

function unique(issues, items, key, objectType) {
  const seen = new Set();
  for (const item of array(items)) {
    const id = item?.[key];
    if (!id) {
      issue(issues, 'error', 'missing_id', `${objectType} missing ${key}`, objectType);
      continue;
    }
    if (seen.has(id)) {
      issue(issues, 'error', 'duplicate_id', `${objectType} duplicate ${key}: ${id}`, objectType, id);
    }
    seen.add(id);
  }
}

function ref(issues, map, id, code, message, objectType, objectId, severity = 'error') {
  if (id && !map.has(id)) {
    issue(issues, severity, code, `${message}: ${id}`, objectType, objectId);
  }
}

function sourcePath(build) {
  if (!build?.sourcePath) {
    return null;
  }
  return path.isAbsolute(build.sourcePath) ? build.sourcePath : path.join(repoRoot, build.sourcePath);
}

async function readState() {
  const text = (await fs.readFile(statePath, 'utf8')).replace(/^\uFEFF/, '');
  return JSON.parse(text);
}

function doctor(state) {
  const issues = [];
  const organizations = indexBy(state.organizations, 'organizationId');
  const users = indexBy(state.users, 'userId');
  const developers = indexBy(state.developers, 'developerId');
  const models = indexBy(state.models, 'modelId');
  const builds = indexBy(state.modelBuilds, 'modelBuildId');
  const skus = indexBy(state.modelSkus, 'skuId');
  const orders = indexBy(state.orders, 'orderId');
  const entitlements = indexBy(state.entitlements, 'entitlementId');
  const devices = indexBy(state.devices, 'deviceId');

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
  ].forEach(([objectType, items, key]) => unique(issues, items, key, objectType));

  const emails = new Set();
  for (const user of array(state.users)) {
    if (user.email) {
      const email = user.email.toLowerCase();
      if (emails.has(email)) {
        issue(issues, 'error', 'duplicate_email', `duplicate user email: ${email}`, 'user', user.userId);
      }
      emails.add(email);
    }
    if (Object.prototype.hasOwnProperty.call(user, 'password')) {
      issue(issues, 'error', 'plain_password_present', 'user has plain password field', 'user', user.userId);
    }
    if (!user.passwordHash || !user.passwordSalt) {
      issue(issues, 'error', 'password_hash_missing', 'user missing password hash or salt', 'user', user.userId);
    }
    ref(issues, organizations, user.organizationId, 'organization_missing', 'user organization missing', 'user', user.userId);
  }

  for (const developer of array(state.developers)) {
    ref(issues, organizations, developer.organizationId, 'organization_missing', 'developer organization missing', 'developer', developer.developerId);
  }
  for (const model of array(state.models)) {
    ref(issues, developers, model.developerId, 'developer_missing', 'model developer missing', 'model', model.modelId);
    ref(issues, builds, model.currentBuildId, 'build_missing', 'model current build missing', 'model', model.modelId);
  }
  for (const build of array(state.modelBuilds)) {
    ref(issues, models, build.modelId, 'model_missing', 'build model missing', 'modelBuild', build.modelBuildId);
    const absolute = sourcePath(build);
    if (!absolute) {
      issue(issues, 'error', 'source_path_missing', 'build sourcePath missing', 'modelBuild', build.modelBuildId);
    } else if (!fsSync.existsSync(absolute)) {
      issue(issues, 'error', 'source_file_missing', `build source file missing: ${absolute}`, 'modelBuild', build.modelBuildId);
    }
  }
  for (const sku of array(state.modelSkus)) {
    ref(issues, models, sku.modelId, 'model_missing', 'SKU model missing', 'sku', sku.skuId);
    ref(issues, builds, sku.buildId, 'build_missing', 'SKU build missing', 'sku', sku.skuId);
  }
  for (const order of array(state.orders)) {
    ref(issues, organizations, order.buyerOrganizationId, 'organization_missing', 'order buyer organization missing', 'order', order.orderId);
    ref(issues, users, order.buyerUserId, 'user_missing', 'order buyer user missing', 'order', order.orderId);
    for (const item of array(order.items)) {
      ref(issues, skus, item.skuId, 'sku_missing', 'order item SKU missing', 'order', order.orderId);
      ref(issues, models, item.modelId, 'model_missing', 'order item model missing', 'order', order.orderId);
    }
  }
  for (const entitlement of array(state.entitlements)) {
    ref(issues, organizations, entitlement.organizationId, 'organization_missing', 'entitlement organization missing', 'entitlement', entitlement.entitlementId);
    ref(issues, models, entitlement.modelId, 'model_missing', 'entitlement model missing', 'entitlement', entitlement.entitlementId);
    if (entitlement.modelSkuId) {
      ref(issues, skus, entitlement.modelSkuId, 'sku_missing', 'entitlement SKU missing', 'entitlement', entitlement.entitlementId);
    }
    if (entitlement.assignedToType === 'user') {
      ref(issues, users, entitlement.assignedToId, 'assigned_user_missing', 'entitlement assigned user missing', 'entitlement', entitlement.entitlementId);
    } else if (entitlement.assignedToType === 'organization') {
      ref(issues, organizations, entitlement.assignedToId, 'assigned_organization_missing', 'entitlement assigned organization missing', 'entitlement', entitlement.entitlementId);
    } else if (entitlement.assignedToType === 'device') {
      ref(issues, devices, entitlement.assignedToId, 'assigned_device_missing', 'entitlement assigned device missing', 'entitlement', entitlement.entitlementId, 'warning');
    }
  }
  for (const ticket of array(state.tickets)) {
    ref(issues, entitlements, ticket.entitlementId, 'entitlement_missing', 'ticket entitlement missing', 'ticket', ticket.ticketId);
    ref(issues, users, ticket.userId, 'user_missing', 'ticket user missing', 'ticket', ticket.ticketId);
    ref(issues, organizations, ticket.organizationId, 'organization_missing', 'ticket organization missing', 'ticket', ticket.ticketId);
    ref(issues, models, ticket.modelId, 'model_missing', 'ticket model missing', 'ticket', ticket.ticketId);
    ref(issues, builds, ticket.modelBuildId, 'build_missing', 'ticket build missing', 'ticket', ticket.ticketId);
  }
  for (const lease of array(state.leases)) {
    ref(issues, entitlements, lease.entitlementId, 'entitlement_missing', 'lease entitlement missing', 'lease', lease.leaseId);
    ref(issues, users, lease.userId, 'user_missing', 'lease user missing', 'lease', lease.leaseId);
    ref(issues, organizations, lease.organizationId, 'organization_missing', 'lease organization missing', 'lease', lease.leaseId);
    ref(issues, models, lease.modelId, 'model_missing', 'lease model missing', 'lease', lease.leaseId);
  }
  for (const invoice of array(state.invoices)) {
    ref(issues, orders, invoice.orderId, 'order_missing', 'invoice order missing', 'invoice', invoice.invoiceId);
  }
  for (const settlement of array(state.settlements)) {
    ref(issues, orders, settlement.orderId, 'order_missing', 'settlement order missing', 'settlement', settlement.settlementId);
    ref(issues, developers, settlement.developerId, 'developer_missing', 'settlement developer missing', 'settlement', settlement.settlementId);
    ref(issues, models, settlement.modelId, 'model_missing', 'settlement model missing', 'settlement', settlement.settlementId);
  }
  for (const withdrawal of array(state.withdrawals)) {
    ref(issues, developers, withdrawal.developerId, 'developer_missing', 'withdrawal developer missing', 'withdrawal', withdrawal.withdrawalId);
  }

  const errors = issues.filter((item) => item.severity === 'error');
  const warnings = issues.filter((item) => item.severity === 'warning');
  return {
    ok: errors.length === 0,
    status: errors.length > 0 ? 'error' : warnings.length > 0 ? 'warning' : 'ok',
    statePath,
    summary: {
      errors: errors.length,
      warnings: warnings.length,
      issues: issues.length,
    },
    issues,
  };
}

async function main() {
  const result = doctor(await readState());
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.ok ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
