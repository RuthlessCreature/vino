# vino_platform 测试计划

- Product: `vino_platform`
- Date: 2026-04-29
- Status: Draft

## 测试目标

- 验证模型从上架、购买、授权到 iPhone 下载可完整闭环。
- 验证未授权、过期、撤销、设备不匹配等负向场景可靠。
- 验证模型文件哈希、加密包和票据过期机制可用。
- 验证运营后台能追踪订单、授权、设备和下载审计。

## P0 端到端用例

| ID | Scenario | Steps | Expected |
| --- | --- | --- | --- |
| E2E-001 | 管理员上传模型 | 登录后台，上传 `.mlpackage`，等待构建完成 | 生成 ModelBuild、sha256、byteCount |
| E2E-002 | 模型审核上架 | 提交审核，审核通过，配置 SKU | 模型在商城可见 |
| E2E-003 | 线下订单授权 | 采购方下单，运营确认收款 | 订单 paid，生成 Entitlement |
| E2E-004 | iPhone 拉取模型 | 终端登录，调用模型列表 | 只返回已授权模型 |
| E2E-005 | iPhone 下载模型 | 申请票据，下载，校验，安装 | 模型安装成功，metadata 带 license |
| E2E-006 | 离线租约续期 | 终端调用续租接口 | 更新 leaseExpiresAt |
| E2E-007 | ingest 上传 | 终端上传图片和推理结果 | 后台可查资产和结果 |

## 负向用例

| ID | Scenario | Expected |
| --- | --- | --- |
| NEG-001 | 未登录请求模型列表 | 401 |
| NEG-002 | 无 Entitlement 请求模型列表 | 返回空列表 |
| NEG-003 | 无授权申请下载票据 | 403 |
| NEG-004 | 合同到期后申请票据 | 403 |
| NEG-005 | 下载票据过期后下载 | 404 |
| NEG-006 | 设备 ID 与租约不匹配 | 403 |
| NEG-007 | 模型哈希不匹配 | 终端安装失败，后台记录失败 |
| NEG-008 | 重复支付回调 | 只处理一次 |
| NEG-009 | 重复 ingest idempotencyKey | 返回已有记录，不重复写入 |
| NEG-010 | 普通开发者访问运营审核接口 | 403 |

## 接口测试

必须覆盖：

- Auth：登录、token 过期、角色权限。
- Catalog：模型列表、详情、搜索、上下架过滤。
- Upload：格式校验、大小限制、hash 计算。
- Review：提交、通过、驳回、重新提交。
- Order：创建、确认收款、取消、退款标记。
- Entitlement：创建、分配、撤销、过期过滤。
- Delivery：ticket、download、lease renew。
- Ingest：asset、result、log、stat。
- Audit：关键动作写入日志。

## 安全测试

- 越权访问其他组织模型、订单、设备。
- 修改 modelId 下载未授权模型。
- 重放过期下载票据。
- 使用其他设备 ID 续租。
- 上传非法扩展名或超大文件。
- 支付回调签名错误。
- 高频申请下载票据触发限流。
- 审计日志不能被普通用户删除或修改。

## 性能测试

| Target | MVP Gate |
| --- | --- |
| 模型列表 | P95 < 500 ms |
| 下载票据 | P95 < 800 ms |
| 100 个并发模型列表请求 | 错误率 < 1% |
| 10 个并发 500 MB 模型下载 | 服务稳定，无内存暴涨 |
| ingest 1000 条结果 | 去重和查询正常 |

## 兼容测试

- `vino_iPhone` 当前 `AuthService` 登录字段。
- `CloudModelCatalog` 字段解析。
- `ModelDownloadTicketResponse` 字段解析。
- `ModelFileStore` 对 `bundle-archive` 和 `vino-aesgcm-v1` 的安装。
- `ModelLicenseVerifier` 对设备绑定和租约过期的判断。

## 发布 Gate

发布前必须满足：

- E2E-001 到 E2E-007 全部通过。
- NEG-001 到 NEG-010 全部通过。
- 所有 P0 API 有自动化测试。
- 关键后台页面有冒烟测试。
- 下载与授权链路有审计记录。
- 生产配置强制 HTTPS、密钥环境变量、对象存储权限隔离。

## 下一步

在实现开始时同步创建 API 测试集合，后续每个阶段都把新增接口纳入回归。
