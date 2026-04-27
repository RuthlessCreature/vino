const loginSection = document.getElementById('loginSection');
const dashboardSection = document.getElementById('dashboardSection');
const loginForm = document.getElementById('loginForm');
const loginAccountInput = document.getElementById('loginAccountInput');
const loginPasswordInput = document.getElementById('loginPasswordInput');
const loginErrorLabel = document.getElementById('loginErrorLabel');
const currentAdminLabel = document.getElementById('currentAdminLabel');
const logoutButton = document.getElementById('logoutButton');

const summaryCards = document.getElementById('summaryCards');
const modelsTableBody = document.getElementById('modelsTableBody');
const assetsTableBody = document.getElementById('assetsTableBody');
const resultsTableBody = document.getElementById('resultsTableBody');
const usersTableBody = document.getElementById('usersTableBody');
const entitlementsTableBody = document.getElementById('entitlementsTableBody');
const modelCountLabel = document.getElementById('modelCountLabel');
const assetCountLabel = document.getElementById('assetCountLabel');
const resultCountLabel = document.getElementById('resultCountLabel');
const userCountLabel = document.getElementById('userCountLabel');
const entitlementCountLabel = document.getElementById('entitlementCountLabel');
const lastUpdatedLabel = document.getElementById('lastUpdatedLabel');
const refreshButton = document.getElementById('refreshButton');
const userForm = document.getElementById('userForm');
const entitlementForm = document.getElementById('entitlementForm');
const entitlementIdInput = document.getElementById('entitlementIdInput');
const entitlementAssignedToInput = document.getElementById('entitlementAssignedToInput');
const entitlementModelInput = document.getElementById('entitlementModelInput');
const entitlementRenewalModeInput = document.getElementById('entitlementRenewalModeInput');
const entitlementRenewalEndsAtInput = document.getElementById('entitlementRenewalEndsAtInput');
const entitlementLicenseIdInput = document.getElementById('entitlementLicenseIdInput');
const entitlementDeviceBindingInput = document.getElementById('entitlementDeviceBindingInput');
const cancelEntitlementEditButton = document.getElementById('cancelEntitlementEditButton');
const renewalEndsAtField = document.getElementById('renewalEndsAtField');

const storageKey = 'vino.cloud.admin.session';
const loginAccountStorageKey = 'vino.cloud.admin.account';
const state = {
  authToken: '',
  viewer: null,
  users: [],
  models: [],
  entitlements: [],
  refreshTimer: null,
};

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function saveSession(session) {
  state.authToken = session?.accessToken || '';
  state.viewer = session?.user || null;
  if (session) {
    localStorage.setItem(storageKey, JSON.stringify(session));
  } else {
    localStorage.removeItem(storageKey);
  }
}

function saveLoginAccount(account) {
  const value = String(account || '').trim();
  if (value) {
    localStorage.setItem(loginAccountStorageKey, value);
  } else {
    localStorage.removeItem(loginAccountStorageKey);
  }
}

function loadLoginAccount() {
  return localStorage.getItem(loginAccountStorageKey) || '';
}

function loadSession() {
  const raw = localStorage.getItem(storageKey);
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    localStorage.removeItem(storageKey);
    return null;
  }
}

function showLogin(message = '') {
  dashboardSection.classList.add('is-hidden');
  loginSection.classList.remove('is-hidden');
  loginAccountInput.value = loadLoginAccount();
  loginPasswordInput.value = '';
  if (message) {
    loginErrorLabel.textContent = message;
    loginErrorLabel.classList.remove('is-hidden');
  } else {
    loginErrorLabel.textContent = '';
    loginErrorLabel.classList.add('is-hidden');
  }
  if (state.refreshTimer) {
    clearInterval(state.refreshTimer);
    state.refreshTimer = null;
  }
  if (loginAccountInput.value) {
    loginPasswordInput.focus();
  } else {
    loginAccountInput.focus();
  }
}

function showDashboard() {
  loginSection.classList.add('is-hidden');
  dashboardSection.classList.remove('is-hidden');
  const label = state.viewer
    ? `${state.viewer.displayName || state.viewer.email} · ${state.viewer.email || 'admin'}`
    : '已登录';
  currentAdminLabel.textContent = label;
  loginErrorLabel.textContent = '';
  loginErrorLabel.classList.add('is-hidden');
}

function formatBytes(bytes) {
  const value = Number(bytes || 0);
  if (value < 1024) return `${value} B`;
  const units = ['KB', 'MB', 'GB'];
  let size = value / 1024;
  let index = 0;
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024;
    index += 1;
  }
  return `${size.toFixed(size >= 10 ? 1 : 2)} ${units[index]}`;
}

function formatLeaseDate(value) {
  return value ? value.replace('T', ' ').replace('.000Z', 'Z') : '永久';
}

function formatDateTimeLocal(value) {
  if (!value) {
    return '';
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  const offset = date.getTimezoneOffset();
  const local = new Date(date.getTime() - offset * 60 * 1000);
  return local.toISOString().slice(0, 16);
}

async function fetchJson(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      'Content-Type': 'application/json',
      ...(state.authToken ? { Authorization: `Bearer ${state.authToken}` } : {}),
      ...(options.headers || {}),
    },
    ...options,
  });
  const payload = await response.json();
  if (!response.ok) {
    const error = new Error(payload.error || `HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return payload;
}

function renderCards(summary) {
  const cards = [
    { label: '在线会话', value: String(summary.activeSessions || 0), detail: `用户 ${summary.users || 0}` },
    { label: '模型目录', value: String(summary.models || 0), detail: `授权 ${summary.entitlements || 0}` },
    { label: '永久授权', value: String(summary.perpetualEntitlements || 0), detail: `定期 ${summary.fixedEntitlements || 0}` },
    { label: '有效租约', value: String(summary.activeLeases || 0), detail: '已下发到设备' },
    { label: '上传资产', value: String(summary.assets || 0), detail: '图片 / 视频' },
    { label: '结果总量', value: String(summary.results || 0), detail: `日志 ${summary.logs || 0} · 统计 ${summary.stats || 0}` },
  ];

  summaryCards.innerHTML = cards.map((card) => `
    <article class="card">
      <div class="card-label">${escapeHtml(card.label)}</div>
      <div class="card-value">${escapeHtml(card.value)}</div>
      <div class="card-detail">${escapeHtml(card.detail)}</div>
    </article>
  `).join('');
}

function renderModels(models) {
  modelCountLabel.textContent = `${models.length} 个`;
  if (models.length === 0) {
    modelsTableBody.innerHTML = '<tr><td colspan="6" class="muted">暂无模型</td></tr>';
    return;
  }
  modelsTableBody.innerHTML = models.map((model) => `
    <tr>
      <td>
        <div>${escapeHtml(model.name)}</div>
        <div class="table-subtle mono">${escapeHtml(model.id)}</div>
      </td>
      <td>${escapeHtml(model.version)}</td>
      <td>${escapeHtml(model.assignmentCount)}</td>
      <td>${escapeHtml(model.userAssignmentCount)}</td>
      <td>${escapeHtml(model.organizationAssignmentCount)}</td>
      <td>${escapeHtml(formatBytes(model.byteCount))}</td>
    </tr>
  `).join('');
}

function renderUsers(users) {
  userCountLabel.textContent = `${users.length} 个`;
  if (users.length === 0) {
    usersTableBody.innerHTML = '<tr><td colspan="4" class="muted">暂无用户</td></tr>';
    return;
  }
  usersTableBody.innerHTML = users.map((user) => `
    <tr>
      <td>
        <div>${escapeHtml(user.displayName)}</div>
        <div class="table-subtle mono">${escapeHtml(user.email)}</div>
      </td>
      <td><span class="badge">${escapeHtml(user.role === 'admin' ? '管理员' : '成员')}</span></td>
      <td>
        <div>${escapeHtml(user.organizationName)}</div>
        <div class="table-subtle mono">${escapeHtml(user.organizationId)}</div>
      </td>
      <td>${escapeHtml(user.assignedModelCount || 0)}</td>
    </tr>
  `).join('');
}

function renderEntitlements(entitlements) {
  entitlementCountLabel.textContent = `${entitlements.length} 条`;
  if (entitlements.length === 0) {
    entitlementsTableBody.innerHTML = '<tr><td colspan="6" class="muted">暂无授权</td></tr>';
    return;
  }
  entitlementsTableBody.innerHTML = entitlements.map((entitlement) => `
    <tr>
      <td>
        <div>${escapeHtml(entitlement.assignedToLabel)}</div>
        <div class="table-subtle mono">${escapeHtml(entitlement.licenseId)}</div>
      </td>
      <td>${escapeHtml(entitlement.modelName)}</td>
      <td><span class="badge">${escapeHtml(entitlement.renewalMode === 'fixed' ? '截止时间' : '永久')}</span></td>
      <td class="mono">${escapeHtml(formatLeaseDate(entitlement.renewalEndsAt))}</td>
      <td>${entitlement.isRenewableNow ? '<span class="badge badge-success">生效中</span>' : '<span class="badge badge-danger">已到期</span>'}</td>
      <td class="actions-cell">
        <button class="btn btn-small" type="button" data-action="edit-entitlement" data-entitlement-id="${escapeHtml(entitlement.entitlementId)}">编辑</button>
        <button class="btn btn-small btn-danger" type="button" data-action="delete-entitlement" data-entitlement-id="${escapeHtml(entitlement.entitlementId)}">删除</button>
      </td>
    </tr>
  `).join('');
}

function renderAssets(assets) {
  assetCountLabel.textContent = `${assets.length} 条`;
  if (assets.length === 0) {
    assetsTableBody.innerHTML = '<tr><td colspan="4" class="muted">暂无资产</td></tr>';
    return;
  }
  assetsTableBody.innerHTML = assets.map((asset) => `
    <tr>
      <td>${escapeHtml(asset.deviceId || '-')}</td>
      <td class="mono">${escapeHtml(asset.fileName || '-')}</td>
      <td>${escapeHtml(asset.category || '-')}</td>
      <td class="mono">${escapeHtml(asset.capturedAt || '-')}</td>
    </tr>
  `).join('');
}

function renderResults(results) {
  resultCountLabel.textContent = `${results.length} 条`;
  if (results.length === 0) {
    resultsTableBody.innerHTML = '<tr><td colspan="4" class="muted">暂无结果</td></tr>';
    return;
  }
  resultsTableBody.innerHTML = results.map((result) => `
    <tr>
      <td>${escapeHtml(result.deviceId || '-')}</td>
      <td>${escapeHtml(result.resultType || '-')}</td>
      <td class="mono">${escapeHtml(result.jobId || '-')}</td>
      <td class="mono">${escapeHtml(result.capturedAt || '-')}</td>
    </tr>
  `).join('');
}

function updateEntitlementFormOptions() {
  entitlementAssignedToInput.innerHTML = state.users.map((user) => `
    <option value="${escapeHtml(user.userId)}">${escapeHtml(`${user.displayName} · ${user.email}`)}</option>
  `).join('');
  entitlementModelInput.innerHTML = state.models.map((model) => `
    <option value="${escapeHtml(model.id)}">${escapeHtml(`${model.name} · ${model.version}`)}</option>
  `).join('');
}

function toggleRenewalEndsAtField() {
  const isFixed = entitlementRenewalModeInput.value === 'fixed';
  renewalEndsAtField.classList.toggle('is-hidden', !isFixed);
  entitlementRenewalEndsAtInput.required = isFixed;
}

function resetEntitlementForm() {
  entitlementIdInput.value = '';
  entitlementForm.reset();
  entitlementDeviceBindingInput.checked = true;
  entitlementRenewalModeInput.value = 'perpetual';
  toggleRenewalEndsAtField();
}

function fillEntitlementForm(entitlementId) {
  const entitlement = state.entitlements.find((item) => item.entitlementId === entitlementId);
  if (!entitlement) {
    return;
  }
  entitlementIdInput.value = entitlement.entitlementId;
  entitlementAssignedToInput.value = entitlement.assignedToId;
  entitlementModelInput.value = entitlement.modelId;
  entitlementRenewalModeInput.value = entitlement.renewalMode || 'perpetual';
  entitlementRenewalEndsAtInput.value = formatDateTimeLocal(entitlement.renewalEndsAt);
  entitlementLicenseIdInput.value = entitlement.licenseId || '';
  entitlementDeviceBindingInput.checked = entitlement.deviceBindingRequired !== false;
  toggleRenewalEndsAtField();
}

async function refreshOverview() {
  try {
    const payload = await fetchJson('/api/cloud/v1/admin/overview');
    state.users = payload.users || [];
    state.models = payload.models || [];
    state.entitlements = payload.entitlements || [];

    renderCards(payload.summary || {});
    renderUsers(state.users);
    renderModels(state.models);
    renderEntitlements(state.entitlements);
    renderAssets(payload.recentAssets || []);
    renderResults(payload.recentResults || []);
    updateEntitlementFormOptions();
    lastUpdatedLabel.textContent = `最近刷新 ${formatLeaseDate(payload.now)}`;

    if (!document.activeElement || document.activeElement === document.body) {
      resetEntitlementForm();
    }
  } catch (error) {
    if (error.status === 401 || error.status === 403) {
      saveSession(null);
      showLogin('登录已失效，请重新登录。');
      return;
    }
    window.alert(error.message);
  }
}

loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const formData = new FormData(loginForm);
  const account = String(formData.get('account') || '').trim();
  saveLoginAccount(account);
  try {
    const payload = await fetchJson('/api/cloud/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        account,
        password: formData.get('password'),
        deviceId: 'cloud-console',
        deviceName: 'Cloud Console',
        platform: 'web',
      }),
    });
    if (payload.user?.role !== 'admin') {
      showLogin('当前账号不是管理员。');
      return;
    }
    saveLoginAccount(account);
    saveSession(payload);
    showDashboard();
    await refreshOverview();
    if (!state.refreshTimer) {
      state.refreshTimer = setInterval(refreshOverview, 5000);
    }
  } catch (error) {
    showLogin(error.message);
  }
});

logoutButton.addEventListener('click', () => {
  saveSession(null);
  showLogin();
});

userForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const formData = new FormData(userForm);
  const payload = {
    displayName: formData.get('displayName'),
    email: formData.get('email'),
    password: formData.get('password'),
    role: formData.get('role'),
    organizationId: formData.get('organizationId'),
    organizationName: formData.get('organizationName'),
  };
  try {
    await fetchJson('/api/cloud/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    userForm.reset();
    document.getElementById('userRoleInput').value = 'member';
    document.getElementById('userOrganizationIdInput').value = state.users[0]?.organizationId || 'org-demo-001';
    document.getElementById('userOrganizationNameInput').value = state.users[0]?.organizationName || 'Vino Demo Factory';
    await refreshOverview();
  } catch (error) {
    window.alert(error.message);
  }
});

entitlementForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const payload = {
    entitlementId: entitlementIdInput.value || undefined,
    assignedToType: 'user',
    assignedToId: entitlementAssignedToInput.value,
    modelId: entitlementModelInput.value,
    renewalMode: entitlementRenewalModeInput.value,
    renewalEndsAt: entitlementRenewalModeInput.value === 'fixed' ? entitlementRenewalEndsAtInput.value : null,
    licenseId: entitlementLicenseIdInput.value || undefined,
    deviceBindingRequired: entitlementDeviceBindingInput.checked,
  };
  try {
    await fetchJson('/api/cloud/v1/admin/entitlements', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    resetEntitlementForm();
    await refreshOverview();
  } catch (error) {
    window.alert(error.message);
  }
});

entitlementsTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button[data-action]');
  if (!button) {
    return;
  }
  const entitlementId = button.dataset.entitlementId;
  if (button.dataset.action === 'edit-entitlement') {
    fillEntitlementForm(entitlementId);
    entitlementForm.scrollIntoView({ behavior: 'smooth', block: 'center' });
    return;
  }
  if (button.dataset.action === 'delete-entitlement') {
    if (!window.confirm('确认删除这条授权吗？')) {
      return;
    }
    try {
      await fetchJson(`/api/cloud/v1/admin/entitlements/${entitlementId}/delete`, {
        method: 'POST',
      });
      await refreshOverview();
    } catch (error) {
      window.alert(error.message);
    }
  }
});

cancelEntitlementEditButton.addEventListener('click', () => {
  resetEntitlementForm();
});

entitlementRenewalModeInput.addEventListener('change', () => {
  toggleRenewalEndsAtField();
});

refreshButton.addEventListener('click', async () => {
  await refreshOverview();
});

toggleRenewalEndsAtField();

const persistedSession = loadSession();
if (persistedSession?.accessToken) {
  saveSession(persistedSession);
  showDashboard();
  refreshOverview();
  state.refreshTimer = setInterval(refreshOverview, 5000);
} else {
  showLogin();
}
