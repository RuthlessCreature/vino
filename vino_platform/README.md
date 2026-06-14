# vino_platform

> 状态：Draft  
> 日期：2026-04-29  
> 边界：`vino_platform` 是云端模型交易、授权、分发与运营后台；`vino_iPhone` 是终端执行 App，本轮不修改。

## 定位

`vino_platform` 不是把 `vino_iPhone` 做成 App 内模型商城，而是给工业视觉客户、模型开发者和平台运营方使用的 Web 平台：

- 采购方在 Web 上浏览、购买、试用、管理模型授权。
- 开发者在 Web 上入驻、上传模型、管理版本、查看成交与结算。
- 平台运营方在 Web 后台审核模型、配置价格、处理订单、分配授权、处理售后。
- `vino_iPhone` 只登录账号、同步可用模型、申请下载票据、安装并按授权运行模型。

## 和现有工程的关系

- `vino_iPhone`：保持终端定位，不承载购买、支付、开发者入驻、平台运营等复杂交易流程。
- `vino_cloud`：作为模型下载、账号授权、Entitlement、离线租约、AES-GCM 加密分发的 MVP 参考实现。
- `vino_platform`：在 `vino_cloud` 的下载与授权链路上扩展完整交易平台能力，包括商城、订单、支付、结算、审核、发票、运营后台和审计。
- `vino_Desktop`：不作为首发核心商业平台，可继续保留为调试、演示或现场运维工具。

## 文档索引

- [00-executive-summary.md](docs/00-executive-summary.md)：产品收敛结论、MVP 范围与成功指标。
- [01-prd.md](docs/01-prd.md)：角色、功能范围、用户故事、验收标准。
- [02-architecture.md](docs/02-architecture.md)：服务分层、模型下载链路、部署与质量属性。
- [03-data-model.md](docs/03-data-model.md)：核心实体、字段、关系、状态机。
- [04-api-contract.md](docs/04-api-contract.md)：Web 平台 API、iPhone 终端兼容 API、错误与幂等规则。
- [05-implementation-plan.md](docs/05-implementation-plan.md)：分阶段落地、里程碑、RACI、风险。
- [06-security-compliance.md](docs/06-security-compliance.md)：模型资产、交易、隐私、审核与 App Store 边界。
- [07-test-plan.md](docs/07-test-plan.md)：端到端验收、接口、安全、性能与回归测试。
- [08-role-matrix.md](docs/08-role-matrix.md)：账户、角色、页面、按钮和数据隔离矩阵。

## 第一版原则

1. 先做可卖、可分配、可下载、可追责的 B2B 平台，不做消费级 App 内商城。
2. 先复用 `vino_cloud` 已跑通的授权下载协议，再替换存储、数据库、支付和队列。
3. 先支持平台人工审核和人工/线下收款兜底，再逐步接入自动支付、自动结算和发票。
4. 先服务 `CoreML` 工业视觉模型，避免变成泛 AI 插件市场。
5. 所有模型资产必须有版本、哈希、授权、下载票据、设备绑定和审计记录。

## 启动

```sh
npm start
```

默认端口：`8797`

默认后台：`http://127.0.0.1:8797/`

可配置环境变量：

- `PORT`：Web 服务端口，默认 `8797`。
- `HOST`：监听地址，Docker/ECS 默认 `0.0.0.0`。
- `VINO_DATA_ROOT`：本地数据目录，默认 `vino_platform/data`。
- `VINO_STATE_PATH`：状态文件路径，默认 `VINO_DATA_ROOT/state.json`。
- `VINO_MODEL_UPLOAD_ROOT`：开发者上传模型构建的落盘目录。
- `VINO_ARTIFACT_CACHE_ROOT`：模型 artifact 落盘缓存目录，默认 `VINO_DATA_ROOT/artifact-cache`。
- `VINO_DOWNLOAD_WORK_ROOT`：一次性加密下载包临时目录，默认 `VINO_DATA_ROOT/download-work`。
- `VINO_BACKUP_ROOT`：`state.json` 备份目录，默认 `VINO_DATA_ROOT/backups`。
- `VINO_EXTERNAL_BASE_URL`：返回给 iPhone 下载票据的公网根地址，绑定域名或反代 HTTPS 后必须设置。
- `VINO_REQUEST_BODY_LIMIT`：JSON 请求体上限，默认 `200mb`。
- `VINO_RATE_LIMIT_ENABLED` / `VINO_RATE_LIMIT_MAX` / `VINO_RATE_LIMIT_AUTH_MAX`：基础内存限频，默认每 IP 每分钟 600 次，登录口 30 次。
- `VINO_TICKET_RETENTION_DAYS` / `VINO_DOWNLOAD_WORK_RETENTION_MINUTES` / `VINO_ARTIFACT_CACHE_RETENTION_DAYS`：维护清理保留期。
- `VINO_SESSION_TTL_DAYS`：Web 与终端 API token 有效天数，默认 `7`。
- `VINO_SEED_DEMO_DATA=false`：关闭默认演示账号注入，公开 ECS 首次启动建议配合 `VINO_BOOTSTRAP_ADMIN_PASSWORD` 使用。
- `VINO_SKIP_MODEL_DISCOVERY=1`：跳过仓库 `models/` 自动发现，适合隔离测试。

回归测试：

```sh
npm test
```

测试会使用临时数据目录和临时端口启动平台，不会污染当前演示数据。

Docker / ECS 单容器启动：

```sh
cp .env.example .env
npm run deploy:check
docker compose up -d --build
docker compose ps
```

生产入口建议用 Nginx/SLB 做 HTTPS 反代，并把 `.env` 里的 `VINO_EXTERNAL_BASE_URL` 改成最终公网 HTTPS 地址。详细步骤见 [docs/09-ecs-docker-deploy.md](docs/09-ecs-docker-deploy.md)。

文件态备份和恢复：

```sh
npm run backup
npm run restore -- ./data/backups/state-YYYY-MM-DDTHH-MM-SS.json.gz
npm run doctor
npm run maintenance -- --dry-run
npm run maintenance
```

模型下载压测：

```sh
npm run test:download
VINO_STRESS_MODEL_MB=500 npm run test:download
```

压测脚本会创建临时 `.mlmodel`，走终端登录、模型同步、下载票据和加密下载，并用流式读取统计下载字节数。

文件态运行说明：

- 单个 Node 进程内会对所有读取/写入 `state.json` 的 API 做串行化，避免并发请求互相覆盖状态。
- 不要在同一份 `/app/data/state.json` 前面横向扩多个容器；要横向扩展时先迁 PostgreSQL / 对象存储。

运维状态接口：

```text
GET /api/platform/v1/admin/ops/status
GET /api/platform/v1/admin/ops/doctor
POST /api/platform/v1/admin/ops/maintenance
```

这些接口需要平台管理员、管理员或平台运营 token。`ops/status` 会返回运行时、配置风险、`state.json`、备份、缓存、下载工作目录、ticket/session 和核心集合计数；`ops/doctor` 会检查重复 ID、引用完整性、明文密码、模型源文件和交易授权关系；`ops/maintenance` 会清理失效 session、过期/已用 ticket 和残留下载临时文件，`dryRun=true` 时只预览。

演示账号：

- 平台超级管理员：`admin` / `meiyoumima`
- 平台运营：`ops@vino.cc` / `demo123`
- 审核员：`reviewer@vino.cc` / `demo123`
- 财务：`finance@vino.cc` / `demo123`
- 采购管理员：`buyer@vino.cc` / `demo123`
- 现场操作员：`demo@vino.cc` / `demo123`
- 开发者：`developer@vino.cc` / `demo123`

## 已落地的 MVP 能力

- Web 后台：总览、订单、授权、用户、SKU、模型状态、设备、资产、结果、审计。
- 角色权限：不同账号按角色展示不同页面、数据和操作按钮，并在后端 API 侧同步拦截越权访问。
- 模型商城：搜索、分类、试用授权、收藏、评价。
- 开发者中心：开发者入驻、资质状态、模型草稿、提交审核、平台审核。
- 交易闭环：创建订单、优惠券抵扣、人工确认收款、自动生成 Entitlement。
- 授权闭环：手动授权、组织/用户分配、撤销、离线租约。
- 终端兼容 API：登录、模型列表、下载票据、下载模型、续租。
- 模型分发：自动发现仓库 `models/` 下 CoreML 文件，生成 `bundle-archive`，返回 `vino-aesgcm-v1` 加密包。
- ingest：图片/视频资产、推理结果、日志、统计。
- 技术服务：售后工单、工单回复/关闭、定制需求、开发者报价。
- 财务运营：发票申请/审核、开发者结算、提现申请/审核、优惠券、活动、分类、平台参数。
- 安全底座：演示密码会迁移为 PBKDF2 hash 存储，登录仍保持原账号密码。
- 自动化验收：覆盖账号、上传、审核、订单、支付、授权、下载、租约、ingest、工单、定制、发票、提现、退款、设备封禁和审计。
- 审计：关键业务动作写入审计日志。

## 下一步

把当前文件态 MVP 升级为数据库、对象存储、队列、真实支付、真实发票/结算和生产级鉴权部署。
