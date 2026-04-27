# vino_cloud

零依赖 Node.js 云端原型，提供：

- Web 控制台：`GET /`
- 授权后台：用户管理、模型分配、永久/定期续租配置
- 健康与总览：`GET /api/cloud/v1/health`、`GET /api/cloud/v1/overview`
- `POST /api/cloud/v1/auth/login`
- `GET /api/cloud/v1/models`
- `POST /api/cloud/v1/models/:id/download-ticket`
- `GET /api/cloud/v1/download/:ticketId`
- `POST /api/cloud/v1/licenses/lease/renew`
- `POST /api/cloud/v1/ingest/asset`
- `POST /api/cloud/v1/ingest/result`
- `POST /api/cloud/v1/ingest/log`
- `POST /api/cloud/v1/ingest/stat`
- 兼容入口：`/uploadLog`、`/uploadStat`、`/uploadData`

## 启动

```sh
cd vino_cloud
npm start
```

默认端口：`8787`

默认控制台：`http://127.0.0.1:8787/`

## 授权后台说明

- 模型不再对同组织下所有用户默认可见。
- 每个模型需要在控制台显式分配给具体用户后，该用户才能在 iPhone 端发现与下载。
- 续租规则支持两种：
  - `永久`：`leaseExpiresAt = null`，本地可长期使用。
  - `截止时间`：到指定时间后，不再出现在模型列表里，续租接口也会拒绝。
- 后台页可直接创建用户、分配模型、切换续租模式、删除授权。

## MVP 说明

- 演示模型：`models/yolov8n.mlpackage`
- 自动导入：把 `.mlpackage` / `.mlmodel` / `.mlmodelc` 放进仓库根目录 `models/`，云端会自动发现并出现在授权后台，随后可按用户分配
- 下载产物：自定义 `bundle-archive`，与 `vino_iPhone` 当前 `ModelFileStore` 兼容
- 模型分发：下载票据返回临时解密材料，`GET /download/:ticketId` 返回 `vino-aesgcm-v1` 加密包
- 数据落地：`vino_cloud/data`
- ingest 端点当前允许 `vino_local` / `vino_iPhone` 直接推送，便于 MVP 联调

## 当前边界

- 当前加密链路用于商业模型分发 MVP，算法为 `AES-256-GCM`
- 生产环境应配合 `HTTPS` 使用，避免票据与临时解密材料在明文链路暴露

## 演示账号

- 账号：`demo@vino.cc`
- 密码：`demo123`
