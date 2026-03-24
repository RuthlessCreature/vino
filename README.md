# vino

`vino` 是一个面向工业场景的移动视觉采集与推理系统，拆成两端：

- `vino_iPhone`：iPhone 侧采集、预览、参数控制、模型管理、结果回传。
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

## 本轮已落地内容

- `vino_iPhone`：真实 `Xcode` 工程，含全屏相机预览、Overlay 控件、IP 刷新、控制平面、模型管理与多模型并行推理。
- `vino_Desktop`：`C++20` 控制核心 + 原生 macOS GUI，含设备墙、参数工作区、模型分发、数据终端、实时预览镜像和批量 HTTP 网关。
- 模型分发链路：已支持本地分块进度统计、设备端 `reply/correlationId` 回执聚合与逐设备状态跟踪。
- `shared`：协议 Schema 与示例消息，方便两端对齐。

## 下一阶段建议

1. 补桌面端更完整的结果归档、缓存和浏览界面。
2. 增强模型分发的图形化进度、失败明细和批量反馈。
3. 补 iPhone 真正的远程 HTTP POST 上传与失败重试。
