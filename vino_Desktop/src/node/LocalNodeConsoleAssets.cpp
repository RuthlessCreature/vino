#include "vino_desktop/LocalNodeConsoleAssets.hpp"

namespace vino::desktop {

std::string local_node_console_html() {
    return R"VINO(<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>vino LocalNode</title>
  <link rel="stylesheet" href="/app.css" />
</head>
<body class="shell">
  <header class="topbar">
    <div>
      <div class="eyebrow">vino local node</div>
      <h1>本地数据台</h1>
    </div>
    <div class="top-actions">
      <button id="refreshButton" class="btn btn-primary" type="button">刷新</button>
      <button id="reindexButton" class="btn" type="button">重建索引</button>
    </div>
  </header>

  <nav class="links" id="viewTabs">
    <button class="view-tab active" type="button" data-view="archive">文件归档</button>
    <button class="view-tab" type="button" data-view="results">检测结果</button>
    <button class="view-tab" type="button" data-view="logs">运行日志</button>
    <button class="view-tab" type="button" data-view="stats">统计数据</button>
    <button class="view-tab" type="button" data-view="outbox">补传队列</button>
  </nav>

  <section id="statusBanner" class="notice hidden"></section>
  <section id="summaryCards" class="summary-grid"></section>

  <main class="page-shell">
    <section class="page active" data-page="archive">
      <div class="page-header">
        <h2>文件归档</h2>
        <span class="subtitle">上传文件 · 本地预览 · 文件落盘</span>
      </div>

      <section class="panel">
        <form id="uploadForm" class="upload-grid">
          <label>
            <span>设备 ID</span>
            <input id="uploadDeviceId" type="text" placeholder="device-demo" />
          </label>
          <label>
            <span>产品 UUID</span>
            <input id="uploadProductUUID" type="text" placeholder="P-2026-04-27-0001" />
          </label>
          <label>
            <span>点位</span>
            <input id="uploadPointIndex" type="number" min="0" value="0" />
          </label>
          <label>
            <span>文件</span>
            <input id="uploadFile" type="file" accept="image/*,video/*,.txt,.json,.csv,.log" />
          </label>
          <button class="btn btn-primary" type="submit">上传到本地</button>
        </form>
        <div id="actionOutput" class="info-line muted">这里就做三件事：收文件、存本地、给你看。</div>
      </section>

      <section class="archive-grid">
        <section class="panel">
          <div class="panel-head">
            <h3>本地文件</h3>
            <span class="muted" id="assetCountLabel">0 条</span>
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>类型</th>
                  <th>文件名</th>
                  <th>设备</th>
                  <th>大小</th>
                  <th>时间</th>
                  <th>状态</th>
                  <th>操作</th>
                </tr>
              </thead>
              <tbody id="assetsTableBody"></tbody>
            </table>
          </div>
        </section>

        <section class="panel">
          <div class="panel-head">
            <h3 id="assetPreviewTitle">文件预览</h3>
            <a id="assetOpenLink" class="link-button hidden" href="#" target="_blank" rel="noreferrer">打开原文件</a>
          </div>
          <div id="assetPreviewMedia" class="preview-box empty">
            <div class="preview-empty">没有选中文件</div>
          </div>
          <dl id="assetPreviewMeta" class="meta-grid"></dl>
        </section>
      </section>
    </section>

    <section class="page" data-page="results">
      <div class="page-header">
        <h2>检测结果</h2>
        <span class="subtitle">本地保存的结果记录</span>
      </div>
      <section class="panel">
        <div class="panel-head">
          <h3>结果列表</h3>
          <span class="muted" id="resultCountLabel">0 条</span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>结果类型</th>
                <th>设备</th>
                <th>产品 UUID</th>
                <th>点位</th>
                <th>时间</th>
                <th>作业 ID</th>
              </tr>
            </thead>
            <tbody id="resultsTableBody"></tbody>
          </table>
        </div>
      </section>
    </section>

    <section class="page" data-page="logs">
      <div class="page-header">
        <h2>运行日志</h2>
        <span class="subtitle">本地接收的日志记录</span>
      </div>
      <section class="panel">
        <div class="panel-head">
          <h3>日志列表</h3>
          <span class="muted" id="logCountLabel">0 条</span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>级别</th>
                <th>设备</th>
                <th>分类</th>
                <th>内容</th>
                <th>时间</th>
              </tr>
            </thead>
            <tbody id="logsTableBody"></tbody>
          </table>
        </div>
      </section>
    </section>

    <section class="page" data-page="stats">
      <div class="page-header">
        <h2>统计数据</h2>
        <span class="subtitle">本地接收的统计值</span>
      </div>
      <section class="panel">
        <div class="panel-head">
          <h3>统计列表</h3>
          <span class="muted" id="statCountLabel">0 条</span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>指标</th>
                <th>数值</th>
                <th>设备</th>
                <th>时间</th>
                <th>记录 ID</th>
              </tr>
            </thead>
            <tbody id="statsTableBody"></tbody>
          </table>
        </div>
      </section>
    </section>

    <section class="page" data-page="outbox">
      <div class="page-header">
        <h2>补传队列</h2>
        <span class="subtitle">云端配置 · 手动补传 · 队列状态</span>
      </div>

      <section class="panel">
        <form id="cloudSyncForm" class="cloud-grid">
          <label>
            <span>云端地址</span>
            <input id="cloudBaseURL" type="text" placeholder="http://127.0.0.1:8787" />
          </label>
          <label class="toggle-row">
            <input id="cloudSyncEnabled" type="checkbox" />
            <span>启用自动补传</span>
          </label>
          <div class="inline-actions">
            <button class="btn btn-primary" type="submit">保存</button>
            <button id="flushOutboxButton" class="btn" type="button">立即补传</button>
          </div>
        </form>
        <div id="cloudSyncOutput" class="info-line muted">补传状态</div>
      </section>

      <section class="panel">
        <div class="panel-head">
          <h3>队列列表</h3>
          <span class="muted" id="outboxCountLabel">0 条</span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>类型</th>
                <th>引用</th>
                <th>目标</th>
                <th>状态</th>
                <th>更新时间</th>
              </tr>
            </thead>
            <tbody id="outboxTableBody"></tbody>
          </table>
        </div>
      </section>
    </section>
  </main>

  <script src="/app.js"></script>
</body>
</html>
)VINO";
}

std::string local_node_console_css() {
    return R"VINO(:root {
  color-scheme: dark;
  --bg: #0b0f14;
  --panel: #111826;
  --panel-soft: #0f1722;
  --line: #1f2a3a;
  --line-strong: rgba(98, 208, 255, 0.45);
  --text: #e7eef8;
  --muted: #93a7c2;
  --accent: #5bc8ff;
  --accent-strong: #8be0ff;
  --success: #38dba0;
  --warn: #ffcf57;
  --danger: #ff6b6b;
  --glass-bg: rgba(14, 20, 32, 0.72);
  --glass-soft: rgba(17, 28, 45, 0.56);
  --glass-border: rgba(91, 200, 255, 0.26);
}

* {
  box-sizing: border-box;
}

html,
body {
  min-height: 100%;
  margin: 0;
}

body {
  font-family: "Inter", "Segoe UI", sans-serif;
  color: var(--text);
  background:
    radial-gradient(circle at 15% 20%, rgba(91, 200, 255, 0.18), transparent 38%),
    radial-gradient(circle at 75% 10%, rgba(56, 219, 160, 0.1), transparent 30%),
    radial-gradient(circle at 80% 85%, rgba(255, 255, 255, 0.06), transparent 35%),
    repeating-linear-gradient(0deg, rgba(91, 200, 255, 0.04), rgba(91, 200, 255, 0.04) 1px, transparent 1px, transparent 32px),
    repeating-linear-gradient(90deg, rgba(91, 200, 255, 0.04), rgba(91, 200, 255, 0.04) 1px, transparent 1px, transparent 32px),
    var(--bg);
}

.shell {
  max-width: 1480px;
  margin: 0 auto;
  padding: 20px 24px 28px;
}

.topbar,
.panel,
.notice,
.summary-card,
.links {
  border: 1px solid var(--glass-border);
  background: var(--glass-bg);
  box-shadow: 0 18px 40px rgba(6, 10, 18, 0.45);
  backdrop-filter: blur(24px);
}

.topbar {
  border-radius: 20px;
  padding: 20px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
}

.eyebrow,
.subtitle,
label span {
  text-transform: uppercase;
  letter-spacing: 0.14em;
  color: var(--muted);
}

.eyebrow {
  font-size: 12px;
  margin-bottom: 8px;
}

h1,
h2,
h3 {
  margin: 0;
}

h1 {
  font-size: 30px;
}

h2 {
  font-size: 22px;
}

h3 {
  font-size: 18px;
}

.subtitle,
label span {
  font-size: 12px;
}

.top-actions,
.inline-actions {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.btn,
.view-tab,
.link-button {
  appearance: none;
  border-radius: 999px;
  border: 1px solid rgba(91, 200, 255, 0.28);
  background: rgba(10, 16, 26, 0.55);
  color: var(--accent-strong);
  cursor: pointer;
  transition: background 0.2s ease, color 0.2s ease, border 0.2s ease;
}

.btn {
  padding: 10px 16px;
  font-size: 13px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.btn-primary,
.view-tab.active {
  background: rgba(91, 200, 255, 0.24);
  border-color: var(--line-strong);
  color: #f7fbff;
}

.btn:hover,
.view-tab:hover,
.link-button:hover {
  background: rgba(91, 200, 255, 0.18);
  color: #f7fbff;
}

.links {
  margin-top: 14px;
  border-radius: 18px;
  padding: 12px 16px;
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.view-tab {
  padding: 9px 14px;
  font-size: 13px;
}

.notice {
  margin-top: 14px;
  border-radius: 16px;
  padding: 14px 16px;
}

.notice.success {
  color: var(--success);
}

.notice.warn {
  color: var(--warn);
}

.notice.error {
  color: var(--danger);
}

.hidden {
  display: none !important;
}

.summary-grid {
  margin-top: 14px;
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
}

.summary-card {
  border-radius: 18px;
  padding: 18px;
}

.summary-card .label {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--muted);
  margin-bottom: 10px;
}

.summary-card .value {
  font-size: 28px;
  font-weight: 700;
}

.summary-card .detail {
  margin-top: 8px;
  color: var(--muted);
  font-size: 13px;
  line-height: 1.5;
}

.page-shell {
  margin-top: 16px;
}

.page {
  display: none;
}

.page.active {
  display: grid;
  gap: 16px;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}

.panel {
  border-radius: 20px;
  padding: 18px;
}

.panel-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 14px;
}

.upload-grid {
  display: grid;
  grid-template-columns: 1fr 1fr 0.7fr 1.3fr auto;
  gap: 12px;
  align-items: end;
}

.cloud-grid {
  display: grid;
  grid-template-columns: 1.4fr auto auto;
  gap: 12px;
  align-items: end;
}

.archive-grid {
  display: grid;
  grid-template-columns: 1.3fr 0.9fr;
  gap: 16px;
}

label {
  display: grid;
  gap: 8px;
}

input[type="text"],
input[type="number"],
input[type="file"] {
  width: 100%;
  padding: 10px 12px;
  border-radius: 10px;
  border: 1px solid rgba(91, 200, 255, 0.18);
  background: rgba(10, 16, 26, 0.72);
  color: var(--text);
}

input:focus {
  outline: none;
  border-color: var(--line-strong);
  box-shadow: 0 0 0 1px var(--line-strong);
}

.toggle-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 0;
}

.toggle-row input {
  width: auto;
}

.info-line {
  margin-top: 14px;
  min-height: 20px;
  color: var(--muted);
}

.table-wrap {
  border: 1px solid var(--line);
  border-radius: 14px;
  overflow: auto;
  background: var(--glass-soft);
}

table {
  width: 100%;
  border-collapse: collapse;
}

thead {
  background: rgba(12, 18, 30, 0.7);
}

th,
td {
  padding: 13px 14px;
  border-bottom: 1px solid rgba(91, 200, 255, 0.08);
  text-align: left;
  vertical-align: top;
  font-size: 14px;
}

tbody tr:hover {
  background: rgba(91, 200, 255, 0.06);
}

.badge {
  display: inline-flex;
  align-items: center;
  padding: 5px 9px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
}

.badge.ok {
  color: var(--success);
  background: rgba(56, 219, 160, 0.12);
}

.badge.warn {
  color: var(--warn);
  background: rgba(255, 207, 87, 0.14);
}

.badge.error {
  color: var(--danger);
  background: rgba(255, 107, 107, 0.12);
}

.badge.info {
  color: var(--accent-strong);
  background: rgba(91, 200, 255, 0.12);
}

.preview-box {
  min-height: 320px;
  border: 1px dashed rgba(91, 200, 255, 0.24);
  border-radius: 16px;
  background: rgba(10, 16, 26, 0.4);
  display: grid;
  place-items: center;
  overflow: hidden;
}

.preview-box img,
.preview-box video {
  width: 100%;
  height: 100%;
  object-fit: contain;
  display: block;
  background: #05080f;
}

.preview-box.empty {
  color: var(--muted);
}

.preview-empty {
  padding: 24px;
  text-align: center;
}

.meta-grid {
  margin-top: 14px;
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}

.meta-item {
  border: 1px solid rgba(91, 200, 255, 0.14);
  border-radius: 14px;
  padding: 12px;
  background: rgba(10, 16, 26, 0.36);
}

.meta-item dt {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--muted);
  margin-bottom: 8px;
}

.meta-item dd {
  margin: 0;
  line-height: 1.5;
  word-break: break-word;
}

.mono {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}

.link-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 8px 12px;
  text-decoration: none;
}

@media (max-width: 1200px) {
  .summary-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .upload-grid,
  .cloud-grid,
  .archive-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 760px) {
  .shell {
    padding: 14px;
  }

  .topbar,
  .page-header,
  .panel-head {
    flex-direction: column;
    align-items: flex-start;
  }

  .summary-grid,
  .meta-grid {
    grid-template-columns: 1fr;
  }

  .top-actions,
  .inline-actions {
    width: 100%;
    flex-direction: column;
  }
}
)VINO";
}

std::string local_node_console_js() {
    return R"VINO(const apiBase = '/api/local/v1';

const state = {
  activeView: 'archive',
  selectedAssetId: '',
  storage: {},
  assets: [],
  results: [],
  logs: [],
  stats: [],
  jobs: [],
};

const summaryCards = document.getElementById('summaryCards');
const statusBanner = document.getElementById('statusBanner');
const refreshButton = document.getElementById('refreshButton');
const reindexButton = document.getElementById('reindexButton');
const uploadForm = document.getElementById('uploadForm');
const cloudSyncForm = document.getElementById('cloudSyncForm');
const flushOutboxButton = document.getElementById('flushOutboxButton');
const assetsTableBody = document.getElementById('assetsTableBody');
const resultsTableBody = document.getElementById('resultsTableBody');
const logsTableBody = document.getElementById('logsTableBody');
const statsTableBody = document.getElementById('statsTableBody');
const outboxTableBody = document.getElementById('outboxTableBody');
const assetCountLabel = document.getElementById('assetCountLabel');
const resultCountLabel = document.getElementById('resultCountLabel');
const logCountLabel = document.getElementById('logCountLabel');
const statCountLabel = document.getElementById('statCountLabel');
const outboxCountLabel = document.getElementById('outboxCountLabel');
const actionOutput = document.getElementById('actionOutput');
const cloudSyncOutput = document.getElementById('cloudSyncOutput');
const assetPreviewTitle = document.getElementById('assetPreviewTitle');
const assetPreviewMedia = document.getElementById('assetPreviewMedia');
const assetPreviewMeta = document.getElementById('assetPreviewMeta');
const assetOpenLink = document.getElementById('assetOpenLink');
const tabs = Array.from(document.querySelectorAll('.view-tab'));
const pages = Array.from(document.querySelectorAll('.page'));

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatBytes(bytes) {
  const value = Number(bytes || 0);
  if (value < 1024) return `${value} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let size = value / 1024;
  let index = 0;
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024;
    index += 1;
  }
  return `${size.toFixed(size >= 10 ? 1 : 2)} ${units[index]}`;
}

function badge(label, className = 'info') {
  return `<span class="badge ${className}">${escapeHtml(label)}</span>`;
}

function toneForStatus(status) {
  const normalized = String(status || '').toLowerCase();
  if (normalized === 'synced' || normalized === 'online') return 'ok';
  if (normalized === 'retry' || normalized === 'pending') return 'warn';
  if (normalized === 'error' || normalized === 'failed' || normalized === 'offline') return 'error';
  return 'info';
}

function assetContentUrl(assetId) {
  return `${apiBase}/assets/${encodeURIComponent(assetId || '')}/content`;
}

function isImageAsset(asset) {
  const category = String(asset.category || '').toLowerCase();
  const name = String(asset.fileName || '').toLowerCase();
  return category === 'image' || /\.(jpg|jpeg|png|webp|gif|bmp|tif|tiff|svg)$/.test(name);
}

function isVideoAsset(asset) {
  const category = String(asset.category || '').toLowerCase();
  const name = String(asset.fileName || '').toLowerCase();
  return category === 'video' || /\.(mp4|mov|m4v|webm|ogv|avi)$/.test(name);
}

function assetTypeLabel(asset) {
  if (isImageAsset(asset)) return '图片';
  if (isVideoAsset(asset)) return '视频';
  return '文件';
}

function setBanner(message, kind = 'success') {
  statusBanner.textContent = message;
  statusBanner.className = `notice ${kind}`;
}

function clearBanner() {
  statusBanner.textContent = '';
  statusBanner.className = 'notice hidden';
}

async function fetchJson(path, options = undefined) {
  const response = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });

  const text = await response.text();
  let payload = {};
  try {
    payload = text ? JSON.parse(text) : {};
  } catch (error) {
    payload = { raw: text };
  }

  if (!response.ok) {
    throw new Error(payload.error || payload.message || `HTTP ${response.status}`);
  }
  return payload;
}

function setActiveView(view) {
  state.activeView = view;
  tabs.forEach((tab) => tab.classList.toggle('active', tab.dataset.view === view));
  pages.forEach((page) => page.classList.toggle('active', page.dataset.page === view));
}

function renderSummary(storage) {
  const cloudSync = storage.cloudSync || {};
  const cards = [
    {
      label: '本地文件',
      value: String(storage.assetCount || 0),
      detail: `总大小 ${formatBytes(storage.totalBytes || 0)}`,
    },
    {
      label: '检测结果',
      value: String(storage.resultCount || 0),
      detail: storage.lastSyncAt || '暂无时间',
    },
    {
      label: '运行日志',
      value: String(storage.logCount || 0),
      detail: storage.databasePath || '-',
    },
    {
      label: '补传队列',
      value: String(storage.pendingJobs || 0),
      detail: cloudSync.enabled ? (cloudSync.baseURL || '已启用') : '未启用',
    },
  ];

  summaryCards.innerHTML = cards.map((card) => `
    <article class="summary-card">
      <div class="label">${escapeHtml(card.label)}</div>
      <div class="value">${escapeHtml(card.value)}</div>
      <div class="detail mono">${escapeHtml(card.detail)}</div>
    </article>
  `).join('');
}

function renderAssetPreview() {
  const asset = state.assets.find((item) => item.assetId === state.selectedAssetId);
  if (!asset) {
    assetPreviewTitle.textContent = '文件预览';
    assetPreviewMedia.className = 'preview-box empty';
    assetPreviewMedia.innerHTML = '<div class="preview-empty">没有选中文件</div>';
    assetPreviewMeta.innerHTML = '';
    assetOpenLink.classList.add('hidden');
    assetOpenLink.removeAttribute('href');
    return;
  }

  assetPreviewTitle.textContent = asset.fileName || '文件预览';
  assetOpenLink.href = assetContentUrl(asset.assetId);
  assetOpenLink.classList.remove('hidden');

  if (isImageAsset(asset)) {
    assetPreviewMedia.className = 'preview-box';
    assetPreviewMedia.innerHTML = `<img src="${assetContentUrl(asset.assetId)}" alt="${escapeHtml(asset.fileName || 'image')}" />`;
  } else if (isVideoAsset(asset)) {
    assetPreviewMedia.className = 'preview-box';
    assetPreviewMedia.innerHTML = `<video src="${assetContentUrl(asset.assetId)}" controls preload="metadata"></video>`;
  } else {
    assetPreviewMedia.className = 'preview-box empty';
    assetPreviewMedia.innerHTML = '<div class="preview-empty">这个文件类型不做内嵌预览，点右上角可以直接打开原文件。</div>';
  }

  const fields = [
    ['类型', assetTypeLabel(asset)],
    ['设备 ID', asset.deviceId || '-'],
    ['文件大小', formatBytes(asset.byteCount || 0)],
    ['采集时间', asset.capturedAt || '-'],
    ['云状态', asset.cloudStatus || 'local_only'],
    ['文件路径', asset.filePath || '-'],
  ];

  assetPreviewMeta.innerHTML = fields.map(([label, value]) => `
    <div class="meta-item">
      <dt>${escapeHtml(label)}</dt>
      <dd class="${label === '文件路径' || label.endsWith('ID') || label.includes('时间') ? 'mono' : ''}">${escapeHtml(value)}</dd>
    </div>
  `).join('');
}

function renderAssets(assets) {
  assetCountLabel.textContent = `${assets.length} 条`;
  if (!assets.some((asset) => asset.assetId === state.selectedAssetId)) {
    state.selectedAssetId = assets[0] ? assets[0].assetId : '';
  }

  if (assets.length === 0) {
    assetsTableBody.innerHTML = `
      <tr>
        <td colspan="7" class="muted">暂无本地文件</td>
      </tr>
    `;
    renderAssetPreview();
    return;
  }

  assetsTableBody.innerHTML = assets.map((asset) => `
    <tr>
      <td>${badge(assetTypeLabel(asset), 'info')}</td>
      <td class="mono">${escapeHtml(asset.fileName || '-')}</td>
      <td>${escapeHtml(asset.deviceId || '-')}</td>
      <td>${formatBytes(asset.byteCount || 0)}</td>
      <td class="mono">${escapeHtml(asset.capturedAt || '-')}</td>
      <td>${badge(asset.cloudStatus || 'local_only', toneForStatus(asset.cloudStatus))}</td>
      <td><button type="button" class="link-button" data-asset-focus="${escapeHtml(asset.assetId || '')}">查看</button></td>
    </tr>
  `).join('');

  renderAssetPreview();
}

function renderResults(results) {
  resultCountLabel.textContent = `${results.length} 条`;
  if (results.length === 0) {
    resultsTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="muted">暂无结果</td>
      </tr>
    `;
    return;
  }

  resultsTableBody.innerHTML = results.map((item) => `
    <tr>
      <td>${escapeHtml(item.resultType || '-')}</td>
      <td>${escapeHtml(item.deviceId || '-')}</td>
      <td class="mono">${escapeHtml(item.productUUID || '-')}</td>
      <td>${escapeHtml(String(item.pointIndex ?? '-'))}</td>
      <td class="mono">${escapeHtml(item.capturedAt || '-')}</td>
      <td class="mono">${escapeHtml(item.jobId || '-')}</td>
    </tr>
  `).join('');
}

function renderLogs(logs) {
  logCountLabel.textContent = `${logs.length} 条`;
  if (logs.length === 0) {
    logsTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="muted">暂无日志</td>
      </tr>
    `;
    return;
  }

  logsTableBody.innerHTML = logs.map((item) => `
    <tr>
      <td>${badge(item.level || 'info', toneForStatus(item.level))}</td>
      <td>${escapeHtml(item.deviceId || '-')}</td>
      <td>${escapeHtml(item.category || '-')}</td>
      <td>${escapeHtml(item.message || '-')}</td>
      <td class="mono">${escapeHtml(item.capturedAt || item.createdAt || '-')}</td>
    </tr>
  `).join('');
}

function renderStats(stats) {
  statCountLabel.textContent = `${stats.length} 条`;
  if (stats.length === 0) {
    statsTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="muted">暂无统计</td>
      </tr>
    `;
    return;
  }

  statsTableBody.innerHTML = stats.map((item) => `
    <tr>
      <td>${escapeHtml(item.metric || '-')}</td>
      <td>${escapeHtml(item.value || '-')}</td>
      <td>${escapeHtml(item.deviceId || '-')}</td>
      <td class="mono">${escapeHtml(item.capturedAt || item.createdAt || '-')}</td>
      <td class="mono">${escapeHtml(item.statId || '-')}</td>
    </tr>
  `).join('');
}

function renderCloudSync(cloudSync) {
  const normalized = cloudSync || {};
  document.getElementById('cloudBaseURL').value = normalized.baseURL || '';
  document.getElementById('cloudSyncEnabled').checked = Boolean(normalized.enabled);

  if (!normalized.enabled) {
    cloudSyncOutput.textContent = '自动补传关闭，本地只保存数据。';
    return;
  }

  const parts = [
    normalized.baseURL || '未配置地址',
    normalized.lastFlushStatus || 'idle',
  ];
  if (normalized.lastFlushAt) parts.push(normalized.lastFlushAt);
  if (normalized.lastError) parts.push(`错误：${normalized.lastError}`);
  cloudSyncOutput.textContent = parts.join(' · ');
}

function renderOutbox(jobs) {
  outboxCountLabel.textContent = `${jobs.length} 条`;
  if (jobs.length === 0) {
    outboxTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="muted">暂无待补传任务</td>
      </tr>
    `;
    return;
  }

  outboxTableBody.innerHTML = jobs.map((job) => `
    <tr>
      <td>${escapeHtml(job.jobType || '-')}</td>
      <td class="mono">${escapeHtml(job.refId || '-')}</td>
      <td class="mono">${escapeHtml(job.cloudEndpoint || '-')}</td>
      <td>${badge(job.status || 'pending', toneForStatus(job.status))}</td>
      <td class="mono">${escapeHtml(job.updatedAt || '-')}</td>
    </tr>
  `).join('');
}

async function refreshOverview(showToast = false) {
  try {
    const [health, assetsPayload, resultsPayload, logsPayload, statsPayload, outboxPayload] = await Promise.all([
      fetchJson(`${apiBase}/health`),
      fetchJson(`${apiBase}/assets?limit=30`),
      fetchJson(`${apiBase}/results?limit=50`),
      fetchJson(`${apiBase}/logs?limit=50`),
      fetchJson(`${apiBase}/stats?limit=50`),
      fetchJson(`${apiBase}/outbox?limit=50`),
    ]);

    state.storage = health.storage || {};
    state.assets = Array.isArray(assetsPayload.assets) ? assetsPayload.assets : [];
    state.results = Array.isArray(resultsPayload.results) ? resultsPayload.results : [];
    state.logs = Array.isArray(logsPayload.logs) ? logsPayload.logs : [];
    state.stats = Array.isArray(statsPayload.stats) ? statsPayload.stats : [];
    state.jobs = Array.isArray(outboxPayload.jobs) ? outboxPayload.jobs : [];

    renderSummary(state.storage);
    renderAssets(state.assets);
    renderResults(state.results);
    renderLogs(state.logs);
    renderStats(state.stats);
    renderCloudSync(state.storage.cloudSync || {});
    renderOutbox(state.jobs);

    if (showToast) {
      setBanner('本地数据已刷新', 'success');
      setTimeout(clearBanner, 1600);
    }
  } catch (error) {
    setBanner(`刷新失败：${error.message}`, 'error');
  }
}

tabs.forEach((tab) => {
  tab.addEventListener('click', () => {
    setActiveView(tab.dataset.view || 'archive');
  });
});

assetsTableBody.addEventListener('click', (event) => {
  const target = event.target.closest('[data-asset-focus]');
  if (!target) return;
  state.selectedAssetId = target.getAttribute('data-asset-focus') || '';
  renderAssetPreview();
});

refreshButton.addEventListener('click', () => refreshOverview(true));

reindexButton.addEventListener('click', async () => {
  try {
    const result = await fetchJson(`${apiBase}/index/rebuild`, { method: 'POST' });
    actionOutput.textContent = `索引已刷新：当前本地文件 ${result.storage.assetCount || 0} 条`;
    setBanner('索引已重建', 'success');
    refreshOverview();
  } catch (error) {
    setBanner(`索引失败：${error.message}`, 'error');
  }
});

uploadForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const fileInput = document.getElementById('uploadFile');
  const file = fileInput.files[0];
  const deviceId = document.getElementById('uploadDeviceId').value.trim();
  const productUUID = document.getElementById('uploadProductUUID').value.trim();
  const pointIndex = Number(document.getElementById('uploadPointIndex').value || 0);

  if (!deviceId) {
    setBanner('请输入设备 ID', 'warn');
    return;
  }
  if (!file) {
    setBanner('请选择文件', 'warn');
    return;
  }

  const contentBase64 = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const value = String(reader.result || '');
      const marker = value.indexOf(',');
      resolve(marker >= 0 ? value.slice(marker + 1) : value);
    };
    reader.onerror = () => reject(new Error('文件读取失败'));
    reader.readAsDataURL(file);
  });

  try {
    const result = await fetchJson(`${apiBase}/ingest/asset`, {
      method: 'POST',
      body: JSON.stringify({
        deviceId,
        fileName: file.name,
        category: file.type.startsWith('image/') ? 'image' : file.type.startsWith('video/') ? 'video' : '',
        productUUID,
        pointIndex,
        contentBase64,
      }),
    });
    actionOutput.textContent = `已保存：${result.fileName} -> ${result.assetId}`;
    setBanner('文件已存到本地', 'success');
    uploadForm.reset();
    refreshOverview();
  } catch (error) {
    setBanner(`上传失败：${error.message}`, 'error');
  }
});

cloudSyncForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    const result = await fetchJson(`${apiBase}/cloud/config`, {
      method: 'POST',
      body: JSON.stringify({
        baseURL: document.getElementById('cloudBaseURL').value.trim(),
        enabled: document.getElementById('cloudSyncEnabled').checked,
      }),
    });
    renderCloudSync(result.cloudSync || {});
    setBanner('补传配置已保存', 'success');
    refreshOverview();
  } catch (error) {
    setBanner(`补传配置失败：${error.message}`, 'error');
  }
});

flushOutboxButton.addEventListener('click', async () => {
  try {
    const result = await fetchJson(`${apiBase}/outbox/flush`, { method: 'POST' });
    const report = result.report || {};
    cloudSyncOutput.textContent = `本次补传：尝试 ${report.attempted || 0}，成功 ${report.succeeded || 0}，失败 ${report.failed || 0}`;
    setBanner('补传已执行', report.failed ? 'warn' : 'success');
    refreshOverview();
  } catch (error) {
    setBanner(`补传失败：${error.message}`, 'error');
  }
});

refreshOverview();
setInterval(() => refreshOverview(false), 5000);
)VINO";
}

} // namespace vino::desktop
