import Foundation

@MainActor
public final class CloudControlCoordinator: ObservableObject {
    @Published public private(set) var statusSummary: String = "未登录"
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastErrorMessage: String?

    private let authService: AuthService
    private let sessionStore: AuthSessionStore
    private let modelStore: ModelFileStore
    private let uploadService: AssetUploadService

    private weak var appState: VinoAppState?
    private weak var inferenceRuntime: InferenceRuntime?
    private var lastInferenceUploadAt: Date = .distantPast

    public init(
        authService: AuthService = AuthService(),
        sessionStore: AuthSessionStore = AuthSessionStore(),
        modelStore: ModelFileStore = ModelFileStore(),
        uploadService: AssetUploadService = AssetUploadService()
    ) {
        self.authService = authService
        self.sessionStore = sessionStore
        self.modelStore = modelStore
        self.uploadService = uploadService
    }

    public func start(appState: VinoAppState, inferenceRuntime: InferenceRuntime) {
        self.appState = appState
        self.inferenceRuntime = inferenceRuntime

        Task {
            await restoreSessionIfPossible()
            await refreshBufferedCount()
        }
    }

    public func signIn() {
        Task {
            guard let appState else { return }
            isBusy = true
            statusSummary = "登录中…"
            appState.lastCloudMessage = "正在登录云端…"
            lastErrorMessage = nil
            defer { isBusy = false }

            do {
                let session = try await authService.login(
                    baseURL: appState.cloudBaseURL,
                    email: appState.cloudLoginEmail,
                    password: appState.cloudLoginPassword
                )
                await sessionStore.saveSession(session)
                appState.updateCloudSession(session)
                statusSummary = "已登录 · \(session.user.organizationName)"
                lastErrorMessage = nil
                appState.lastCloudMessage = "登录成功"
                await syncCatalogInternal()
                await refreshBufferedCount()
            } catch {
                lastErrorMessage = error.localizedDescription
                appState.lastCloudMessage = error.localizedDescription
                statusSummary = "登录失败"
            }
        }
    }

    public func signOut() {
        Task {
            guard let appState else { return }
            await sessionStore.clearSession()
            appState.updateCloudSession(nil)
            appState.applyCloudCatalog(.init())
            statusSummary = "未登录"
            appState.lastCloudMessage = "已退出登录"
            await refreshBufferedCount()
        }
    }

    public func syncCatalog() {
        Task { await syncCatalogInternal() }
    }

    public func downloadFirstAvailableModel(activateAfterInstall: Bool = true) {
        guard let modelID = appState?.cloudCatalog.models.first?.id else {
            appState?.lastCloudMessage = "云端暂无可用模型"
            return
        }
        downloadModel(modelID: modelID, activateAfterInstall: activateAfterInstall)
    }

    public func downloadModel(modelID: String, activateAfterInstall: Bool = true) {
        guard !isBusy else {
            appState?.lastCloudMessage = "已有模型任务在执行"
            return
        }

        isBusy = true
        Task {
            guard let appState, let session = appState.cloudSession else {
                self.isBusy = false
                return
            }
            guard let descriptor = appState.cloudCatalog.models.first(where: { $0.id == modelID }) else {
                self.isBusy = false
                return
            }

            let shouldResumeInference = appState.inferenceEnabled
            if shouldResumeInference {
                inferenceRuntime?.setEnabled(false)
                appState.lastStatusMessage = "模型切换中，推理已暂时暂停"
            }
            defer { isBusy = false }
            defer {
                if shouldResumeInference {
                    inferenceRuntime?.setEnabled(true)
                }
            }

            do {
                appState.lastCloudMessage = "正在申请下载授权…"
                let ticket = try await authService.createDownloadTicket(
                    baseURL: appState.cloudBaseURL,
                    session: session,
                    modelID: modelID
                )
                appState.lastCloudMessage = "正在下载模型…"
                let downloadedURL = try await authService.downloadArtifact(ticket: ticket)
                defer { try? FileManager.default.removeItem(at: downloadedURL) }

                try await modelStore.beginInstall(
                    transferID: ticket.ticketID,
                    modelID: descriptor.id,
                    modelName: descriptor.name,
                    version: descriptor.version,
                    fileName: ticket.fileName,
                    sourceFormat: ticket.sourceFormat,
                    transportFormat: ticket.transportFormat,
                    expectedSHA256: ticket.sha256,
                    modelBuildID: ticket.modelBuildID,
                    licenseID: ticket.license.licenseID,
                    organizationID: ticket.organizationID,
                    leaseExpiresAt: ticket.license.leaseExpiresAt,
                    policyFlags: ticket.license.policyFlags,
                    isEncrypted: ticket.isEncrypted,
                    deviceBindingID: ticket.license.deviceBindingID ?? ModelLicenseVerifier.currentDeviceBindingID(),
                    encryptionEnvelope: ticket.encryption?.envelope,
                    encryptionAlgorithm: ticket.encryption?.algorithm,
                    encryptionKeyDerivation: ticket.encryption?.keyDerivation,
                    encryptionTicketSecret: ticket.encryption?.ticketSecret
                )

                appState.lastCloudMessage = "正在安装模型…"
                try await appendDownloadedArtifact(at: downloadedURL, transferID: ticket.ticketID)

                var record = try await modelStore.commitInstall(transferID: ticket.ticketID)
                if activateAfterInstall {
                    try await modelStore.activateExclusively(modelID: record.id)
                    record.isActive = true
                    record.isEnabled = true
                }

                appState.installModel(record)
                if activateAfterInstall {
                    appState.activateModel(modelID: record.id)
                }
                inferenceRuntime?.refreshModels(from: appState.modelCatalog)
                appState.lastCloudMessage = "模型已下载 · \(descriptor.name)"
                appState.lastStatusMessage = "模型已切换 · \(descriptor.name)"
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
                appState.lastCloudMessage = error.localizedDescription
                appState.lastStatusMessage = "模型下载失败 · \(error.localizedDescription)"
            }
        }
    }

    public func renewLeaseForSelectedModel() {
        Task {
            guard let appState, let session = appState.cloudSession else { return }
            guard let modelID = appState.selectedModelID ?? appState.modelCatalog.activeModels.first?.id else {
                appState.lastCloudMessage = "暂无已选择模型"
                return
            }

            isBusy = true
            defer { isBusy = false }

            do {
                let response = try await authService.renewLease(
                    baseURL: appState.cloudBaseURL,
                    session: session,
                    modelID: modelID
                )
                try await modelStore.updateLease(
                    modelID: modelID,
                    leaseExpiresAt: response.leaseExpiresAt,
                    policyFlags: response.policyFlags,
                    licenseID: response.licenseID,
                    deviceBindingID: response.deviceBindingID
                )
                appState.updateModelLease(
                    modelID: modelID,
                    leaseExpiresAt: response.leaseExpiresAt,
                    policyFlags: response.policyFlags,
                    licenseID: response.licenseID,
                    deviceBindingID: response.deviceBindingID
                )
                appState.lastCloudMessage = "租约已续期 · \(modelID)"
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
                appState.lastCloudMessage = error.localizedDescription
            }
        }
    }

    public func flushBufferedUploads() {
        Task { await refreshBufferedCount(flush: true) }
    }

    public func handleCapturedMedia(url: URL, category: String, context: RemoteCaptureContext) async {
        guard let appState, appState.persistMediaEnabled else { return }
        let pendingCount = await uploadService.processCapturedMedia(
            fileURL: url,
            category: category,
            context: context,
            deviceName: appState.deviceName,
            deviceID: ModelLicenseVerifier.currentDeviceBindingID(),
            localNodeBaseURL: appState.localNodeBaseURL,
            cloudBaseURL: appState.cloudBaseURL,
            session: appState.cloudSession
        )
        appState.pendingUploadCount = pendingCount
    }

    public func handleInferenceReport(_ report: InferenceFrameReport, context: RemoteCaptureContext) async {
        guard let appState, appState.persistMediaEnabled else { return }
        guard !report.detections.isEmpty else { return }
        guard Date().timeIntervalSince(lastInferenceUploadAt) >= 2 else { return }
        lastInferenceUploadAt = Date()

        let pendingCount = await uploadService.processInferenceReport(
            report,
            context: context,
            deviceName: appState.deviceName,
            deviceID: ModelLicenseVerifier.currentDeviceBindingID(),
            localNodeBaseURL: appState.localNodeBaseURL,
            cloudBaseURL: appState.cloudBaseURL,
            session: appState.cloudSession
        )
        appState.pendingUploadCount = pendingCount
    }

    private func restoreSessionIfPossible() async {
        guard let appState else { return }
        guard let session = await sessionStore.loadSession(), !session.isExpired else {
            statusSummary = "未登录"
            return
        }

        appState.updateCloudSession(session)
        statusSummary = "已登录 · \(session.user.organizationName)"
        appState.lastCloudMessage = "已恢复云端会话"
        await syncCatalogInternal()
    }

    private func syncCatalogInternal() async {
        guard let appState, let session = appState.cloudSession, !session.isExpired else {
            statusSummary = "未登录"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let catalog = try await authService.fetchModelCatalog(
                baseURL: appState.cloudBaseURL,
                session: session
            )
            appState.applyCloudCatalog(catalog)
            statusSummary = "模型清单 \(catalog.models.count) 个"
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            appState.lastCloudMessage = error.localizedDescription
        }
    }

    private func appendDownloadedArtifact(at fileURL: URL, transferID: String) async throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        while let chunk = try handle.read(upToCount: 192 * 1024), !chunk.isEmpty {
            try await modelStore.appendChunk(
                transferID: transferID,
                chunkBase64: chunk.base64EncodedString()
            )
        }
    }

    private func refreshBufferedCount(flush: Bool = false) async {
        guard let appState else { return }
        let pendingCount: Int
        if flush {
            pendingCount = await uploadService.flushBufferedJobs(
                localNodeBaseURL: appState.localNodeBaseURL,
                cloudBaseURL: appState.cloudBaseURL,
                session: appState.cloudSession
            )
        } else {
            pendingCount = await uploadService.countJobs()
        }
        appState.pendingUploadCount = pendingCount
    }
}
