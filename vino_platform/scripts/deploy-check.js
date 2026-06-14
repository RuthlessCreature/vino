const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const repoRoot = path.resolve(root, '..');
const deployEnv = String(process.env.VINO_DEPLOY_ENV || process.env.NODE_ENV || 'development').toLowerCase();
const isProduction = deployEnv === 'production';
const externalBaseUrl = String(process.env.VINO_EXTERNAL_BASE_URL || '').trim();
const seedDemoData = parseBoolean(process.env.VINO_SEED_DEMO_DATA, true);
const bootstrapPassword = String(process.env.VINO_BOOTSTRAP_ADMIN_PASSWORD || '');
const dataRoot = path.resolve(process.env.VINO_DATA_ROOT || path.join(root, 'data'));
const statePath = path.resolve(process.env.VINO_STATE_PATH || path.join(dataRoot, 'state.json'));
const modelUploadRoot = path.resolve(process.env.VINO_MODEL_UPLOAD_ROOT || path.join(dataRoot, 'model-builds'));
const backupRoot = path.resolve(process.env.VINO_BACKUP_ROOT || path.join(dataRoot, 'backups'));
const modelsRoot = path.resolve(process.env.VINO_MODELS_ROOT || path.join(repoRoot, 'models'));
const bodyLimit = String(process.env.VINO_REQUEST_BODY_LIMIT || '200mb');

function parseBoolean(value, defaultValue = false) {
  if (value == null || value === '') {
    return defaultValue;
  }
  return ['1', 'true', 'yes', 'on'].includes(String(value).trim().toLowerCase());
}

async function canWriteDirectory(directoryPath) {
  await fs.mkdir(directoryPath, { recursive: true });
  const probePath = path.join(directoryPath, `.deploy-check-${process.pid}-${Date.now()}`);
  await fs.writeFile(probePath, 'ok');
  await fs.rm(probePath, { force: true });
}

function checkExternalUrl(errors, warnings) {
  if (!externalBaseUrl) {
    warnings.push('VINO_EXTERNAL_BASE_URL is empty; download tickets will fall back to request Host.');
    return;
  }
  let parsed;
  try {
    parsed = new URL(externalBaseUrl);
  } catch {
    errors.push('VINO_EXTERNAL_BASE_URL must be a valid absolute URL.');
    return;
  }
  if (isProduction && parsed.protocol !== 'https:') {
    errors.push('production VINO_EXTERNAL_BASE_URL must use https.');
  }
  if (isProduction && ['127.0.0.1', 'localhost', '0.0.0.0'].includes(parsed.hostname)) {
    errors.push('production VINO_EXTERNAL_BASE_URL must not point to localhost.');
  }
}

async function main() {
  const errors = [];
  const warnings = [];

  checkExternalUrl(errors, warnings);
  if (isProduction && seedDemoData) {
    errors.push('production should set VINO_SEED_DEMO_DATA=false.');
  }
  if (isProduction && !bootstrapPassword && !fsSync.existsSync(statePath)) {
    errors.push('production first boot needs VINO_BOOTSTRAP_ADMIN_PASSWORD when state.json does not exist.');
  }
  if (bodyLimit.toLowerCase().endsWith('gb')) {
    warnings.push('VINO_REQUEST_BODY_LIMIT is very large; prefer object storage before large public uploads.');
  }
  if (!fsSync.existsSync(modelsRoot)) {
    warnings.push(`models root does not exist yet: ${modelsRoot}`);
  }

  for (const directoryPath of [dataRoot, modelUploadRoot, backupRoot]) {
    try {
      await canWriteDirectory(directoryPath);
    } catch (error) {
      errors.push(`cannot write ${directoryPath}: ${error.message}`);
    }
  }

  const result = {
    ok: errors.length === 0,
    deployEnv,
    dataRoot,
    statePath,
    modelUploadRoot,
    backupRoot,
    modelsRoot,
    externalBaseUrl: externalBaseUrl || null,
    seedDemoData,
    warnings,
    errors,
  };
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.ok ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
