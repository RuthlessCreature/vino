# vino_Desktop

`vino_Desktop` 面向工业视觉上位机控制台，当前工程由 `C++20` 控制核心、HTTP 批处理网关和一个可编译的原生 macOS GUI 组成。

## 当前包含

- `Protocol`：与 iPhone 侧一致的消息信封渲染
- `DesktopController`：TCP 控制会话、设备注册、媒体分块接收
- `BatchGatewayServer`：`POST /api/v1/batch`、`GET /api/v1/devices`、`GET /api/v1/jobs/{jobId}`
- `MiniJson`：无第三方依赖的小型 JSON 解析/序列化器
- `DesktopRuntime`：GUI 与控制核心之间的运行时桥接
- `MacApp.mm`：黑色极简风格的原生 AppKit GUI
- 模型上传回执跟踪：基于 `messageId / correlationId` 聚合 begin / chunk / commit 阶段回执
- 数据终端增强：日志搜索、级别过滤、当前设备过滤、彩色等级显示、导出日志
- 结果归档浏览：按设备浏览最新媒体文件，并支持直接打开或在 Finder 中定位
- `build_local.sh`：基于 `CMake` 的本地一键构建入口
- `vino_local_node`：无 GUI 的本地接收节点，含 `SQLite` 资产索引、本地 API、Outbox 队列和云端自动转发

## UI 方向

- 当前已落地原生 macOS GUI：
  - 左侧设备墙：手动 IP、网段扫描、Bonjour 发现
  - 中间工作区：相机参数、上下文、录制/拍照/能力获取、实时预览镜像、最新媒体/推理摘要预览
- 右侧侧栏：别名、模型管理、批量动作、模型传输状态、原始 JSON
- 底部数据终端：连接、状态、媒体、推理日志，支持过滤 / 搜索 / 导出
- Dear ImGui 仍保留为后续跨平台 GUI 方案，不阻塞当前交付。

## 构建

```sh
/Applications/CMake.app/Contents/bin/cmake -S . -B build_cmake -DCMAKE_BUILD_TYPE=Debug
/Applications/CMake.app/Contents/bin/cmake --build build_cmake --parallel 6
```

或者：

```sh
./build_local.sh
```

打包 DMG：

```sh
./package_dmg.sh
```

## 运行

GUI：

```sh
open ./build_cmake/vino_Desktop.app
```

DMG：

```sh
open ./dist/vino_Desktop-0.1.0.dmg
```

CLI / daemon：

```sh
./build_cmake/vino_desktop_blueprint --daemon --connect 192.168.31.25
```

LocalNode：

```sh
./build_cmake/vino_local_node --api-port 49030 --batch-port 49020
```

启用云端自动转发：

```sh
./build_cmake/vino_local_node \
  --api-port 49030 \
  --batch-port 49020 \
  --cloud-base-url http://127.0.0.1:8787 \
  --cloud-sync on
```

批量接口默认监听：

- `http://127.0.0.1:49020/api/v1/batch`
- `http://127.0.0.1:49020/api/v1/devices`

本地节点接口默认监听：

- `http://127.0.0.1:49030/`
- `http://127.0.0.1:49030/api/local/v1/health`
- `http://127.0.0.1:49030/api/local/v1/devices`
- `http://127.0.0.1:49030/api/local/v1/storage/summary`
- `http://127.0.0.1:49030/api/local/v1/assets`
- `http://127.0.0.1:49030/api/local/v1/outbox`
- `http://127.0.0.1:49030/api/local/v1/cloud/config`
- `http://127.0.0.1:49030/api/local/v1/ingest/asset`
- `http://127.0.0.1:49030/api/local/v1/ingest/result`
- `http://127.0.0.1:49030/api/local/v1/ingest/log`
- `http://127.0.0.1:49030/api/local/v1/ingest/stat`

macOS App 运行时数据目录：

- `~/Library/Application Support/vino`

## 当前已打通

- TCP JSONL 控制连接
- 网段扫描 + Bonjour 发现
- 设备状态 / 能力 / 推理结果聚合
- 轻量实时预览镜像接收与显示
- 最新媒体文件预览与推理摘要
- 设备别名本地持久化
- GUI 相机参数工作区
- CoreML 模型上传、激活、停用、删除
- 模型上传本地进度与设备端回执聚合
- 多设备批量拍照与推理开关
- 媒体分块接收与本地落盘
- 媒体归档下拉浏览、打开与定位
- 终端日志过滤、设备作用域筛选与导出
- LocalNode 控制台：设备、资产、Outbox、云同步配置可视化
- LocalNode Outbox：`asset/result/log/stat` 自动补传 `vino_cloud`
