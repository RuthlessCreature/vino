import CoreGraphics
import Foundation

public struct InferenceDetection: Identifiable, Codable, Hashable {
    public var id: UUID
    public var modelID: String
    public var modelName: String
    public var label: String
    public var confidence: Double
    public var boundingBox: CGRect?

    public init(
        id: UUID = UUID(),
        modelID: String,
        modelName: String,
        label: String,
        confidence: Double,
        boundingBox: CGRect? = nil
    ) {
        self.id = id
        self.modelID = modelID
        self.modelName = modelName
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct InferenceFrameReport: Identifiable, Codable, Hashable {
    public var id: UUID
    public var frameIndex: Int
    public var capturedAt: Date
    public var latencyMS: Double
    public var imageWidth: Int
    public var imageHeight: Int
    public var detections: [InferenceDetection]

    public init(
        id: UUID = UUID(),
        frameIndex: Int,
        capturedAt: Date,
        latencyMS: Double,
        imageWidth: Int,
        imageHeight: Int,
        detections: [InferenceDetection]
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.capturedAt = capturedAt
        self.latencyMS = latencyMS
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.detections = detections
    }
}

