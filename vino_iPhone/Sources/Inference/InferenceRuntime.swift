import AVFoundation
import CoreML
import Foundation
import ImageIO
import QuartzCore
import Vision

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
    private var frameIndex = 0
    private var isProcessingFrame = false

    public var onReportPublished: ((InferenceFrameReport) -> Void)?

    public init(modelStore: ModelFileStore = ModelFileStore()) {
        self.modelStore = modelStore
    }

    public func refreshModels(from catalog: CoreMLCatalog) {
        let activeRecords = catalog.activeModels
        activeModelNames = activeRecords.map(\.name)

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
                self.workers = finalizedWorkers
                self.lastErrorMessage = finalizedErrors.isEmpty ? nil : finalizedErrors.joined(separator: " | ")
                self.activeModelNames = finalizedWorkers.map(\.modelName)
            }
        }
    }

    public func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        if !isEnabled {
            latestDetections = []
        }
    }

    public func submit(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) {
        guard isEnabled, !workers.isEmpty else { return }
        guard !isProcessingFrame else { return }

        isProcessingFrame = true
        isBusy = true
        frameIndex += 1
        let currentFrameIndex = frameIndex
        let captureTime = Date()
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let workerSnapshot = workers
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
                self.latestReport = report
                self.latestDetections = report.detections
                self.isBusy = false
                self.isProcessingFrame = false
                self.onReportPublished?(report)
            }
        }
    }

    public func submit(photoData: Data) {
        guard isEnabled, !workers.isEmpty else { return }
        guard let source = CGImageSourceCreateWithData(photoData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }

        isBusy = true
        frameIndex += 1
        let currentFrameIndex = frameIndex
        let captureTime = Date()
        let workerSnapshot = workers
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
        request.imageCropAndScaleOption = .scaleFill

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
        request.imageCropAndScaleOption = .scaleFill

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
        var detections: [InferenceDetection] = []

        for observation in observations {
            if let recognized = observation as? VNRecognizedObjectObservation {
                let topLabel = recognized.labels.first
                detections.append(
                    InferenceDetection(
                        modelID: modelID,
                        modelName: modelName,
                        label: topLabel?.identifier ?? "object",
                        confidence: Double(topLabel?.confidence ?? recognized.confidence),
                        boundingBox: recognized.boundingBox
                    )
                )
                continue
            }

            if let classification = observation as? VNClassificationObservation {
                detections.append(
                    InferenceDetection(
                        modelID: modelID,
                        modelName: modelName,
                        label: classification.identifier,
                        confidence: Double(classification.confidence),
                        boundingBox: nil
                    )
                )
            }
        }

        return detections
    }
}

private struct PixelBufferBox: @unchecked Sendable {
    let value: CVPixelBuffer
}

private struct CGImageBox: @unchecked Sendable {
    let value: CGImage
}
