const fs = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const root = path.resolve(__dirname, '..');
const dataRoot = path.resolve(process.env.VINO_DATA_ROOT || path.join(root, 'data'));
const statePath = path.resolve(process.env.VINO_STATE_PATH || path.join(dataRoot, 'state.json'));
const backupRoot = path.resolve(process.env.VINO_BACKUP_ROOT || path.join(dataRoot, 'backups'));
const artifactCacheRoot = path.resolve(process.env.VINO_ARTIFACT_CACHE_ROOT || path.join(dataRoot, 'artifact-cache'));
const downloadWorkRoot = path.resolve(process.env.VINO_DOWNLOAD_WORK_ROOT || path.join(dataRoot, 'download-work'));

function parsePositiveInt(value, defaultValue) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.floor(number) : defaultValue;
}

function flag(name) {
  return process.argv.includes(name);
}

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

async function readState() {
  const text = (await fs.readFile(statePath, 'utf8')).replace(/^\uFEFF/, '');
  const state = JSON.parse(text);
  for (const key of ['sessions', 'tickets', 'auditLogs']) {
    if (!Array.isArray(state[key])) {
      state[key] = [];
    }
  }
  return state;
}

async function writeState(state) {
  await fs.mkdir(path.dirname(statePath), { recursive: true });
  const tempPath = `${statePath}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(tempPath, JSON.stringify(state, null, 2));
  await fs.rename(tempPath, statePath);
}

async function writeSafetyBackup() {
  if (!fsSync.existsSync(statePath)) {
    return null;
  }
  await fs.mkdir(backupRoot, { recursive: true });
  const backupPath = path.join(backupRoot, `pre-maintenance-state-${stamp()}.json.gz`);
  const current = await fs.readFile(statePath);
  await fs.writeFile(backupPath, zlib.gzipSync(current, { level: 9 }));
  return backupPath;
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

function compactState(state, options) {
  const now = Date.now();
  const ticketRetentionMs = options.ticketRetentionDays * 24 * 60 * 60 * 1000;
  const sessionsBefore = state.sessions.length;
  const ticketsBefore = state.tickets.length;
  const sessions = state.sessions.filter((session) =>
    session && !session.revokedAt && new Date(session.expiresAt).getTime() > now
  );
  const tickets = state.tickets.filter((ticket) => !shouldRemoveTicket(ticket, now, ticketRetentionMs));
  if (!options.dryRun) {
    state.sessions = sessions;
    state.tickets = tickets;
  }
  return {
    sessionsBefore,
    sessionsAfter: sessions.length,
    sessionsRemoved: sessionsBefore - sessions.length,
    ticketsBefore,
    ticketsAfter: tickets.length,
    ticketsRemoved: ticketsBefore - tickets.length,
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

async function main() {
  const options = {
    dryRun: flag('--dry-run'),
    cleanArtifactCache: flag('--clean-artifact-cache'),
    ticketRetentionDays: parsePositiveInt(process.env.VINO_TICKET_RETENTION_DAYS, 30),
    downloadWorkRetentionMinutes: parsePositiveInt(process.env.VINO_DOWNLOAD_WORK_RETENTION_MINUTES, 60),
    artifactCacheRetentionDays: parsePositiveInt(process.env.VINO_ARTIFACT_CACHE_RETENTION_DAYS, 30),
  };

  if (!fsSync.existsSync(statePath)) {
    throw new Error(`state file not found: ${statePath}`);
  }
  const state = await readState();
  const stateSummary = compactState(state, options);
  const downloadWork = await cleanupDirectoryFiles(downloadWorkRoot, {
    olderThanMs: options.downloadWorkRetentionMinutes * 60 * 1000,
    dryRun: options.dryRun,
  });
  const artifactCache = options.cleanArtifactCache
    ? await cleanupDirectoryFiles(artifactCacheRoot, {
      olderThanMs: options.artifactCacheRetentionDays * 24 * 60 * 60 * 1000,
      dryRun: options.dryRun,
    })
    : null;

  const changed = stateSummary.sessionsRemoved > 0
    || stateSummary.ticketsRemoved > 0
    || downloadWork.removedFiles > 0
    || (artifactCache?.removedFiles || 0) > 0;
  const safetyBackupPath = !options.dryRun && changed ? await writeSafetyBackup() : null;
  if (!options.dryRun && (stateSummary.sessionsRemoved > 0 || stateSummary.ticketsRemoved > 0)) {
    state.auditLogs.push({
      auditId: `audit-maint-${stamp()}`,
      actorUserId: null,
      actorType: 'system',
      action: 'ops.maintenance',
      objectType: 'ops',
      objectId: 'maintenance',
      payload: { options, state: stateSummary, files: { downloadWork, artifactCache } },
      createdAt: new Date().toISOString(),
    });
    await writeState(state);
  }

  console.log(JSON.stringify({
    ok: true,
    dryRun: options.dryRun,
    changed,
    safetyBackupPath,
    options,
    state: stateSummary,
    files: {
      downloadWork,
      artifactCache,
    },
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
