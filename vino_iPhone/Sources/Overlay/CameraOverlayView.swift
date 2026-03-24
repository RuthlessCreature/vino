import SwiftUI

public struct CameraOverlayView: View {
    @ObservedObject private var appState: VinoAppState
    @ObservedObject private var cameraController: CameraSessionController
    @ObservedObject private var controlPlane: ControlPlaneCoordinator

    @State private var isTopPanelExpanded = false
    @State private var isControlDeckExpanded = true

    private let ipAddresses: [IPAddressDescriptor]

    public init(
        appState: VinoAppState,
        cameraController: CameraSessionController,
        ipAddresses: [IPAddressDescriptor],
        controlPlane: ControlPlaneCoordinator
    ) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._cameraController = ObservedObject(wrappedValue: cameraController)
        self._controlPlane = ObservedObject(wrappedValue: controlPlane)
        self.ipAddresses = ipAddresses
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                topPanel(width: geometry.size.width)

                Spacer(minLength: 0)

                controlDeck(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func topPanel(width: CGFloat) -> some View {
        collapsiblePanel(
            title: appState.deviceName,
            subtitle: "状态 / 网络",
            summary: topSummary,
            isExpanded: $isTopPanelExpanded,
            fillOpacity: 0.34
        ) {
            topPanelContent(width: width)
        }
    }

    @ViewBuilder
    private func topPanelContent(width: CGFloat) -> some View {
        if width > 560 {
            HStack(alignment: .top, spacing: 8) {
                statusBlock
                networkBlock
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                statusBlock
                networkBlock
            }
        }
    }

    private var statusBlock: some View {
        infoBlock(title: "状态") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    statePill("连接", value: appState.isConnectedToDesktop ? "已连" : "未连", color: appState.isConnectedToDesktop ? VinoTheme.success : .white.opacity(0.45))
                    statePill("模式", value: appState.captureMode.label, color: VinoTheme.accent)
                    statePill("对焦", value: appState.focusMode == .continuousAuto ? "自动" : "锁定", color: .white)
                    statePill("录制", value: appState.isRecording ? "开启" : "关闭", color: appState.isRecording ? VinoTheme.danger : .white.opacity(0.45))
                    statePill("推理", value: appState.inferenceEnabled ? "开启" : "关闭", color: appState.inferenceEnabled ? VinoTheme.success : .white.opacity(0.45))
                }

                compactInfoLine("当前状态", value: appState.lastStatusMessage)
                compactInfoLine("最近文件", value: cameraController.lastCapturedFileURL?.lastPathComponent ?? "暂无本地媒体")
            }
        }
    }

    private var networkBlock: some View {
        infoBlock(title: "网络") {
            VStack(alignment: .leading, spacing: 8) {
                compactInfoLine(
                    "IP 地址",
                    value: ipAddresses.isEmpty ? "等待网络接口..." : ipAddresses.map(\.displayValue).joined(separator: "  |  ")
                )
                compactInfoLine("服务状态", value: controlPlane.serviceSummary)
                compactInfoLine("远程上下文", value: contextSummary)
                compactInfoLine("当前模型", value: activeModelSummary)
            }
        }
    }

    private func controlDeck(width: CGFloat, height: CGFloat) -> some View {
        let supportedProfiles = cameraController.capabilities.supportsProRes
            ? RecordingProfile.allCases
            : RecordingProfile.allCases.filter { $0 != .proRes }

        let columns = [
            GridItem(.flexible(minimum: max(140, (width - 40) / 2)), spacing: 8),
            GridItem(.flexible(minimum: max(140, (width - 40) / 2)), spacing: 8)
        ]

        return collapsiblePanel(
            title: "控制台",
            subtitle: "相机参数 / 触发 / 上下文",
            summary: controlDeckSummary,
            isExpanded: $isControlDeckExpanded,
            fillOpacity: 0.42
        ) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        compactSelectionGroup(title: "模式", items: CaptureMode.allCases, current: appState.captureMode) { selected in
                            appState.captureMode = selected
                        }

                        compactSelectionGroup(title: "镜头", items: cameraController.availableLenses, current: appState.selectedLens) { selected in
                            appState.selectedLens = selected
                            cameraController.switchLens(to: selected, appState: appState)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        compactSelectionGroup(title: "编码", items: supportedProfiles, current: appState.recordingProfile) { selected in
                            appState.recordingProfile = selected
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            sectionTitle("采集")

                            HStack(spacing: 8) {
                                compactActionButton(
                                    title: primaryActionTitle,
                                    color: appState.captureMode == .photo ? VinoTheme.accent : (appState.isRecording ? VinoTheme.danger : VinoTheme.warning),
                                    foreground: .black
                                ) {
                                    cameraController.triggerPrimaryAction(appState: appState)
                                }

                                compactActionButton(title: "刷新能力", color: .white.opacity(0.12), foreground: .white) {
                                    cameraController.refreshCapabilities(appState: appState)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    HStack(spacing: 8) {
                        compactToggle(
                            title: "自动对焦",
                            isOn: Binding(
                                get: { appState.focusMode == .continuousAuto },
                                set: { appState.focusMode = $0 ? .continuousAuto : .locked }
                            )
                        )

                        compactToggle(
                            title: "平滑对焦",
                            isOn: $appState.smoothAutoFocusEnabled,
                            enabled: appState.focusMode == .continuousAuto && cameraController.capabilities.supportsSmoothAutoFocus
                        )

                        compactToggle(title: "闪光灯", isOn: $appState.flashEnabled, enabled: cameraController.capabilities.supportsFlash)
                    }

                    HStack(spacing: 8) {
                        compactToggle(title: "推理", isOn: $appState.inferenceEnabled)
                        compactToggle(title: "推送媒体", isOn: $appState.persistMediaEnabled)
                    }

                    compactTextField("产品 UUID", text: $appState.activeContext.productUUID, keyboard: .default)

                    HStack(spacing: 8) {
                        compactTextField(
                            "点位号",
                            text: Binding(
                                get: { String(appState.activeContext.pointIndex) },
                                set: { appState.activeContext.pointIndex = Int($0) ?? 0 }
                            ),
                            keyboard: .numberPad
                        )

                        compactTextField("任务 ID", text: $appState.activeContext.jobID, keyboard: .default)
                    }

                    compactTextField("远程 POST 地址", text: $appState.remotePostURL, keyboard: .URL)

                    LazyVGrid(columns: columns, spacing: 8) {
                        CompactAdjustableControlCard(
                            title: "帧率",
                            value: $cameraController.settings.frameRate,
                            range: cameraController.capabilities.frameRate,
                            formatter: { String(format: "%.0f fps", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }

                        CompactAdjustableControlCard(
                            title: "色温",
                            value: $cameraController.settings.whiteBalanceTemperature,
                            range: cameraController.capabilities.whiteBalanceTemperature,
                            formatter: { String(format: "%.0f K", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }

                        CompactAdjustableControlCard(
                            title: "色调",
                            value: $cameraController.settings.whiteBalanceTint,
                            range: cameraController.capabilities.whiteBalanceTint,
                            formatter: { String(format: "%.0f", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }

                        CompactAdjustableControlCard(
                            title: "曝光时间",
                            value: $cameraController.settings.exposureSeconds,
                            range: cameraController.capabilities.exposureSeconds,
                            formatter: { String(format: "%.4f s", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }

                        CompactAdjustableControlCard(
                            title: "ISO",
                            value: $cameraController.settings.iso,
                            range: cameraController.capabilities.iso,
                            formatter: { String(format: "%.0f", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }

                        CompactAdjustableControlCard(
                            title: "曝光补偿",
                            value: $cameraController.settings.exposureBias,
                            range: cameraController.capabilities.exposureBias,
                            formatter: { String(format: "%.1f", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }

                        CompactAdjustableControlCard(
                            title: "变焦",
                            value: $cameraController.settings.zoomFactor,
                            range: cameraController.capabilities.zoomFactor,
                            formatter: { String(format: "%.1fx", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }

                        CompactAdjustableControlCard(
                            title: "焦点位置",
                            value: $cameraController.settings.lensPosition,
                            range: cameraController.capabilities.lensPosition,
                            enabled: appState.focusMode == .locked,
                            formatter: { String(format: "%.2f", $0) }
                        ) {
                            cameraController.apply(appState: appState)
                        }
                    }
                }
            }
            .frame(maxHeight: min(max(height * 0.48, 220), 360))
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var topSummary: String {
        let link = appState.isConnectedToDesktop ? "已连接上位机" : "未连接上位机"
        return "\(link) · \(appState.captureMode.label) · \(appState.lastStatusMessage)"
    }

    private var controlDeckSummary: String {
        [
            "模式：\(appState.captureMode.label)",
            "推理：\(appState.inferenceEnabled ? "开" : "关")",
            "录制：\(appState.isRecording ? "进行中" : "待机")"
        ].joined(separator: "  |  ")
    }

    private var primaryActionTitle: String {
        switch appState.captureMode {
        case .photo:
            return "执行拍照"
        case .stream:
            return appState.isRecording ? "停止录像" : "开始录像"
        }
    }

    private var activeModelSummary: String {
        let activeModels = appState.modelCatalog.activeModels
        if activeModels.isEmpty {
            return "未启用模型"
        }

        return activeModels
            .map { "\($0.name)@\($0.version)" }
            .joined(separator: "  |  ")
    }

    private var contextSummary: String {
        let product = appState.activeContext.productUUID.isEmpty ? "未设置" : appState.activeContext.productUUID
        let job = appState.activeContext.jobID.isEmpty ? "未设置" : appState.activeContext.jobID
        return "产品：\(product)  |  点位：\(appState.activeContext.pointIndex)  |  任务：\(job)"
    }

    private func collapsiblePanel<Content: View>(
        title: String,
        subtitle: String,
        summary: String,
        isExpanded: Binding<Bool>,
        fillOpacity: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(subtitle)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(VinoTheme.textSecondary)

                        Text(summary)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(isExpanded.wrappedValue ? 2 : 1)
                            .minimumScaleFactor(0.7)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(VinoTheme.panelStroke, lineWidth: 1)
                        )
                }
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color.black.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VinoTheme.panelStroke.opacity(0.92), lineWidth: 1)
        )
    }

    private func infoBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VinoTheme.panelStroke.opacity(0.82), lineWidth: 1)
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(VinoTheme.textSecondary)
    }

    private func compactInfoLine(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
    }

    private func statePill(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }

    private func compactActionButton(
        title: String,
        color: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func compactToggle(
        title: String,
        isOn: Binding<Bool>,
        enabled: Bool = true
    ) -> some View {
        Button {
            guard enabled else { return }
            isOn.wrappedValue.toggle()
            cameraController.apply(appState: appState)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(enabled ? .white.opacity(0.5) : .white.opacity(0.2))

                Text(isOn.wrappedValue ? "开启" : "关闭")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(enabled ? (isOn.wrappedValue ? VinoTheme.accent : .white) : .white.opacity(0.28))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                (enabled ? (isOn.wrappedValue ? VinoTheme.accent.opacity(0.14) : .black.opacity(0.26)) : .black.opacity(0.18)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(enabled ? VinoTheme.panelStroke : .white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func compactTextField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))

            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VinoTheme.panelStroke, lineWidth: 1)
                )
        }
    }

    private func compactSelectionGroup<Item: Identifiable & Hashable>(
        title: String,
        items: [Item],
        current: Item,
        onSelect: @escaping (Item) -> Void
    ) -> some View where Item: CustomStringConvertible {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)

            HStack(spacing: 6) {
                ForEach(items, id: \.id) { item in
                    let isSelected = item == current

                    Button {
                        onSelect(item)
                    } label: {
                        Text(item.description)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(isSelected ? .black : .white)
                            .background(
                                isSelected ? VinoTheme.accent : .black.opacity(0.26),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isSelected ? VinoTheme.accent : VinoTheme.panelStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct CompactAdjustableControlCard: View {
    let title: String
    @Binding var value: Double
    let range: ControlRange
    var enabled: Bool = true
    let formatter: (Double) -> String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VinoTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                Text(formatter(value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(enabled ? .white : .white.opacity(0.32))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 6) {
                Button("-") {
                    guard enabled else { return }
                    value = range.clamped(value - range.step)
                    onChange()
                }
                .buttonStyle(CompactStepButtonStyle(enabled: enabled))

                Slider(
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            value = range.clamped(newValue)
                            onChange()
                        }
                    ),
                    in: range.min...range.max
                )
                .tint(enabled ? VinoTheme.accent : .white.opacity(0.18))
                .disabled(!enabled)

                Button("+") {
                    guard enabled else { return }
                    value = range.clamped(value + range.step)
                    onChange()
                }
                .buttonStyle(CompactStepButtonStyle(enabled: enabled))
            }
        }
        .padding(8)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(enabled ? VinoTheme.panelStroke : .white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct CompactStepButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(enabled ? .white : .white.opacity(0.3))
            .frame(width: 28, height: 28)
            .background(.black.opacity(configuration.isPressed ? 0.5 : 0.24), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(enabled ? VinoTheme.panelStroke : .white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension CaptureMode: CustomStringConvertible {
    public var description: String { label }
}

extension LensChoice: CustomStringConvertible {
    public var description: String { label }
}

extension RecordingProfile: CustomStringConvertible {
    public var description: String { label }
}
