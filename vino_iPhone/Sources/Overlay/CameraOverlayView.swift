import SwiftUI
import UIKit

public struct CameraOverlayView: View {
    @ObservedObject private var appState: VinoAppState
    @ObservedObject private var cameraController: CameraSessionController
    @ObservedObject private var controlPlane: ControlPlaneCoordinator
    @ObservedObject private var cloudCoordinator: CloudControlCoordinator
    @State private var isCloudCatalogPresented = false

    @Binding private var isTopGridVisible: Bool
    @Binding private var isControlDeckVisible: Bool

    private let ipAddresses: [IPAddressDescriptor]

    public init(
        appState: VinoAppState,
        cameraController: CameraSessionController,
        ipAddresses: [IPAddressDescriptor],
        controlPlane: ControlPlaneCoordinator,
        cloudCoordinator: CloudControlCoordinator,
        isTopGridVisible: Binding<Bool>,
        isControlDeckVisible: Binding<Bool>
    ) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._cameraController = ObservedObject(wrappedValue: cameraController)
        self._controlPlane = ObservedObject(wrappedValue: controlPlane)
        self._cloudCoordinator = ObservedObject(wrappedValue: cloudCoordinator)
        self._isTopGridVisible = isTopGridVisible
        self._isControlDeckVisible = isControlDeckVisible
        self.ipAddresses = ipAddresses
    }

    public var body: some View {
        GeometryReader { geometry in
            let overlayWidth = min(max(geometry.size.width - 20, 0), 760)

            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    topStatusBar(width: overlayWidth)
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)

                VStack(spacing: 8) {
                    if isTopGridVisible {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            topInfoGrid(width: overlayWidth)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 48)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)
                }

                VStack {
                    Spacer(minLength: 0)

                    if isControlDeckVisible {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            controlDeck(width: overlayWidth, height: geometry.size.height)
                            Spacer(minLength: 0)
                        }
                            .padding(.bottom, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: isControlDeckVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isCloudCatalogPresented) {
            CloudModelCatalogSheet(appState: appState, cloudCoordinator: cloudCoordinator)
        }
    }

    private func topStatusBar(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(appState.deviceName)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Divider()
                .frame(height: 12)
                .overlay(.white.opacity(0.14))

            Text(primaryIPText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            topChip(appState.isConnectedToDesktop ? "已连接" : "未连接", color: appState.isConnectedToDesktop ? VinoTheme.success : .white.opacity(0.45))
            topChip(appState.captureMode.label, color: VinoTheme.accent)

            if appState.inferenceEnabled {
                topChip("推理", color: VinoTheme.success)
            }

            topChip(appState.cloudSession == nil ? "云未登" : "云已登", color: appState.cloudSession == nil ? .white.opacity(0.45) : VinoTheme.success)

            if appState.isRecording {
                topChip("录制中", color: VinoTheme.danger)
            }

            topChip(isControlDeckVisible ? "控制台开" : "控制台关", color: isControlDeckVisible ? VinoTheme.warning : .white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(VinoTheme.panelStroke.opacity(0.86), lineWidth: 1)
        )
        .frame(width: width, alignment: .center)
    }

    private func topInfoGrid(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("设备信息")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text("音量+ 隐藏")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VinoTheme.textSecondary)
            }

            let gridColumns = [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]

            LazyVGrid(columns: gridColumns, spacing: 8) {
                infoCard(title: "状态") {
                    infoLine("连接", appState.isConnectedToDesktop ? "已连接上位机" : "未连接上位机")
                    infoLine("模式", appState.captureMode.label)
                    infoLine("推理", appState.inferenceEnabled ? "开启" : "关闭")
                    infoLine("录制", appState.isRecording ? "进行中" : "待机")
                    infoLine("最近状态", appState.lastStatusMessage)
                }

                infoCard(title: "网络") {
                    infoLine("主 IP", primaryIPText)
                    infoLine("全部 IP", ipAddresses.isEmpty ? "等待网络" : ipAddresses.map(\.displayValue).joined(separator: "  |  "))
                    infoLine("服务", controlPlane.serviceSummary)
                    infoLine("模型", activeModelSummary)
                }

                infoCard(title: "云端") {
                    infoLine("会话", appState.cloudSessionSummary)
                    infoLine("同步", appState.lastCloudSyncAt.isEmpty ? "未同步" : appState.lastCloudSyncAt)
                    infoLine("消息", appState.lastCloudMessage)
                }

                infoCard(title: "云控制") {
                    infoLine("登录网址", trimmedOrFallback(appState.cloudBaseURL))
                    infoLine("账号", trimmedOrFallback(appState.cloudLoginEmail))
                    infoLine("状态", cloudTaskSummary)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VinoTheme.panelStroke.opacity(0.92), lineWidth: 1)
        )
        .frame(width: width, alignment: .center)
    }

    private func controlDeck(width: CGFloat, height: CGFloat) -> some View {
        let supportedProfiles = cameraController.capabilities.supportsProRes
            ? RecordingProfile.allCases
            : RecordingProfile.allCases.filter { $0 != .proRes }
        let contentWidth = max(width - 20, 0)

        let columns = [
            GridItem(.flexible(minimum: max(140, (contentWidth - 8) / 2)), spacing: 8),
            GridItem(.flexible(minimum: max(140, (contentWidth - 8) / 2)), spacing: 8)
        ]

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("控制台")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    Text(controlDeckSummary)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }

                Spacer(minLength: 0)

                Text("音量- 隐藏")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VinoTheme.textSecondary)
            }

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

                                compactActionButton(title: "重读能力", color: .white.opacity(0.12), foreground: .white) {
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
                        compactInfoStrip(title: "云状态", value: cloudTaskSummary)
                    }

                    compactInfoStrip(title: "状态", value: appState.lastStatusMessage)
                    compactInfoStrip(title: "模型", value: activeModelSummary)
                    compactInfoStrip(title: "最近文件", value: cameraController.lastCapturedFileURL?.lastPathComponent ?? "暂无")
                    compactInfoStrip(title: "云端", value: appState.cloudSessionSummary)

                    HStack(spacing: 8) {
                        compactActionButton(
                            title: appState.cloudSession == nil ? "云端登录" : "退出登录",
                            color: appState.cloudSession == nil ? VinoTheme.success : .white.opacity(0.12),
                            foreground: appState.cloudSession == nil ? .black : .white,
                            enabled: !cloudCoordinator.isBusy
                        ) {
                            if appState.cloudSession == nil {
                                cloudCoordinator.signIn()
                            } else {
                                cloudCoordinator.signOut()
                            }
                        }

                        compactActionButton(
                            title: "同步模型清单",
                            color: VinoTheme.accent,
                            foreground: .black,
                            enabled: appState.cloudSession != nil && !cloudCoordinator.isBusy
                        ) {
                            presentCloudModelCatalog()
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 8) {
                        CompactTextEntryCard(
                            title: "登录网址",
                            text: $appState.cloudBaseURL,
                            keyboardType: .URL,
                            textContentType: .URL
                        )
                        CompactTextEntryCard(
                            title: "账号",
                            text: $appState.cloudLoginEmail,
                            keyboardType: .emailAddress,
                            textContentType: .username
                        )
                        CompactTextEntryCard(
                            title: "密码",
                            text: $appState.cloudLoginPassword,
                            isSecure: true,
                            textContentType: .password
                        )
                    }

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
                .frame(width: contentWidth, alignment: .top)
            }
            .frame(maxHeight: min(max(height * 0.44, 210), 340))
        }
        .padding(10)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VinoTheme.panelStroke.opacity(0.92), lineWidth: 1)
        )
        .frame(width: width, alignment: .center)
    }

    private var primaryIPText: String {
        ipAddresses.first?.displayValue ?? "等待网络"
    }

    private var controlDeckSummary: String {
        [
            "模式：\(appState.captureMode.label)",
            "推理：\(appState.inferenceEnabled ? "开" : "关")",
            "录制：\(appState.isRecording ? "进行中" : "待机")"
        ].joined(separator: "  |  ")
    }

    private var cloudTaskSummary: String {
        if cloudCoordinator.isBusy {
            return "处理中…"
        }
        return cloudCoordinator.lastErrorMessage ?? cloudCoordinator.statusSummary
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
            return "未加载模型"
        }

        return activeModels.map { "\($0.name)@\($0.version)" }.joined(separator: "  |  ")
    }

    private func trimmedOrFallback(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private func presentCloudModelCatalog() {
        guard appState.cloudSession != nil else {
            appState.lastCloudMessage = "请先登录云端"
            return
        }
        isCloudCatalogPresented = true
        cloudCoordinator.syncCatalog()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(VinoTheme.textSecondary)
    }

    private func topChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.black.opacity(0.28), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
    }

    private func compactInfoStrip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VinoTheme.panelStroke, lineWidth: 1)
        )
    }

    private func infoCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VinoTheme.panelStroke.opacity(0.86), lineWidth: 1)
        )
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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

    private func compactActionButton(
        title: String,
        color: Color,
        foreground: Color,
        enabled: Bool = true,
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
        .foregroundStyle(enabled ? foreground : foreground.opacity(0.5))
        .background((enabled ? color : color.opacity(0.35)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(enabled ? 1 : 0.72)
        .disabled(!enabled)
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

private struct CloudModelCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var appState: VinoAppState
    @ObservedObject private var cloudCoordinator: CloudControlCoordinator

    init(appState: VinoAppState, cloudCoordinator: CloudControlCoordinator) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._cloudCoordinator = ObservedObject(wrappedValue: cloudCoordinator)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    summaryCard

                    if cloudCoordinator.isBusy && appState.cloudCatalog.models.isEmpty {
                        loadingCard
                    } else if appState.cloudCatalog.models.isEmpty {
                        emptyCard
                    } else {
                        ForEach(appState.cloudCatalog.models) { descriptor in
                            modelCard(descriptor)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("模型下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("退出") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新") {
                        cloudCoordinator.syncCatalog()
                    }
                    .disabled(cloudCoordinator.isBusy || appState.cloudSession == nil)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.cloudSessionSummary)
                .font(.headline)

            Text(syncStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let lastError = cloudCoordinator.lastErrorMessage, !lastError.isEmpty {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("正在同步模型清单…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前账号还没有可下载的模型")
                .font(.headline)
            Text("你可以点右上角刷新，或者直接退出不下载。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func modelCard(_ descriptor: CloudModelDescriptor) -> some View {
        let installedRecord = appState.modelCatalog.models.first(where: { $0.id == descriptor.id })

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("版本 \(descriptor.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if let installedRecord {
                    statusChip(title: installedRecord.isActive ? "已加载" : "已下载")
                }
            }

            Text(descriptor.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                detailChip(title: ByteCountFormatter.string(fromByteCount: Int64(descriptor.byteCount), countStyle: .file))
                detailChip(title: descriptor.sourceFormat.uppercased())
                if descriptor.isEncrypted {
                    detailChip(title: "加密")
                }
            }

            Button {
                cloudCoordinator.downloadModel(modelID: descriptor.id)
                dismiss()
            } label: {
                Text(installedRecord?.isActive == true ? "重新下载并加载" : "下载并加载到 iPhone")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(VinoTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(cloudCoordinator.isBusy)
            .opacity(cloudCoordinator.isBusy ? 0.6 : 1)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var syncStatusText: String {
        if cloudCoordinator.isBusy {
            return "正在同步模型清单…"
        }
        if let syncedAt = appState.cloudCatalog.syncedAt ?? (!appState.lastCloudSyncAt.isEmpty ? appState.lastCloudSyncAt : nil) {
            return "已同步：\(syncedAt)"
        }
        return "还没有同步过模型清单"
    }

    private func statusChip(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(VinoTheme.success, in: Capsule(style: .continuous))
    }

    private func detailChip(title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule(style: .continuous))
    }
}

private struct CompactTextEntryCard: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(VinoTheme.textSecondary)

            if isSecure {
                SecureField(title, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .submitLabel(.done)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                TextField(title, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .submitLabel(.done)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VinoTheme.panelStroke, lineWidth: 1)
        )
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
