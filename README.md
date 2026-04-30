# vino

`vino` 是一个面向工业场景的移动视觉采集、边缘推理、模型授权与结果回传系统，当前收敛为“终端 + 平台 + 可选本地/桌面工具”的产品形态：

- `vino_iPhone`：iPhone 侧采集、预览、参数控制、模型管理、结果回传。
- `vino_platform`：Web 模型交易、开发者入驻、模型审核、订单授权、加密分发、运营后台文档与后续实现入口。
- `vino_cloud`：零依赖 Node.js 云端 MVP，当前用于参考账号授权、模型分配、下载票据、离线租约和 ingest 链路。
- `vino_Desktop`：上位机侧设备发现、批量控制、模型分发、数据终端、POST 网关。

整个工程强调三件事：清晰、可控、可扩展。UI 走黑色极简线条未来主义风格，但交互保持工业软件该有的直接与确定性。

## 目录

```text
vino/
├─ docs/
│  ├─ architecture.md
│  ├─ feature-checklist.md
│  ├─ protocol.md
│  └─ ui-language.md
├─ shared/
│  ├─ examples/
│  └─ schemas/
├─ vino_platform/
│  ├─ README.md
│  └─ docs/
├─ vino_cloud/
│  ├─ README.md
│  ├─ public/
│  └─ server.js
├─ vino_iPhone/
│  ├─ AppHost/
│  ├─ README.md
│  ├─ Sources/
│  └─ vino_iPhone.xcodeproj/
└─ vino_Desktop/
   ├─ CMakeLists.txt
   ├─ README.md
   ├─ build_local.sh
   ├─ include/
   └─ src/
```

## 当前设计结论

- 控制协议 `v1` 采用 `Bonjour + TCP JSONL`，避免 iPhone 侧先引入过重的 HTTP/WebSocket 服务栈。
- 上位机额外暴露 `POST /api/v1/batch`，用于批量控制已连接 iPhone。
- 图片、视频、模型文件采用分块消息协议，后续可平滑升级到二进制帧。
- 远程触发统一带上 `productUUID + pointIndex`，作为采集与推理数据的基准上下文。
- `ProRes` 在实现上建模为录制编码档位，而不是镜头；镜头切换与录制档位解耦，兼容性更清楚。
- `vino_iPhone` 继续保持终端定位，不在 App 内承载完整购买、支付、开发者入驻或平台运营流程。
- `vino_platform` 承接 Web 侧模型交易、授权、分发和后台能力；模型下载与离线租约先参照 `vino_cloud`。

## 本轮已落地内容

- `vino_iPhone`：真实 `Xcode` 工程，含全屏相机预览、Overlay 控件、IP 刷新、控制平面、模型管理与多模型并行推理。
- `vino_Desktop`：`C++20` 控制核心 + 原生 macOS GUI，含设备墙、参数工作区、模型分发、数据终端、实时预览镜像和批量 HTTP 网关。
- `vino_cloud`：已跑通 Web 控制台、用户与模型授权、下载票据、AES-GCM 加密模型包、离线租约续期和 ingest。
- `vino_platform`：新增平台文档，覆盖执行摘要、PRD、架构、数据模型、API 契约、落地计划、安全合规与测试计划。
- `vino_platform`：新增零依赖 Node.js MVP，可运行 Web 后台与终端兼容 API，覆盖模型发现、商城搜索、试用、收藏评价、开发者入驻、模型提审、SKU、订单、优惠券、授权、下载票据、AES-GCM 加密包、离线租约、ingest、售后工单、定制需求、发票、结算提现、活动、分类、系统参数、角色权限和审计。
- 模型分发链路：已支持本地分块进度统计、设备端 `reply/correlationId` 回执聚合与逐设备状态跟踪。
- `shared`：协议 Schema 与示例消息，方便两端对齐。

## vino_platform 启动

```sh
cd vino_platform
npm start
```

默认端口：`8797`

默认后台：`http://127.0.0.1:8797/`

演示账号：

- 平台超级管理员：`admin` / `meiyoumima`
- 平台运营：`ops@vino.cc` / `demo123`
- 审核员：`reviewer@vino.cc` / `demo123`
- 财务：`finance@vino.cc` / `demo123`
- 采购管理员：`buyer@vino.cc` / `demo123`
- 现场操作员：`demo@vino.cc` / `demo123`
- 开发者：`developer@vino.cc` / `demo123`

## 下一阶段建议

1. 把 `vino_platform` 当前文件态 MVP 升级为数据库、对象存储和队列版本。
2. 接入真实在线支付、退款、结算、发票、开发者提现和企业 SSO。
3. 补本地 Web ingest 节点的缓存、断网续传和云端转发能力。
