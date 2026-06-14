const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');

function parsePositiveInt(value, defaultValue) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.floor(number) : defaultValue;
}

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
  while (Date.now() - startedAt < 15000) {
    if (child.exitCode !== null) {
      throw new Error(`server exited before health check: ${child.exitCode}`);
    }
    try {
      const response = await fetch(`${baseUrl}/readyz`);
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
  const response = await fetch(`${baseUrl}${pathName}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Forwarded-For': '203.0.113.201',
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

async function login(baseUrl) {
  return api(baseUrl, '/api/cloud/v1/auth/login', {
    method: 'POST',
    body: {
      email: 'demo@vino.cc',
      password: 'demo123',
      deviceId: 'download-stress-device',
      deviceName: 'download-stress-device',
      platform: 'iOS',
    },
  });
}

async function createSparseModel(modelPath, sizeBytes) {
  await fs.mkdir(path.dirname(modelPath), { recursive: true });
  const file = await fs.open(modelPath, 'w');
  try {
    await file.truncate(sizeBytes);
  } finally {
    await file.close();
  }
}

async function readDownload(response) {
  let byteCount = 0;
  let first = Buffer.alloc(0);
  for await (const chunk of response.body) {
    const buffer = Buffer.from(chunk);
    if (first.length < 16) {
      first = Buffer.concat([first, buffer]).subarray(0, 16);
    }
    byteCount += buffer.length;
  }
  return { byteCount, first };
}

async function main() {
  const sizeMb = parsePositiveInt(process.env.VINO_STRESS_MODEL_MB, 16);
  const sizeBytes = sizeMb * 1024 * 1024;
  const port = parsePositiveInt(process.env.VINO_STRESS_PORT, 20000 + Math.floor(Math.random() * 2000));
  const baseUrl = `http://127.0.0.1:${port}`;
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'vino-platform-download-stress-'));
  const modelName = `stress-${Date.now()}`;
  const modelsRoot = path.join(tempRoot, 'models');
  const modelPath = path.join(modelsRoot, `${modelName}.mlmodel`);
  const dataRoot = path.join(tempRoot, 'data');

  await createSparseModel(modelPath, sizeBytes);

  const env = {
    ...process.env,
    PORT: String(port),
    VINO_DATA_ROOT: dataRoot,
    VINO_STATE_PATH: path.join(dataRoot, 'state.json'),
    VINO_MODELS_ROOT: modelsRoot,
    VINO_MODEL_UPLOAD_ROOT: path.join(dataRoot, 'model-builds'),
    VINO_ARTIFACT_CACHE_ROOT: path.join(dataRoot, 'artifact-cache'),
    VINO_DOWNLOAD_WORK_ROOT: path.join(dataRoot, 'download-work'),
    VINO_INGEST_ASSET_ROOT: path.join(dataRoot, 'assets'),
    VINO_EXTERNAL_BASE_URL: baseUrl,
    VINO_RATE_LIMIT_MAX: '1000',
    VINO_RATE_LIMIT_AUTH_MAX: '100',
  };

  const child = spawn(process.execPath, ['server.js'], {
    cwd: ROOT,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const logs = [];
  child.stdout.on('data', (chunk) => logs.push(chunk.toString()));
  child.stderr.on('data', (chunk) => logs.push(chunk.toString()));

  const startedAt = Date.now();
  try {
    await waitForServer(baseUrl, child);
    const session = await login(baseUrl);
    const listed = await api(baseUrl, '/api/cloud/v1/models', { token: session.accessToken });
    const model = listed.models.find((item) => item.name === modelName);
    assert.ok(model, `discovered model not found: ${modelName}`);
    assert.equal(model.byteCount, sizeBytes);

    const ticket = await api(baseUrl, `/api/cloud/v1/models/${model.id}/download-ticket`, {
      token: session.accessToken,
      method: 'POST',
      body: {
        deviceId: 'download-stress-device',
        deviceName: 'download-stress-device',
      },
    });
    assert.equal(ticket.byteCount, sizeBytes);
    assert.equal(ticket.downloadURL, `${baseUrl}/api/cloud/v1/download/${ticket.ticketId}`);

    const response = await fetch(`${baseUrl}/api/cloud/v1/download/${ticket.ticketId}`);
    assert.equal(response.ok, true);
    const download = await readDownload(response);
    assert.equal(download.first.subarray(0, 7).toString('utf8'), 'VINOENC');
    assert.ok(download.byteCount > sizeBytes, 'encrypted envelope should be larger than plaintext');

    const elapsedMs = Date.now() - startedAt;
    console.log(JSON.stringify({
      ok: true,
      sizeMb,
      sizeBytes,
      downloadedBytes: download.byteCount,
      elapsedMs,
      modelId: model.id,
      ticketId: ticket.ticketId,
      artifactCacheRoot: env.VINO_ARTIFACT_CACHE_ROOT,
    }, null, 2));
  } catch (error) {
    error.message = `${error.message}\nserver logs:\n${logs.join('')}`;
    throw error;
  } finally {
    await stopChild(child);
    await fs.rm(tempRoot, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
