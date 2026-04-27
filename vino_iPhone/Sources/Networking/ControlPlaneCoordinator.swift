import Combine
import Foundation
import Network

@MainActor
public final class ControlPlaneCoordinator: ObservableObject {
    @Published public private(set) var serviceSummary: String
    @Published public private(set) var lastStatusJSON: String

    public var mediaCaptureMirror: ((URL, String) -> Void)?

    private let listenerPort: UInt16 = 48920
    private let previewListenerPort: UInt16 = 48921
    private let deviceID: String
    private let networkQueue = DispatchQueue(label: "vino.control.listener", qos: .userInitiated)
    private let modelStore = ModelFileStore()

    private weak var appState: VinoAppState?
    private weak var cameraController: CameraSessionController?
    private weak var inferenceRuntime: InferenceRuntime?
    private var listener: NWListener?
    private var previewListener: NWListener?
    private var peers: [UUID: ControlPeer] = [:]
    private var previewPeers: [UUID: PreviewPeer] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var lastStatusData: Data?
    private var latestIPAddresses: [IPAddressDescriptor] = []
    private var controlStateText = "待机"
    private var previewStateText = "待机"

    public init() {
        self.deviceID = UUID().uuidString.lowercased()
        self.serviceSummary = "控制 TCP 48920 · 待机 ｜ 预览 TCP 48921 · 待机"
        self.lastStatusJSON = ""
    }

    public func start(
        appState: VinoAppState,
        cameraController: CameraSessionController,
        inferenceRuntime: InferenceRuntime
    ) {
        self.appState = appState
        self.cameraController = cameraController
        self.inferenceRuntime = inferenceRuntime

        cameraController.onMediaCaptured = { [weak self] url, category in
            Task { @MainActor [weak self] in
                await self?.pushMedia(url: url, category: category)
                self?.mediaCaptureMirror?(url, category)
            }
        }
        cameraController.onPhotoDataCaptured = { [weak inferenceRuntime] data in
            inferenceRuntime?.submit(photoData: data)
        }

        Task {
            do {
                var catalog = try await modelStore.importBundledModelsIfNeeded()
                if catalog.activeModels.count > 1, let primaryModelID = catalog.activeModels.first?.id {
                    try? await modelStore.activateExclusively(modelID: primaryModelID)
                    if let normalizedCatalog = try? await modelStore.loadCatalog() {
                        catalog = normalizedCatalog
                    }
                }
                appState.modelCatalog = catalog
                appState.selectedModelID = catalog.activeModels.first?.id ?? catalog.models.first?.id
                if let activeModel = catalog.activeModels.first {
                    appState.lastStatusMessage = "模型已就绪 · \(activeModel.name)"
                } else if !catalog.models.isEmpty {
                    appState.lastStatusMessage = "发现本地模型，但没有激活项"
                } else {
                    appState.lastStatusMessage = "未发现本地模型"
                }
                inferenceRuntime.refreshModels(from: catalog)
            } catch {
                appState.modelCatalog = CoreMLCatalog(models: [])
                appState.selectedModelID = nil
                appState.lastStatusMessage = "模型加载失败 · \(error.localizedDescription)"
                inferenceRuntime.refreshModels(from: appState.modelCatalog)
            }
            inferenceRuntime.setEnabled(appState.inferenceEnabled)
        }

        startListenerIfNeeded(serviceName: appState.deviceName)
        startHeartbeatLoop()
        startStatusLoop()
    }

    public func stop() {
        heartbeatTask?.cancel()
        statusTask?.cancel()
        heartbeatTask = nil
        statusTask = nil

        peers.values.forEach { $0.connection.cancel() }
        peers.removeAll()
        previewPeers.values.forEach { $0.connection.cancel() }
        previewPeers.removeAll()
        appState?.isConnectedToDesktop = false
        appState?.remotePostURL = ""

        listener?.cancel()
        listener = nil
        previewListener?.cancel()
        previewListener = nil
        controlStateText = "已停止"
        previewStateText = "已停止"
        refreshServiceSummary()
    }

    public func publishStatus(
        appState: VinoAppState,
        settings: CameraSettings,
        ipAddresses: [IPAddressDescriptor]
    ) {
        latestIPAddresses = ipAddresses

        let payload = DeviceStatusPayload(
            deviceName: appState.deviceName,
            captureMode: appState.captureMode,
            selectedLens: appState.selectedLens,
            recordingProfile: appState.recordingProfile,
            focusMode: appState.focusMode,
            smoothAutoFocusEnabled: appState.smoothAutoFocusEnabled,
            flashEnabled: appState.flashEnabled,
            settings: settings,
            ipAddresses: ipAddresses.map(\.displayValue),
            inferenceEnabled: appState.inferenceEnabled,
            persistMediaEnabled: appState.persistMediaEnabled,
            remotePostURL: appState.remotePostURL,
            selectedModelID: appState.selectedModelID,
            activeModelIDs: appState.activeModelIDs,
            isRecording: appState.isRecording,
            message: appState.lastStatusMessage
        )

        let envelope = VinoEnvelope(
            kind: .status,
            action: "device.status.push",
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            context: VinoContext(
                productUUID: appState.activeContext.productUUID.isEmpty ? nil : appState.activeContext.productUUID,
                pointIndex: appState.activeContext.pointIndex,
                jobID: appState.activeContext.jobID.isEmpty ? nil : appState.activeContext.jobID
            ),
            payload: payload
        )

        let displayEncoder = JSONEncoder()
        displayEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let displayData = try? displayEncoder.encode(envelope),
           let json = String(data: displayData, encoding: .utf8) {
            lastStatusJSON = json
        }

        let wireEncoder = JSONEncoder()
        if let wireData = try? wireEncoder.encode(envelope) {
            lastStatusData = wireData + Data([0x0A])
            broadcast(rawData: lastStatusData)
        }
    }

    public func broadcastCapabilities() {
        sendCapabilities(to: nil)
    }

    private func startListenerIfNeeded(serviceName: String) {
        if listener == nil {
            do {
                let parameters = NWParameters.tcp
                let port = NWEndpoint.Port(rawValue: listenerPort) ?? .init(integerLiteral: 48920)
                let listener = try NWListener(using: parameters, on: port)

                listener.service = NWListener.Service(name: serviceName, type: "_vino-control._tcp")
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            self.controlStateText = "已就绪"
                        case .failed(let error):
                            self.controlStateText = "启动失败 · \(error.localizedDescription)"
                        case .cancelled:
                            self.controlStateText = "已停止"
                        default:
                            break
                        }
                        self.refreshServiceSummary()
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor [weak self] in
                        self?.accept(connection)
                    }
                }

                listener.start(queue: networkQueue)
                self.listener = listener
            } catch {
                controlStateText = "启动失败"
                refreshServiceSummary()
            }
        }

        if previewListener == nil {
            do {
                let parameters = NWParameters.tcp
                let port = NWEndpoint.Port(rawValue: previewListenerPort) ?? .init(integerLiteral: 48921)
                let previewListener = try NWListener(using: parameters, on: port)

                previewListener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            self.previewStateText = "已就绪"
                        case .failed(let error):
                            self.previewStateText = "启动失败 · \(error.localizedDescription)"
                        case .cancelled:
                            self.previewStateText = "已停止"
                        default:
                            break
                        }
                        self.refreshServiceSummary()
                    }
                }

                previewListener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor [weak self] in
                        self?.acceptPreview(connection)
                    }
                }

                previewListener.start(queue: networkQueue)
                self.previewListener = previewListener
            } catch {
                previewStateText = "启动失败"
                refreshServiceSummary()
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let peerID = UUID()
        let peer = ControlPeer(id: peerID, connection: connection)
        peers[peerID] = peer

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.appState?.isConnectedToDesktop = true
                    if let desktopURL = self.inferredDesktopPostURL(from: connection) {
                        self.appState?.remotePostURL = desktopURL
                    }
                    self.controlStateText = "已连接 \(self.peers.count) 台上位机"
                    self.refreshServiceSummary()
                    self.sendHello(to: peerID)
                    self.sendCapabilities(to: peerID)
                    if let data = self.lastStatusData {
                        self.send(rawData: data, to: peerID)
                    }
                case .failed, .cancelled:
                    self.peers.removeValue(forKey: peerID)
                    self.appState?.isConnectedToDesktop = !self.peers.isEmpty
                    if self.peers.isEmpty {
                        self.appState?.remotePostURL = ""
                    }
                    self.controlStateText = self.peers.isEmpty ? "已就绪" : "已连接 \(self.peers.count) 台上位机"
                    self.refreshServiceSummary()
                default:
                    break
                }
            }
        }

        connection.start(queue: networkQueue)
        receiveNext(from: peerID)
    }

    private func receiveNext(from peerID: UUID) {
        guard let peer = peers[peerID] else { return }

        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self, let peer = self.peers[peerID] else { return }

                if let data, !data.isEmpty {
                    peer.buffer.append(data)
                    self.drainBuffer(for: peerID)
                }

                if isComplete || error != nil {
                    peer.connection.cancel()
                    self.peers.removeValue(forKey: peerID)
                    self.appState?.isConnectedToDesktop = !self.peers.isEmpty
                    if self.peers.isEmpty {
                        self.appState?.remotePostURL = ""
                    }
                    self.controlStateText = self.peers.isEmpty ? "已就绪" : "已连接 \(self.peers.count) 台上位机"
                    self.refreshServiceSummary()
                    return
                }

                self.receiveNext(from: peerID)
            }
        }
    }

    private func acceptPreview(_ connection: NWConnection) {
        let peerID = UUID()
        let peer = PreviewPeer(id: peerID, connection: connection)
        previewPeers[peerID] = peer

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.previewStateText = "已连接 \(self.previewPeers.count) 路预览"
                    self.refreshServiceSummary()
                case .failed, .cancelled:
                    self.previewPeers.removeValue(forKey: peerID)
                    self.previewStateText = self.previewPeers.isEmpty ? "已就绪" : "已连接 \(self.previewPeers.count) 路预览"
                    self.refreshServiceSummary()
                default:
                    break
                }
            }
        }

        connection.start(queue: networkQueue)
    }

    private func drainBuffer(for peerID: UUID) {
        guard let peer = peers[peerID] else { return }

        while let newlineRange = peer.buffer.range(of: Data([0x0A])) {
            let lineData = peer.buffer.subdata(in: 0..<newlineRange.lowerBound)
            peer.buffer.removeSubrange(0..<newlineRange.upperBound)

            guard
                !lineData.isEmpty,
                let line = String(data: lineData, encoding: .utf8)
            else {
                continue
            }

            handleIncomingLine(line, from: peerID)
        }
    }

    private func handleIncomingLine(_ line: String, from peerID: UUID) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            sendReply(to: peerID, correlationID: nil, action: "unknown", status: "invalid", message: "invalid json")
            return
        }

        let action = object["action"] as? String ?? ""
        let correlationID = object["messageId"] as? String
        let context = object["context"] as? [String: Any]
        applyContext(context)

        switch action {
        case "camera.capabilities.get":
            sendCapabilities(to: peerID)
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "capabilities reported")

        case "camera.config.patch":
            guard
                let payload = object["payload"],
                let patch = decodePayload(CameraConfigPatch.self, from: payload),
                let appState,
                let cameraController
            else {
                sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "invalid payload")
                return
            }

            if let settings = patch.settings {
                cameraController.settings = settings.clamped(to: cameraController.capabilities)
            }
            appState.apply(patch: patch, capabilities: cameraController.capabilities)

            if let selectedLens = patch.selectedLens {
                cameraController.switchLens(to: selectedLens, appState: appState)
            } else {
                cameraController.apply(appState: appState)
            }

            sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "camera patch applied")

        case "camera.mode.set":
            guard let appState, let cameraController else { return }
            let payload = object["payload"] as? [String: Any]
            if let modeValue = payload?["captureMode"] as? String, let mode = CaptureMode(rawValue: modeValue) {
                appState.captureMode = mode
                cameraController.apply(appState: appState)
                sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "mode updated")
            } else {
                sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "missing captureMode")
            }

        case "camera.focus.mode.set":
            guard let appState, let cameraController else { return }
            let payload = object["payload"] as? [String: Any]
            if let focusValue = payload?["focusMode"] as? String, let mode = FocusControlMode(rawValue: focusValue) {
                appState.focusMode = mode
                cameraController.apply(appState: appState)
                sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "focus mode updated")
            } else {
                sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "missing focusMode")
            }

        case "camera.flash.set":
            guard let appState, let cameraController else { return }
            let payload = object["payload"] as? [String: Any]
            appState.flashEnabled = payload?["enabled"] as? Bool ?? false
            cameraController.apply(appState: appState)
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "flash updated")

        case "capture.photo.trigger":
            guard let appState, let cameraController else { return }
            appState.captureMode = .photo
            cameraController.triggerPrimaryAction(appState: appState)
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "photo trigger queued")

        case "capture.recording.set":
            guard let appState, let cameraController else { return }
            let payload = object["payload"] as? [String: Any]
            let enabled = (payload?["enabled"] as? Bool) ?? (payload?["isRecording"] as? Bool) ?? false
            appState.captureMode = .stream
            cameraController.setRecording(enabled, appState: appState)
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: enabled ? "recording started" : "recording stopped")

        case "capture.storage.set":
            guard let appState else { return }
            let payload = object["payload"] as? [String: Any]
            appState.persistMediaEnabled = payload?["persistMediaEnabled"] as? Bool ?? appState.persistMediaEnabled
            if let remotePostURL = payload?["remotePostURL"] as? String {
                appState.remotePostURL = remotePostURL
            }
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "storage updated")

        case "inference.runtime.set":
            guard let appState, let inferenceRuntime else { return }
            let payload = object["payload"] as? [String: Any]
            appState.inferenceEnabled = payload?["enabled"] as? Bool ?? appState.inferenceEnabled
            inferenceRuntime.setEnabled(appState.inferenceEnabled)
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "inference updated")

        case "device.alias.set":
            guard let appState else { return }
            let payload = object["payload"] as? [String: Any]
            if let alias = payload?["name"] as? String {
                appState.updateAlias(alias)
                sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "alias updated")
            } else {
                sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "missing name")
            }

        case "inference.model.remove":
            handleModelRemove(object: object, peerID: peerID, correlationID: correlationID, action: action)

        case "inference.model.activate":
            handleModelActivation(object: object, peerID: peerID, correlationID: correlationID, action: action, isActive: true)

        case "inference.model.deactivate":
            handleModelActivation(object: object, peerID: peerID, correlationID: correlationID, action: action, isActive: false)

        case "inference.model.install.begin":
            handleModelInstallBegin(object: object, peerID: peerID, correlationID: correlationID, action: action)

        case "inference.model.install.chunk":
            handleModelInstallChunk(object: object, peerID: peerID, correlationID: correlationID, action: action)

        case "inference.model.install.commit":
            handleModelInstallCommit(object: object, peerID: peerID, correlationID: correlationID, action: action)

        default:
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "unsupported", message: "action not supported")
        }

        if shouldPublishStatusAfterHandlingAction(action),
           let appState,
           let cameraController {
            publishStatus(appState: appState, settings: cameraController.settings, ipAddresses: latestIPAddresses)
        }
    }

    private func shouldPublishStatusAfterHandlingAction(_ action: String) -> Bool {
        switch action {
        case "camera.capabilities.get",
             "inference.model.install.begin",
             "inference.model.install.chunk":
            return false
        default:
            return true
        }
    }

    private func handleModelRemove(object: [String: Any], peerID: UUID, correlationID: String?, action: String) {
        guard let appState else { return }
        let payload = object["payload"] as? [String: Any]
        guard let modelID = payload?["modelId"] as? String else {
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "missing modelId")
            return
        }

        Task {
            let didRemove = (try? await modelStore.remove(modelID: modelID)) ?? false
            await MainActor.run {
                if didRemove {
                    appState.removeModel(modelID: modelID)
                    self.inferenceRuntime?.refreshModels(from: appState.modelCatalog)
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "model removed")
                    self.sendCapabilities(to: nil)
                } else {
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "model not found")
                }
            }
        }
    }

    private func handleModelActivation(
        object: [String: Any],
        peerID: UUID,
        correlationID: String?,
        action: String,
        isActive: Bool
    ) {
        guard let appState else { return }
        let payload = object["payload"] as? [String: Any]
        guard let modelID = payload?["modelId"] as? String else {
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "missing modelId")
            return
        }

        Task {
            if isActive {
                try? await self.modelStore.activateExclusively(modelID: modelID)
            } else {
                try? await self.modelStore.updateFlags(modelID: modelID, isActive: false)
            }
            await MainActor.run {
                if isActive {
                    appState.activateModel(modelID: modelID)
                } else {
                    appState.deactivateModel(modelID: modelID)
                }
                self.inferenceRuntime?.refreshModels(from: appState.modelCatalog)
                self.sendCapabilities(to: nil)
                self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: isActive ? "model activated" : "model deactivated")
            }
        }
    }

    private func handleModelInstallBegin(object: [String: Any], peerID: UUID, correlationID: String?, action: String) {
        let payload = object["payload"] as? [String: Any]
        guard
            let transferID = payload?["transferId"] as? String,
            let modelID = payload?["modelId"] as? String,
            let modelName = payload?["modelName"] as? String,
            let version = payload?["version"] as? String,
            let fileName = payload?["fileName"] as? String
        else {
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "invalid install begin payload")
            return
        }

        let sourceFormat = (payload?["sourceFormat"] as? String) ?? URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let transportFormat = (payload?["transportFormat"] as? String) ?? "raw-file"

        Task {
            do {
                try await modelStore.beginInstall(
                    transferID: transferID,
                    modelID: modelID,
                    modelName: modelName,
                    version: version,
                    fileName: fileName,
                    sourceFormat: sourceFormat,
                    transportFormat: transportFormat
                )

                await MainActor.run {
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "model transfer opened")
                }
            } catch {
                await MainActor.run {
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "model transfer open failed")
                }
            }
        }
    }

    private func handleModelInstallChunk(object: [String: Any], peerID: UUID, correlationID: String?, action: String) {
        let payload = object["payload"] as? [String: Any]
        guard
            let transferID = payload?["transferId"] as? String,
            let chunkBase64 = payload?["chunkBase64"] as? String
        else {
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "invalid install chunk payload")
            return
        }

        Task {
            do {
                try await modelStore.appendChunk(transferID: transferID, chunkBase64: chunkBase64)
                await MainActor.run {
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "chunk appended")
                }
            } catch {
                await MainActor.run {
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "chunk append failed")
                }
            }
        }
    }

    private func handleModelInstallCommit(object: [String: Any], peerID: UUID, correlationID: String?, action: String) {
        guard let appState else { return }
        let payload = object["payload"] as? [String: Any]
        guard let transferID = payload?["transferId"] as? String else {
            sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "missing transferId")
            return
        }

        let activateAfterInstall = payload?["activateAfterInstall"] as? Bool ?? false

        Task {
            do {
                let record = try await modelStore.commitInstall(transferID: transferID)
                if activateAfterInstall {
                    try? await self.modelStore.activateExclusively(modelID: record.id)
                }
                await MainActor.run {
                    appState.installModel(record)
                    if activateAfterInstall {
                        appState.activateModel(modelID: record.id)
                    }
                    self.inferenceRuntime?.refreshModels(from: appState.modelCatalog)
                    self.sendCapabilities(to: peerID)
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "accepted", message: "model installed")
                }
            } catch {
                await MainActor.run {
                    self.sendReply(to: peerID, correlationID: correlationID, action: action, status: "rejected", message: "model install failed")
                }
            }
        }
    }

    private func decodePayload<T: Decodable>(_ type: T.Type, from value: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(value) else {
            return nil
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: value),
            let decoded = try? JSONDecoder().decode(type, from: data)
        else {
            return nil
        }

        return decoded
    }

    private func applyContext(_ context: [String: Any]?) {
        guard let appState, let context else { return }
        let productUUID = context["productUUID"] as? String
        let pointIndex = context["pointIndex"] as? Int
        let jobID = context["jobId"] as? String
        appState.applyRemoteContext(productUUID: productUUID, pointIndex: pointIndex, jobID: jobID)
    }

    private func sendHello(to peerID: UUID?) {
        guard appState != nil else { return }

        let payload: [String: Any] = [
            "platform": "iOS",
            "version": "0.1.0",
            "capabilities": [
                "supportsProRes": cameraController?.capabilities.supportsProRes ?? false,
                "supportsSmoothAutoFocus": cameraController?.capabilities.supportsSmoothAutoFocus ?? false,
                "supportedLenses": (cameraController?.capabilities.supportedLenses ?? []).map(\.rawValue)
            ]
        ]

        sendDynamicEnvelope(
            kind: "hello",
            action: "device.hello",
            payload: payload,
            correlationID: nil,
            to: peerID
        )
    }

    private func sendCapabilities(to peerID: UUID?) {
        guard let appState, let cameraController else { return }

        let envelope = VinoEnvelope(
            kind: .status,
            action: "camera.capabilities.report",
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            payload: CapabilitiesReportPayload(
                capabilities: cameraController.capabilities,
                models: appState.modelCatalog.models
            )
        )

        sendEnvelope(envelope, to: peerID)
    }

    private func sendReply(
        to peerID: UUID?,
        correlationID: String?,
        action: String,
        status: String,
        message: String
    ) {
        guard let appState else { return }

        let envelope = VinoEnvelope(
            correlationID: correlationID,
            kind: .reply,
            action: action,
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            payload: ReplyPayload(status: status, message: message)
        )

        sendEnvelope(envelope, to: peerID)
    }

    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.sendHeartbeat()
            }
        }
    }

    private func startStatusLoop() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if let data = self.lastStatusData {
                    self.broadcast(rawData: data)
                }
            }
        }
    }

    private func sendHeartbeat() {
        guard let appState else { return }

        let envelope = VinoEnvelope(
            kind: .heartbeat,
            action: "device.heartbeat",
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            payload: HeartbeatPayload(
                service: serviceSummary,
                connectedPeers: peers.count,
                message: appState.lastStatusMessage
            )
        )

        sendEnvelope(envelope, to: nil)
    }

    public func publishInferenceReport(_ report: InferenceFrameReport) {
        guard let appState else { return }

        let envelope = VinoEnvelope(
            kind: .status,
            action: "inference.result.push",
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            context: VinoContext(
                productUUID: appState.activeContext.productUUID.isEmpty ? nil : appState.activeContext.productUUID,
                pointIndex: appState.activeContext.pointIndex,
                jobID: appState.activeContext.jobID.isEmpty ? nil : appState.activeContext.jobID
            ),
            payload: InferenceFramePayload(report: report)
        )

        sendEnvelope(envelope, to: nil)
    }

    public func publishPreviewFrameJPEG(_ data: Data, imageWidth: Int, imageHeight: Int, frameIndex: Int) {
        guard let appState, !previewPeers.isEmpty, appState.captureMode == .stream else { return }

        let envelope = VinoEnvelope(
            kind: .status,
            action: "preview.frame.push",
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            context: VinoContext(
                productUUID: appState.activeContext.productUUID.isEmpty ? nil : appState.activeContext.productUUID,
                pointIndex: appState.activeContext.pointIndex,
                jobID: appState.activeContext.jobID.isEmpty ? nil : appState.activeContext.jobID
            ),
            payload: PreviewFramePayload(
                frameIndex: frameIndex,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                jpegBase64: data.base64EncodedString(),
                byteCount: data.count
            )
        )

        let encoder = JSONEncoder()
        guard let wireData = try? encoder.encode(envelope) else { return }
        broadcastPreview(rawData: wireData + Data([0x0A]))
    }

    private func pushMedia(url: URL, category: String) async {
        guard let appState, appState.persistMediaEnabled, !peers.isEmpty else { return }
        guard let data = try? Data(contentsOf: url) else { return }

        let transferID = UUID().uuidString.uppercased()
        let context = VinoContext(
            productUUID: appState.activeContext.productUUID.isEmpty ? nil : appState.activeContext.productUUID,
            pointIndex: appState.activeContext.pointIndex,
            jobID: appState.activeContext.jobID.isEmpty ? nil : appState.activeContext.jobID
        )

        let beginEnvelope = VinoEnvelope(
            kind: .command,
            action: "media.push.begin",
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            context: context,
            payload: MediaPushBeginPayload(
                transferID: transferID,
                category: category,
                fileName: url.lastPathComponent,
                byteCount: data.count
            )
        )
        sendEnvelope(beginEnvelope, to: nil)

        let chunkSize = 256 * 1024
        var chunkIndex = 0
        var offset = 0

        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            let chunkEnvelope = VinoEnvelope(
                kind: .command,
                action: "media.push.chunk",
                source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
                context: context,
                payload: MediaPushChunkPayload(
                    transferID: transferID,
                    chunkIndex: chunkIndex,
                    chunkBase64: Data(chunk).base64EncodedString()
                )
            )
            sendEnvelope(chunkEnvelope, to: nil)
            offset = end
            chunkIndex += 1
        }

        let commitEnvelope = VinoEnvelope(
            kind: .command,
            action: "media.push.commit",
            source: VinoSource(role: "iphone", deviceID: deviceID, name: appState.deviceName),
            context: context,
            payload: MediaPushCommitPayload(transferID: transferID)
        )
        sendEnvelope(commitEnvelope, to: nil)
    }

    private func sendEnvelope<Payload: Codable>(_ envelope: VinoEnvelope<Payload>, to peerID: UUID?) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(envelope) else { return }
        let lineData = data + Data([0x0A])
        if let peerID {
            send(rawData: lineData, to: peerID)
        } else {
            broadcast(rawData: lineData)
        }
    }

    private func sendDynamicEnvelope(
        kind: String,
        action: String,
        payload: [String: Any],
        correlationID: String?,
        to peerID: UUID?
    ) {
        guard let appState else { return }

        let object: [String: Any] = [
            "protocol": "vino.control/1",
            "messageId": UUID().uuidString.uppercased(),
            "correlationId": correlationID as Any,
            "kind": kind,
            "action": action,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": [
                "role": "iphone",
                "deviceId": deviceID,
                "name": appState.deviceName
            ],
            "payload": payload
        ]

        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object),
            let lineData = String(data: data, encoding: .utf8).map({ Data(($0 + "\n").utf8) })
        else {
            return
        }

        if let peerID {
            send(rawData: lineData, to: peerID)
        } else {
            broadcast(rawData: lineData)
        }
    }

    private func broadcast(rawData: Data?) {
        guard let rawData else { return }
        for peerID in peers.keys {
            send(rawData: rawData, to: peerID)
        }
    }

    private func broadcastPreview(rawData: Data) {
        for peerID in previewPeers.keys {
            sendPreview(rawData: rawData, to: peerID)
        }
    }

    private func send(rawData: Data, to peerID: UUID) {
        guard let peer = peers[peerID] else { return }
        peer.connection.send(content: rawData, completion: .contentProcessed { _ in })
    }

    private func sendPreview(rawData: Data, to peerID: UUID) {
        guard let peer = previewPeers[peerID] else { return }
        peer.connection.send(content: rawData, completion: .contentProcessed { _ in })
    }

    private func refreshServiceSummary() {
        serviceSummary = "控制 TCP \(listenerPort) · \(controlStateText) ｜ 预览 TCP \(previewListenerPort) · \(previewStateText)"
    }

    private func inferredDesktopPostURL(from connection: NWConnection) -> String? {
        guard case let .hostPort(host, _) = connection.endpoint else {
            return nil
        }

        let hostText = host.debugDescription
        let formattedHost = hostText.contains(":") && !hostText.hasPrefix("[")
            ? "[\(hostText)]"
            : hostText
        return "http://\(formattedHost):49020/api/v1/ingest"
    }
}

private final class ControlPeer {
    let id: UUID
    let connection: NWConnection
    var buffer = Data()

    init(id: UUID, connection: NWConnection) {
        self.id = id
        self.connection = connection
    }
}

private final class PreviewPeer {
    let id: UUID
    let connection: NWConnection

    init(id: UUID, connection: NWConnection) {
        self.id = id
        self.connection = connection
    }
}
