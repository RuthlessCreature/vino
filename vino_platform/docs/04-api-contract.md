# vino_platform API 契约

- Product: `vino_platform`
- Date: 2026-04-29
- Status: Draft

## 约定

- Base path: `/api/platform/v1`
- 兼容 path: `/api/cloud/v1` 可作为 `vino_iPhone` 过渡兼容层。
- Auth: `Authorization: Bearer <accessToken>`
- Time: ISO 8601 UTC。
- Idempotency: 写接口支持 `Idempotency-Key` header，ingest 可继续支持 body 内 `idempotencyKey`。
- Error:

```json
{
  "error": {
    "code": "entitlement_not_found",
    "message": "model is not assigned to current user",
    "requestId": "req_..."
  }
}
```

## iPhone 终端兼容 API

这些接口应优先兼容 `vino_cloud`，避免改动 `vino_iPhone`。

### 登录

`POST /api/cloud/v1/auth/login`

Request:

```json
{
  "email": "demo@vino.cc",
  "password": "demo123",
  "deviceId": "iphone-device-binding-id",
  "deviceName": "iPhone",
  "platform": "iOS"
}
```

Response:

```json
{
  "accessToken": "token",
  "tokenType": "Bearer",
  "expiresAt": "2026-05-06T00:00:00.000Z",
  "user": {
    "userId": "user_001",
    "email": "demo@vino.cc",
    "displayName": "Demo Operator",
    "organizationId": "org_001",
    "organizationName": "Vino Demo Factory",
    "role": "operator"
  }
}
```

### 模型列表

`GET /api/cloud/v1/models`

Rules:

- 只返回当前会话有 Entitlement 的模型。
- 过期、撤销、未审核、未上架模型不返回。
- 如果模型有设备绑定要求，返回 `license.deviceBindingRequired = true`。

Response:

```json
{
  "models": [
    {
      "id": "model_001",
      "name": "PCB Defect Detector",
      "version": "1.0.0",
      "summary": "PCB 缺陷检测模型",
      "organizationId": "org_001",
      "modelBuildId": "build_001",
      "fileName": "pcb_defect.mlpackage",
      "sourceFormat": "mlpackage",
      "transportFormat": "bundle-archive",
      "sha256": "hex",
      "byteCount": 123456,
      "isEncrypted": true,
      "supportedPlatforms": ["ios"],
      "tags": ["coreml", "industrial"],
      "license": {
        "licenseId": "lic_001",
        "leaseExpiresAt": "2026-05-29T00:00:00.000Z",
        "policyFlags": ["offline", "device-bound"],
        "deviceBindingRequired": true,
        "deviceBindingId": "iphone-device-binding-id"
      }
    }
  ],
  "syncedAt": "2026-04-29T00:00:00.000Z"
}
```

### 下载票据

`POST /api/cloud/v1/models/{modelId}/download-ticket`

Request:

```json
{
  "deviceId": "iphone-device-binding-id",
  "deviceName": "iPhone"
}
```

Response:

```json
{
  "ticketId": "ticket_001",
  "modelId": "model_001",
  "organizationId": "org_001",
  "deviceId": "iphone-device-binding-id",
  "expiresAt": "2026-04-29T00:15:00.000Z",
  "fileName": "pcb_defect.mlpackage",
  "sourceFormat": "mlpackage",
  "transportFormat": "bundle-archive",
  "sha256": "hex",
  "byteCount": 123456,
  "modelBuildId": "build_001",
  "isEncrypted": true,
  "license": {
    "licenseId": "lic_001",
    "leaseExpiresAt": "2026-05-29T00:00:00.000Z",
    "policyFlags": ["offline", "device-bound"],
    "deviceBindingRequired": true,
    "deviceBindingId": "iphone-device-binding-id"
  },
  "encryption": {
    "envelope": "vino-aesgcm-v1",
    "algorithm": "aes-256-gcm",
    "keyDerivation": "sha256(ticketSecret:modelId:deviceId:modelBuildId)",
    "ticketSecret": "temporary-secret"
  },
  "downloadURL": "https://platform.example.com/api/cloud/v1/download/ticket_001"
}
```

### 下载文件

`GET /api/cloud/v1/download/{ticketId}`

Rules:

- 票据默认 15 分钟过期。
- 返回 `VINOENC1` 魔数开头的 `vino-aesgcm-v1` 加密包。
- 明文包哈希必须等于 ticket 中的 `sha256`。
- 票据过期、撤销、设备不匹配时返回 404 或 403。

### 租约续期

`POST /api/cloud/v1/licenses/lease/renew`

Request:

```json
{
  "modelId": "model_001",
  "deviceId": "iphone-device-binding-id"
}
```

Response:

```json
{
  "modelId": "model_001",
  "licenseId": "lic_001",
  "leaseExpiresAt": "2026-05-29T00:00:00.000Z",
  "policyFlags": ["offline", "device-bound"],
  "deviceBindingId": "iphone-device-binding-id"
}
```

## Web 平台 API

### 组织与用户

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/platform/v1/auth/login` | Web 登录 |
| GET | `/api/platform/v1/me` | 当前用户 |
| GET | `/api/platform/v1/organizations/{id}` | 组织详情 |
| GET | `/api/platform/v1/organizations/{id}/users` | 组织用户 |
| POST | `/api/platform/v1/organizations/{id}/users` | 邀请或创建用户 |
| PATCH | `/api/platform/v1/users/{id}` | 更新角色、状态 |

### 开发者

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/platform/v1/developers` | 创建入驻申请 |
| GET | `/api/platform/v1/developers/{id}` | 开发者资料 |
| POST | `/api/platform/v1/developers/{id}/qualifications` | 上传资质 |
| POST | `/api/platform/v1/admin/developers/{id}/review` | 审核入驻 |

### 模型

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/platform/v1/models` | 商城模型列表 |
| POST | `/api/platform/v1/developer/models` | 创建模型草稿 |
| PATCH | `/api/platform/v1/developer/models/{id}` | 更新模型信息 |
| POST | `/api/platform/v1/developer/models/{id}/builds` | 上传模型构建 |
| POST | `/api/platform/v1/developer/models/{id}/submit-review` | 提交审核 |
| POST | `/api/platform/v1/admin/models/{id}/review` | 审核模型 |
| POST | `/api/platform/v1/admin/models/{id}/publish` | 上架 |
| POST | `/api/platform/v1/admin/models/{id}/delist` | 下架 |

### 商品与订单

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/platform/v1/admin/model-skus` | 创建 SKU |
| GET | `/api/platform/v1/model-skus/{id}` | SKU 详情 |
| POST | `/api/platform/v1/orders` | 创建订单 |
| GET | `/api/platform/v1/orders/{id}` | 订单详情 |
| POST | `/api/platform/v1/admin/orders/{id}/confirm-payment` | P0 手工确认收款 |
| POST | `/api/platform/v1/payments/webhooks/{provider}` | P1 支付回调 |
| POST | `/api/platform/v1/orders/{id}/refund` | 退款申请 |

### 授权

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/platform/v1/admin/entitlements` | 授权列表 |
| POST | `/api/platform/v1/admin/entitlements` | 手工创建或调整授权 |
| POST | `/api/platform/v1/admin/entitlements/{id}/assign` | 分配给组织、用户、设备 |
| POST | `/api/platform/v1/admin/entitlements/{id}/revoke` | 撤销授权 |
| GET | `/api/platform/v1/devices` | 设备列表 |
| POST | `/api/platform/v1/admin/devices/{id}/block` | 封禁设备 |

### ingest

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/platform/v1/ingest/asset` | 上传图片、视频或二进制资产 |
| POST | `/api/platform/v1/ingest/result` | 上传推理结果 |
| POST | `/api/platform/v1/ingest/log` | 上传日志 |
| POST | `/api/platform/v1/ingest/stat` | 上传统计 |
| GET | `/api/platform/v1/admin/ingest/assets` | 后台查看资产 |
| GET | `/api/platform/v1/admin/ingest/results` | 后台查看结果 |

## 状态码

| Code | Meaning |
| --- | --- |
| 200 | 成功 |
| 201 | 创建成功 |
| 400 | 请求格式错误 |
| 401 | 未登录或 token 失效 |
| 403 | 权限不足、授权不可用、设备不匹配 |
| 404 | 资源不存在或下载票据过期 |
| 409 | 幂等冲突、重复资源 |
| 422 | 业务校验失败 |
| 429 | 限流 |
| 500 | 服务异常 |

## `vino_cloud` 兼容迁移

| Existing | Platform |
| --- | --- |
| `/api/cloud/v1/auth/login` | 保留给终端，内部转发到 Identity |
| `/api/cloud/v1/models` | 保留给终端，内部调用 Entitlement + Catalog |
| `/api/cloud/v1/models/:id/download-ticket` | 保留给终端，内部调用 Delivery |
| `/api/cloud/v1/download/:ticketId` | 保留给终端，内部调用 Delivery |
| `/api/cloud/v1/licenses/lease/renew` | 保留给终端，内部调用 License |
| `/api/cloud/v1/ingest/*` | 可兼容，逐步迁移到 `/api/platform/v1/ingest/*` |

## 下一步

优先实现终端兼容 API 的生产版，再实现 Web 后台 API。这样 `vino_iPhone` 可以先接入，交易平台界面随后补齐。
