import CoreML
import Foundation

public actor ModelFileStore {
    public struct Metadata: Codable {
        public var id: String
        public var name: String
        public var version: String
        public var originalFileName: String
        public var runtimeEntryName: String
        public var isEnabled: Bool
        public var isActive: Bool
    }

    public struct PendingTransfer {
        public var transferID: String
        public var modelID: String
        public var modelName: String
        public var version: String
        public var fileName: String
        public var data: Data
    }

    private var pendingTransfers: [String: PendingTransfer] = [:]

    public init() {}

    public func beginInstall(
        transferID: String,
        modelID: String,
        modelName: String,
        version: String,
        fileName: String
    ) {
        pendingTransfers[transferID] = PendingTransfer(
            transferID: transferID,
            modelID: modelID,
            modelName: modelName,
            version: version,
            fileName: fileName,
            data: Data()
        )
    }

    public func appendChunk(transferID: String, chunkBase64: String) throws {
        guard var transfer = pendingTransfers[transferID] else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard let chunk = Data(base64Encoded: chunkBase64) else {
            throw CocoaError(.coderInvalidValue)
        }

        transfer.data.append(chunk)
        pendingTransfers[transferID] = transfer
    }

    public func commitInstall(transferID: String) throws -> CoreMLModelRecord {
        guard let transfer = pendingTransfers.removeValue(forKey: transferID) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let folder = try modelRootURL()
        let modelFolder = folder.appendingPathComponent(transfer.modelID, isDirectory: true)
        if FileManager.default.fileExists(atPath: modelFolder.path) {
            try FileManager.default.removeItem(at: modelFolder)
        }
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)

        let originalURL = modelFolder.appendingPathComponent(transfer.fileName)
        try transfer.data.write(to: originalURL, options: .atomic)

        let runtimeURL = try materializeRuntimeModel(at: originalURL, modelFolder: modelFolder)
        let metadata = Metadata(
            id: transfer.modelID,
            name: transfer.modelName,
            version: transfer.version,
            originalFileName: transfer.fileName,
            runtimeEntryName: runtimeURL.lastPathComponent,
            isEnabled: true,
            isActive: false
        )

        let metadataURL = modelFolder.appendingPathComponent("metadata.json")
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: metadataURL, options: .atomic)

        return CoreMLModelRecord(
            id: transfer.modelID,
            name: transfer.modelName,
            version: transfer.version,
            isEnabled: true,
            isActive: false
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
                    isActive: metadata.isActive
                )
            )
        }

        return CoreMLCatalog(models: models.sorted { $0.name < $1.name })
    }

    private func loadMetadata(at url: URL) throws -> Metadata {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Metadata.self, from: data)
    }

    private func materializeRuntimeModel(at originalURL: URL, modelFolder: URL) throws -> URL {
        switch originalURL.pathExtension.lowercased() {
        case "mlmodel":
            let compiledURL = try MLModel.compileModel(at: originalURL)
            let destinationURL = modelFolder.appendingPathComponent("\(originalURL.deletingPathExtension().lastPathComponent).mlmodelc", isDirectory: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: compiledURL, to: destinationURL)
            return destinationURL

        default:
            return originalURL
        }
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
