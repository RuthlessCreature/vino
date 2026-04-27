import CoreML
import CryptoKit
import Foundation

public actor ModelFileStore {
    private static let bundleArchiveMagic = Data("VINOAR01".utf8)
    private static let encryptedEnvelopeMagic = Data("VINOENC1".utf8)

    public struct Metadata: Codable {
        public var id: String
        public var name: String
        public var version: String
        public var originalFileName: String
        public var runtimeEntryName: String
        public var isEnabled: Bool
        public var isActive: Bool
        public var modelBuildID: String?
        public var modelHash: String?
        public var licenseID: String?
        public var organizationID: String?
        public var leaseExpiresAt: String?
        public var policyFlags: [String]
        public var isEncrypted: Bool
        public var deviceBindingID: String?
    }

    public struct PendingTransfer {
        public var transferID: String
        public var modelID: String
        public var modelName: String
        public var version: String
        public var fileName: String
        public var sourceFormat: String
        public var transportFormat: String
        public var expectedSHA256: String?
        public var modelBuildID: String?
        public var licenseID: String?
        public var organizationID: String?
        public var leaseExpiresAt: String?
        public var policyFlags: [String]
        public var isEncrypted: Bool
        public var deviceBindingID: String?
        public var encryptionEnvelope: String?
        public var encryptionAlgorithm: String?
        public var encryptionKeyDerivation: String?
        public var encryptionTicketSecret: String?
        public var stagingURL: URL
    }

    private var pendingTransfers: [String: PendingTransfer] = [:]

    public init() {}

    public func beginInstall(
        transferID: String,
        modelID: String,
        modelName: String,
        version: String,
        fileName: String,
        sourceFormat: String,
        transportFormat: String,
        expectedSHA256: String? = nil,
        modelBuildID: String? = nil,
        licenseID: String? = nil,
        organizationID: String? = nil,
        leaseExpiresAt: String? = nil,
        policyFlags: [String] = [],
        isEncrypted: Bool = false,
        deviceBindingID: String? = nil,
        encryptionEnvelope: String? = nil,
        encryptionAlgorithm: String? = nil,
        encryptionKeyDerivation: String? = nil,
        encryptionTicketSecret: String? = nil
    ) throws {
        if let existingTransfer = pendingTransfers.removeValue(forKey: transferID) {
            try? removePendingTransferFile(at: existingTransfer.stagingURL)
        }

        let stagingURL = try pendingTransferFileURL(transferID: transferID)
        if FileManager.default.fileExists(atPath: stagingURL.path) {
            try FileManager.default.removeItem(at: stagingURL)
        }
        FileManager.default.createFile(atPath: stagingURL.path, contents: nil)

        pendingTransfers[transferID] = PendingTransfer(
            transferID: transferID,
            modelID: modelID,
            modelName: modelName,
            version: version,
            fileName: fileName,
            sourceFormat: sourceFormat,
            transportFormat: transportFormat,
            expectedSHA256: expectedSHA256,
            modelBuildID: modelBuildID,
            licenseID: licenseID,
            organizationID: organizationID,
            leaseExpiresAt: leaseExpiresAt,
            policyFlags: policyFlags,
            isEncrypted: isEncrypted,
            deviceBindingID: deviceBindingID,
            encryptionEnvelope: encryptionEnvelope,
            encryptionAlgorithm: encryptionAlgorithm,
            encryptionKeyDerivation: encryptionKeyDerivation,
            encryptionTicketSecret: encryptionTicketSecret,
            stagingURL: stagingURL
        )
    }

    public func appendChunk(transferID: String, chunkBase64: String) throws {
        guard let transfer = pendingTransfers[transferID] else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard let chunk = Data(base64Encoded: chunkBase64) else {
            throw CocoaError(.coderInvalidValue)
        }

        let handle = try FileHandle(forWritingTo: transfer.stagingURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: chunk)
    }

    public func commitInstall(transferID: String) throws -> CoreMLModelRecord {
        guard let transfer = pendingTransfers.removeValue(forKey: transferID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { try? removePendingTransferFile(at: transfer.stagingURL) }

        let payloadHash: String
        if transfer.isEncrypted {
            let payloadData = try payloadData(for: transfer)
            payloadHash = ModelLicenseVerifier.sha256Hex(payloadData)
        } else {
            payloadHash = try sha256Hex(forFileAt: transfer.stagingURL)
        }
        if let expectedSHA256 = transfer.expectedSHA256,
           !expectedSHA256.isEmpty,
           payloadHash.caseInsensitiveCompare(expectedSHA256) != .orderedSame {
            throw CocoaError(.fileReadCorruptFile)
        }

        let folder = try modelRootURL()
        let modelFolder = folder.appendingPathComponent(transfer.modelID, isDirectory: true)
        if FileManager.default.fileExists(atPath: modelFolder.path) {
            try FileManager.default.removeItem(at: modelFolder)
        }
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        let originalURL = try installSourceArtifact(for: transfer, in: modelFolder)

        let runtimeURL = try materializeRuntimeModel(
            at: originalURL,
            sourceFormat: transfer.sourceFormat,
            modelFolder: modelFolder
        )
        try cleanupSourceArtifactIfNeeded(
            originalURL: originalURL,
            runtimeURL: runtimeURL,
            isEncrypted: transfer.isEncrypted
        )
        let metadata = Metadata(
            id: transfer.modelID,
            name: transfer.modelName,
            version: transfer.version,
            originalFileName: transfer.fileName,
            runtimeEntryName: runtimeURL.lastPathComponent,
            isEnabled: true,
            isActive: false,
            modelBuildID: transfer.modelBuildID,
            modelHash: transfer.expectedSHA256 ?? payloadHash,
            licenseID: transfer.licenseID,
            organizationID: transfer.organizationID,
            leaseExpiresAt: transfer.leaseExpiresAt,
            policyFlags: transfer.policyFlags,
            isEncrypted: transfer.isEncrypted,
            deviceBindingID: transfer.deviceBindingID
        )

        let metadataURL = modelFolder.appendingPathComponent("metadata.json")
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)

        return CoreMLModelRecord(
            id: transfer.modelID,
            name: transfer.modelName,
            version: transfer.version,
            isEnabled: true,
            isActive: false,
            modelBuildID: transfer.modelBuildID,
            modelHash: transfer.expectedSHA256 ?? payloadHash,
            licenseID: transfer.licenseID,
            organizationID: transfer.organizationID,
            leaseExpiresAt: transfer.leaseExpiresAt,
            policyFlags: transfer.policyFlags,
            isEncrypted: transfer.isEncrypted,
            deviceBindingID: transfer.deviceBindingID
        )
    }

    @discardableResult
    public func remove(modelID: String) throws -> Bool {
        let modelFolder = try modelRootURL().appendingPathComponent(modelID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelFolder.path) else {
            return false
        }

        try FileManager.default.removeItem(at: modelFolder)
        return true
    }

    public func runtimeModelURL(modelID: String) throws -> URL? {
        let root = try modelRootURL()
        let modelFolder = root.appendingPathComponent(modelID, isDirectory: true)
        let metadataURL = modelFolder.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let metadata = try loadMetadata(at: metadataURL)
        let validation = ModelLicenseVerifier.validate(metadata: metadata)
        guard validation.isValid else {
            return nil
        }
        let runtimeURL = modelFolder.appendingPathComponent(metadata.runtimeEntryName, isDirectory: true)
        return FileManager.default.fileExists(atPath: runtimeURL.path) ? runtimeURL : nil
    }

    public func updateFlags(modelID: String, isEnabled: Bool? = nil, isActive: Bool? = nil) throws {
        let root = try modelRootURL()
        let modelFolder = root.appendingPathComponent(modelID, isDirectory: true)
        let metadataURL = modelFolder.appendingPathComponent("metadata.json")
        var metadata = try loadMetadata(at: metadataURL)

        if let isEnabled {
            metadata.isEnabled = isEnabled
        }
        if let isActive {
            metadata.isActive = isActive
        }

        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    public func activateExclusively(modelID: String) throws {
        let root = try modelRootURL()
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var found = false

        for child in children {
            let metadataURL = child.appendingPathComponent("metadata.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                continue
            }

            var metadata = try loadMetadata(at: metadataURL)
            if metadata.id == modelID {
                metadata.isEnabled = true
                metadata.isActive = true
                found = true
            } else {
                metadata.isActive = false
            }

            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
        }

        guard found else {
            throw CocoaError(.fileNoSuchFile)
        }
    }

    public func updateLease(
        modelID: String,
        leaseExpiresAt: String?,
        policyFlags: [String],
        licenseID: String? = nil,
        deviceBindingID: String? = nil
    ) throws {
        let root = try modelRootURL()
        let modelFolder = root.appendingPathComponent(modelID, isDirectory: true)
        let metadataURL = modelFolder.appendingPathComponent("metadata.json")
        var metadata = try loadMetadata(at: metadataURL)
        metadata.leaseExpiresAt = leaseExpiresAt
        metadata.policyFlags = policyFlags
        if let licenseID {
            metadata.licenseID = licenseID
        }
        if let deviceBindingID {
            metadata.deviceBindingID = deviceBindingID
        }

        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    public func metadata(modelID: String) throws -> Metadata? {
        let root = try modelRootURL()
        let modelFolder = root.appendingPathComponent(modelID, isDirectory: true)
        let metadataURL = modelFolder.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        return try loadMetadata(at: metadataURL)
    }

    public func loadCatalog() throws -> CoreMLCatalog {
        let root = try modelRootURL()
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var models: [CoreMLModelRecord] = []

        for child in children {
            let metadataURL = child.appendingPathComponent("metadata.json")
            guard FileManager.default.fileExists(atPath: metadataURL.path) else {
                continue
            }

            let metadata = try loadMetadata(at: metadataURL)
            models.append(
                CoreMLModelRecord(
                    id: metadata.id,
                    name: metadata.name,
                    version: metadata.version,
                    isEnabled: metadata.isEnabled,
                    isActive: metadata.isActive,
                    modelBuildID: metadata.modelBuildID,
                    modelHash: metadata.modelHash,
                    licenseID: metadata.licenseID,
                    organizationID: metadata.organizationID,
                    leaseExpiresAt: metadata.leaseExpiresAt,
                    policyFlags: metadata.policyFlags,
                    isEncrypted: metadata.isEncrypted,
                    deviceBindingID: metadata.deviceBindingID
                )
            )
        }

        return CoreMLCatalog(models: models.sorted { $0.name < $1.name })
    }

    public func importBundledModelsIfNeeded(bundle: Bundle = .main) throws -> CoreMLCatalog {
        let bundledURLs = bundledModelURLs(in: bundle)
        for bundledURL in bundledURLs {
            try installBundledModelIfNeeded(from: bundledURL)
        }

        var catalog = try loadCatalog()
        if catalog.activeModels.isEmpty, let firstModelID = catalog.enabledModels.first?.id {
            try activateExclusively(modelID: firstModelID)
            catalog = try loadCatalog()
        }
        return catalog
    }

    private func loadMetadata(at url: URL) throws -> Metadata {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Metadata.self, from: data)
    }

    private func bundledModelURLs(in bundle: Bundle) -> [URL] {
        let fileManager = FileManager.default
        let modelsFolderURL = bundle.resourceURL?.appendingPathComponent("models", isDirectory: true)
        let searchRoot: URL?
        if let modelsFolderURL, fileManager.fileExists(atPath: modelsFolderURL.path) {
            searchRoot = modelsFolderURL
        } else {
            searchRoot = bundle.resourceURL
        }

        guard let searchRoot else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urlsByModelID: [String: URL] = [:]
        while let candidate = enumerator.nextObject() as? URL {
            let pathExtension = candidate.pathExtension.lowercased()
            switch pathExtension {
            case "mlmodel", "mlpackage", "mlmodelc":
                let modelID = bundledModelID(for: candidate)
                if let existing = urlsByModelID[modelID] {
                    if bundledModelPriority(candidate) > bundledModelPriority(existing) {
                        urlsByModelID[modelID] = candidate
                    }
                } else {
                    urlsByModelID[modelID] = candidate
                }
                enumerator.skipDescendants()
            default:
                continue
            }
        }

        return urlsByModelID.values.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func installBundledModelIfNeeded(from resourceURL: URL) throws {
        let fileManager = FileManager.default
        let root = try modelRootURL()
        let modelID = bundledModelID(for: resourceURL)
        let modelFolder = root.appendingPathComponent(modelID, isDirectory: true)
        let metadataURL = modelFolder.appendingPathComponent("metadata.json")

        let existingMetadata = fileManager.fileExists(atPath: metadataURL.path) ? try? loadMetadata(at: metadataURL) : nil
        if let existingMetadata {
            let runtimeURL = modelFolder.appendingPathComponent(existingMetadata.runtimeEntryName, isDirectory: true)
            if existingMetadata.originalFileName == resourceURL.lastPathComponent,
               fileManager.fileExists(atPath: runtimeURL.path) {
                return
            }
        }

        let preservedEnabled = existingMetadata?.isEnabled ?? true
        let preservedActive = existingMetadata?.isActive ?? false
        if fileManager.fileExists(atPath: modelFolder.path) {
            try fileManager.removeItem(at: modelFolder)
        }
        try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        let isDirectory = (try? resourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let originalURL = modelFolder.appendingPathComponent(resourceURL.lastPathComponent, isDirectory: isDirectory)
        try fileManager.copyItem(at: resourceURL, to: originalURL)

        let runtimeURL = try materializeRuntimeModel(
            at: originalURL,
            sourceFormat: resourceURL.pathExtension.lowercased(),
            modelFolder: modelFolder
        )

        let metadata = Metadata(
            id: modelID,
            name: bundledModelName(for: resourceURL),
            version: "bundle",
            originalFileName: resourceURL.lastPathComponent,
            runtimeEntryName: runtimeURL.lastPathComponent,
            isEnabled: preservedEnabled,
            isActive: preservedActive,
            modelBuildID: "bundle:\(resourceURL.lastPathComponent)",
            modelHash: nil,
            licenseID: nil,
            organizationID: nil,
            leaseExpiresAt: nil,
            policyFlags: [],
            isEncrypted: false,
            deviceBindingID: nil
        )

        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)
    }

    private func bundledModelID(for resourceURL: URL) -> String {
        let baseName = resourceURL.deletingPathExtension().lastPathComponent
        let normalized = baseName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return normalized.isEmpty ? "bundled-model" : normalized
    }

    private func bundledModelName(for resourceURL: URL) -> String {
        let baseName = resourceURL.deletingPathExtension().lastPathComponent
        return baseName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func bundledModelPriority(_ resourceURL: URL) -> Int {
        switch resourceURL.pathExtension.lowercased() {
        case "mlmodelc":
            return 3
        case "mlpackage":
            return 2
        case "mlmodel":
            return 1
        default:
            return 0
        }
    }

    private func payloadData(for transfer: PendingTransfer) throws -> Data {
        let transferData = try Data(contentsOf: transfer.stagingURL, options: [.mappedIfSafe])
        guard transfer.isEncrypted else {
            return transferData
        }

        guard transfer.encryptionEnvelope == "vino-aesgcm-v1",
              transfer.encryptionAlgorithm == "aes-256-gcm",
              transfer.encryptionKeyDerivation == "sha256(ticketSecret:modelId:deviceId:modelBuildId)",
              let ticketSecret = transfer.encryptionTicketSecret,
              !ticketSecret.isEmpty else {
            throw CocoaError(.fileReadUnknown)
        }

        let envelope = try parseEncryptedEnvelope(transferData)
        guard envelope.algorithm == transfer.encryptionAlgorithm else {
            throw CocoaError(.fileReadUnknown)
        }

        let bindingID = transfer.deviceBindingID ?? ModelLicenseVerifier.currentDeviceBindingID()
        let keyMaterial = Data("\(ticketSecret):\(transfer.modelID):\(bindingID):\(transfer.modelBuildID ?? "")".utf8)
        let symmetricKey = SymmetricKey(data: ModelLicenseVerifier.sha256Data(keyMaterial))
        let nonce = try AES.GCM.Nonce(data: envelope.nonce)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: envelope.ciphertext, tag: envelope.tag)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    private func installSourceArtifact(for transfer: PendingTransfer, in modelFolder: URL) throws -> URL {
        if transfer.isEncrypted {
            let payloadData = try payloadData(for: transfer)
            return try installSourceArtifact(
                payloadData: payloadData,
                fileName: transfer.fileName,
                transportFormat: transfer.transportFormat,
                modelFolder: modelFolder
            )
        }

        return try installSourceArtifact(
            payloadURL: transfer.stagingURL,
            fileName: transfer.fileName,
            transportFormat: transfer.transportFormat,
            modelFolder: modelFolder
        )
    }

    private func installSourceArtifact(
        payloadData: Data,
        fileName: String,
        transportFormat: String,
        modelFolder: URL
    ) throws -> URL {
        switch transportFormat {
        case "bundle-archive":
            let originalURL = modelFolder.appendingPathComponent(fileName, isDirectory: true)
            try unpackBundleArchive(payloadData, to: originalURL)
            return originalURL

        case "raw-file":
            let originalURL = modelFolder.appendingPathComponent(fileName)
            try payloadData.write(to: originalURL, options: .atomic)
            return originalURL

        default:
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func installSourceArtifact(
        payloadURL: URL,
        fileName: String,
        transportFormat: String,
        modelFolder: URL
    ) throws -> URL {
        switch transportFormat {
        case "bundle-archive":
            let originalURL = modelFolder.appendingPathComponent(fileName, isDirectory: true)
            try unpackBundleArchive(from: payloadURL, to: originalURL)
            return originalURL

        case "raw-file":
            let originalURL = modelFolder.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: originalURL.path) {
                try FileManager.default.removeItem(at: originalURL)
            }
            try FileManager.default.copyItem(at: payloadURL, to: originalURL)
            return originalURL

        default:
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func parseEncryptedEnvelope(_ data: Data) throws -> (
        algorithm: String,
        nonce: Data,
        tag: Data,
        ciphertext: Data
    ) {
        var cursor = 0

        func readData(count: Int) throws -> Data {
            guard count >= 0, data.count - cursor >= count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let range = cursor..<(cursor + count)
            cursor += count
            return data.subdata(in: range)
        }

        func readUInt32() throws -> UInt32 {
            let value = try readData(count: 4)
            return value.enumerated().reduce(0) { partial, entry in
                partial | (UInt32(entry.element) << (UInt32(entry.offset) * 8))
            }
        }

        func readUInt64() throws -> UInt64 {
            let value = try readData(count: 8)
            return value.enumerated().reduce(0) { partial, entry in
                partial | (UInt64(entry.element) << (UInt64(entry.offset) * 8))
            }
        }

        let magic = try readData(count: Self.encryptedEnvelopeMagic.count)
        guard magic == Self.encryptedEnvelopeMagic else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let version = try readUInt32()
        guard version == 1 else {
            throw CocoaError(.fileReadUnknown)
        }

        let algorithmLength = Int(try readUInt32())
        let nonceLength = Int(try readUInt32())
        let tagLength = Int(try readUInt32())
        let ciphertextLength = try readUInt64()
        guard ciphertextLength <= UInt64(Int.max) else {
            throw CocoaError(.fileReadTooLarge)
        }

        let algorithmData = try readData(count: algorithmLength)
        guard let algorithm = String(data: algorithmData, encoding: .utf8), !algorithm.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let nonce = try readData(count: nonceLength)
        let tag = try readData(count: tagLength)
        let ciphertext = try readData(count: Int(ciphertextLength))
        guard cursor == data.count else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return (algorithm: algorithm, nonce: nonce, tag: tag, ciphertext: ciphertext)
    }

    private func materializeRuntimeModel(at originalURL: URL, sourceFormat: String, modelFolder: URL) throws -> URL {
        switch sourceFormat.lowercased() {
        case "mlmodel":
            return try compileModelToRuntime(at: originalURL, modelFolder: modelFolder)

        case "mlpackage":
            do {
                return try compileModelToRuntime(at: originalURL, modelFolder: modelFolder)
            } catch {
                let fallbackURL = originalURL
                    .appendingPathComponent("Data", isDirectory: true)
                    .appendingPathComponent("com.apple.CoreML", isDirectory: true)
                    .appendingPathComponent("model.mlmodel")
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    return try compileModelToRuntime(at: fallbackURL, modelFolder: modelFolder)
                }
                throw error
            }

        case "mlmodelc":
            return originalURL

        default:
            switch originalURL.pathExtension.lowercased() {
            case "mlmodel":
                return try compileModelToRuntime(at: originalURL, modelFolder: modelFolder)
            case "mlmodelc":
                return originalURL
            default:
                return originalURL
            }
        }
    }

    private func compileModelToRuntime(at originalURL: URL, modelFolder: URL) throws -> URL {
        let compiledURL = try MLModel.compileModel(at: originalURL)
        let destinationURL = modelFolder.appendingPathComponent("\(originalURL.deletingPathExtension().lastPathComponent).mlmodelc", isDirectory: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: compiledURL, to: destinationURL)
        return destinationURL
    }

    private func cleanupSourceArtifactIfNeeded(originalURL: URL, runtimeURL: URL, isEncrypted: Bool) throws {
        guard isEncrypted else {
            return
        }
        guard originalURL.standardizedFileURL != runtimeURL.standardizedFileURL else {
            return
        }
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: originalURL)
    }

    private func unpackBundleArchive(_ archiveData: Data, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var cursor = 0

        func readData(count: Int) throws -> Data {
            guard count >= 0, archiveData.count - cursor >= count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let range = cursor..<(cursor + count)
            cursor += count
            return archiveData.subdata(in: range)
        }

        func readUInt32() throws -> UInt32 {
            let data = try readData(count: 4)
            return data.enumerated().reduce(0) { partial, entry in
                partial | (UInt32(entry.element) << (UInt32(entry.offset) * 8))
            }
        }

        func readUInt64() throws -> UInt64 {
            let data = try readData(count: 8)
            return data.enumerated().reduce(0) { partial, entry in
                partial | (UInt64(entry.element) << (UInt64(entry.offset) * 8))
            }
        }

        let magic = try readData(count: Self.bundleArchiveMagic.count)
        guard magic == Self.bundleArchiveMagic else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let version = try readUInt32()
        guard version == 1 else {
            throw CocoaError(.fileReadUnknown)
        }

        let fileCount = Int(try readUInt32())
        for _ in 0..<fileCount {
            let pathLength = Int(try readUInt32())
            let byteCount = try readUInt64()
            guard byteCount <= UInt64(Int.max) else {
                throw CocoaError(.fileReadTooLarge)
            }

            let pathData = try readData(count: pathLength)
            guard let relativePath = String(data: pathData, encoding: .utf8),
                  !relativePath.isEmpty,
                  !relativePath.contains(".."),
                  !relativePath.hasPrefix("/") else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let fileData = try readData(count: Int(byteCount))
            let fileURL = destinationURL.appendingPathComponent(relativePath, isDirectory: false)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileData.write(to: fileURL, options: .atomic)
        }

        guard cursor == archiveData.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func unpackBundleArchive(from archiveURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let inputHandle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? inputHandle.close() }

        func readData(count: Int) throws -> Data {
            guard count >= 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }

            var collected = Data()
            collected.reserveCapacity(count)

            while collected.count < count {
                let remaining = count - collected.count
                guard let chunk = try inputHandle.read(upToCount: remaining), !chunk.isEmpty else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                collected.append(chunk)
            }

            return collected
        }

        func readUInt32() throws -> UInt32 {
            let data = try readData(count: 4)
            return data.enumerated().reduce(0) { partial, entry in
                partial | (UInt32(entry.element) << (UInt32(entry.offset) * 8))
            }
        }

        func readUInt64() throws -> UInt64 {
            let data = try readData(count: 8)
            return data.enumerated().reduce(0) { partial, entry in
                partial | (UInt64(entry.element) << (UInt64(entry.offset) * 8))
            }
        }

        let magic = try readData(count: Self.bundleArchiveMagic.count)
        guard magic == Self.bundleArchiveMagic else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let version = try readUInt32()
        guard version == 1 else {
            throw CocoaError(.fileReadUnknown)
        }

        let fileCount = Int(try readUInt32())
        let chunkSize = 256 * 1024

        for _ in 0..<fileCount {
            let pathLength = Int(try readUInt32())
            let byteCount = try readUInt64()
            guard byteCount <= UInt64(Int.max) else {
                throw CocoaError(.fileReadTooLarge)
            }

            let pathData = try readData(count: pathLength)
            guard let relativePath = String(data: pathData, encoding: .utf8),
                  !relativePath.isEmpty,
                  !relativePath.contains(".."),
                  !relativePath.hasPrefix("/") else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let fileURL = destinationURL.appendingPathComponent(relativePath, isDirectory: false)
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileManager.createFile(atPath: fileURL.path, contents: nil)

            do {
                let outputHandle = try FileHandle(forWritingTo: fileURL)
                defer { try? outputHandle.close() }

                var remaining = Int(byteCount)
                while remaining > 0 {
                    let nextCount = min(chunkSize, remaining)
                    let chunk = try readData(count: nextCount)
                    try outputHandle.write(contentsOf: chunk)
                    remaining -= chunk.count
                }
            }
        }

        let trailingData = try inputHandle.readToEnd() ?? Data()
        guard trailingData.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private func pendingTransferFileURL(transferID: String) throws -> URL {
        let root = try pendingTransfersRootURL()
        return root.appendingPathComponent("\(transferID).payload", isDirectory: false)
    }

    private func pendingTransfersRootURL() throws -> URL {
        let root = try modelRootURL()
            .deletingLastPathComponent()
            .appendingPathComponent("transfers", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func removePendingTransferFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func sha256Hex(forFileAt fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func modelRootURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("vino/models", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
