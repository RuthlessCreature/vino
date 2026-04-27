import Foundation
import SwiftUI
import UIKit

public enum CaptureMode: String, CaseIterable, Codable, Identifiable {
    case stream
    case photo

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .stream: "视频流"
        case .photo: "拍照"
        }
    }
}

public enum LensChoice: String, CaseIterable, Codable, Identifiable {
    case wide
    case ultraWide
    case telephoto

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wide: "主摄"
        case .ultraWide: "超广角"
        case .telephoto: "长焦"
        }
    }
}

public enum RecordingProfile: String, CaseIterable, Codable, Identifiable {
    case h264
    case hevc
    case proRes

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .proRes: "ProRes"
        }
    }
}

public enum FocusControlMode: String, CaseIterable, Codable, Identifiable {
    case continuousAuto
    case locked

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .continuousAuto: "自动对焦"
        case .locked: "锁定对焦"
        }
    }
}

public struct ControlRange: Codable, Hashable {
    public var min: Double
    public var max: Double
    public var step: Double

    public init(min: Double, max: Double, step: Double) {
        self.min = min
        self.max = max
        self.step = step
    }

    public func clamped(_ value: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}

public struct CameraCapabilities: Codable, Hashable {
    public var frameRate: ControlRange
    public var whiteBalanceTemperature: ControlRange
    public var whiteBalanceTint: ControlRange
    public var exposureSeconds: ControlRange
    public var iso: ControlRange
    public var exposureBias: ControlRange
    public var zoomFactor: ControlRange
    public var lensPosition: ControlRange
    public var supportsSmoothAutoFocus: Bool
    public var supportsFlash: Bool
    public var supportedLenses: [LensChoice]
    public var supportsProRes: Bool

    public init(
        frameRate: ControlRange,
        whiteBalanceTemperature: ControlRange,
        whiteBalanceTint: ControlRange,
        exposureSeconds: ControlRange,
        iso: ControlRange,
        exposureBias: ControlRange,
        zoomFactor: ControlRange,
        lensPosition: ControlRange,
        supportsSmoothAutoFocus: Bool,
        supportsFlash: Bool,
        supportedLenses: [LensChoice],
        supportsProRes: Bool
    ) {
        self.frameRate = frameRate
        self.whiteBalanceTemperature = whiteBalanceTemperature
        self.whiteBalanceTint = whiteBalanceTint
        self.exposureSeconds = exposureSeconds
        self.iso = iso
        self.exposureBias = exposureBias
        self.zoomFactor = zoomFactor
        self.lensPosition = lensPosition
        self.supportsSmoothAutoFocus = supportsSmoothAutoFocus
        self.supportsFlash = supportsFlash
        self.supportedLenses = supportedLenses
        self.supportsProRes = supportsProRes
    }

    public static let fallback = CameraCapabilities(
        frameRate: ControlRange(min: 1, max: 60, step: 1),
        whiteBalanceTemperature: ControlRange(min: 2800, max: 8000, step: 50),
        whiteBalanceTint: ControlRange(min: -150, max: 150, step: 1),
        exposureSeconds: ControlRange(min: 1.0 / 8000.0, max: 1.0 / 2.0, step: 0.0005),
        iso: ControlRange(min: 20, max: 1600, step: 1),
        exposureBias: ControlRange(min: -8, max: 8, step: 0.1),
        zoomFactor: ControlRange(min: 1, max: 15, step: 0.1),
        lensPosition: ControlRange(min: 0, max: 1, step: 0.01),
        supportsSmoothAutoFocus: true,
        supportsFlash: true,
        supportedLenses: [.wide],
        supportsProRes: false
    )
}

public struct CameraSettings: Codable, Hashable {
    public var frameRate: Double
    public var whiteBalanceTemperature: Double
    public var whiteBalanceTint: Double
    public var exposureSeconds: Double
    public var iso: Double
    public var exposureBias: Double
    public var zoomFactor: Double
    public var lensPosition: Double

    public init(
        frameRate: Double = 30,
        whiteBalanceTemperature: Double = 5000,
        whiteBalanceTint: Double = 0,
        exposureSeconds: Double = 1.0 / 100.0,
        iso: Double = 50,
        exposureBias: Double = 0,
        zoomFactor: Double = 1,
        lensPosition: Double = 0.5
    ) {
        self.frameRate = frameRate
        self.whiteBalanceTemperature = whiteBalanceTemperature
        self.whiteBalanceTint = whiteBalanceTint
        self.exposureSeconds = exposureSeconds
        self.iso = iso
        self.exposureBias = exposureBias
        self.zoomFactor = zoomFactor
        self.lensPosition = lensPosition
    }

    public func clamped(to capabilities: CameraCapabilities) -> CameraSettings {
        CameraSettings(
            frameRate: capabilities.frameRate.clamped(frameRate),
            whiteBalanceTemperature: capabilities.whiteBalanceTemperature.clamped(whiteBalanceTemperature),
            whiteBalanceTint: capabilities.whiteBalanceTint.clamped(whiteBalanceTint),
            exposureSeconds: capabilities.exposureSeconds.clamped(exposureSeconds),
            iso: capabilities.iso.clamped(iso),
            exposureBias: capabilities.exposureBias.clamped(exposureBias),
            zoomFactor: capabilities.zoomFactor.clamped(zoomFactor),
            lensPosition: capabilities.lensPosition.clamped(lensPosition)
        )
    }
}

public struct RemoteCaptureContext: Codable, Hashable {
    public var productUUID: String
    public var pointIndex: Int
    public var jobID: String

    public init(productUUID: String = "", pointIndex: Int = 0, jobID: String = "") {
        self.productUUID = productUUID
        self.pointIndex = pointIndex
        self.jobID = jobID
    }
}

public final class VinoAppState: ObservableObject {
    private enum PersistentKey {
        static let cloudBaseURL = "vino.cloud.baseURL"
        static let localNodeBaseURL = "vino.localNode.baseURL"
        static let cloudLoginEmail = "vino.cloud.loginEmail"
    }

    private static let defaultCloudBaseURL = "http://172.20.10.3:8787"
    private static let defaultLocalNodeBaseURL = "http://127.0.0.1:49030"
    private static let defaultCloudLoginEmail = "demo@vino.cc"
    private static let defaultCloudLoginPassword = "demo123"
    private static let cloudLoginPasswordAccount = "cloud-login-password"
    private static let cloudLoginPasswordKeychain = KeychainStore(service: "cc.vino.iphone.login")

    @Published public var deviceName: String
    @Published public var captureMode: CaptureMode
    @Published public var focusMode: FocusControlMode
    @Published public var smoothAutoFocusEnabled: Bool
    @Published public var flashEnabled: Bool
    @Published public var inferenceEnabled: Bool
    @Published public var persistMediaEnabled: Bool
    @Published public var remotePostURL: String
    @Published public var selectedLens: LensChoice
    @Published public var recordingProfile: RecordingProfile
    @Published public var selectedModelID: String?
    @Published public var activeContext: RemoteCaptureContext
    @Published public var lastStatusMessage: String
    @Published public var isRecording: Bool
    @Published public var isConnectedToDesktop: Bool
    @Published public var modelCatalog: CoreMLCatalog
    @Published public var cloudBaseURL: String {
        didSet { Self.savePersistentString(cloudBaseURL, forKey: PersistentKey.cloudBaseURL) }
    }
    @Published public var localNodeBaseURL: String {
        didSet { Self.savePersistentString(localNodeBaseURL, forKey: PersistentKey.localNodeBaseURL) }
    }
    @Published public var cloudLoginEmail: String {
        didSet { Self.savePersistentString(cloudLoginEmail, forKey: PersistentKey.cloudLoginEmail) }
    }
    @Published public var cloudLoginPassword: String {
        didSet { Self.saveCloudLoginPassword(cloudLoginPassword) }
    }
    @Published public var cloudSession: AuthSession?
    @Published public var cloudCatalog: CloudModelCatalog
    @Published public var lastCloudSyncAt: String
    @Published public var pendingUploadCount: Int
    @Published public var lastCloudMessage: String

    public init() {
        self.deviceName = UIDevice.current.name
        self.captureMode = .stream
        self.focusMode = .continuousAuto
        self.smoothAutoFocusEnabled = true
        self.flashEnabled = false
        self.inferenceEnabled = false
        self.persistMediaEnabled = false
        self.remotePostURL = ""
        self.selectedLens = .wide
        self.recordingProfile = .hevc
        self.selectedModelID = CoreMLCatalog.sample.models.first(where: \.isActive)?.id
        self.activeContext = RemoteCaptureContext()
        self.lastStatusMessage = "空闲"
        self.isRecording = false
        self.isConnectedToDesktop = false
        self.modelCatalog = .sample
        self.cloudBaseURL = Self.persistentString(forKey: PersistentKey.cloudBaseURL, defaultValue: Self.defaultCloudBaseURL)
        self.localNodeBaseURL = Self.persistentString(forKey: PersistentKey.localNodeBaseURL, defaultValue: Self.defaultLocalNodeBaseURL)
        self.cloudLoginEmail = Self.persistentString(forKey: PersistentKey.cloudLoginEmail, defaultValue: Self.defaultCloudLoginEmail)
        self.cloudLoginPassword = Self.defaultCloudLoginPassword
        self.cloudSession = nil
        self.cloudCatalog = CloudModelCatalog()
        self.lastCloudSyncAt = ""
        self.pendingUploadCount = 0
        self.lastCloudMessage = "未登录"
        restoreCloudLoginPassword()
    }

    private static func persistentString(forKey key: String, defaultValue: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? defaultValue
    }

    private static func savePersistentString(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func saveCloudLoginPassword(_ password: String) {
        Task {
            try? await cloudLoginPasswordKeychain.save(Data(password.utf8), account: cloudLoginPasswordAccount)
        }
    }

    private func restoreCloudLoginPassword() {
        Task { [weak self] in
            let data: Data?
            do {
                data = try await Self.cloudLoginPasswordKeychain.load(account: Self.cloudLoginPasswordAccount)
            } catch {
                data = nil
            }

            guard let data, let password = String(data: data, encoding: .utf8) else {
                return
            }

            await MainActor.run {
                self?.cloudLoginPassword = password
            }
        }
    }

    public var activeModelIDs: [String] {
        modelCatalog.activeModels.map(\.id)
    }

    public func apply(patch: CameraConfigPatch, capabilities: CameraCapabilities) {
        if let captureMode = patch.captureMode {
            self.captureMode = captureMode
        }
        if let focusMode = patch.focusMode {
            self.focusMode = focusMode
        }
        if let selectedLens = patch.selectedLens {
            self.selectedLens = selectedLens
        }
        if let recordingProfile = patch.recordingProfile {
            self.recordingProfile = recordingProfile
        }
        if let smoothAutoFocusEnabled = patch.smoothAutoFocusEnabled {
            self.smoothAutoFocusEnabled = smoothAutoFocusEnabled
        }
        if let flashEnabled = patch.flashEnabled {
            self.flashEnabled = flashEnabled
        }
        if let inferenceEnabled = patch.inferenceEnabled {
            self.inferenceEnabled = inferenceEnabled
        }
        if let persistMediaEnabled = patch.persistMediaEnabled {
            self.persistMediaEnabled = persistMediaEnabled
        }
        if let remotePostURL = patch.remotePostURL {
            self.remotePostURL = remotePostURL
        }
        if let settings = patch.settings {
            let clamped = settings.clamped(to: capabilities)
            lastStatusMessage = "已应用远程参数"
            if focusMode == .continuousAuto {
                self.smoothAutoFocusEnabled = patch.smoothAutoFocusEnabled ?? self.smoothAutoFocusEnabled
            }
            NotificationCenter.default.post(
                name: .vinoCameraSettingsPatched,
                object: clamped
            )
        }
    }

    public func updateAlias(_ alias: String) {
        guard !alias.isEmpty else { return }
        deviceName = alias
        lastStatusMessage = "设备名称已更新"
    }

    public func applyRemoteContext(productUUID: String?, pointIndex: Int?, jobID: String?) {
        if let productUUID {
            activeContext.productUUID = productUUID
        }
        if let pointIndex {
            activeContext.pointIndex = pointIndex
        }
        if let jobID {
            activeContext.jobID = jobID
        }
    }

    public func installModel(_ record: CoreMLModelRecord) {
        modelCatalog.upsert(record)
        lastStatusMessage = "模型已安装 · \(record.name)"
    }

    public func removeModel(modelID: String) {
        _ = modelCatalog.remove(modelID: modelID)
        if selectedModelID == modelID {
            selectedModelID = nil
        }
        lastStatusMessage = "模型已删除 · \(modelID)"
    }

    public func activateModel(modelID: String) {
        modelCatalog.activate(modelID: modelID)
        selectedModelID = modelID
        lastStatusMessage = "模型已激活 · \(modelID)"
    }

    public func deactivateModel(modelID: String) {
        modelCatalog.deactivate(modelID: modelID)
        if selectedModelID == modelID {
            selectedModelID = nil
        }
        lastStatusMessage = "模型已停用 · \(modelID)"
    }

    public func setModelEnabled(_ isEnabled: Bool, modelID: String) {
        modelCatalog.setEnabled(isEnabled, for: modelID)
        if !isEnabled, selectedModelID == modelID {
            selectedModelID = nil
        }
        lastStatusMessage = isEnabled ? "模型已启用 · \(modelID)" : "模型已禁用 · \(modelID)"
    }

    public func updateCloudSession(_ session: AuthSession?) {
        cloudSession = session
        if let session {
            cloudBaseURL = session.cloudBaseURL
            cloudLoginEmail = session.user.email
            lastCloudMessage = "已登录 · \(session.user.organizationName)"
        } else {
            lastCloudMessage = "未登录"
        }
    }

    public func applyCloudCatalog(_ catalog: CloudModelCatalog) {
        cloudCatalog = catalog
        lastCloudSyncAt = catalog.syncedAt ?? ISO8601DateFormatter().string(from: Date())
        lastCloudMessage = catalog.models.isEmpty ? "当前账号暂无可下载模型" : "模型清单已同步"
    }

    public func updateModelLease(
        modelID: String,
        leaseExpiresAt: String?,
        policyFlags: [String],
        licenseID: String? = nil,
        deviceBindingID: String? = nil
    ) {
        guard let index = modelCatalog.models.firstIndex(where: { $0.id == modelID }) else {
            return
        }

        modelCatalog.models[index].leaseExpiresAt = leaseExpiresAt
        modelCatalog.models[index].policyFlags = policyFlags
        if let licenseID {
            modelCatalog.models[index].licenseID = licenseID
        }
        if let deviceBindingID {
            modelCatalog.models[index].deviceBindingID = deviceBindingID
        }
    }

    public var cloudSessionSummary: String {
        guard let cloudSession else {
            return "未登录"
        }
        return "\(cloudSession.user.organizationName) · \(cloudSession.user.displayName)"
    }

    public var uploadBufferSummary: String {
        pendingUploadCount == 0 ? "缓冲为空" : "待补传 \(pendingUploadCount) 条"
    }
}

public extension Notification.Name {
    static let vinoCameraSettingsPatched = Notification.Name("vino.camera.settings.patched")
}
