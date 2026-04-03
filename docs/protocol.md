# vino protocol v1

## 传输层

### 设备发现

- Bonjour 服务名：`_vino-control._tcp`
- 默认端口：`48920`
- 补充发现方式：Desktop 可对指定网段做 TCP 探测

### 控制通道

- 传输方式：`TCP + JSON Lines`
- 每条消息一行 UTF‑8 JSON
- `protocol` 字段固定为 `vino.control/1`

### 文件传输

- 模型、图像、视频走分块消息
- `chunkSize` 建议 `256 KB`
- `file.begin -> file.chunk -> file.commit`
- 后续可升级到 `binary-frame/v2`，不影响动作命名

### 实时预览镜像

- 当前 MVP 方案：沿控制通道发送低频 `preview.frame.push`
- 负载为 `base64 JPEG`
- 适合上位机做轻量实时镜像，不替代正式媒体回传链路

## 通用信封

```json
{
  "protocol": "vino.control/1",
  "messageId": "6D6B6C40-225E-41D0-AF04-9E2B1C4B45B2",
  "correlationId": null,
  "kind": "command",
  "action": "camera.config.patch",
  "timestamp": "2026-03-24T09:30:00Z",
  "source": {
    "role": "desktop",
    "deviceId": "desktop-main",
    "name": "vino console"
  },
  "target": {
    "deviceIds": ["iphone-001"]
  },
  "context": {
    "productUUID": "P-2026-03-24-0001",
    "pointIndex": 7,
    "jobId": "job-001"
  },
  "payload": {}
}
```

## 字段说明

- `messageId`
  - 每条消息全局唯一
  - `reply` 必须通过它建立关联
- `correlationId`
  - 普通主动消息可为 `null`
  - `reply` 必须回填被响应消息的 `messageId`
- `kind`
  - `hello`
  - `heartbeat`
  - `status`
  - `command`
  - `reply`
  - `file.begin`
  - `file.chunk`
  - `file.commit`
  - `error`
- `action`
  - 命名空间格式：`domain.verb`
  - 例如：`camera.config.patch`
- `context`
  - 远程触发必带 `productUUID` 与 `pointIndex`

## 核心动作

### 设备

- `device.hello`
- `device.heartbeat`
- `device.status.push`
- `device.alias.set`

### 相机

- `camera.capabilities.get`
- `camera.capabilities.report`
- `camera.mode.set`
- `camera.config.patch`
- `camera.focus.mode.set`
- `camera.flash.set`

### 采集

- `capture.photo.trigger`
- `capture.recording.set`
- `capture.storage.set`

### 推理

- `inference.runtime.set`
- `inference.model.install.begin`
- `inference.model.install.chunk`
- `inference.model.install.commit`
- `inference.model.remove`
- `inference.model.activate`
- `inference.model.deactivate`
- `inference.result.push`

### 数据

- `preview.frame.push`
- `media.push.begin`
- `media.push.chunk`
- `media.push.commit`

## 状态上报建议频率

- `heartbeat`：1 秒
- `status`：参数变化时立即发送；无变化时 3 秒一次
- `inference.result.push`：实时推理完成一帧即发送
- `preview.frame.push`：建议 2~4 FPS 的轻量镜像节奏

## Reply / 回执约定

- 所有 `reply` 消息都应带：
  - `correlationId = 原始请求的 messageId`
  - `action = 原始请求 action`
  - `payload.status`
  - `payload.message`
- 建议状态值：
  - `accepted`
  - `rejected`
  - `unsupported`
- 对于分阶段动作，建议每个阶段单独回执：
  - `inference.model.install.begin`
  - `inference.model.install.chunk`
  - `inference.model.install.commit`
- Desktop 当前已按 `correlationId` 聚合模型上传阶段回执，可生成逐设备传输状态。

## 典型负载

### `preview.frame.push`

```json
{
  "imageWidth": 480,
  "imageHeight": 270,
  "frameIndex": 1284,
  "encoding": "jpeg-base64",
  "jpegBase64": "/9j/4AAQSkZJRgABAQAAAQABAAD..."
}
```

说明：

- 当前 iPhone 端在 `stream` 模式下自动推送轻量预览镜像
- 这条链路优先用于 GUI 实时观察，不替代正式 `media.push.*`

## 当前实现说明

- iPhone 侧当前支持多模型并行 Vision/CoreML 推理，每个激活模型独占一个工作队列。
- 视频流模式下实时推理并渲染框；拍照时如果推理开启，也会对静态照片做一次推理。
- 远端模型安装支持：
  - 单文件 `mlmodel` 直接分块上传，手机端编译成 `mlmodelc`
  - 目录型 `mlpackage` / `mlmodelc` 由 Desktop 自动打包为 bundle archive 后上传
  - 手机端收到 `mlpackage` 后解包并编译成 `mlmodelc`
  - 手机端收到 `mlmodelc` 后解包并直接作为运行时目录使用
- iPhone 侧当前在 `stream` 模式下会自动推送低频 JPEG 预览帧，Desktop 可直接显示实时镜像。
- Desktop 侧当前会跟踪模型上传的本地分块进度，以及设备端对 `begin / chunk / commit` 的回执结果。

## Desktop POST 网关

### `POST /api/v1/batch`

```json
{
  "requestId": "batch-20260324-001",
  "operations": [
    {
      "target": {
        "deviceIds": ["iphone-001", "iphone-002"]
      },
      "action": "camera.config.patch",
      "context": {
        "productUUID": "P-2026-03-24-0001",
        "pointIndex": 2
      },
      "payload": {
        "captureMode": "photo",
        "settings": {
          "frameRate": 24,
          "iso": 80,
          "zoomFactor": 2.0
        }
      }
    },
    {
      "target": {
        "deviceIds": ["iphone-001"]
      },
      "action": "capture.photo.trigger",
      "context": {
        "productUUID": "P-2026-03-24-0001",
        "pointIndex": 2
      },
      "payload": {}
    }
  ]
}
```

### 返回值

```json
{
  "requestId": "batch-20260324-001",
  "accepted": 2,
  "rejected": 0,
  "results": [
    {
      "action": "camera.config.patch",
      "targetDeviceId": "iphone-001",
      "status": "queued"
    }
  ]
}
```

## 兼容性约定

- 不支持的动作必须返回 `reply`，并显式标记 `status = unsupported`
- 字段新增必须保持向后兼容
- 未识别字段接收方直接忽略
