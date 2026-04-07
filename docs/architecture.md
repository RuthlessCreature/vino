# vino architecture

## 目标

`vino` 面向工业检测流程，负责把“采集、推理、远程控制、数据归档”整合为一套边缘 + 本地节点 + 云端后台系统：

- iPhone 作为边缘采集节点。
- 本地 Web 作为现场接收、缓存与转发节点。
- 云端 Web 作为账号、授权、模型与业务后台。

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

## 本地 Web 节点模块

### 1. Ingest API

- 接收图片、视频、推理结果上传。
- 提供局域网内低延迟 `POST` 入口。
- 支持幂等键与分块上传。

### 2. Local Queue & Retry

- 在断网或云端不可达时本地排队。
- 记录待补传任务与失败原因。

### 3. Local Archive

- 保存现场短期图片、视频与结果文件。
- 支持按时间、设备、项目做本地索引。

### 4. Cloud Forwarder

- 把本地接收到的数据异步转发到云端。
- 支持续传、补传与转发确认。

## 云端 Web 侧模块

### 1. Auth & License

- 账号、组织、设备、授权、离线租约。

### 2. Model Catalog

- 模型目录、版本、订单、Entitlement 分配。

### 3. Cloud Control API

- 下发任务、同步配置、查询设备状态。

### 4. Project & Result Console

- 查看项目、设备、图片、视频、推理结果和报表。

## 数据流

1. iPhone 从云端获取授权、模型和任务配置。
2. iPhone 在现场执行采图/录制/推理。
3. iPhone 将图片、视频、推理结果上传到本地 Web 节点。
4. 本地 Web 节点完成缓存、落盘、排队和转发。
5. 云端 Web 接收最终结果并提供查询、管理与审计。

## 可扩展点

- 协议动作按命名空间扩展，如 `camera.*`、`inference.*`、`capture.*`。
- 文件传输版本可独立升级。
- Android 端未来只需复用 `shared` 协议层和本地/云端接口层。

