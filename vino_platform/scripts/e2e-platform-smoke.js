const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
let requestCounter = 0;

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function stopChild(child) {
  if (child.exitCode !== null) {
    return;
  }
  child.kill('SIGTERM');
  await Promise.race([
    new Promise((resolve) => child.once('exit', resolve)),
    delay(2000),
  ]);
  if (child.exitCode === null) {
    child.kill('SIGKILL');
    await Promise.race([
      new Promise((resolve) => child.once('exit', resolve)),
      delay(2000),
    ]);
  }
}

async function waitForServer(baseUrl, child) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < 12000) {
    if (child.exitCode !== null) {
      throw new Error(`server exited before health check: ${child.exitCode}`);
    }
    try {
      const response = await fetch(`${baseUrl}/api/platform/v1/health`);
      if (response.ok) {
        return;
      }
    } catch {
      // Keep polling while the server boots.
    }
    await delay(150);
  }
  throw new Error('server did not become healthy in time');
}

async function api(baseUrl, pathName, { token, method = 'GET', body, headers = {} } = {}) {
  requestCounter += 1;
  const response = await fetch(`${baseUrl}${pathName}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Forwarded-For': `203.0.113.${1 + (requestCounter % 200)}`,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const message = payload.error?.message || `${response.status} ${response.statusText}`;
    const error = new Error(`${method} ${pathName}: ${message}`);
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

async function expectApiError(baseUrl, pathName, expectedStatus, options) {
  try {
    await api(baseUrl, pathName, options);
  } catch (error) {
    assert.equal(error.status, expectedStatus, `${pathName} should return ${expectedStatus}`);
    return error.payload;
  }
  throw new Error(`${pathName} unexpectedly succeeded`);
}

async function login(baseUrl, email, password, deviceId = 'web-console') {
  return api(baseUrl, '/api/platform/v1/auth/login', {
    method: 'POST',
    body: {
      email,
      password,
      deviceId,
      deviceName: deviceId,
      platform: deviceId === 'web-console' ? 'web' : 'iOS',
    },
  });
}

async function main() {
  const port = 18000 + Math.floor(Math.random() * 2000);
  const baseUrl = `http://127.0.0.1:${port}`;
  const externalBaseUrl = 'https://platform.example.test';
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'vino-platform-e2e-'));
  const env = {
    ...process.env,
    PORT: String(port),
    VINO_EXTERNAL_BASE_URL: externalBaseUrl,
    VINO_DATA_ROOT: tempRoot,
    VINO_STATE_PATH: path.join(tempRoot, 'state.json'),
    VINO_MODEL_UPLOAD_ROOT: path.join(tempRoot, 'model-builds'),
    VINO_ARTIFACT_CACHE_ROOT: path.join(tempRoot, 'artifact-cache'),
    VINO_DOWNLOAD_WORK_ROOT: path.join(tempRoot, 'download-work'),
    VINO_INGEST_ASSET_ROOT: path.join(tempRoot, 'assets'),
    VINO_RATE_LIMIT_MAX: '8',
    VINO_RATE_LIMIT_AUTH_MAX: '4',
    VINO_SKIP_MODEL_DISCOVERY: '1',
  };
  const child = spawn(process.execPath, ['server.js'], {
    cwd: ROOT,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const logs = [];
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));

  try {
    await waitForServer(baseUrl, child);

    const health = await api(baseUrl, '/healthz');
    assert.equal(health.status, 'ok');
    const ready = await api(baseUrl, '/readyz');
    assert.equal(ready.status, 'ok');
    assert.equal(ready.artifactCacheRoot, path.resolve(tempRoot, 'artifact-cache'));

    const admin = await login(baseUrl, 'admin', 'meiyoumima');
    const buyer = await login(baseUrl, 'buyer@vino.cc', 'demo123');
    const operator = await login(baseUrl, 'demo@vino.cc', 'demo123', 'e2e-iphone-001');
    const developer = await login(baseUrl, 'developer@vino.cc', 'demo123');
    const finance = await login(baseUrl, 'finance@vino.cc', 'demo123');

    const logoutProbe = await login(baseUrl, 'buyer@vino.cc', 'demo123', 'e2e-logout-probe');
    await api(baseUrl, '/api/platform/v1/auth/logout', {
      token: logoutProbe.accessToken,
      method: 'POST',
      body: {},
    });
    await expectApiError(baseUrl, '/api/platform/v1/me', 401, { token: logoutProbe.accessToken });

    const missing = await expectApiError(baseUrl, '/api/platform/v1/definitely-missing', 404, {
      headers: { 'X-Request-Id': 'e2e-missing-route' },
    });
    assert.equal(missing.error.code, 'not_found');
    assert.equal(missing.error.requestId, 'e2e-missing-route');

    const overview0 = await api(baseUrl, '/api/platform/v1/dashboard/overview', { token: admin.accessToken });
    assert.equal(overview0.summary.models, 0, 'isolated test state should not discover repo models');

    const opsStatus = await api(baseUrl, '/api/platform/v1/admin/ops/status', { token: admin.accessToken });
    assert.equal(opsStatus.service, 'vino_platform');
    assert.equal(opsStatus.paths.dataRoot, tempRoot);
    assert.equal(opsStatus.storage.stateFile.exists, true);
    assert.equal(opsStatus.config.rateLimit.enabled, true);
    assert.equal(opsStatus.collections.users >= 7, true);
    assert.equal(opsStatus.risks.some((risk) => risk.code === 'backup_missing'), true);
    await expectApiError(baseUrl, '/api/platform/v1/admin/ops/status', 403, { token: buyer.accessToken });
    const doctor0 = await api(baseUrl, '/api/platform/v1/admin/ops/doctor', { token: admin.accessToken });
    assert.equal(doctor0.ok, true);
    assert.equal(doctor0.summary.errors, 0);
    await expectApiError(baseUrl, '/api/platform/v1/admin/ops/doctor', 403, { token: buyer.accessToken });

    const unique = Date.now().toString().slice(-8);
    const created = await api(baseUrl, '/api/platform/v1/developer/models', {
      token: developer.accessToken,
      method: 'POST',
      body: {
        name: `E2E Surface Model ${unique}`,
        category: 'cv',
        summary: 'End-to-end uploaded model',
        tags: 'coreml,e2e',
      },
    });
    const modelId = created.model.modelId;

    const build = await api(baseUrl, `/api/platform/v1/developer/models/${modelId}/builds`, {
      token: developer.accessToken,
      method: 'POST',
      body: {
        fileName: `e2e-${unique}.mlmodel`,
        version: '1.2.3',
        contentBase64: Buffer.from(`fake-coreml-bundle-${unique}`).toString('base64'),
      },
    });
    assert.match(build.build.sha256, /^[a-f0-9]{64}$/);

    await api(baseUrl, `/api/platform/v1/developer/models/${modelId}/submit-review`, {
      token: developer.accessToken,
      method: 'POST',
      body: {},
    });
    const published = await api(baseUrl, `/api/platform/v1/admin/models/${modelId}/publish`, {
      token: admin.accessToken,
      method: 'POST',
      body: {},
    });
    assert.equal(published.model.status, 'listed');
    assert.ok(published.sku.skuId);

    const marketplace = await api(baseUrl, `/api/platform/v1/marketplace/search?q=${encodeURIComponent(unique)}`, {
      token: buyer.accessToken,
    });
    assert.equal(marketplace.models.length, 1);

    await expectApiError(baseUrl, '/api/platform/v1/orders', 403, {
      token: operator.accessToken,
      method: 'POST',
      body: { skuId: published.sku.skuId },
    });

    const order1 = await api(baseUrl, '/api/platform/v1/orders', {
      token: buyer.accessToken,
      method: 'POST',
      body: { skuId: published.sku.skuId, quantity: 1, paymentMode: 'offline_transfer', idempotencyKey: `order-${unique}-manual` },
    });
    assert.equal(order1.order.status, 'pending_payment');

    const orderReplay = await api(baseUrl, '/api/platform/v1/orders', {
      token: buyer.accessToken,
      method: 'POST',
      body: { skuId: published.sku.skuId, quantity: 1, paymentMode: 'offline_transfer', idempotencyKey: `order-${unique}-manual` },
    });
    assert.equal(orderReplay.replayed, true);
    assert.equal(orderReplay.order.orderId, order1.order.orderId);

    const paid1 = await api(baseUrl, `/api/platform/v1/admin/orders/${order1.order.orderId}/confirm-payment`, {
      token: admin.accessToken,
      method: 'POST',
      headers: { 'Idempotency-Key': `pay-${unique}-manual` },
      body: { provider: 'manual' },
    });
    assert.equal(paid1.order.status, 'paid');
    assert.equal(paid1.entitlements.length, 1);
    assert.equal(paid1.settlements.length, 1);

    const invoice = await api(baseUrl, '/api/platform/v1/invoices', {
      token: buyer.accessToken,
      method: 'POST',
      body: {
        orderId: order1.order.orderId,
        invoiceType: 'vat_normal',
        title: 'Vino Demo Factory',
        taxNumber: 'TAX-E2E',
        deliveryEmail: 'ap@vino.cc',
      },
    });
    assert.equal(invoice.invoice.status, 'pending');
    const issued = await api(baseUrl, `/api/platform/v1/admin/invoices/${invoice.invoice.invoiceId}/review`, {
      token: finance.accessToken,
      method: 'POST',
      body: { decision: 'approve' },
    });
    assert.equal(issued.invoice.status, 'issued');

    const withdrawal = await api(baseUrl, '/api/platform/v1/developer/withdrawals', {
      token: developer.accessToken,
      method: 'POST',
      body: { accountName: 'Vino Model Lab', accountNo: '6222000000000000' },
    });
    assert.equal(withdrawal.withdrawal.status, 'pending');
    const withdrawalPaid = await api(baseUrl, `/api/platform/v1/admin/withdrawals/${withdrawal.withdrawal.withdrawalId}/review`, {
      token: finance.accessToken,
      method: 'POST',
      body: { decision: 'approve' },
    });
    assert.equal(withdrawalPaid.withdrawal.status, 'paid');

    const cloudModels = await api(baseUrl, '/api/cloud/v1/models', { token: operator.accessToken });
    assert.equal(cloudModels.models.some((item) => item.id === modelId), true);

    const ticket = await api(baseUrl, `/api/cloud/v1/models/${modelId}/download-ticket`, {
      token: operator.accessToken,
      method: 'POST',
      body: { deviceId: 'e2e-iphone-001', deviceName: 'E2E iPhone' },
    });
    assert.equal(ticket.modelId, modelId);
    assert.match(ticket.encryption.ticketSecret, /^[a-f0-9]+$/);
    assert.equal(ticket.downloadURL, `${externalBaseUrl}/api/cloud/v1/download/${ticket.ticketId}`);

    const download = await fetch(`${baseUrl}/api/cloud/v1/download/${ticket.ticketId}`);
    assert.equal(download.ok, true);
    const downloadBytes = Buffer.from(await download.arrayBuffer());
    assert.equal(downloadBytes.subarray(0, 7).toString('utf8'), 'VINOENC');

    const lease = await api(baseUrl, '/api/cloud/v1/licenses/lease/renew', {
      token: operator.accessToken,
      method: 'POST',
      body: { modelId, deviceId: 'e2e-iphone-001' },
    });
    assert.equal(lease.modelId, modelId);

    await api(baseUrl, '/api/platform/v1/ingest/asset', {
      method: 'POST',
      body: {
        idempotencyKey: `asset-${unique}`,
        organizationId: 'org-demo-001',
        deviceId: 'e2e-iphone-001',
        fileName: 'capture.png',
        contentBase64: Buffer.from('png-bytes').toString('base64'),
      },
    });
    await api(baseUrl, '/api/platform/v1/ingest/result', {
      method: 'POST',
      body: {
        idempotencyKey: `result-${unique}`,
        organizationId: 'org-demo-001',
        deviceId: 'e2e-iphone-001',
        resultType: 'classification',
        payload: { ok: true },
      },
    });
    const assets = await api(baseUrl, '/api/platform/v1/admin/ingest/assets', { token: admin.accessToken });
    assert.equal(assets.assets.some((item) => item.assetId === `asset-${unique}`), true);

    const ticketCase = await api(baseUrl, '/api/platform/v1/support/tickets', {
      token: buyer.accessToken,
      method: 'POST',
      body: { title: '模型现场误报', category: 'technical', priority: 'high', modelId, body: '现场发现误报。' },
    });
    const ticketClosed = await api(baseUrl, `/api/platform/v1/support/tickets/${ticketCase.ticket.supportTicketId}/reply`, {
      token: admin.accessToken,
      method: 'POST',
      body: { body: '已复现并给出处理方案。', status: 'closed' },
    });
    assert.equal(ticketClosed.ticket.status, 'closed');

    const custom = await api(baseUrl, '/api/platform/v1/custom-requests', {
      token: buyer.accessToken,
      method: 'POST',
      body: { title: '定制焊缝复检模型', scenario: '焊缝复检', budgetAmount: 88000, dueAt: '2026-06-30' },
    });
    const proposal = await api(baseUrl, `/api/platform/v1/custom-requests/${custom.request.customRequestId}/proposal`, {
      token: developer.accessToken,
      method: 'POST',
      body: { quoteAmount: 76000, body: '两周首版交付。' },
    });
    const accepted = await api(baseUrl, `/api/platform/v1/custom-requests/${custom.request.customRequestId}/proposals/${proposal.proposal.proposalId}/accept`, {
      token: buyer.accessToken,
      method: 'POST',
      body: {},
    });
    assert.equal(accepted.request.status, 'in_delivery');

    const webhookOrder = await api(baseUrl, '/api/platform/v1/orders', {
      token: buyer.accessToken,
      method: 'POST',
      body: { skuId: published.sku.skuId, quantity: 1, paymentMode: 'online', idempotencyKey: `order-${unique}-webhook` },
    });
    const webhookPaid = await api(baseUrl, '/api/platform/v1/payments/webhooks/mockpay', {
      method: 'POST',
      headers: { 'Idempotency-Key': `webhook-${unique}` },
      body: { orderId: webhookOrder.order.orderId, status: 'succeeded', amount: webhookOrder.order.totalAmount, providerTradeNo: `mock-${unique}` },
    });
    assert.equal(webhookPaid.order.status, 'paid');
    const webhookReplay = await api(baseUrl, '/api/platform/v1/payments/webhooks/mockpay', {
      method: 'POST',
      headers: { 'Idempotency-Key': `webhook-${unique}` },
      body: { orderId: webhookOrder.order.orderId, status: 'succeeded', amount: webhookOrder.order.totalAmount, providerTradeNo: `mock-${unique}` },
    });
    assert.equal(webhookReplay.replayed, true);

    const overview1 = await api(baseUrl, '/api/platform/v1/dashboard/overview', { token: admin.accessToken });
    const device = overview1.devices.find((item) => item.deviceBindingId === 'e2e-iphone-001');
    assert.ok(device);
    await api(baseUrl, `/api/platform/v1/admin/devices/${device.deviceId}/block`, {
      token: admin.accessToken,
      method: 'POST',
      body: { reason: 'E2E block' },
    });
    await expectApiError(baseUrl, '/api/cloud/v1/licenses/lease/renew', 403, {
      token: operator.accessToken,
      method: 'POST',
      body: { modelId, deviceId: 'e2e-iphone-001' },
    });
    await api(baseUrl, `/api/platform/v1/admin/devices/${device.deviceId}/block`, {
      token: admin.accessToken,
      method: 'POST',
      body: { block: false },
    });

    const refund = await api(baseUrl, `/api/platform/v1/orders/${order1.order.orderId}/refund`, {
      token: admin.accessToken,
      method: 'POST',
      body: { reason: 'E2E refund' },
    });
    assert.equal(refund.order.status, 'refunded');
    assert.equal(refund.revoked.length, 1);

    const maintenancePreview = await api(baseUrl, '/api/platform/v1/admin/ops/maintenance', {
      token: admin.accessToken,
      method: 'POST',
      body: { dryRun: true, ticketRetentionDays: 0, downloadWorkRetentionMinutes: 0 },
    });
    assert.equal(maintenancePreview.dryRun, true);
    assert.equal(maintenancePreview.state.ticketsRemoved >= 1, true);
    await expectApiError(baseUrl, '/api/platform/v1/admin/ops/maintenance', 403, {
      token: buyer.accessToken,
      method: 'POST',
      body: { dryRun: true },
    });
    const maintenanceRun = await api(baseUrl, '/api/platform/v1/admin/ops/maintenance', {
      token: admin.accessToken,
      method: 'POST',
      body: { dryRun: false, ticketRetentionDays: 0, downloadWorkRetentionMinutes: 0 },
    });
    assert.equal(maintenanceRun.dryRun, false);
    assert.equal(maintenanceRun.state.ticketsRemoved >= 1, true);

    await api(baseUrl, '/api/platform/v1/admin/users', {
      token: admin.accessToken,
      method: 'POST',
      body: {
        displayName: 'E2E Operator',
        email: `e2e-${unique}@vino.cc`,
        password: 'demo123',
        role: 'buyer_operator',
        organizationId: 'org-demo-001',
      },
    });
    const concurrentEmails = Array.from({ length: 5 }, (_, index) => `e2e-concurrent-${index}-${unique}@vino.cc`);
    await Promise.all(concurrentEmails.map((email, index) => api(baseUrl, '/api/platform/v1/admin/users', {
      token: admin.accessToken,
      method: 'POST',
      body: {
        displayName: `E2E Concurrent ${index}`,
        email,
        password: 'demo123',
        role: 'buyer_operator',
        organizationId: 'org-demo-001',
      },
    })));
    const doctor1 = await api(baseUrl, '/api/platform/v1/admin/ops/doctor', { token: admin.accessToken });
    assert.equal(doctor1.ok, true);
    assert.equal(doctor1.summary.errors, 0);

    const stateText = await fs.readFile(path.join(tempRoot, 'state.json'), 'utf8');
    const state = JSON.parse(stateText);
    assert.equal(state.users.every((user) => !Object.prototype.hasOwnProperty.call(user, 'password')), true);
    assert.equal(state.users.every((user) => user.passwordHash && user.passwordSalt), true);
    assert.equal(concurrentEmails.every((email) => state.users.some((user) => user.email === email)), true);
    assert.equal(state.auditLogs.length > 10, true);

    let rateLimited = null;
    for (let index = 0; index < 12; index += 1) {
      const requestId = `e2e-rate-${index}`;
      const response = await fetch(`${baseUrl}/api/platform/v1/rate-limit-probe`, {
        headers: {
          'X-Forwarded-For': '198.51.100.77',
          'X-Request-Id': requestId,
        },
      });
      const payload = await response.json();
      if (response.status === 429) {
        rateLimited = payload;
        assert.equal(payload.error.code, 'rate_limited');
        assert.equal(payload.error.requestId, requestId);
        assert.equal(response.headers.get('x-request-id'), requestId);
        assert.equal(response.headers.has('retry-after'), true);
        break;
      }
      assert.equal(response.status, 404);
    }
    assert.ok(rateLimited, 'rate limit should eventually return 429 for a single client IP');

    console.log(JSON.stringify({
      ok: true,
      port,
      modelId,
      orderIds: [order1.order.orderId, webhookOrder.order.orderId],
      checks: [
        'auth',
        'health-ready',
        'logout-revocation',
        'request-id-errors',
        'rate-limit',
        'ops-status',
        'state-doctor',
        'ops-maintenance',
        'state-write-lock',
        'password-hash-migration',
        'developer-build-upload',
        'review-publish',
        'marketplace',
        'order-idempotency',
        'manual-payment',
        'invoice',
        'withdrawal',
        'terminal-models',
        'download-ticket',
        'public-download-url',
        'encrypted-download',
        'streamed-download',
        'lease-renew',
        'ingest',
        'support',
        'custom-request',
        'payment-webhook-idempotency',
        'device-block',
        'refund',
        'audit',
      ],
    }, null, 2));
  } finally {
    await stopChild(child);
    await fs.rm(tempRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
