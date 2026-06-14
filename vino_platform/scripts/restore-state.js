const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const root = path.resolve(__dirname, '..');
const dataRoot = path.resolve(process.env.VINO_DATA_ROOT || path.join(root, 'data'));
const backupRoot = path.resolve(process.env.VINO_BACKUP_ROOT || path.join(dataRoot, 'backups'));
const statePath = path.resolve(process.env.VINO_STATE_PATH || path.join(dataRoot, 'state.json'));
const restoreSource = process.argv[2] || process.env.VINO_RESTORE_BACKUP;

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function readBackup(filePath) {
  const bytes = await fs.readFile(filePath);
  return filePath.endsWith('.gz') ? zlib.gunzipSync(bytes) : bytes;
}

function validateState(bytes, sourcePath) {
  const text = bytes.toString('utf8').replace(/^\uFEFF/, '');
  const state = JSON.parse(text);
  if (!state || typeof state !== 'object' || Array.isArray(state)) {
    throw new Error(`backup is not a JSON object: ${sourcePath}`);
  }
  for (const key of ['users', 'organizations', 'models', 'auditLogs']) {
    if (!Array.isArray(state[key])) {
      throw new Error(`backup is missing array field: ${key}`);
    }
  }
  return Buffer.from(JSON.stringify(state, null, 2));
}

async function writePreRestoreBackup() {
  if (!fsSync.existsSync(statePath)) {
    return null;
  }
  await fs.mkdir(backupRoot, { recursive: true });
  const safetyBackupPath = path.join(backupRoot, `pre-restore-state-${stamp()}.json.gz`);
  const current = await fs.readFile(statePath);
  await fs.writeFile(safetyBackupPath, zlib.gzipSync(current, { level: 9 }));
  return safetyBackupPath;
}

async function main() {
  if (!restoreSource) {
    throw new Error('usage: node scripts/restore-state.js <state.json[.gz]>');
  }
  const backupPath = path.resolve(restoreSource);
  if (!fsSync.existsSync(backupPath)) {
    throw new Error(`backup file not found: ${backupPath}`);
  }

  const restoredBytes = validateState(await readBackup(backupPath), backupPath);
  await fs.mkdir(path.dirname(statePath), { recursive: true });
  const safetyBackupPath = await writePreRestoreBackup();
  const tempPath = `${statePath}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tempPath, restoredBytes);
  await fs.rename(tempPath, statePath);

  console.log(JSON.stringify({
    ok: true,
    statePath,
    restoredFrom: backupPath,
    safetyBackupPath,
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
