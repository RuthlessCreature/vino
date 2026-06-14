const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const { pipeline } = require('node:stream/promises');

const root = path.resolve(__dirname, '..');
const dataRoot = path.resolve(process.env.VINO_DATA_ROOT || path.join(root, 'data'));
const backupRoot = path.resolve(process.env.VINO_BACKUP_ROOT || path.join(dataRoot, 'backups'));
const statePath = path.resolve(process.env.VINO_STATE_PATH || path.join(dataRoot, 'state.json'));

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function main() {
  await fs.mkdir(backupRoot, { recursive: true });
  if (!fsSync.existsSync(statePath)) {
    throw new Error(`state file not found: ${statePath}`);
  }
  const backupPath = path.join(backupRoot, `state-${stamp()}.json.gz`);
  await pipeline(
    fsSync.createReadStream(statePath),
    zlib.createGzip({ level: 9 }),
    fsSync.createWriteStream(backupPath)
  );
  console.log(JSON.stringify({ ok: true, statePath, backupPath }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
