# vino architecture

## 目标

`vino` 面向工业检测流程，负责把“采集、推理、远程控制、数据归档”整合为一套双端系统：

- iPhone 作为边缘采集节点。
- Desktop 作为控制台、数据终端和批处理网关。

## 设计原则

- 清晰：任何设备当前状态、参数、模型、连接情况都能直接看到。
- 可控：本地 UI 与远程控制使用同一套参数模型。
- 可扩展：协议分版本、动作分命名空间、文件传输独立建模。
- 可追溯：所有远程触发都带 `productUUID` 与 `pointIndex`。

## iPhone 侧模块

### 1. Capture Surface

- `AVCaptureSession` 驱动实时预览。
- `ignoresSafeArea` 全屏显示相机内容。
- 叠加工业化控制层，不侵入预览内容。

### 2. Camera Control Domain

- 统一抽象帧率、色温、色调、曝光时间、ISO、EV、变焦、焦点位置。
- 所有控制项都带动态范围，优先从相机能力读取。
- 自动对焦与定焦模式共享同一状态模型。

### 3. Control Plane

- 通过 Bonjour 广播服务。
- 通过 TCP JSONL 接收远程命令、返回状态、上传分块数据。
- 远程命令与本地 UI 共用同一套 `CameraSettings` / `AppState`。

### 4. Model Registry

- 维护已上传 CoreML 模型的清单。
- 支持安装、删除、启用、停用。
- 模型状态进入设备心跳与状态上报。

### 5. Result Router

- 本地保存图像/视频。
- 可选发送到远程 POST 地址。
- 所有结果带统一上下文元数据。

### 6. Interface Monitor

- 周期刷新当前设备可用 IP。
- 区分 Wi‑Fi、蜂窝、USB/桥接等接口。

## Desktop 侧模块

### 1. Discovery & Fleet View

- 支持手输 IP 直连。
- 支持 Bonjour / 网段探测自动发现。
- 每台 iPhone 以设备卡片展示名字、在线状态、关键参数、模型状态。

### 2. Device Workspace

- 单设备视角下可以完整映射 iPhone 端全部相机控制。
- 保证远程参数项与手机 UI 一致。

### 3. Model Manager

- 给单台或多台设备上传、删除、切换模型。
- 以批量任务视图反馈进度和结果。

### 4. Data Terminal

- 用于查看心跳、错误、命令回执、采集记录、推理输出。
- 强调时序与可检索性，不做 Web 风格界面。

### 5. POST Gateway

- 提供 `POST /api/v1/batch`。
- 允许外部系统一次下发多条操作到任意已连接 iPhone。
- 统一转换为内部协议消息。

## 数据流

1. Desktop 发现 iPhone，建立控制通道。
2. iPhone 主动上报 `hello + capabilities + status`。
3. Desktop 下发参数更新、模型变更、触发动作。
4. iPhone 执行采图/录制/推理，并带上下文输出结果。
5. 结果可回推给 Desktop，也可发往远端 POST 目标。

## 可扩展点

- 协议动作按命名空间扩展，如 `camera.*`、`inference.*`、`capture.*`。
- 文件传输版本可独立升级。
- Android 端未来只需复用 `shared` 协议层和 Desktop 控制层。

