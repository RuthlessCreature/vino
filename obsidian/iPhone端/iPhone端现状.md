---
project: vino
updated: 2026-05-25
tags:
  - vino
  - iphone
---

# iPhone 端现状

## 入口

- Xcode 工程：`vino_iPhone/vino_iPhone.xcodeproj`
- Scheme：`vino_iPhone`
- App 入口：`vino_iPhone/AppHost/VinoPhoneApp.swift`
- 主界面：`vino_iPhone/Sources/App/VinoPhoneShellView.swift`

## 关键模块

| 模块 | 文件 | 职责 |
| --- | --- | --- |
| 相机 | `Sources/Camera/CameraSessionController.swift` | 预览、拍照、录像、参数应用、镜头切换 |
| Overlay | `Sources/Overlay/CameraOverlayView.swift` | 工业控制面板、云登录、模型目录、状态展示 |
| 推理 | `Sources/Inference/InferenceRuntime.swift` | Vision/CoreML 多模型并行推理 |
| 模型管理 | `Sources/Models/ModelFileStore.swift` | 模型安装、解密、hash 校验、编译、激活、删除 |
| 授权校验 | `Sources/Models/ModelLicenseVerifier.swift` | 设备绑定和离线租约校验 |
| 云登录 | `Sources/Auth/AuthService.swift` | 登录、模型列表、票据、下载、续租 |
| 云协调 | `Sources/Networking/CloudControlCoordinator.swift` | 会话恢复、模型同步、下载安装、上传补传 |
| 上传缓冲 | `Sources/Networking/AssetUploadService.swift` | 图片、视频、推理结果缓冲和补传 |
| 控制面 | `Sources/Networking/ControlPlaneCoordinator.swift` | Bonjour、TCP JSONL、状态、回执、模型传输 |

## 已落地能力

- 全屏相机预览和 Overlay 控制层。
- 相机参数：帧率、白平衡、曝光、ISO、EV、变焦、焦点、闪光灯。
- 镜头选择：主摄、超广角、长焦，按设备能力筛选。
- 拍照、录像、本地应用目录保存，并尝试写入系统图库。
- 视频流实时推理，拍照后单次推理。
- 多模型并行推理和检测框 Overlay。
- Desktop 控制协议：Bonjour、TCP JSONL、状态、心跳、能力、回执。
- 云登录、Keychain 会话恢复、云模型目录同步。
- 模型下载票据、AES-GCM 解密、sha256 校验、CoreML 安装。
- 离线租约更新和设备绑定校验。
- 图片、视频、推理结果本地缓冲，并上传到本地节点或 Cloud。

## 当前边界

- 默认 Cloud 地址仍是开发环境地址。
- `localNodeBaseURL` 默认是 `127.0.0.1`，真机联调时必须改成局域网可访问地址。
- 模型大文件下载目前缺少前台进度、取消、断点续传和可解释失败状态。
- ProRes 当前只在状态模型和 UI 中建模，实际录制配置还没有完整落到 AVFoundation。
- 端侧已能缓存上传任务，但缺少生产级退避、重试策略、失败详情和队列管理 UI。
- 后台行为尚未定义，例如退后台时是否继续采集、推理、上传或停止控制面。

