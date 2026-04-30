const els = {
  loginView: document.getElementById('loginView'),
  appView: document.getElementById('appView'),
  loginForm: document.getElementById('loginForm'),
  loginAccountInput: document.getElementById('loginAccountInput'),
  loginPasswordInput: document.getElementById('loginPasswordInput'),
  loginErrorLabel: document.getElementById('loginErrorLabel'),
  currentUserLabel: document.getElementById('currentUserLabel'),
  lastUpdatedLabel: document.getElementById('lastUpdatedLabel'),
  refreshButton: document.getElementById('refreshButton'),
  logoutButton: document.getElementById('logoutButton'),
  summaryGrid: document.getElementById('summaryGrid'),
  orderForm: document.getElementById('orderForm'),
  orderBuyerOrganizationInput: document.getElementById('orderBuyerOrganizationInput'),
  orderSkuInput: document.getElementById('orderSkuInput'),
  orderQuantityInput: document.getElementById('orderQuantityInput'),
  orderPaymentModeInput: document.getElementById('orderPaymentModeInput'),
  orderCouponInput: document.getElementById('orderCouponInput'),
  marketSearchForm: document.getElementById('marketSearchForm'),
  marketQueryInput: document.getElementById('marketQueryInput'),
  marketCategoryInput: document.getElementById('marketCategoryInput'),
  marketTableBody: document.getElementById('marketTableBody'),
  marketCountLabel: document.getElementById('marketCountLabel'),
  developerProfileForm: document.getElementById('developerProfileForm'),
  developerDisplayNameInput: document.getElementById('developerDisplayNameInput'),
  developerTypeInput: document.getElementById('developerTypeInput'),
  developerAgreementInput: document.getElementById('developerAgreementInput'),
  developerModelForm: document.getElementById('developerModelForm'),
  developerModelNameInput: document.getElementById('developerModelNameInput'),
  developerModelCategoryInput: document.getElementById('developerModelCategoryInput'),
  developerModelSummaryInput: document.getElementById('developerModelSummaryInput'),
  developerModelTagsInput: document.getElementById('developerModelTagsInput'),
  developersTableBody: document.getElementById('developersTableBody'),
  developerCountLabel: document.getElementById('developerCountLabel'),
  reviewsTableBody: document.getElementById('reviewsTableBody'),
  reviewCountLabel: document.getElementById('reviewCountLabel'),
  entitlementForm: document.getElementById('entitlementForm'),
  entitlementIdInput: document.getElementById('entitlementIdInput'),
  entitlementModelInput: document.getElementById('entitlementModelInput'),
  entitlementAssignedTypeInput: document.getElementById('entitlementAssignedTypeInput'),
  entitlementAssignedToInput: document.getElementById('entitlementAssignedToInput'),
  entitlementRenewalModeInput: document.getElementById('entitlementRenewalModeInput'),
  entitlementRenewalEndsAtInput: document.getElementById('entitlementRenewalEndsAtInput'),
  entitlementOfflineDaysInput: document.getElementById('entitlementOfflineDaysInput'),
  entitlementDeviceBindingInput: document.getElementById('entitlementDeviceBindingInput'),
  clearEntitlementButton: document.getElementById('clearEntitlementButton'),
  userForm: document.getElementById('userForm'),
  userDisplayNameInput: document.getElementById('userDisplayNameInput'),
  userEmailInput: document.getElementById('userEmailInput'),
  userPasswordInput: document.getElementById('userPasswordInput'),
  userRoleInput: document.getElementById('userRoleInput'),
  userOrganizationInput: document.getElementById('userOrganizationInput'),
  skuForm: document.getElementById('skuForm'),
  skuModelInput: document.getElementById('skuModelInput'),
  skuNameInput: document.getElementById('skuNameInput'),
  skuPriceInput: document.getElementById('skuPriceInput'),
  skuLicenseTypeInput: document.getElementById('skuLicenseTypeInput'),
  skuDurationInput: document.getElementById('skuDurationInput'),
  skuMaxDevicesInput: document.getElementById('skuMaxDevicesInput'),
  skuOfflineDaysInput: document.getElementById('skuOfflineDaysInput'),
  ordersTableBody: document.getElementById('ordersTableBody'),
  auditTableBody: document.getElementById('auditTableBody'),
  entitlementsTableBody: document.getElementById('entitlementsTableBody'),
  modelsTableBody: document.getElementById('modelsTableBody'),
  devicesTableBody: document.getElementById('devicesTableBody'),
  resultsTableBody: document.getElementById('resultsTableBody'),
  assetsTableBody: document.getElementById('assetsTableBody'),
  orderCountLabel: document.getElementById('orderCountLabel'),
  auditCountLabel: document.getElementById('auditCountLabel'),
  entitlementCountLabel: document.getElementById('entitlementCountLabel'),
  userCountLabel: document.getElementById('userCountLabel'),
  skuCountLabel: document.getElementById('skuCountLabel'),
  modelCountLabel: document.getElementById('modelCountLabel'),
  deviceCountLabel: document.getElementById('deviceCountLabel'),
  resultCountLabel: document.getElementById('resultCountLabel'),
  assetCountLabel: document.getElementById('assetCountLabel'),
  supportForm: document.getElementById('supportForm'),
  supportTitleInput: document.getElementById('supportTitleInput'),
  supportCategoryInput: document.getElementById('supportCategoryInput'),
  supportPriorityInput: document.getElementById('supportPriorityInput'),
  supportModelInput: document.getElementById('supportModelInput'),
  supportBodyInput: document.getElementById('supportBodyInput'),
  supportTableBody: document.getElementById('supportTableBody'),
  supportCountLabel: document.getElementById('supportCountLabel'),
  customRequestForm: document.getElementById('customRequestForm'),
  customTitleInput: document.getElementById('customTitleInput'),
  customBudgetInput: document.getElementById('customBudgetInput'),
  customDueInput: document.getElementById('customDueInput'),
  customCurrencyInput: document.getElementById('customCurrencyInput'),
  customScenarioInput: document.getElementById('customScenarioInput'),
  customRequestsTableBody: document.getElementById('customRequestsTableBody'),
  customRequestCountLabel: document.getElementById('customRequestCountLabel'),
  invoiceForm: document.getElementById('invoiceForm'),
  invoiceOrderInput: document.getElementById('invoiceOrderInput'),
  invoiceTypeInput: document.getElementById('invoiceTypeInput'),
  invoiceTitleInput: document.getElementById('invoiceTitleInput'),
  invoiceTaxInput: document.getElementById('invoiceTaxInput'),
  invoiceEmailInput: document.getElementById('invoiceEmailInput'),
  invoicesTableBody: document.getElementById('invoicesTableBody'),
  invoiceCountLabel: document.getElementById('invoiceCountLabel'),
  withdrawalForm: document.getElementById('withdrawalForm'),
  withdrawalAmountInput: document.getElementById('withdrawalAmountInput'),
  withdrawalAccountNameInput: document.getElementById('withdrawalAccountNameInput'),
  withdrawalAccountNoInput: document.getElementById('withdrawalAccountNoInput'),
  withdrawalCountLabel: document.getElementById('withdrawalCountLabel'),
  financeTableBody: document.getElementById('financeTableBody'),
  settlementCountLabel: document.getElementById('settlementCountLabel'),
  couponForm: document.getElementById('couponForm'),
  couponCodeInput: document.getElementById('couponCodeInput'),
  couponNameInput: document.getElementById('couponNameInput'),
  couponValueInput: document.getElementById('couponValueInput'),
  couponLimitInput: document.getElementById('couponLimitInput'),
  couponCountLabel: document.getElementById('couponCountLabel'),
  activityForm: document.getElementById('activityForm'),
  activityTitleInput: document.getElementById('activityTitleInput'),
  activityPlacementInput: document.getElementById('activityPlacementInput'),
  activityDescriptionInput: document.getElementById('activityDescriptionInput'),
  activityCountLabel: document.getElementById('activityCountLabel'),
  categoryForm: document.getElementById('categoryForm'),
  categoryNameInput: document.getElementById('categoryNameInput'),
  categorySlugInput: document.getElementById('categorySlugInput'),
  settingsForm: document.getElementById('settingsForm'),
  settingsCommissionInput: document.getElementById('settingsCommissionInput'),
  settingsTrialDaysInput: document.getElementById('settingsTrialDaysInput'),
  settingsOfflineDaysInput: document.getElementById('settingsOfflineDaysInput'),
  settingsTicketMinutesInput: document.getElementById('settingsTicketMinutesInput'),
  categoryCountLabel: document.getElementById('categoryCountLabel'),
  opsTableBody: document.getElementById('opsTableBody'),
  toast: document.getElementById('toast'),
};

const state = {
  token: localStorage.getItem('vino_platform_token') || '',
  user: JSON.parse(localStorage.getItem('vino_platform_user') || 'null'),
  permissions: JSON.parse(localStorage.getItem('vino_platform_permissions') || 'null'),
  overview: null,
  marketModels: [],
};

const ALL_TABS = ['overview', 'market', 'developer', 'commerce', 'catalog', 'terminal', 'service', 'finance', 'ops'];

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function formatDate(value) {
  if (!value) {
    return '-';
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '-';
  }
  return date.toLocaleString();
}

function formatMoney(value, currency = 'CNY') {
  return `${currency} ${Number(value || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function showToast(message) {
  els.toast.textContent = message;
  els.toast.classList.remove('hidden');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => els.toast.classList.add('hidden'), 2600);
}

async function fetchJson(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
      ...(options.headers || {}),
    },
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(payload.error?.message || payload.error || `HTTP ${response.status}`);
  }
  return payload;
}

function setSession(payload) {
  state.token = payload.accessToken;
  state.user = payload.user;
  state.permissions = payload.permissions || null;
  localStorage.setItem('vino_platform_token', state.token);
  localStorage.setItem('vino_platform_user', JSON.stringify(state.user));
  localStorage.setItem('vino_platform_permissions', JSON.stringify(state.permissions));
}

function clearSession() {
  state.token = '';
  state.user = null;
  state.permissions = null;
  state.overview = null;
  localStorage.removeItem('vino_platform_token');
  localStorage.removeItem('vino_platform_user');
  localStorage.removeItem('vino_platform_permissions');
}

function syncShell() {
  const signedIn = Boolean(state.token);
  els.loginView.classList.toggle('hidden', signedIn);
  els.appView.classList.toggle('hidden', !signedIn);
  els.currentUserLabel.textContent = state.user
    ? `${state.user.displayName} / ${state.user.roleLabel || state.permissions?.roleLabel || state.user.role}`
    : '未登录';
  if (signedIn && state.permissions) {
    applyRoleNavigation({ permissions: state.permissions });
  }
}

function applyRoleNavigation(data) {
  const allowedTabs = new Set(data.permissions?.tabs || state.permissions?.tabs || ['overview']);
  state.permissions = data.permissions || state.permissions;
  localStorage.setItem('vino_platform_permissions', JSON.stringify(state.permissions));
  document.querySelectorAll('.tab').forEach((button) => {
    button.classList.toggle('hidden', !allowedTabs.has(button.dataset.tab));
  });
  document.querySelectorAll('.tab-panel').forEach((panel) => {
    const tabName = panel.id.replace(/Tab$/, '');
    if (!allowedTabs.has(tabName)) {
      panel.classList.remove('active');
    }
  });
  const activeButton = document.querySelector('.tab.active:not(.hidden)');
  if (!activeButton) {
    const firstAllowed = ALL_TABS.find((tabName) => allowedTabs.has(tabName)) || 'overview';
    document.querySelectorAll('.tab').forEach((tab) => tab.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach((panel) => panel.classList.remove('active'));
    document.querySelector(`.tab[data-tab="${firstAllowed}"]`)?.classList.add('active');
    document.getElementById(`${firstAllowed}Tab`)?.classList.add('active');
  }
  els.developerProfileForm.closest('.panel')?.classList.toggle('hidden', !canDeveloperSelfService());
  els.developerModelForm.closest('.panel')?.classList.toggle('hidden', !canDeveloperSelfService());
  els.orderForm.closest('.panel')?.classList.toggle('hidden', !canCreateOrders());
  els.entitlementForm.closest('.panel')?.classList.toggle('hidden', !canManageEntitlements());
  els.skuForm.closest('.panel')?.classList.toggle('hidden', !canManageOps());
  els.userForm.closest('.panel')?.classList.toggle('hidden', !canManageOps());
  els.supportForm.closest('.panel')?.classList.toggle('hidden', !canCreateSupportTickets());
  els.customRequestForm.closest('.panel')?.classList.toggle('hidden', !canCreateCustomRequests());
  els.invoiceForm.closest('.panel')?.classList.toggle('hidden', !canRequestInvoices());
  els.withdrawalForm.closest('.panel')?.classList.toggle('hidden', !canRequestWithdrawals());
  els.couponForm.closest('.panel')?.classList.toggle('hidden', !canManageOps());
  els.activityForm.closest('.panel')?.classList.toggle('hidden', !canManageOps());
  els.categoryForm.closest('.panel')?.classList.toggle('hidden', !canManageOps());
  els.settingsForm.closest('.panel')?.classList.toggle('hidden', !canManageOps());
}

function option(value, label) {
  return `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`;
}

function statusBadge(status) {
  const normalized = String(status || '').toLowerCase();
  const className = ['active', 'paid', 'listed', 'approved', 'ready', 'completed'].includes(normalized)
    ? 'ok'
    : ['pending_payment', 'draft', 'in_review', 'issued'].includes(normalized)
      ? 'warn'
      : ['revoked', 'rejected', 'failed', 'disabled'].includes(normalized)
        ? 'danger'
        : '';
  return `<span class="badge ${className}">${escapeHtml(status || '-')}</span>`;
}

function currentRole() {
  return state.permissions?.role || state.user?.role || '';
}

function hasRole(...roles) {
  return roles.includes(currentRole());
}

function hasFeature(name, fallback) {
  const value = state.permissions?.features?.[name];
  return typeof value === 'boolean' ? value : fallback();
}

function canUseMarketplace() {
  return hasFeature('useMarketplace', () => hasRole('super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator'));
}

function canDeveloperSelfService() {
  return hasFeature('developerSelfService', () => hasRole('developer_admin'));
}

function canManageEntitlements() {
  return hasFeature('manageEntitlements', () => hasRole('super_admin', 'admin', 'platform_ops'));
}

function canCreateOrders() {
  return hasFeature('createOrders', () => hasRole('super_admin', 'admin', 'platform_ops', 'buyer_admin'));
}

function canConfirmPayments() {
  return hasFeature('confirmPayments', () => hasRole('super_admin', 'admin', 'platform_ops', 'finance'));
}

function canReviewModels() {
  return hasFeature('reviewModels', () => hasRole('super_admin', 'admin', 'platform_ops', 'reviewer'));
}

function canReviewFinance() {
  return hasFeature('reviewInvoices', () => hasRole('super_admin', 'admin', 'finance'));
}

function canManageOps() {
  return hasFeature('manageOps', () => hasRole('super_admin', 'admin', 'platform_ops'));
}

function canCreateSupportTickets() {
  return hasFeature('createSupportTickets', () => hasRole('super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator', 'developer_admin'));
}

function canCreateCustomRequests() {
  return hasFeature('createCustomRequests', () => hasRole('super_admin', 'admin', 'platform_ops', 'buyer_admin', 'buyer_operator'));
}

function canSubmitCustomProposals() {
  return hasFeature('submitCustomProposals', () => hasRole('super_admin', 'admin', 'platform_ops', 'developer_admin'));
}

function canRequestInvoices() {
  return hasFeature('requestInvoices', () => hasRole('super_admin', 'admin', 'buyer_admin'));
}

function canRequestWithdrawals() {
  return hasFeature('requestWithdrawals', () => hasRole('developer_admin'));
}

function renderSummary(summary) {
  const cards = [
    ['组织', summary.organizations, 'Organizations'],
    ['用户', summary.users, 'Users'],
    ['模型', summary.models, 'Models'],
    ['订单', summary.orders, `${summary.paidOrders || 0} paid`],
    ['授权', summary.entitlements, 'Entitlements'],
    ['设备', summary.devices, 'Devices'],
    ['工单', summary.supportTickets || 0, 'Support'],
    ['发票', summary.invoices || 0, 'Invoices'],
    ['结算', summary.settlements || 0, 'Settlements'],
  ];
  els.summaryGrid.innerHTML = cards.map(([label, value, detail]) => `
    <article class="summary-card">
      <div class="summary-label">${escapeHtml(label)}</div>
      <div class="summary-value">${escapeHtml(value)}</div>
      <div class="summary-detail">${escapeHtml(detail)}</div>
    </article>
  `).join('');
}

function renderSelects(data) {
  els.orderBuyerOrganizationInput.innerHTML = data.organizations
    .filter((org) => org.type === 'buyer')
    .map((org) => option(org.organizationId, `${org.name} / ${org.organizationId}`))
    .join('');
  els.userOrganizationInput.innerHTML = data.organizations.map((org) => option(org.organizationId, `${org.name} / ${org.organizationId}`)).join('');
  els.entitlementModelInput.innerHTML = data.models.map((model) => option(model.modelId, model.name)).join('');
  els.skuModelInput.innerHTML = data.models.map((model) => option(model.modelId, model.name)).join('');
  els.supportModelInput.innerHTML = '<option value="">不关联模型</option>' + data.models.map((model) => option(model.modelId, model.name)).join('');
  els.invoiceOrderInput.innerHTML = data.orders
    .filter((order) => ['paid', 'delivering', 'completed'].includes(order.status))
    .map((order) => option(order.orderId, `${order.orderId} / ${formatMoney(order.totalAmount, order.currency)}`))
    .join('');
  els.orderCouponInput.innerHTML = '<option value="">不使用优惠券</option>' + data.coupons
    .filter((coupon) => coupon.status === 'active')
    .map((coupon) => option(coupon.code, `${coupon.code} / ${coupon.name}`))
    .join('');
  const categoryOptions = '<option value="">全部分类</option>' + data.categories.map((category) => option(category.slug, `${category.name} / ${category.slug}`)).join('');
  els.marketCategoryInput.innerHTML = categoryOptions;
  els.developerModelCategoryInput.innerHTML = data.categories.map((category) => option(category.slug, category.name)).join('');
  els.orderSkuInput.innerHTML = data.modelSkus.map((sku) => {
    const model = data.models.find((item) => item.modelId === sku.modelId);
    return option(sku.skuId, `${model?.name || sku.modelId} / ${sku.name} / ${formatMoney(sku.priceAmount, sku.currency)}`);
  }).join('');
  renderAssignmentOptions();
}

function renderAssignmentOptions() {
  const data = state.overview;
  if (!data) {
    return;
  }
  if (els.entitlementAssignedTypeInput.value === 'organization') {
    els.entitlementAssignedToInput.innerHTML = data.organizations.map((org) => option(org.organizationId, `${org.name} / ${org.organizationId}`)).join('');
    return;
  }
  els.entitlementAssignedToInput.innerHTML = data.users.map((user) => option(user.userId, `${user.displayName} / ${user.email}`)).join('');
}

function renderOrders(orders) {
  els.orderCountLabel.textContent = `${orders.length}`;
  if (orders.length === 0) {
    els.ordersTableBody.innerHTML = '<tr><td colspan="5" class="empty">暂无订单</td></tr>';
    return;
  }
  els.ordersTableBody.innerHTML = orders.slice(0, 16).map((order) => {
    const org = state.overview.organizations.find((item) => item.organizationId === order.buyerOrganizationId);
    const canConfirm = order.status === 'pending_payment' && canConfirmPayments();
    return `
      <tr>
        <td>
          <div class="mono">${escapeHtml(order.orderId)}</div>
          <div class="subtle">${escapeHtml(formatDate(order.createdAt))}</div>
        </td>
        <td>${escapeHtml(org?.name || order.buyerOrganizationId)}</td>
        <td>
          <div>${escapeHtml(formatMoney(order.totalAmount, order.currency))}</div>
          ${order.discountAmount ? `<div class="subtle">优惠 ${escapeHtml(formatMoney(order.discountAmount, order.currency))}</div>` : ''}
        </td>
        <td>${statusBadge(order.status)}</td>
        <td>
          <div class="row-actions">
            ${canConfirm ? `<button class="btn primary" data-action="confirm-payment" data-order-id="${escapeHtml(order.orderId)}" type="button">确认收款</button>` : ''}
          </div>
        </td>
      </tr>
    `;
  }).join('');
}

function renderEntitlements(entitlements) {
  els.entitlementCountLabel.textContent = `${entitlements.length}`;
  if (entitlements.length === 0) {
    els.entitlementsTableBody.innerHTML = '<tr><td colspan="6" class="empty">暂无授权</td></tr>';
    return;
  }
  els.entitlementsTableBody.innerHTML = entitlements.map((entitlement) => `
    <tr>
      <td>
        <div>${escapeHtml(entitlement.assignedToLabel || entitlement.assignedToId)}</div>
        <div class="subtle">${escapeHtml(entitlement.assignedToType)} / ${escapeHtml(entitlement.licenseId)}</div>
      </td>
      <td>${escapeHtml(entitlement.modelName || entitlement.modelId)}</td>
      <td>${escapeHtml(entitlement.renewalMode || '-')}</td>
      <td>${escapeHtml(formatDate(entitlement.renewalEndsAt || entitlement.endsAt))}</td>
      <td>${statusBadge(entitlement.status)}</td>
      <td>
        <div class="row-actions">
          ${canManageEntitlements() ? `<button class="btn" data-action="edit-entitlement" data-entitlement-id="${escapeHtml(entitlement.entitlementId)}" type="button">编辑</button>` : ''}
          ${canManageEntitlements() && entitlement.status === 'active' ? `<button class="btn danger" data-action="revoke-entitlement" data-entitlement-id="${escapeHtml(entitlement.entitlementId)}" type="button">撤销</button>` : ''}
        </div>
      </td>
    </tr>
  `).join('');
}

function renderModels(models) {
  els.modelCountLabel.textContent = `${models.length}`;
  if (models.length === 0) {
    els.modelsTableBody.innerHTML = '<tr><td colspan="6" class="empty">暂无模型</td></tr>';
    return;
  }
  els.modelsTableBody.innerHTML = models.map((model) => {
    const build = model.currentBuild;
    const sku = model.sku;
    return `
      <tr>
        <td>
          <div>${escapeHtml(model.name)}</div>
          <div class="subtle mono">${escapeHtml(model.modelId)}</div>
        </td>
        <td>${statusBadge(model.status)}</td>
        <td>
          <div>${escapeHtml(build?.sourceFormat || '-')}</div>
          <div class="subtle">${escapeHtml(build?.transportFormat || '-')}</div>
        </td>
        <td>
          <div>${escapeHtml(sku?.name || '-')}</div>
          <div class="subtle">${sku ? escapeHtml(formatMoney(sku.priceAmount, sku.currency)) : ''}</div>
        </td>
        <td>${escapeHtml(model.assignmentCount || 0)}</td>
        <td>
          <div class="row-actions">
            ${canReviewModels() ? `<button class="btn" data-action="model-status" data-status="listed" data-model-id="${escapeHtml(model.modelId)}" type="button">上架</button>` : ''}
            ${canReviewModels() ? `<button class="btn danger" data-action="model-status" data-status="delisted" data-model-id="${escapeHtml(model.modelId)}" type="button">下架</button>` : ''}
          </div>
        </td>
      </tr>
    `;
  }).join('');
}

function renderUsers(users) {
  els.userCountLabel.textContent = `${users.length}`;
}

function renderSkus(skus) {
  els.skuCountLabel.textContent = `${skus.length}`;
}

function renderAudit(logs) {
  els.auditCountLabel.textContent = `${logs.length}`;
  if (logs.length === 0) {
    els.auditTableBody.innerHTML = '<tr><td colspan="3" class="empty">暂无审计</td></tr>';
    return;
  }
  els.auditTableBody.innerHTML = logs.slice(0, 18).map((log) => `
    <tr>
      <td>${escapeHtml(log.action)}</td>
      <td>
        <div>${escapeHtml(log.objectType)}</div>
        <div class="subtle mono">${escapeHtml(log.objectId)}</div>
      </td>
      <td>${escapeHtml(formatDate(log.createdAt))}</td>
    </tr>
  `).join('');
}

function renderDevices(devices) {
  els.deviceCountLabel.textContent = `${devices.length}`;
  if (devices.length === 0) {
    els.devicesTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无设备</td></tr>';
    return;
  }
  els.devicesTableBody.innerHTML = devices.map((device) => {
    const org = state.overview.organizations.find((item) => item.organizationId === device.organizationId);
    return `
      <tr>
        <td>
          <div>${escapeHtml(device.name)}</div>
          <div class="subtle mono">${escapeHtml(device.deviceBindingId)}</div>
        </td>
        <td>${escapeHtml(org?.name || device.organizationId)}</td>
        <td>${escapeHtml(device.platform || '-')}</td>
        <td>${escapeHtml(formatDate(device.lastSeenAt))}</td>
      </tr>
    `;
  }).join('');
}

function renderResults(results) {
  els.resultCountLabel.textContent = `${results.length}`;
  if (results.length === 0) {
    els.resultsTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无结果</td></tr>';
    return;
  }
  els.resultsTableBody.innerHTML = results.map((result) => `
    <tr>
      <td>${escapeHtml(result.deviceName || result.deviceId)}</td>
      <td>${escapeHtml(result.resultType || '-')}</td>
      <td>${escapeHtml(result.productUUID || '-')}</td>
      <td>${escapeHtml(formatDate(result.capturedAt || result.createdAt))}</td>
    </tr>
  `).join('');
}

function renderAssets(assets) {
  els.assetCountLabel.textContent = `${assets.length}`;
  if (assets.length === 0) {
    els.assetsTableBody.innerHTML = '<tr><td colspan="5" class="empty">暂无资产</td></tr>';
    return;
  }
  els.assetsTableBody.innerHTML = assets.map((asset) => `
    <tr>
      <td>${escapeHtml(asset.deviceName || asset.deviceId)}</td>
      <td>
        <div>${escapeHtml(asset.fileName)}</div>
        <div class="subtle">${escapeHtml(asset.byteCount || 0)} bytes</div>
      </td>
      <td>${escapeHtml(asset.category || '-')}</td>
      <td>${escapeHtml(asset.pointIndex || 0)}</td>
      <td>${escapeHtml(formatDate(asset.capturedAt || asset.createdAt))}</td>
    </tr>
  `).join('');
}

function renderMarket(models) {
  els.marketCountLabel.textContent = `${models.length}`;
  if (models.length === 0) {
    els.marketTableBody.innerHTML = '<tr><td colspan="5" class="empty">暂无商城模型</td></tr>';
    return;
  }
  const actionButtons = (model) => canUseMarketplace() ? `
    <button class="btn" data-action="favorite-model" data-model-id="${escapeHtml(model.modelId)}" type="button">收藏</button>
    <button class="btn primary" data-action="trial-model" data-model-id="${escapeHtml(model.modelId)}" type="button">试用</button>
    <button class="btn" data-action="review-model" data-model-id="${escapeHtml(model.modelId)}" type="button">五星评价</button>
  ` : '';
  els.marketTableBody.innerHTML = models.map((model) => `
    <tr>
      <td>
        <div>${escapeHtml(model.name)}</div>
        <div class="subtle">${escapeHtml(model.summary || '')}</div>
      </td>
      <td>${model.sku ? escapeHtml(formatMoney(model.sku.priceAmount, model.sku.currency)) : '-'}</td>
      <td>${escapeHtml(model.rating || '-')} / ${escapeHtml(model.reviewCount || 0)} 条</td>
      <td>${escapeHtml(model.soldCount || 0)}</td>
      <td>
        <div class="row-actions">
          ${actionButtons(model)}
        </div>
      </td>
    </tr>
  `).join('');
}

function renderDevelopers(developers) {
  els.developerCountLabel.textContent = `${developers.length}`;
  if (developers.length === 0) {
    els.developersTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无开发者</td></tr>';
    return;
  }
  els.developersTableBody.innerHTML = developers.map((developer) => `
    <tr>
      <td>
        <div>${escapeHtml(developer.displayName)}</div>
        <div class="subtle">${escapeHtml(developer.developerId)}</div>
      </td>
      <td>${escapeHtml(developer.type || '-')}</td>
      <td>${statusBadge(developer.verificationStatus)}</td>
      <td>
        <div class="row-actions">
          ${canReviewModels() && developer.verificationStatus !== 'approved' ? `<button class="btn primary" data-action="approve-developer" data-developer-id="${escapeHtml(developer.developerId)}" type="button">通过</button>` : ''}
          ${canReviewModels() && developer.verificationStatus !== 'rejected' ? `<button class="btn danger" data-action="reject-developer" data-developer-id="${escapeHtml(developer.developerId)}" type="button">驳回</button>` : ''}
        </div>
      </td>
    </tr>
  `).join('');
}

function renderReviews(reviews) {
  els.reviewCountLabel.textContent = `${reviews.length}`;
  if (reviews.length === 0) {
    els.reviewsTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无审核</td></tr>';
    return;
  }
  els.reviewsTableBody.innerHTML = reviews.map((review) => `
    <tr>
      <td>
        <div>${escapeHtml(review.subjectType)}</div>
        <div class="subtle mono">${escapeHtml(review.subjectId)}</div>
      </td>
      <td>${statusBadge(review.status)}</td>
      <td>${escapeHtml(formatDate(review.createdAt))}</td>
      <td>
        ${canReviewModels() && review.status === 'pending' && review.subjectType === 'model' ? `
          <div class="row-actions">
            <button class="btn primary" data-action="approve-model-review" data-model-id="${escapeHtml(review.subjectId)}" type="button">上架</button>
            <button class="btn danger" data-action="reject-model-review" data-model-id="${escapeHtml(review.subjectId)}" type="button">驳回</button>
          </div>
        ` : ''}
      </td>
    </tr>
  `).join('');
}

function renderSupport(tickets) {
  els.supportCountLabel.textContent = `${tickets.length}`;
  if (tickets.length === 0) {
    els.supportTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无工单</td></tr>';
    return;
  }
  els.supportTableBody.innerHTML = tickets.map((ticket) => `
    <tr>
      <td>
        <div>${escapeHtml(ticket.title)}</div>
        <div class="subtle">${escapeHtml(ticket.supportTicketId)} / ${escapeHtml(formatDate(ticket.createdAt))}</div>
      </td>
      <td>${escapeHtml(ticket.category)} / ${escapeHtml(ticket.priority)}</td>
      <td>${statusBadge(ticket.status)}</td>
      <td>
        <button class="btn" data-action="close-support" data-ticket-id="${escapeHtml(ticket.supportTicketId)}" type="button">关闭</button>
      </td>
    </tr>
  `).join('');
}

function renderCustomRequests(requests) {
  els.customRequestCountLabel.textContent = `${requests.length}`;
  if (requests.length === 0) {
    els.customRequestsTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无定制需求</td></tr>';
    return;
  }
  els.customRequestsTableBody.innerHTML = requests.map((request) => `
    <tr>
      <td>
        <div>${escapeHtml(request.title)}</div>
        <div class="subtle">${escapeHtml(request.scenario || '')}</div>
      </td>
      <td>${escapeHtml(formatMoney(request.budgetAmount, request.currency))}</td>
      <td>${statusBadge(request.status)}</td>
      <td>
        ${canSubmitCustomProposals() ? `<button class="btn" data-action="submit-proposal" data-request-id="${escapeHtml(request.customRequestId)}" type="button">提交报价</button>` : ''}
      </td>
    </tr>
  `).join('');
}

function renderInvoices(invoices) {
  els.invoiceCountLabel.textContent = `${invoices.length}`;
  if (invoices.length === 0) {
    els.invoicesTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无发票</td></tr>';
    return;
  }
  els.invoicesTableBody.innerHTML = invoices.map((invoice) => `
    <tr>
      <td>
        <div>${escapeHtml(invoice.title)}</div>
        <div class="subtle">${escapeHtml(invoice.invoiceId)} / ${escapeHtml(invoice.invoiceNo || '未开票')}</div>
      </td>
      <td>${escapeHtml(formatMoney(invoice.amount, invoice.currency))}</td>
      <td>${statusBadge(invoice.status)}</td>
      <td>
        <div class="row-actions">
          ${canReviewFinance() && invoice.status === 'pending' ? `<button class="btn primary" data-action="issue-invoice" data-invoice-id="${escapeHtml(invoice.invoiceId)}" type="button">开票</button>` : ''}
          ${canReviewFinance() && invoice.status === 'pending' ? `<button class="btn danger" data-action="reject-invoice" data-invoice-id="${escapeHtml(invoice.invoiceId)}" type="button">驳回</button>` : ''}
        </div>
      </td>
    </tr>
  `).join('');
}

function renderFinance(settlements, withdrawals) {
  els.settlementCountLabel.textContent = `${settlements.length}`;
  els.withdrawalCountLabel.textContent = `${withdrawals.length}`;
  const rows = [
    ...settlements.map((settlement) => ({ kind: '结算', id: settlement.settlementId, amount: settlement.payableAmount, currency: settlement.currency, status: settlement.status, detail: settlement.modelId })),
    ...withdrawals.map((withdrawal) => ({ kind: '提现', id: withdrawal.withdrawalId, amount: withdrawal.amount, currency: withdrawal.currency, status: withdrawal.status, detail: withdrawal.accountName, withdrawal })),
  ];
  if (rows.length === 0) {
    els.financeTableBody.innerHTML = '<tr><td colspan="4" class="empty">暂无财务记录</td></tr>';
    return;
  }
  els.financeTableBody.innerHTML = rows.map((row) => `
    <tr>
      <td>
        <div>${escapeHtml(row.kind)} / <span class="mono">${escapeHtml(row.id)}</span></div>
        <div class="subtle">${escapeHtml(row.detail || '')}</div>
      </td>
      <td>${escapeHtml(formatMoney(row.amount, row.currency))}</td>
      <td>${statusBadge(row.status)}</td>
      <td>
        ${canReviewFinance() && row.withdrawal && row.status === 'pending' ? `
          <div class="row-actions">
            <button class="btn primary" data-action="pay-withdrawal" data-withdrawal-id="${escapeHtml(row.id)}" type="button">打款</button>
            <button class="btn danger" data-action="reject-withdrawal" data-withdrawal-id="${escapeHtml(row.id)}" type="button">驳回</button>
          </div>
        ` : ''}
      </td>
    </tr>
  `).join('');
}

function renderOps(data) {
  els.couponCountLabel.textContent = `${data.coupons.length}`;
  els.activityCountLabel.textContent = `${data.activities.length}`;
  els.categoryCountLabel.textContent = `${data.categories.length}`;
  const settings = data.platformSettings || {};
  els.settingsCommissionInput.value = settings.commissionRate ?? 0.12;
  els.settingsTrialDaysInput.value = settings.defaultTrialDays ?? 7;
  els.settingsOfflineDaysInput.value = settings.defaultOfflineLeaseDays ?? 30;
  els.settingsTicketMinutesInput.value = settings.downloadTicketMinutes ?? 15;
  const rows = [
    ...data.coupons.map((item) => ({ type: '优惠券', name: `${item.code} / ${item.name}`, status: item.status })),
    ...data.activities.map((item) => ({ type: '活动', name: item.title, status: item.status })),
    ...data.categories.map((item) => ({ type: '分类', name: `${item.name} / ${item.slug}`, status: item.status })),
  ];
  if (rows.length === 0) {
    els.opsTableBody.innerHTML = '<tr><td colspan="3" class="empty">暂无运营配置</td></tr>';
    return;
  }
  els.opsTableBody.innerHTML = rows.map((row) => `
    <tr>
      <td>${escapeHtml(row.type)}</td>
      <td>${escapeHtml(row.name)}</td>
      <td>${statusBadge(row.status)}</td>
    </tr>
  `).join('');
}

function renderAll(data) {
  applyRoleNavigation(data);
  renderSummary(data.summary || {});
  renderSelects(data);
  renderOrders(data.orders || []);
  renderMarket(state.marketModels.length ? state.marketModels : (data.models || []).filter((model) => model.status === 'listed').map((model) => ({
    ...model,
    sku: model.sku,
    rating: null,
    reviewCount: 0,
    soldCount: model.assignmentCount || 0,
  })));
  renderDevelopers(data.developers || []);
  renderReviews(data.reviews || []);
  renderEntitlements(data.entitlements || []);
  renderModels(data.models || []);
  renderUsers(data.users || []);
  renderSkus(data.modelSkus || []);
  renderAudit(data.auditLogs || []);
  renderDevices(data.devices || []);
  renderResults(data.recentResults || []);
  renderAssets(data.recentAssets || []);
  renderSupport(data.supportTickets || []);
  renderCustomRequests(data.customRequests || []);
  renderInvoices(data.invoices || []);
  renderFinance(data.settlements || [], data.withdrawals || []);
  renderOps(data);
  els.lastUpdatedLabel.textContent = formatDate(data.now);
}

async function refreshOverview() {
  if (!state.token) {
    return;
  }
  const data = await fetchJson('/api/platform/v1/dashboard/overview');
  state.overview = data;
  renderAll(data);
}

function fillEntitlementForm(entitlementId) {
  const entitlement = state.overview.entitlements.find((item) => item.entitlementId === entitlementId);
  if (!entitlement) {
    return;
  }
  els.entitlementIdInput.value = entitlement.entitlementId;
  els.entitlementModelInput.value = entitlement.modelId;
  els.entitlementAssignedTypeInput.value = entitlement.assignedToType === 'organization' ? 'organization' : 'user';
  renderAssignmentOptions();
  els.entitlementAssignedToInput.value = entitlement.assignedToId;
  els.entitlementRenewalModeInput.value = entitlement.renewalMode || 'perpetual';
  els.entitlementRenewalEndsAtInput.value = entitlement.renewalEndsAt
    ? new Date(entitlement.renewalEndsAt).toISOString().slice(0, 16)
    : '';
  els.entitlementOfflineDaysInput.value = entitlement.offlineLeaseDays || 30;
  els.entitlementDeviceBindingInput.checked = entitlement.deviceBindingRequired !== false;
  showToast('授权已载入表单');
}

function clearEntitlementForm() {
  els.entitlementIdInput.value = '';
  els.entitlementForm.reset();
  els.entitlementOfflineDaysInput.value = '30';
  els.entitlementDeviceBindingInput.checked = true;
  renderAssignmentOptions();
}

els.loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  els.loginErrorLabel.classList.add('hidden');
  try {
    const payload = await fetchJson('/api/platform/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        email: els.loginAccountInput.value,
        password: els.loginPasswordInput.value,
        deviceId: 'web-console',
        deviceName: 'Platform Console',
        platform: 'web',
      }),
    });
    setSession(payload);
    syncShell();
    await refreshOverview();
  } catch (error) {
    els.loginErrorLabel.textContent = error.message;
    els.loginErrorLabel.classList.remove('hidden');
  }
});

els.logoutButton.addEventListener('click', () => {
  clearSession();
  syncShell();
});

els.refreshButton.addEventListener('click', async () => {
  try {
    await refreshOverview();
    showToast('已刷新');
  } catch (error) {
    showToast(error.message);
  }
});

document.querySelectorAll('.tab').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((tab) => tab.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach((panel) => panel.classList.remove('active'));
    button.classList.add('active');
    document.getElementById(`${button.dataset.tab}Tab`).classList.add('active');
  });
});

els.entitlementAssignedTypeInput.addEventListener('change', renderAssignmentOptions);

els.orderForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/orders', {
      method: 'POST',
      body: JSON.stringify({
        buyerOrganizationId: els.orderBuyerOrganizationInput.value,
        skuId: els.orderSkuInput.value,
        quantity: Number(els.orderQuantityInput.value || 1),
        paymentMode: els.orderPaymentModeInput.value,
        couponCode: els.orderCouponInput.value || undefined,
      }),
    });
    await refreshOverview();
    showToast('订单已创建');
  } catch (error) {
    showToast(error.message);
  }
});

els.ordersTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button || button.dataset.action !== 'confirm-payment') {
    return;
  }
  try {
    await fetchJson(`/api/platform/v1/admin/orders/${button.dataset.orderId}/confirm-payment`, {
      method: 'POST',
      body: JSON.stringify({ provider: 'manual' }),
    });
    await refreshOverview();
    showToast('收款已确认，授权已生成');
  } catch (error) {
    showToast(error.message);
  }
});

els.entitlementForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/admin/entitlements', {
      method: 'POST',
      body: JSON.stringify({
        entitlementId: els.entitlementIdInput.value || undefined,
        modelId: els.entitlementModelInput.value,
        assignedToType: els.entitlementAssignedTypeInput.value,
        assignedToId: els.entitlementAssignedToInput.value,
        renewalMode: els.entitlementRenewalModeInput.value,
        renewalEndsAt: els.entitlementRenewalModeInput.value === 'fixed' ? els.entitlementRenewalEndsAtInput.value : null,
        offlineLeaseDays: Number(els.entitlementOfflineDaysInput.value || 30),
        deviceBindingRequired: els.entitlementDeviceBindingInput.checked,
      }),
    });
    clearEntitlementForm();
    await refreshOverview();
    showToast('授权已保存');
  } catch (error) {
    showToast(error.message);
  }
});

els.clearEntitlementButton.addEventListener('click', clearEntitlementForm);

els.entitlementsTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button) {
    return;
  }
  if (button.dataset.action === 'edit-entitlement') {
    fillEntitlementForm(button.dataset.entitlementId);
  }
  if (button.dataset.action === 'revoke-entitlement') {
    try {
      await fetchJson(`/api/platform/v1/admin/entitlements/${button.dataset.entitlementId}/revoke`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
      await refreshOverview();
      showToast('授权已撤销');
    } catch (error) {
      showToast(error.message);
    }
  }
});

els.userForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({
        displayName: els.userDisplayNameInput.value,
        email: els.userEmailInput.value,
        password: els.userPasswordInput.value || undefined,
        role: els.userRoleInput.value,
        organizationId: els.userOrganizationInput.value,
      }),
    });
    els.userForm.reset();
    await refreshOverview();
    showToast('用户已保存');
  } catch (error) {
    showToast(error.message);
  }
});

els.skuForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/admin/model-skus', {
      method: 'POST',
      body: JSON.stringify({
        modelId: els.skuModelInput.value,
        name: els.skuNameInput.value,
        priceAmount: Number(els.skuPriceInput.value || 0),
        licenseType: els.skuLicenseTypeInput.value,
        durationDays: Number(els.skuDurationInput.value || 365),
        maxDevices: Number(els.skuMaxDevicesInput.value || 1),
        offlineLeaseDays: Number(els.skuOfflineDaysInput.value || 30),
      }),
    });
    await refreshOverview();
    showToast('SKU 已保存');
  } catch (error) {
    showToast(error.message);
  }
});

els.modelsTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button || button.dataset.action !== 'model-status') {
    return;
  }
  try {
    await fetchJson(`/api/platform/v1/admin/models/${button.dataset.modelId}/review`, {
      method: 'POST',
      body: JSON.stringify({ status: button.dataset.status }),
    });
    await refreshOverview();
    showToast('模型状态已更新');
  } catch (error) {
    showToast(error.message);
  }
});

els.marketSearchForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    const params = new URLSearchParams();
    if (els.marketQueryInput.value) params.set('q', els.marketQueryInput.value);
    if (els.marketCategoryInput.value) params.set('category', els.marketCategoryInput.value);
    const payload = await fetchJson(`/api/platform/v1/marketplace/search?${params.toString()}`);
    state.marketModels = payload.models || [];
    renderMarket(state.marketModels);
    showToast('商城搜索已刷新');
  } catch (error) {
    showToast(error.message);
  }
});

els.marketTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button) return;
  const modelId = button.dataset.modelId;
  try {
    if (button.dataset.action === 'favorite-model') {
      await fetchJson(`/api/platform/v1/models/${modelId}/favorite`, { method: 'POST', body: JSON.stringify({}) });
      showToast('已收藏');
    }
    if (button.dataset.action === 'trial-model') {
      await fetchJson(`/api/platform/v1/models/${modelId}/trial-request`, { method: 'POST', body: JSON.stringify({}) });
      await refreshOverview();
      showToast('试用授权已开通');
    }
    if (button.dataset.action === 'review-model') {
      await fetchJson(`/api/platform/v1/models/${modelId}/reviews`, {
        method: 'POST',
        body: JSON.stringify({ rating: 5, title: '现场验证通过', body: '模型效果符合试运行预期。' }),
      });
      state.marketModels = [];
      await refreshOverview();
      showToast('评价已发布');
    }
  } catch (error) {
    showToast(error.message);
  }
});

els.developerProfileForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/developer/profile', {
      method: 'POST',
      body: JSON.stringify({
        displayName: els.developerDisplayNameInput.value,
        type: els.developerTypeInput.value,
        agreementSigned: els.developerAgreementInput.checked,
        submit: true,
      }),
    });
    await refreshOverview();
    showToast('开发者入驻已提交');
  } catch (error) {
    showToast(error.message);
  }
});

els.developerModelForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    const payload = await fetchJson('/api/platform/v1/developer/models', {
      method: 'POST',
      body: JSON.stringify({
        name: els.developerModelNameInput.value,
        category: els.developerModelCategoryInput.value,
        summary: els.developerModelSummaryInput.value,
        tags: els.developerModelTagsInput.value,
      }),
    });
    await fetchJson(`/api/platform/v1/developer/models/${payload.model.modelId}/submit-review`, {
      method: 'POST',
      body: JSON.stringify({}),
    });
    els.developerModelForm.reset();
    await refreshOverview();
    showToast('模型草稿已提交审核');
  } catch (error) {
    showToast(error.message);
  }
});

els.developersTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button) return;
  const decision = button.dataset.action === 'reject-developer' ? 'reject' : 'approve';
  try {
    await fetchJson(`/api/platform/v1/admin/developers/${button.dataset.developerId}/review`, {
      method: 'POST',
      body: JSON.stringify({ decision }),
    });
    await refreshOverview();
    showToast(decision === 'approve' ? '开发者已通过' : '开发者已驳回');
  } catch (error) {
    showToast(error.message);
  }
});

els.reviewsTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button) return;
  const decision = button.dataset.action === 'reject-model-review' ? 'reject' : 'approve';
  try {
    await fetchJson(`/api/platform/v1/admin/models/${button.dataset.modelId}/review`, {
      method: 'POST',
      body: JSON.stringify({ decision, status: decision === 'approve' ? 'listed' : 'rejected' }),
    });
    await refreshOverview();
    showToast(decision === 'approve' ? '模型已上架' : '模型已驳回');
  } catch (error) {
    showToast(error.message);
  }
});

els.supportForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/support/tickets', {
      method: 'POST',
      body: JSON.stringify({
        title: els.supportTitleInput.value,
        category: els.supportCategoryInput.value,
        priority: els.supportPriorityInput.value,
        modelId: els.supportModelInput.value || undefined,
        body: els.supportBodyInput.value,
      }),
    });
    els.supportForm.reset();
    await refreshOverview();
    showToast('工单已提交');
  } catch (error) {
    showToast(error.message);
  }
});

els.supportTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button || button.dataset.action !== 'close-support') {
    return;
  }
  try {
    await fetchJson(`/api/platform/v1/support/tickets/${button.dataset.ticketId}/reply`, {
      method: 'POST',
      body: JSON.stringify({ body: '已处理并关闭', status: 'closed' }),
    });
    await refreshOverview();
    showToast('工单已关闭');
  } catch (error) {
    showToast(error.message);
  }
});

els.customRequestForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/custom-requests', {
      method: 'POST',
      body: JSON.stringify({
        title: els.customTitleInput.value,
        budgetAmount: Number(els.customBudgetInput.value || 0),
        dueAt: els.customDueInput.value || undefined,
        currency: els.customCurrencyInput.value,
        scenario: els.customScenarioInput.value,
      }),
    });
    els.customRequestForm.reset();
    await refreshOverview();
    showToast('定制需求已发布');
  } catch (error) {
    showToast(error.message);
  }
});

els.customRequestsTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button || button.dataset.action !== 'submit-proposal') {
    return;
  }
  try {
    await fetchJson(`/api/platform/v1/custom-requests/${button.dataset.requestId}/proposal`, {
      method: 'POST',
      body: JSON.stringify({ quoteAmount: 68000, body: '平台演示报价：2 周交付首版模型。' }),
    });
    await refreshOverview();
    showToast('报价已提交');
  } catch (error) {
    showToast(error.message);
  }
});

els.invoiceForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/invoices', {
      method: 'POST',
      body: JSON.stringify({
        orderId: els.invoiceOrderInput.value,
        invoiceType: els.invoiceTypeInput.value,
        title: els.invoiceTitleInput.value,
        taxNumber: els.invoiceTaxInput.value,
        deliveryEmail: els.invoiceEmailInput.value,
      }),
    });
    els.invoiceForm.reset();
    await refreshOverview();
    showToast('发票申请已提交');
  } catch (error) {
    showToast(error.message);
  }
});

els.invoicesTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button) {
    return;
  }
  const decision = button.dataset.action === 'reject-invoice' ? 'reject' : 'approve';
  try {
    await fetchJson(`/api/platform/v1/admin/invoices/${button.dataset.invoiceId}/review`, {
      method: 'POST',
      body: JSON.stringify({ decision }),
    });
    await refreshOverview();
    showToast(decision === 'reject' ? '发票已驳回' : '发票已开具');
  } catch (error) {
    showToast(error.message);
  }
});

els.withdrawalForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/developer/withdrawals', {
      method: 'POST',
      body: JSON.stringify({
        amount: Number(els.withdrawalAmountInput.value || 0) || undefined,
        accountName: els.withdrawalAccountNameInput.value,
        accountNo: els.withdrawalAccountNoInput.value,
      }),
    });
    els.withdrawalForm.reset();
    await refreshOverview();
    showToast('提现申请已提交');
  } catch (error) {
    showToast(error.message);
  }
});

els.financeTableBody.addEventListener('click', async (event) => {
  const button = event.target.closest('button');
  if (!button) {
    return;
  }
  const decision = button.dataset.action === 'reject-withdrawal' ? 'reject' : 'approve';
  try {
    await fetchJson(`/api/platform/v1/admin/withdrawals/${button.dataset.withdrawalId}/review`, {
      method: 'POST',
      body: JSON.stringify({ decision }),
    });
    await refreshOverview();
    showToast(decision === 'reject' ? '提现已驳回' : '提现已打款');
  } catch (error) {
    showToast(error.message);
  }
});

els.couponForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/admin/coupons', {
      method: 'POST',
      body: JSON.stringify({
        code: els.couponCodeInput.value,
        name: els.couponNameInput.value,
        discountValue: Number(els.couponValueInput.value || 0),
        usageLimit: Number(els.couponLimitInput.value || 0),
      }),
    });
    await refreshOverview();
    showToast('优惠券已保存');
  } catch (error) {
    showToast(error.message);
  }
});

els.activityForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/admin/activities', {
      method: 'POST',
      body: JSON.stringify({
        title: els.activityTitleInput.value,
        placement: els.activityPlacementInput.value,
        description: els.activityDescriptionInput.value,
      }),
    });
    await refreshOverview();
    showToast('活动已保存');
  } catch (error) {
    showToast(error.message);
  }
});

els.categoryForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/admin/categories', {
      method: 'POST',
      body: JSON.stringify({
        name: els.categoryNameInput.value,
        slug: els.categorySlugInput.value,
      }),
    });
    els.categoryForm.reset();
    await refreshOverview();
    showToast('分类已保存');
  } catch (error) {
    showToast(error.message);
  }
});

els.settingsForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  try {
    await fetchJson('/api/platform/v1/admin/settings', {
      method: 'POST',
      body: JSON.stringify({
        commissionRate: Number(els.settingsCommissionInput.value || 0),
        defaultTrialDays: Number(els.settingsTrialDaysInput.value || 7),
        defaultOfflineLeaseDays: Number(els.settingsOfflineDaysInput.value || 30),
        downloadTicketMinutes: Number(els.settingsTicketMinutesInput.value || 15),
      }),
    });
    await refreshOverview();
    showToast('系统参数已保存');
  } catch (error) {
    showToast(error.message);
  }
});

syncShell();
if (state.token) {
  refreshOverview().catch(() => {
    clearSession();
    syncShell();
  });
}
