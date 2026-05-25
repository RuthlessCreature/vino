---
project: vino
updated: 2026-05-25
tags:
  - vino
  - protocol
  - api
---

# 协议与 API

## 控制协议

| 项 | 值 |
| --- | --- |
| Bonjour 服务 | `_vino-control._tcp` |
| 默认控制端口 | `48920` |
| 传输 | `TCP + JSON Lines` |
| 协议字段 | `vino.control/1` |
| 文件传输 | `file.begin -> file.chunk -> file.commit` |
| 轻量预览 | `preview.frame.push`，`base64 JPEG`，建议 2 到 4 FPS |

核心动作：

- 设备：`device.hello`、`device.heartbeat`、`device.status.push`、`device.alias.set`
- 相机：`camera.capabilities.get`、`camera.config.patch`、`camera.mode.set`、`camera.focus.mode.set`、`camera.flash.set`
- 采集：`capture.photo.trigger`、`capture.recording.set`
- 推理：`inference.runtime.set`、`inference.result.push`、`inference.model.*`
- 数据：`media.push.*`、`preview.frame.push`

回执约定：

- `kind = reply`
- `correlationId = 原始 messageId`
- `action = 原始 action`
- `payload.status = accepted | rejected | unsupported`

## iPhone 兼容 API

这些接口是 iPhone 端当前已经对接的 Cloud 侧契约，正式平台也应保留。

| Method | Path | 用途 |
| --- | --- | --- |
| POST | `/api/cloud/v1/auth/login` | 终端登录 |
| GET | `/api/cloud/v1/models` | 获取已授权模型列表 |
| POST | `/api/cloud/v1/models/:id/download-ticket` | 申请下载票据 |
| GET | `/api/cloud/v1/download/:ticketId` | 下载加密模型包 |
| POST | `/api/cloud/v1/licenses/lease/renew` | 续租离线租约 |
| POST | `/api/cloud/v1/ingest/asset` | 上传图片、视频或二进制资产 |
| POST | `/api/cloud/v1/ingest/result` | 上传推理结果 |
| POST | `/api/cloud/v1/ingest/log` | 上传日志 |
| POST | `/api/cloud/v1/ingest/stat` | 上传统计 |

## 平台 API 方向

正式平台 API 使用 `/api/platform/v1`，其中终端兼容接口继续保留 `/api/cloud/v1`。

首要模块：

- Identity & Org
- Developer Profile
- Model Catalog
- Review & Compliance
- Commerce
- Entitlement & Lease
- Model Delivery
- Ingest & Result
- Admin & Audit

## 状态码约定

| Code | 含义 |
| --- | --- |
| 200 / 201 | 成功 |
| 400 | 请求格式错误 |
| 401 | 未登录或 token 失效 |
| 403 | 权限不足、授权不可用、设备不匹配 |
| 404 | 资源不存在或下载票据过期 |
| 409 | 幂等冲突、重复资源 |
| 422 | 业务校验失败 |
| 429 | 限流 |
| 500 | 服务异常 |

