import AVFoundation
import CoreML
import Foundation
import ImageIO
import QuartzCore
import Vision

private enum InferenceTuning {
    static let objectConfidenceThreshold = 0.35
    static let classificationConfidenceThreshold = 0.65
    static let minimumBoundingBoxExtent: CGFloat = 0.02
    static let minimumBoundingBoxArea: CGFloat = 0.0012
    static let maximumRenderedDetections = 12
    static let nonMaximumSuppressionIOUThreshold: CGFloat = 0.45
}

@MainActor
public final class InferenceRuntime: ObservableObject {
    @Published public private(set) var activeModelNames: [String] = []
    @Published public private(set) var latestReport: InferenceFrameReport?
    @Published public private(set) var latestDetections: [InferenceDetection] = []
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastErrorMessage: String?

    private let modelStore: ModelFileStore
    private let coordinationQueue = DispatchQueue(label: "vino.inference.runtime", qos: .userInitiated)

    private var workers: [InferenceModelWorker] = []
    private var isEnabled = false
    private var isReloadingModels = false
    private var frameIndex = 0
    private var isProcessingFrame = false
    private var modelLoadGeneration = 0
    private var runtimeGeneration = 0

    public var onReportPublished: ((InferenceFrameReport) -> Void)?

    public init(modelStore: ModelFileStore = ModelFileStore()) {
        self.modelStore = modelStore
    }

    public func refreshModels(from catalog: CoreMLCatalog) {
        let activeRecords = catalog.activeModels
        activeModelNames = activeRecords.map(\.name)
        modelLoadGeneration += 1
        runtimeGeneration += 1
        let loadGeneration = modelLoadGeneration
        workers = []
        latestDetections = []
        latestReport = nil
        isBusy = false
        if activeRecords.isEmpty {
            lastErrorMessage = nil
            activeModelNames = []
            isReloadingModels = false
            return
        }
        isReloadingModels = true

        Task.detached(priority: .userInitiated) { [modelStore] in
            var loadedWorkers: [InferenceModelWorker] = []
            var loadErrors: [String] = []

            for record in activeRecords {
                do {
                    guard let modelURL = try await modelStore.runtimeModelURL(modelID: record.id) else {
                        loadErrors.append("missing runtime for \(record.name)")
                        continue
                    }

                    let configuration = MLModelConfiguration()
                    configuration.computeUnits = .all
                    configuration.allowLowPrecisionAccumulationOnGPU = false

                    let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                    let visionModel = try VNCoreMLModel(for: model)
                    loadedWorkers.append(
                        InferenceModelWorker(
                            modelID: record.id,
                            modelName: record.name,
                            modelVersion: record.version,
                            visionModel: visionModel
                        )
                    )
                } catch {
                    loadErrors.append("\(record.name): \(error.localizedDescription)")
                }
            }

            let finalizedWorkers = loadedWorkers
            let finalizedErrors = loadErrors

            await MainActor.run {
                guard loadGeneration == self.modelLoadGeneration else {
                    return
                }
                self.workers = finalizedWorkers
                self.isReloadingModels = false
                if finalizedWorkers.isEmpty {
                    self.lastErrorMessage = finalizedErrors.isEmpty ? "没有可用的推理模型" : finalizedErrors.joined(separator: " | ")
                } else {
                    self.lastErrorMessage = finalizedErrors.isEmpty ? nil : finalizedErrors.joined(separator: " | ")
                }
                self.activeModelNames = finalizedWorkers.map(\.modelName)
            }
        }
    }

    public func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        if !isEnabled {
            runtimeGeneration += 1
            latestDetections = []
            latestReport = nil
            isBusy = false
            isProcessingFrame = false
        } else if isReloadingModels {
            lastErrorMessage = "模型正在切换，请稍候"
        } else if workers.isEmpty {
            lastErrorMessage = activeModelNames.isEmpty ? "没有激活的本地模型" : "模型尚未完成加载"
        } else {
            lastErrorMessage = nil
        }
    }

    public func submit(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) {
        guard isEnabled, !isReloadingModels, !workers.isEmpty else { return }
        guard !isProcessingFrame else { return }

        isProcessingFrame = true
        isBusy = true
        frameIndex += 1
        let currentFrameIndex = frameIndex
        let captureTime = Date()
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let workerSnapshot = workers
        let generation = runtimeGeneration
        let pixelBufferBox = PixelBufferBox(value: pixelBuffer)

        coordinationQueue.async { [weak self] in
            guard let self else { return }

            let startedAt = CACurrentMediaTime()
            let group = DispatchGroup()
            let lock = NSLock()
            var collected: [InferenceDetection] = []

            for worker in workerSnapshot {
                group.enter()
                worker.queue.async {
                    defer { group.leave() }
                    let results = worker.predict(pixelBuffer: pixelBufferBox.value, orientation: orientation)
                    lock.lock()
                    collected.append(contentsOf: results)
                    lock.unlock()
                }
            }

            group.wait()
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000.0

            let report = InferenceFrameReport(
                frameIndex: currentFrameIndex,
                capturedAt: captureTime,
                latencyMS: elapsed,
                imageWidth: width,
                imageHeight: height,
                detections: collected.sorted { $0.confidence > $1.confidence }
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.runtimeGeneration, self.isEnabled, !self.isReloadingModels else {
                    self.isBusy = false
                    self.isProcessingFrame = false
                    return
                }
                self.latestReport = report
                self.latestDetections = report.detections
                self.isBusy = false
                self.isProcessingFrame = false
                self.onReportPublished?(report)
            }
        }
    }

    public func submit(photoData: Data) {
        guard isEnabled, !isReloadingModels, !workers.isEmpty else { return }
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }

        isBusy = true
        frameIndex += 1
        let currentFrameIndex = frameIndex
        let captureTime = Date()
        let workerSnapshot = workers
        let generation = runtimeGeneration
        let cgImageBox = CGImageBox(value: cgImage)

        coordinationQueue.async { [weak self] in
            guard let self else { return }
            let startedAt = CACurrentMediaTime()
            let group = DispatchGroup()
            let lock = NSLock()
            var collected: [InferenceDetection] = []

            for worker in workerSnapshot {
                group.enter()
                worker.queue.async {
                    defer { group.leave() }
                    let results = worker.predict(cgImage: cgImageBox.value, orientation: .up)
                    lock.lock()
                    collected.append(contentsOf: results)
                    lock.unlock()
                }
            }

            group.wait()
            let elapsed = (CACurrentMediaTime() - startedAt) * 1000.0
            let report = InferenceFrameReport(
                frameIndex: currentFrameIndex,
                capturedAt: captureTime,
                latencyMS: elapsed,
                imageWidth: cgImage.width,
                imageHeight: cgImage.height,
                detections: collected.sorted { $0.confidence > $1.confidence }
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.runtimeGeneration, self.isEnabled, !self.isReloadingModels else {
                    self.isBusy = false
                    return
                }
                self.latestReport = report
                self.latestDetections = report.detections
                self.isBusy = false
                self.onReportPublished?(report)
            }
        }
    }
}

private final class InferenceModelWorker: @unchecked Sendable {
    let modelID: String
    let modelName: String
    let modelVersion: String
    let visionModel: VNCoreMLModel
    let queue: DispatchQueue

    init(modelID: String, modelName: String, modelVersion: String, visionModel: VNCoreMLModel) {
        self.modelID = modelID
        self.modelName = modelName
        self.modelVersion = modelVersion
        self.visionModel = visionModel
        self.queue = DispatchQueue(label: "vino.inference.model.\(modelID)", qos: .userInitiated)
    }

    func predict(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [InferenceDetection] {
        var collected: [InferenceDetection] = []
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, _ in
            guard let self else { return }
            collected = Self.extractDetections(
                observations: request.results ?? [],
                modelID: self.modelID,
                modelName: self.modelName
            )
        }
        request.imageCropAndScaleOption = .scaleFit

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
            try handler.perform([request])
        } catch {
            return []
        }

        return collected
    }

    func predict(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> [InferenceDetection] {
        var collected: [InferenceDetection] = []
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, _ in
            guard let self else { return }
            collected = Self.extractDetections(
                observations: request.results ?? [],
                modelID: self.modelID,
                modelName: self.modelName
            )
        }
        request.imageCropAndScaleOption = .scaleFit

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
        } catch {
            return []
        }

        return collected
    }

    private static func extractDetections(
        observations: [VNObservation],
        modelID: String,
        modelName: String
    ) -> [InferenceDetection] {
        var objectDetections: [InferenceDetection] = []
        var classifications: [InferenceDetection] = []

        for observation in observations {
            if let recognized = observation as? VNRecognizedObjectObservation {
                let topLabel = recognized.labels.first
                let confidence = Double(topLabel?.confidence ?? recognized.confidence)
                let normalizedBox = recognized.boundingBox.standardized
                guard confidence >= InferenceTuning.objectConfidenceThreshold else {
                    continue
                }
                guard
                    normalizedBox.width >= InferenceTuning.minimumBoundingBoxExtent,
                    normalizedBox.height >= InferenceTuning.minimumBoundingBoxExtent,
                    normalizedBox.width * normalizedBox.height >= InferenceTuning.minimumBoundingBoxArea
                else {
                    continue
                }

                objectDetections.append(
                    InferenceDetection(
                        modelID: modelID,
                        modelName: modelName,
                        label: topLabel?.identifier ?? "object",
                        confidence: confidence,
                        boundingBox: normalizedBox
                    )
                )
                continue
            }

            if let classification = observation as? VNClassificationObservation {
                let confidence = Double(classification.confidence)
                guard confidence >= InferenceTuning.classificationConfidenceThreshold else {
                    continue
                }

                classifications.append(
                    InferenceDetection(
                        modelID: modelID,
                        modelName: modelName,
                        label: classification.identifier,
                        confidence: confidence,
                        boundingBox: nil
                    )
                )
            }
        }

        let filteredObjects = nonMaximumSuppression(objectDetections)
        let filteredClassifications = classifications
            .sorted { $0.confidence > $1.confidence }
            .prefix(3)

        return filteredObjects + filteredClassifications
    }

    private static func nonMaximumSuppression(_ detections: [InferenceDetection]) -> [InferenceDetection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [InferenceDetection] = []

        for detection in sorted {
            guard let candidateBox = detection.boundingBox else {
                continue
            }

            let overlapsExisting = kept.contains { existing in
                guard
                    existing.modelID == detection.modelID,
                    existing.label == detection.label,
                    let existingBox = existing.boundingBox
                else {
                    return false
                }
                return intersectionOverUnion(candidateBox, existingBox) >= InferenceTuning.nonMaximumSuppressionIOUThreshold
            }

            guard !overlapsExisting else {
                continue
            }

            kept.append(detection)
            if kept.count >= InferenceTuning.maximumRenderedDetections {
                break
            }
        }

        return kept
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = (lhs.width * lhs.height) + (rhs.width * rhs.height) - intersectionArea
        guard unionArea > 0 else {
            return 0
        }

        return intersectionArea / unionArea
    }
}

private struct PixelBufferBox: @unchecked Sendable {
    let value: CVPixelBuffer
}

private struct CGImageBox: @unchecked Sendable {
    let value: CGImage
}
