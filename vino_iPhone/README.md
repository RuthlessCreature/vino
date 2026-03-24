# vino_iPhone

`vino_iPhone` 现在是一个可直接在 Xcode 中打开并编译的 iPhone App 工程。

## 打开方式

- Xcode 工程：`vino_iPhone/vino_iPhone.xcodeproj`
- 共享 Scheme：`vino_iPhone`
- App 入口：`vino_iPhone/AppHost/VinoPhoneApp.swift`

## 当前包含

- `Sources/App/VinoPhoneShellView.swift`：全屏相机预览 + 推理框 Overlay + 控制 UI
- `Sources/Camera/CameraSessionController.swift`：相机能力读取、参数应用、拍照、录像
- `Sources/Networking/ControlPlaneCoordinator.swift`：Bonjour + TCP JSONL 控制面、状态回推、模型传输
- `Sources/Inference/InferenceRuntime.swift`：多模型并行 Vision/CoreML 推理运行时
- `Sources/Models/ModelFileStore.swift`：CoreML 模型安装、编译、激活、删除

## 构建命令

```sh
cd vino_iPhone
xcodebuild -project vino_iPhone.xcodeproj -scheme vino_iPhone -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## 权限说明

- 相机权限：实时预览、拍照、录像、推理输入
- 局域网权限：与 `vino_Desktop` 进行发现、控制与状态同步
- Bonjour 服务：`_vino-control._tcp`
