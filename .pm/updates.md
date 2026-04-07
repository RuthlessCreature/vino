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
