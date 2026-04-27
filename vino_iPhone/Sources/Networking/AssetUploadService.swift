import Foundation

public actor AssetUploadService {
    private enum JobKind: String, Codable {
        case asset
        case result
    }

    private struct BufferedUploadJob: Codable {
        var id: String
        var kind: JobKind
        var createdAt: String
        var deviceID: String
        var deviceName: String
        var category: String?
        var fileName: String?
        var bufferedFileName: String?
        var context: RemoteCaptureContext
        var report: InferenceFrameReport?
        var localUploadedAt: String?
        var cloudUploadedAt: String?
        var lastError: String?
    }

    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func processCapturedMedia(
        fileURL: URL,
        category: String,
        context: RemoteCaptureContext,
        deviceName: String,
        deviceID: String,
        localNodeBaseURL: String,
        cloudBaseURL: String,
        session: AuthSession?
    ) async -> Int {
        do {
            var job = try createAssetJob(
                fileURL: fileURL,
                category: category,
                context: context,
                deviceName: deviceName,
                deviceID: deviceID
            )
            try save(job)
            try await flushJob(&job, localNodeBaseURL: localNodeBaseURL, cloudBaseURL: cloudBaseURL, session: session)
            return countJobs()
        } catch {
            return countJobs()
        }
    }

    public func processInferenceReport(
        _ report: InferenceFrameReport,
        context: RemoteCaptureContext,
        deviceName: String,
        deviceID: String,
        localNodeBaseURL: String,
        cloudBaseURL: String,
        session: AuthSession?
    ) async -> Int {
        do {
            var job = BufferedUploadJob(
                id: UUID().uuidString.lowercased(),
                kind: .result,
                createdAt: Self.nowISO8601(),
                deviceID: deviceID,
                deviceName: deviceName,
                category: nil,
                fileName: nil,
                bufferedFileName: nil,
                context: context,
                report: report,
                localUploadedAt: nil,
                cloudUploadedAt: nil,
                lastError: nil
            )
            try save(job)
            try await flushJob(&job, localNodeBaseURL: localNodeBaseURL, cloudBaseURL: cloudBaseURL, session: session)
            return countJobs()
        } catch {
            return countJobs()
        }
    }

    public func flushBufferedJobs(
        localNodeBaseURL: String,
        cloudBaseURL: String,
        session: AuthSession?
    ) async -> Int {
        let urls = jobManifestURLs()
        for url in urls {
            guard var job = load(url) else {
                continue
            }
            try? await flushJob(&job, localNodeBaseURL: localNodeBaseURL, cloudBaseURL: cloudBaseURL, session: session)
        }
        return countJobs()
    }

    public func countJobs() -> Int {
        jobManifestURLs().count
    }

    private func createAssetJob(
        fileURL: URL,
        category: String,
        context: RemoteCaptureContext,
        deviceName: String,
        deviceID: String
    ) throws -> BufferedUploadJob {
        let jobID = UUID().uuidString.lowercased()
        let extensionPart = fileURL.pathExtension.isEmpty ? "" : ".\(fileURL.pathExtension.lowercased())"
        let bufferedFileName = "\(jobID)\(extensionPart)"
        let destinationURL = bufferedFilesRootURL().appendingPathComponent(bufferedFileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)

        return BufferedUploadJob(
            id: jobID,
            kind: .asset,
            createdAt: Self.nowISO8601(),
            deviceID: deviceID,
            deviceName: deviceName,
            category: category,
            fileName: fileURL.lastPathComponent,
            bufferedFileName: bufferedFileName,
            context: context,
            report: nil,
            localUploadedAt: nil,
            cloudUploadedAt: nil,
            lastError: nil
        )
    }

    private func flushJob(
        _ job: inout BufferedUploadJob,
        localNodeBaseURL: String,
        cloudBaseURL: String,
        session: AuthSession?
    ) async throws {
        let requiresLocal = normalizedBaseURL(localNodeBaseURL) != nil
        let requiresCloud = normalizedBaseURL(cloudBaseURL) != nil

        if requiresLocal, job.localUploadedAt == nil {
            do {
                try await upload(job: job, baseURL: localNodeBaseURL, pathPrefix: "/api/local/v1", bearerToken: nil)
                job.localUploadedAt = Self.nowISO8601()
                job.lastError = nil
                try save(job)
            } catch {
                job.lastError = error.localizedDescription
                try save(job)
            }
        }

        if requiresCloud, job.cloudUploadedAt == nil, let session, !session.isExpired {
            do {
                try await upload(job: job, baseURL: cloudBaseURL, pathPrefix: "/api/cloud/v1", bearerToken: session.accessToken)
                job.cloudUploadedAt = Self.nowISO8601()
                job.lastError = nil
                try save(job)
            } catch {
                job.lastError = error.localizedDescription
                try save(job)
            }
        }

        let localDone = !requiresLocal || job.localUploadedAt != nil
        let cloudDone = !requiresCloud || job.cloudUploadedAt != nil
        if localDone && cloudDone {
            try remove(job)
        }
    }

    private func upload(job: BufferedUploadJob, baseURL: String, pathPrefix: String, bearerToken: String?) async throws {
        switch job.kind {
        case .asset:
            guard
                let fileName = job.fileName,
                let bufferedFileName = job.bufferedFileName
            else {
                throw CloudServiceError.serverMessage("buffer asset metadata missing")
            }

            let fileURL = bufferedFilesRootURL().appendingPathComponent(bufferedFileName)
            let data = try Data(contentsOf: fileURL)
            let body: [String: Any] = [
                "idempotencyKey": job.id,
                "deviceId": job.deviceID,
                "deviceName": job.deviceName,
                "fileName": fileName,
                "category": job.category ?? "binary",
                "capturedAt": job.createdAt,
                "productUUID": job.context.productUUID,
                "pointIndex": job.context.pointIndex,
                "jobId": job.context.jobID,
                "contentBase64": data.base64EncodedString()
            ]
            let path = pathPrefix == "/api/local/v1" ? "\(pathPrefix)/ingest/asset" : "\(pathPrefix)/ingest/asset"
            _ = try await sendJSON(baseURL: baseURL, path: path, bearerToken: bearerToken, body: body)

        case .result:
            let report = job.report
            let reportData = try encoder.encode(report)
            let reportObject = try JSONSerialization.jsonObject(with: reportData)
            let body: [String: Any] = [
                "idempotencyKey": job.id,
                "deviceId": job.deviceID,
                "deviceName": job.deviceName,
                "resultType": "inference_frame",
                "capturedAt": job.createdAt,
                "productUUID": job.context.productUUID,
                "pointIndex": job.context.pointIndex,
                "jobId": job.context.jobID,
                "payload": reportObject
            ]
            let path = pathPrefix == "/api/local/v1" ? "\(pathPrefix)/ingest/result" : "\(pathPrefix)/ingest/result"
            _ = try await sendJSON(baseURL: baseURL, path: path, bearerToken: bearerToken, body: body)
        }
    }

    private func sendJSON(
        baseURL: String,
        path: String,
        bearerToken: String?,
        body: [String: Any]
    ) async throws -> [String: Any] {
        guard
            let normalized = normalizedBaseURL(baseURL),
            let url = URL(string: normalized + path)
        else {
            throw CloudServiceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = object["error"] as? String ?? object["message"] as? String
            {
                throw CloudServiceError.serverMessage(message)
            }
            throw CloudServiceError.serverMessage("HTTP \(httpResponse.statusCode)")
        }

        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func save(_ job: BufferedUploadJob) throws {
        try prepareRoots()
        let url = jobManifestURL(for: job.id)
        let data = try encoder.encode(job)
        try data.write(to: url, options: .atomic)
    }

    private func load(_ url: URL) -> BufferedUploadJob? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(BufferedUploadJob.self, from: data)
    }

    private func remove(_ job: BufferedUploadJob) throws {
        let manifestURL = jobManifestURL(for: job.id)
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        if let bufferedFileName = job.bufferedFileName {
            let fileURL = bufferedFilesRootURL().appendingPathComponent(bufferedFileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func prepareRoots() throws {
        try FileManager.default.createDirectory(at: jobRootURL(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bufferedFilesRootURL(), withIntermediateDirectories: true)
    }

    private func jobManifestURLs() -> [URL] {
        try? prepareRoots()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: jobRootURL(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func jobManifestURL(for id: String) -> URL {
        jobRootURL().appendingPathComponent("\(id).json")
    }

    private func jobRootURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("vino/upload_buffer/jobs", isDirectory: true)
    }

    private func bufferedFilesRootURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("vino/upload_buffer/files", isDirectory: true)
    }

    private func normalizedBaseURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        }
        let value = "http://\(trimmed)"
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    private static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
