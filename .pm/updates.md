## 2026-03-27
- commit

## 2026-03-24
- FIRST COMMIT

## 2026-04-06
- 根据同步后的仓库内容，更新 `.pm/project.yml`，把占位元数据替换为真实的功能、需求、阶段、风险与后续动作。
- 记录本轮同步的关键进展：协议文档更新、示例 CoreML 模型入库、iPhone 端模型文件落地增强、Desktop 端模型上传与回执/并发控制增强。
- 新增 `docs/model-commerce-strategy.md`，梳理 Web 售卖模型、iPhone 账号登录下载、设备鉴权与离线授权的商业与产品方案。
- 追加产品方向判断：`vino` 首发商业形态更适合收敛为 `iPhone 执行端 + Web 控制台 + 服务端接收链路`，Desktop 降为可选内部工具。
- 进一步明确架构分层：`本地 Web` 专门负责接收图片/视频/结果并做缓存转发，`云端 Web` 负责账号、授权、售卖、模型与业务后台。
- 新增 `docs/vino-老板汇报-商业逻辑.md`，整理一版偏老板视角的商业逻辑汇报文案，重点说明卖什么、怎么赚钱、为什么去 Desktop 化。
- 新增 `docs/vino-boss-deck.md` 和 `docs/vino-boss-deck.pptx`，生成一版可直接给老板看的商业逻辑汇报 PPT。
- 新增 `docs/generate_boss_deck.py`，用于后续改稿后重新生成 `pptx`。

## 2026-04-29
- 根据《AI模型交易平台核心功能细化及落地执行方案》、`docs/model-commerce-strategy.md` 与 `vino_cloud` MVP，实现 `vino_platform` 文档目录。
- 明确 `vino_iPhone` 保持终端定位，本轮不改；模型下载、授权、离线租约和加密分发参考 `vino_cloud`。
- 新增 `vino_platform/README.md` 和 7 份平台文档，覆盖执行摘要、PRD、架构、数据模型、API 契约、落地计划、安全合规与测试计划。
- 更新 `.pm/project.yml`，把 `vino_platform` 纳入项目功能、需求、链接和下一步动作。
- 新增 `vino_platform` 零依赖 Node.js MVP，包含 Web 后台、模型自动发现、SKU、订单、授权、下载票据、AES-GCM 加密分发、离线租约和 ingest。
- 更新根 `README.md` 与 `vino_platform/README.md`，补充启动方式、演示账号和后续生产化方向。
- 继续补齐 `vino_platform` 六大业务板块：模型商城搜索/试用/收藏/评价、开发者入驻/模型提审、优惠券订单、售后工单、定制需求、发票、结算提现、活动、分类、平台参数和审计。
- 通过 Node API 验证与 in-app browser 页面验证，确认后台 9 个主功能页均可访问。
- 修正账号权限模型：新增平台运营、审核员、财务、采购管理员、现场操作员、开发者等演示账号，按角色返回不同页面、数据范围和操作能力。
- 后端补齐 RBAC 拦截，避免审核员/财务/采购/开发者通过 API 越权访问全量后台、订单、授权、商城、入驻、发票或提现接口。
- 新增 `vino_platform/docs/08-role-matrix.md`，记录账号、角色、页面、按钮和数据隔离矩阵。
