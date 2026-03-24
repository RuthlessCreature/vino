import Foundation

public enum VinoMessageKind: String, Codable {
    case hello
    case heartbeat
    case status
    case command
    case reply
    case fileBegin = "file.begin"
    case fileChunk = "file.chunk"
    case fileCommit = "file.commit"
    case error
}

public struct VinoSource: Codable, Hashable {
    public var role: String
    public var deviceID: String
    public var name: String?

    public init(role: String, deviceID: String, name: String? = nil) {
        self.role = role
        self.deviceID = deviceID
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case role
        case deviceID = "deviceId"
        case name
    }
}

public struct VinoTarget: Codable, Hashable {
    public var deviceIDs: [String]
    public var all: Bool

    public init(deviceIDs: [String] = [], all: Bool = false) {
        self.deviceIDs = deviceIDs
        self.all = all
    }

    enum CodingKeys: String, CodingKey {
        case deviceIDs = "deviceIds"
        case all
    }
}

public struct VinoContext: Codable, Hashable {
    public var productUUID: String?
    public var pointIndex: Int?
    public var jobID: String?

    public init(productUUID: String? = nil, pointIndex: Int? = nil, jobID: String? = nil) {
        self.productUUID = productUUID
        self.pointIndex = pointIndex
        self.jobID = jobID
    }

    enum CodingKeys: String, CodingKey {
        case productUUID
        case pointIndex
        case jobID = "jobId"
    }
}

public struct VinoEnvelope<Payload: Codable>: Codable {
    public var `protocol`: String
    public var messageID: String
    public var correlationID: String?
    public var kind: VinoMessageKind
    public var action: String
    public var timestamp: String
    public var source: VinoSource
    public var target: VinoTarget?
    public var context: VinoContext?
    public var payload: Payload

    public init(
        protocol: String = "vino.control/1",
        messageID: String = UUID().uuidString.uppercased(),
        correlationID: String? = nil,
        kind: VinoMessageKind,
        action: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        source: VinoSource,
        target: VinoTarget? = nil,
        context: VinoContext? = nil,
        payload: Payload
    ) {
        self.protocol = `protocol`
        self.messageID = messageID
        self.correlationID = correlationID
        self.kind = kind
        self.action = action
        self.timestamp = timestamp
        self.source = source
        self.target = target
        self.context = context
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case `protocol`
        case messageID = "messageId"
        case correlationID = "correlationId"
        case kind
        case action
        case timestamp
        case source
        case target
        case context
        case payload
    }
}

public struct DeviceStatusPayload: Codable, Hashable {
    public var deviceName: String
    public var captureMode: CaptureMode
    public var selectedLens: LensChoice
    public var recordingProfile: RecordingProfile
    public var focusMode: FocusControlMode
    public var smoothAutoFocusEnabled: Bool
    public var flashEnabled: Bool
    public var settings: CameraSettings
    public var ipAddresses: [String]
    public var inferenceEnabled: Bool
    public var persistMediaEnabled: Bool
    public var remotePostURL: String
    public var selectedModelID: String?
    public var activeModelIDs: [String]
    public var isRecording: Bool
    public var message: String

    public init(
        deviceName: String,
        captureMode: CaptureMode,
        selectedLens: LensChoice,
        recordingProfile: RecordingProfile,
        focusMode: FocusControlMode,
        smoothAutoFocusEnabled: Bool,
        flashEnabled: Bool,
        settings: CameraSettings,
        ipAddresses: [String],
        inferenceEnabled: Bool,
        persistMediaEnabled: Bool,
        remotePostURL: String,
        selectedModelID: String?,
        activeModelIDs: [String],
        isRecording: Bool,
        message: String
    ) {
        self.deviceName = deviceName
        self.captureMode = captureMode
        self.selectedLens = selectedLens
        self.recordingProfile = recordingProfile
        self.focusMode = focusMode
        self.smoothAutoFocusEnabled = smoothAutoFocusEnabled
        self.flashEnabled = flashEnabled
        self.settings = settings
        self.ipAddresses = ipAddresses
        self.inferenceEnabled = inferenceEnabled
        self.persistMediaEnabled = persistMediaEnabled
        self.remotePostURL = remotePostURL
        self.selectedModelID = selectedModelID
        self.activeModelIDs = activeModelIDs
        self.isRecording = isRecording
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case deviceName
        case captureMode
        case selectedLens
        case recordingProfile
        case focusMode
        case smoothAutoFocusEnabled
        case flashEnabled
        case settings
        case ipAddresses
        case inferenceEnabled
        case persistMediaEnabled
        case remotePostURL
        case selectedModelID = "selectedModelId"
        case activeModelIDs = "activeModelIds"
        case isRecording
        case message
    }
}

public struct CameraConfigPatch: Codable, Hashable {
    public var captureMode: CaptureMode?
    public var focusMode: FocusControlMode?
    public var selectedLens: LensChoice?
    public var recordingProfile: RecordingProfile?
    public var smoothAutoFocusEnabled: Bool?
    public var flashEnabled: Bool?
    public var inferenceEnabled: Bool?
    public var persistMediaEnabled: Bool?
    public var remotePostURL: String?
    public var settings: CameraSettings?

    public init(
        captureMode: CaptureMode? = nil,
        focusMode: FocusControlMode? = nil,
        selectedLens: LensChoice? = nil,
        recordingProfile: RecordingProfile? = nil,
        smoothAutoFocusEnabled: Bool? = nil,
        flashEnabled: Bool? = nil,
        inferenceEnabled: Bool? = nil,
        persistMediaEnabled: Bool? = nil,
        remotePostURL: String? = nil,
        settings: CameraSettings? = nil
    ) {
        self.captureMode = captureMode
        self.focusMode = focusMode
        self.selectedLens = selectedLens
        self.recordingProfile = recordingProfile
        self.smoothAutoFocusEnabled = smoothAutoFocusEnabled
        self.flashEnabled = flashEnabled
        self.inferenceEnabled = inferenceEnabled
        self.persistMediaEnabled = persistMediaEnabled
        self.remotePostURL = remotePostURL
        self.settings = settings
    }
}

public struct ReplyPayload: Codable, Hashable {
    public var status: String
    public var message: String
    public var details: [String: String]?

    public init(status: String, message: String, details: [String: String]? = nil) {
        self.status = status
        self.message = message
        self.details = details
    }
}

public struct HeartbeatPayload: Codable, Hashable {
    public var service: String
    public var connectedPeers: Int
    public var message: String

    public init(service: String, connectedPeers: Int, message: String) {
        self.service = service
        self.connectedPeers = connectedPeers
        self.message = message
    }
}

public struct CapabilitiesReportPayload: Codable, Hashable {
    public var capabilities: CameraCapabilities
    public var models: [CoreMLModelRecord]

    public init(capabilities: CameraCapabilities, models: [CoreMLModelRecord]) {
        self.capabilities = capabilities
        self.models = models
    }
}

public struct MediaPushBeginPayload: Codable, Hashable {
    public var transferID: String
    public var category: String
    public var fileName: String
    public var byteCount: Int

    public init(transferID: String, category: String, fileName: String, byteCount: Int) {
        self.transferID = transferID
        self.category = category
        self.fileName = fileName
        self.byteCount = byteCount
    }

    enum CodingKeys: String, CodingKey {
        case transferID = "transferId"
        case category
        case fileName
        case byteCount
    }
}

public struct MediaPushChunkPayload: Codable, Hashable {
    public var transferID: String
    public var chunkIndex: Int
    public var chunkBase64: String

    public init(transferID: String, chunkIndex: Int, chunkBase64: String) {
        self.transferID = transferID
        self.chunkIndex = chunkIndex
        self.chunkBase64 = chunkBase64
    }

    enum CodingKeys: String, CodingKey {
        case transferID = "transferId"
        case chunkIndex
        case chunkBase64
    }
}

public struct MediaPushCommitPayload: Codable, Hashable {
    public var transferID: String
    public var checksum: String

    public init(transferID: String, checksum: String = "") {
        self.transferID = transferID
        self.checksum = checksum
    }

    enum CodingKeys: String, CodingKey {
        case transferID = "transferId"
        case checksum
    }
}

public struct InferenceDetectionPayload: Codable, Hashable {
    public var modelID: String
    public var modelName: String
    public var label: String
    public var confidence: Double
    public var minX: Double?
    public var minY: Double?
    public var width: Double?
    public var height: Double?

    public init(from detection: InferenceDetection) {
        self.modelID = detection.modelID
        self.modelName = detection.modelName
        self.label = detection.label
        self.confidence = detection.confidence
        self.minX = detection.boundingBox.map { Double($0.minX) }
        self.minY = detection.boundingBox.map { Double($0.minY) }
        self.width = detection.boundingBox.map { Double($0.width) }
        self.height = detection.boundingBox.map { Double($0.height) }
    }

    enum CodingKeys: String, CodingKey {
        case modelID = "modelId"
        case modelName
        case label
        case confidence
        case minX
        case minY
        case width
        case height
    }
}

public struct InferenceFramePayload: Codable, Hashable {
    public var frameIndex: Int
    public var latencyMS: Double
    public var imageWidth: Int
    public var imageHeight: Int
    public var detections: [InferenceDetectionPayload]

    public init(report: InferenceFrameReport) {
        self.frameIndex = report.frameIndex
        self.latencyMS = report.latencyMS
        self.imageWidth = report.imageWidth
        self.imageHeight = report.imageHeight
        self.detections = report.detections.map(InferenceDetectionPayload.init(from:))
    }

    enum CodingKeys: String, CodingKey {
        case frameIndex
        case latencyMS = "latencyMs"
        case imageWidth
        case imageHeight
        case detections
    }
}

public struct PreviewFramePayload: Codable, Hashable {
    public var frameIndex: Int
    public var imageWidth: Int
    public var imageHeight: Int
    public var jpegBase64: String
    public var byteCount: Int

    public init(frameIndex: Int, imageWidth: Int, imageHeight: Int, jpegBase64: String, byteCount: Int) {
        self.frameIndex = frameIndex
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.jpegBase64 = jpegBase64
        self.byteCount = byteCount
    }
}
