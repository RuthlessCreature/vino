---
project: vino
updated: 2026-05-25
tags:
  - vino
  - cloud
  - todo
---

# CLOUD 端 TODO

## P0 先定方向

- [ ] 明确正式 Cloud 基线：`vino_cloud` 只保留演示和联调，生产能力迁到 `vino_platform`。
- [ ] 冻结 iPhone 兼容 API 字段：登录、模型列表、下载票据、下载、续租、ingest。
- [ ] 写一份 `vino_cloud -> vino_platform` 迁移清单，覆盖 users、models、entitlements、leases、tickets、ingests。

## P0 生产化底座

- [ ] 把文件态 `state.json` 迁到 PostgreSQL，补 schema、migration、seed 数据和回滚脚本。
- [ ] 把模型、加密产物、图片、视频和附件迁到对象存储，本地磁盘只用于开发或缓存。
- [ ] 引入环境变量配置：端口、数据库、对象存储、JWT/会话密钥、AES 密钥、外部 URL、HTTPS。
- [ ] 密码改为 hash 存储，禁止生产环境保留明文演示密码。
- [ ] 会话 token 支持过期、撤销、刷新和审计。
- [ ] RBAC 在后端接口全覆盖，不只依赖前端按钮隐藏。
- [ ] 给所有写接口补 `requestId`、`Idempotency-Key` 和统一错误格式。
- [ ] 生产环境强制 HTTPS，下载 URL 不返回明文内网地址。

## P0 模型分发和授权

- [ ] 建立模型上传流水线：格式白名单、大小限制、sha256、Manifest 检查、状态机。
- [ ] 建立 Model、ModelBuild、ModelSKU、Entitlement、OfflineLease、DownloadTicket 的正式表结构。
- [ ] 下载票据只保存 secret hash 或加密封装，避免服务端长期保存明文 ticket secret。
- [ ] 下载票据加 TTL、一次性使用策略、限频和异常告警。
- [ ] 大模型下载改为流式输出，避免整包读入内存。
- [ ] Entitlement 支持组织、用户、设备、站点四类分配，并明确优先级和冲突规则。
- [ ] 授权撤销后立即停止新票据和新续租，已有模型按租约到期失效。
- [ ] 下载、续租、撤销、哈希失败、设备不匹配都写审计日志。

## P0 ingest 和结果归档

- [ ] asset 上传从 JSON base64 迁到 multipart 或签名直传，保留小文件 JSON 兼容层。
- [ ] ingest 用 `idempotencyKey` 做唯一索引，重复提交返回已有记录。
- [ ] 图片、视频、推理结果按组织、设备、项目上下文隔离。
- [ ] 给 ingest 增加保留期、清理任务和后台查询分页。
- [ ] 记录 `productUUID`、`pointIndex`、`jobId`，保证现场数据可追溯。

## P0 自动化测试和验收

- [ ] 覆盖 iPhone 兼容接口自动化测试：login、models、download-ticket、download、renew、ingest。
- [ ] 覆盖负向授权测试：未登录、未授权、过期、撤销、设备不匹配、票据过期。
- [ ] 覆盖 RBAC 测试：普通用户不能访问运营、审核、财务、授权管理接口。
- [ ] 覆盖下载包测试：AES-GCM 解密、sha256 校验、错误 key、损坏包。
- [ ] 覆盖 500 MB 级模型下载冒烟测试和并发下载压力测试。

## P1 交易平台闭环

- [ ] 完成采购方下单、线下收款凭证、运营确认收款、自动生成 Entitlement。
- [ ] 完成开发者入驻、资质审核、模型提审、驳回原因、重新提交。
- [ ] 完成 SKU 配置：试用、订阅、永久、项目期、设备数、离线租约天数。
- [ ] 完成订单、授权、设备、下载、ingest 的后台检索和导出。
- [ ] 接入在线支付、退款、发票、开发者结算和提现。
- [ ] 完成审计日志不可篡改策略和导出能力。

## P2 运维和部署

- [ ] 提供 Docker Compose 或部署脚本，包含 app、PostgreSQL、Redis、对象存储和 worker。
- [ ] 增加结构化日志、指标、APM、告警和健康检查。
- [ ] 增加备份、恢复演练和数据迁移演练。
- [ ] 增加本地 Web 节点：断网缓存、联网补传、云端转发确认。
- [ ] 增加企业 SSO、MFA、IP allowlist 和高危操作审批流。

