import AVFoundation
import CoreMedia
import Foundation
import Photos
import UIKit
import ImageIO

public final class CameraSessionController: ObservableObject {
    public let session = AVCaptureSession()

    @Published public private(set) var capabilities: CameraCapabilities = .fallback
    @Published public var settings: CameraSettings = CameraSettings().clamped(to: .fallback)
    @Published public private(set) var availableLenses: [LensChoice] = [.wide]
    @Published public private(set) var lastCapturedFileURL: URL?

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var photoCaptureDelegates: [Int64: PhotoCaptureProcessor] = [:]
    private var movieRecordingDelegate: MovieRecordingProcessor?
    private let videoOutputQueue = DispatchQueue(label: "vino.camera.video.frames", qos: .userInteractive)
    private lazy var sampleBufferProxy = SampleBufferProxy { [weak self] pixelBuffer in
        self?.onVideoFrame?(pixelBuffer)
    }

    public var onMediaCaptured: ((URL, String) -> Void)?
    public var onPhotoDataCaptured: ((Data) -> Void)?
    public var onVideoFrame: ((CVPixelBuffer) -> Void)?

    public init() {}

    public func start(appState: VinoAppState) {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorization {
        case .authorized:
            configureAndStart(for: appState.selectedLens, appState: appState)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted, let self else { return }
                self.configureAndStart(for: appState.selectedLens, appState: appState)
            }
        default:
            DispatchQueue.main.async {
                appState.lastStatusMessage = "相机权限被拒绝"
            }
        }
    }

    public func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    public func switchLens(to lens: LensChoice, appState: VinoAppState) {
        configureAndStart(for: lens, appState: appState)
    }

    public func apply(appState: VinoAppState) {
        let desiredSettings = settings
        let focusMode = appState.focusMode
        let smoothAutoFocusEnabled = appState.smoothAutoFocusEnabled
        let flashEnabled = appState.flashEnabled

        guard let device = videoDeviceInput?.device else {
            return
        }

        do {
            try device.lockForConfiguration()

            let fps = Int32(max(1, desiredSettings.frameRate.rounded()))
            let frameDuration = CMTime(value: 1, timescale: fps)
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration

            device.videoZoomFactor = capabilities.zoomFactor.clamped(desiredSettings.zoomFactor)

            if focusMode == .continuousAuto, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = smoothAutoFocusEnabled
                }
            } else if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(
                    lensPosition: Float(capabilities.lensPosition.clamped(desiredSettings.lensPosition)),
                    completionHandler: nil
                )
            }

            if device.isWhiteBalanceModeSupported(.locked) {
                let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(desiredSettings.whiteBalanceTemperature),
                    tint: Float(desiredSettings.whiteBalanceTint)
                )
                var gains = device.deviceWhiteBalanceGains(for: values)
                gains = normalizedGains(gains, maxGain: device.maxWhiteBalanceGain)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }

            if device.isExposureModeSupported(.custom) {
                let durationSeconds = capabilities.exposureSeconds.clamped(desiredSettings.exposureSeconds)
                let duration = CMTimeMakeWithSeconds(durationSeconds, preferredTimescale: 1_000_000_000)
                let iso = Float(capabilities.iso.clamped(desiredSettings.iso))
                device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            }

            let desiredBias = Float(desiredSettings.exposureBias)

            if device.minExposureTargetBias <= desiredBias,
               desiredBias <= device.maxExposureTargetBias {
                device.setExposureTargetBias(Float(desiredSettings.exposureBias), completionHandler: nil)
            }

            device.unlockForConfiguration()
            appState.lastStatusMessage = flashEnabled ? "相机参数已更新 · 闪光灯已就绪" : "相机参数已更新"
        } catch {
            appState.lastStatusMessage = "相机参数更新失败"
        }
    }

    public func triggerPrimaryAction(appState: VinoAppState) {
        switch appState.captureMode {
        case .photo:
            capturePhoto(appState: appState)
        case .stream:
            if appState.isRecording {
                stopRecording(appState: appState)
            } else {
                startRecording(appState: appState)
            }
        }
    }

    public func refreshCapabilities(appState: VinoAppState) {
        configureAndStart(for: appState.selectedLens, appState: appState)
    }

    private func configureAndStart(for lens: LensChoice, appState: VinoAppState) {
        let discoveredLenses = discoverLenses()
        availableLenses = discoveredLenses

        if !discoveredLenses.contains(appState.selectedLens), let first = discoveredLenses.first {
            appState.selectedLens = first
        }

        guard let device = makeDevice(for: lens) ?? makeDevice(for: .wide) else {
            appState.lastStatusMessage = "未找到可用相机"
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            session.beginConfiguration()
            session.sessionPreset = .high

            for existingInput in session.inputs {
                session.removeInput(existingInput)
            }

            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
            }

            if !session.outputs.contains(where: { $0 === photoOutput }),
               session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            if !session.outputs.contains(where: { $0 === movieOutput }),
               session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            if !session.outputs.contains(where: { $0 === videoDataOutput }),
               session.canAddOutput(videoDataOutput) {
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                videoDataOutput.setSampleBufferDelegate(sampleBufferProxy, queue: videoOutputQueue)
                session.addOutput(videoDataOutput)
                videoDataOutput.connection(with: .video)?.videoRotationAngle = 90
            }

            session.commitConfiguration()

            let updatedCapabilities = capabilities(for: device)
            capabilities = updatedCapabilities
            settings = settings.clamped(to: updatedCapabilities)

            apply(appState: appState)

            if !session.isRunning {
                session.startRunning()
            }

            appState.lastStatusMessage = "镜头已就绪 · \(lens.label)"
        } catch {
            appState.lastStatusMessage = "相机配置失败"
        }
    }

    private func discoverLenses() -> [LensChoice] {
        var lenses: [LensChoice] = []

        if makeDevice(for: .wide) != nil {
            lenses.append(.wide)
        }
        if makeDevice(for: .ultraWide) != nil {
            lenses.append(.ultraWide)
        }
        if makeDevice(for: .telephoto) != nil {
            lenses.append(.telephoto)
        }

        return lenses.isEmpty ? [.wide] : lenses
    }

    private func makeDevice(for lens: LensChoice) -> AVCaptureDevice? {
        let deviceType: AVCaptureDevice.DeviceType

        switch lens {
        case .wide:
            deviceType = .builtInWideAngleCamera
        case .ultraWide:
            deviceType = .builtInUltraWideCamera
        case .telephoto:
            deviceType = .builtInTelephotoCamera
        }

        return AVCaptureDevice.default(deviceType, for: .video, position: .back)
    }

    private func capabilities(for device: AVCaptureDevice) -> CameraCapabilities {
        let frameRanges = device.activeFormat.videoSupportedFrameRateRanges
        let minFrameRate = frameRanges.map(\.minFrameRate).min() ?? 1
        let maxFrameRate = frameRanges.map(\.maxFrameRate).max() ?? 60

        let minExposureSeconds = max(CMTimeGetSeconds(device.activeFormat.minExposureDuration), 1.0 / 10_000.0)
        let maxExposureSeconds = max(CMTimeGetSeconds(device.activeFormat.maxExposureDuration), minExposureSeconds)

        return CameraCapabilities(
            frameRate: ControlRange(min: minFrameRate, max: maxFrameRate, step: 1),
            whiteBalanceTemperature: ControlRange(min: 2800, max: 8000, step: 50),
            whiteBalanceTint: ControlRange(min: -150, max: 150, step: 1),
            exposureSeconds: ControlRange(min: minExposureSeconds, max: maxExposureSeconds, step: 0.0005),
            iso: ControlRange(min: Double(device.activeFormat.minISO), max: Double(device.activeFormat.maxISO), step: 1),
            exposureBias: ControlRange(min: Double(device.minExposureTargetBias), max: Double(device.maxExposureTargetBias), step: 0.1),
            zoomFactor: ControlRange(min: 1, max: Double(device.maxAvailableVideoZoomFactor), step: 0.1),
            lensPosition: ControlRange(min: 0, max: 1, step: 0.01),
            supportsSmoothAutoFocus: device.isSmoothAutoFocusSupported,
            supportsFlash: device.hasFlash,
            supportedLenses: discoverLenses(),
            supportsProRes: false
        )
    }

    private func normalizedGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        maxGain: Float
    ) -> AVCaptureDevice.WhiteBalanceGains {
        AVCaptureDevice.WhiteBalanceGains(
            redGain: min(max(1.0, gains.redGain), maxGain),
            greenGain: min(max(1.0, gains.greenGain), maxGain),
            blueGain: min(max(1.0, gains.blueGain), maxGain)
        )
    }

    private func capturePhoto(appState: VinoAppState) {
        let photoSettings: AVCapturePhotoSettings
        let photoFileExtension: String
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            photoFileExtension = "jpg"
        } else if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            photoFileExtension = "heic"
        } else {
            photoSettings = AVCapturePhotoSettings()
            photoFileExtension = "jpg"
        }

        if appState.flashEnabled {
            photoSettings.flashMode = .on
        } else {
            photoSettings.flashMode = .off
        }

        let outputURL = Self.makeMediaURL(
            fileExtension: photoFileExtension,
            category: "photo",
            context: appState.activeContext
        )
        let processor = PhotoCaptureProcessor(outputURL: outputURL) { [weak self] result in
            DispatchQueue.main.async {
                self?.photoCaptureDelegates.removeValue(forKey: Int64(photoSettings.uniqueID))
                switch result {
                case .success(let output):
                    let (fileURL, photoData) = output
                    self?.lastCapturedFileURL = fileURL
                    self?.saveMediaToPhotoLibrary(url: fileURL, kind: .photo, appState: appState)
                    self?.onPhotoDataCaptured?(photoData)
                    self?.onMediaCaptured?(fileURL, "photo")
                case .failure:
                    appState.lastStatusMessage = "拍照失败"
                }
            }
        }

        photoCaptureDelegates[Int64(photoSettings.uniqueID)] = processor
        photoOutput.capturePhoto(with: photoSettings, delegate: processor)
        appState.lastStatusMessage = "已开始拍照"
    }

    public func setRecording(_ isEnabled: Bool, appState: VinoAppState) {
        if isEnabled {
            startRecording(appState: appState)
        } else {
            stopRecording(appState: appState)
        }
    }

    private func startRecording(appState: VinoAppState) {
        guard !movieOutput.isRecording else { return }

        let outputURL = Self.makeMediaURL(
            fileExtension: "mov",
            category: "video",
            context: appState.activeContext
        )
        let delegate = MovieRecordingProcessor(outputURL: outputURL) { [weak self] result in
            DispatchQueue.main.async {
                self?.movieRecordingDelegate = nil
                appState.isRecording = false

                switch result {
                case .success(let fileURL):
                    self?.lastCapturedFileURL = fileURL
                    self?.saveMediaToPhotoLibrary(url: fileURL, kind: .video, appState: appState)
                    self?.onMediaCaptured?(fileURL, "video")
                case .failure:
                    appState.lastStatusMessage = "录像失败"
                }
            }
        }

        movieRecordingDelegate = delegate
        movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)
        appState.isRecording = true
        appState.lastStatusMessage = "已开始录像"
    }

    private func stopRecording(appState: VinoAppState) {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        appState.lastStatusMessage = "正在停止录像"
    }

    private static func makeMediaURL(
        fileExtension: String,
        category: String,
        context: RemoteCaptureContext
    ) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let fileName = buildMediaFileName(
            timestamp: formatter.string(from: Date()),
            category: category,
            fileExtension: fileExtension,
            context: context
        )

        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = baseDirectory
            .appendingPathComponent("vino_media", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    private static func buildMediaFileName(
        timestamp: String,
        category: String,
        fileExtension: String,
        context: RemoteCaptureContext
    ) -> String {
        var segments = ["vino", category]

        if !context.productUUID.isEmpty {
            segments.append(sanitizedPathComponent(context.productUUID))
        }

        if context.pointIndex != 0 {
            segments.append(String(format: "pt%03d", context.pointIndex))
        }

        if !context.jobID.isEmpty {
            segments.append(sanitizedPathComponent(context.jobID))
        }

        segments.append(timestamp)
        return segments.joined(separator: "_") + ".\(fileExtension)"
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let raw = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        let collapsed = raw.replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "context" : trimmed
    }

    private func saveMediaToPhotoLibrary(url: URL, kind: SavedMediaKind, appState: VinoAppState) {
        let commitSave: () -> Void = {
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: kind.resourceType, fileURL: url, options: options)
            }) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        switch kind {
                        case .photo:
                            appState.lastStatusMessage = "照片已保存到图库 · \(url.lastPathComponent)"
                        case .video:
                            appState.lastStatusMessage = "视频已保存到图库 · \(url.lastPathComponent)"
                        }
                    } else {
                        switch kind {
                        case .photo:
                            appState.lastStatusMessage = "照片已保存到应用目录，但写入图库失败"
                        case .video:
                            appState.lastStatusMessage = "视频已保存到应用目录，但写入图库失败"
                        }
                    }
                }
            }
        }

        let authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch authorization {
        case .authorized, .limited:
            commitSave()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited {
                    commitSave()
                } else {
                    DispatchQueue.main.async {
                        switch kind {
                        case .photo:
                            appState.lastStatusMessage = "照片已保存到应用目录，图库权限未开启"
                        case .video:
                            appState.lastStatusMessage = "视频已保存到应用目录，图库权限未开启"
                        }
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                switch kind {
                case .photo:
                    appState.lastStatusMessage = "照片已保存到应用目录，图库权限未开启"
                case .video:
                    appState.lastStatusMessage = "视频已保存到应用目录，图库权限未开启"
                }
            }
        }
    }
}

private enum SavedMediaKind {
    case photo
    case video

    var resourceType: PHAssetResourceType {
        switch self {
        case .photo:
            return .photo
        case .video:
            return .video
        }
    }
}

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let outputURL: URL
    private let completion: (Result<(URL, Data), Error>) -> Void

    init(outputURL: URL, completion: @escaping (Result<(URL, Data), Error>) -> Void) {
        self.outputURL = outputURL
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CocoaError(.fileWriteUnknown)))
            return
        }

        do {
            try data.write(to: outputURL, options: .atomic)
            completion(.success((outputURL, data)))
        } catch {
            completion(.failure(error))
        }
    }
}

private final class MovieRecordingProcessor: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let outputURL: URL
    private let completion: (Result<URL, Error>) -> Void

    init(outputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        self.outputURL = outputURL
        self.completion = completion
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        _ = connections
        if let error {
            completion(.failure(error))
            return
        }

        completion(.success(outputURL))
    }
}

private final class SampleBufferProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onPixelBuffer: (CVPixelBuffer) -> Void

    init(onPixelBuffer: @escaping (CVPixelBuffer) -> Void) {
        self.onPixelBuffer = onPixelBuffer
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        onPixelBuffer(pixelBuffer)
    }
}
