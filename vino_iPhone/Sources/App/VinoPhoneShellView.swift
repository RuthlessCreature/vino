import SwiftUI
import CoreImage
import AVFoundation
import MediaPlayer
import UIKit

public struct VinoPhoneShellView: View {
    @StateObject private var appState = VinoAppState()
    @StateObject private var cameraController = CameraSessionController()
    @StateObject private var ipMonitor = IPAddressMonitor()
    @StateObject private var controlPlane = ControlPlaneCoordinator()
    @StateObject private var inferenceRuntime = InferenceRuntime()
    @StateObject private var volumeButtonMonitor = VolumeButtonMonitor()
    @State private var previewMirrorRelay = PreviewFrameRelay()
    @State private var isTopGridVisible = false
    @State private var isControlDeckVisible = false

    public init() {}

    public var body: some View {
        contentView
    }

    private var contentView: some View {
        layeredPreview
            .background(VinoTheme.background)
            .modifier(
                VinoRuntimeLifecycleModifier(
                    appState: appState,
                    cameraController: cameraController,
                    ipMonitor: ipMonitor,
                    controlPlane: controlPlane,
                    inferenceRuntime: inferenceRuntime,
                    volumeButtonMonitor: volumeButtonMonitor,
                    previewMirrorRelay: previewMirrorRelay,
                    onSyncStatus: syncStatus,
                    onToggleTopGrid: toggleTopGrid,
                    onToggleControlDeck: toggleControlDeck
                )
            )
            .modifier(
                VinoCameraObserverModifier(
                    appState: appState,
                    cameraController: cameraController,
                    ipMonitor: ipMonitor,
                    controlPlane: controlPlane,
                    onSyncStatus: syncStatus
                )
            )
            .modifier(
                VinoRuntimeStateObserverModifier(
                    appState: appState,
                    controlPlane: controlPlane,
                    inferenceRuntime: inferenceRuntime,
                    onSyncStatus: syncStatus
                )
            )
            .modifier(
                VinoStatusPulseObserverModifier(
                    appState: appState,
                    onSyncStatus: syncStatus
                )
            )
    }

    private var layeredPreview: some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewView(session: cameraController.session)
                .ignoresSafeArea()

            InferenceResultsOverlayView(detections: inferenceRuntime.latestDetections)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.38), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            CameraOverlayView(
                appState: appState,
                cameraController: cameraController,
                ipAddresses: ipMonitor.addresses,
                controlPlane: controlPlane,
                isTopGridVisible: $isTopGridVisible,
                isControlDeckVisible: $isControlDeckVisible
            )

            HiddenSystemVolumeCaptureView(monitor: volumeButtonMonitor)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
    }

    private func syncStatus() {
        controlPlane.publishStatus(
            appState: appState,
            settings: cameraController.settings,
            ipAddresses: ipMonitor.addresses
        )
    }

    private func toggleControlDeck() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isControlDeckVisible.toggle()
        }
    }

    private func toggleTopGrid() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isTopGridVisible.toggle()
        }
    }
}

#Preview {
    VinoPhoneShellView()
}

private struct PreviewFramePacket {
    var jpegData: Data
    var imageWidth: Int
    var imageHeight: Int
    var frameIndex: Int
}

private final class PreviewFrameRelay {
    private let context = CIContext()
    private var lastFrameSentAt: CFAbsoluteTime = 0
    private var frameIndex = 0
    private let minInterval: CFAbsoluteTime = 0.1
    private let maxDimension: CGFloat = 360
    private let jpegQuality: CGFloat = 0.32

    func makePacket(pixelBuffer: CVPixelBuffer) -> PreviewFramePacket? {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameSentAt >= minInterval else { return nil }
        lastFrameSentAt = now

        let sourceWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let scale = min(1.0, maxDimension / max(sourceWidth, sourceHeight))
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if scale < 0.999 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let extent = image.extent.integral
        guard let cgImage = context.createCGImage(image, from: extent) else { return nil }
        guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality) else { return nil }

        frameIndex += 1
        return PreviewFramePacket(
            jpegData: jpegData,
            imageWidth: Int(extent.width),
            imageHeight: Int(extent.height),
            frameIndex: frameIndex
        )
    }
}

private struct VinoRuntimeLifecycleModifier: ViewModifier {
    let appState: VinoAppState
    let cameraController: CameraSessionController
    let ipMonitor: IPAddressMonitor
    let controlPlane: ControlPlaneCoordinator
    let inferenceRuntime: InferenceRuntime
    let volumeButtonMonitor: VolumeButtonMonitor
    let previewMirrorRelay: PreviewFrameRelay
    let onSyncStatus: () -> Void
    let onToggleTopGrid: () -> Void
    let onToggleControlDeck: () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                volumeButtonMonitor.start(
                    onVolumeUp: onToggleTopGrid,
                    onVolumeDown: onToggleControlDeck
                )
                ipMonitor.start()
                cameraController.onVideoFrame = { pixelBuffer in
                    guard appState.captureMode == .stream else { return }
                    inferenceRuntime.submit(pixelBuffer: pixelBuffer)
                    if let packet = previewMirrorRelay.makePacket(pixelBuffer: pixelBuffer) {
                        let jpegData = packet.jpegData
                        let imageWidth = packet.imageWidth
                        let imageHeight = packet.imageHeight
                        let frameIndex = packet.frameIndex
                        Task { @MainActor in
                            controlPlane.publishPreviewFrameJPEG(
                                jpegData,
                                imageWidth: imageWidth,
                                imageHeight: imageHeight,
                                frameIndex: frameIndex
                            )
                        }
                    }
                }
                inferenceRuntime.onReportPublished = { report in
                    controlPlane.publishInferenceReport(report)
                }
                inferenceRuntime.setEnabled(appState.inferenceEnabled)
                inferenceRuntime.refreshModels(from: appState.modelCatalog)
                controlPlane.start(
                    appState: appState,
                    cameraController: cameraController,
                    inferenceRuntime: inferenceRuntime
                )
                cameraController.start(appState: appState)
                onSyncStatus()
            }
            .onDisappear {
                volumeButtonMonitor.stop()
                ipMonitor.stop()
                cameraController.stop()
                controlPlane.stop()
            }
    }
}

private struct VinoCameraObserverModifier: ViewModifier {
    let appState: VinoAppState
    let cameraController: CameraSessionController
    let ipMonitor: IPAddressMonitor
    let controlPlane: ControlPlaneCoordinator
    let onSyncStatus: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: ipMonitor.addresses) { _, _ in
                onSyncStatus()
            }
            .onChange(of: cameraController.settings) { _, _ in
                onSyncStatus()
            }
            .onChange(of: cameraController.capabilities) { _, _ in
                controlPlane.broadcastCapabilities()
                onSyncStatus()
            }
            .onChange(of: appState.focusMode) { _, _ in
                cameraController.apply(appState: appState)
                onSyncStatus()
            }
            .onChange(of: appState.selectedLens) { _, lens in
                cameraController.switchLens(to: lens, appState: appState)
                onSyncStatus()
            }
            .onChange(of: appState.flashEnabled) { _, _ in
                cameraController.apply(appState: appState)
                onSyncStatus()
            }
            .onChange(of: appState.smoothAutoFocusEnabled) { _, _ in
                cameraController.apply(appState: appState)
                onSyncStatus()
            }
    }
}

private struct VinoRuntimeStateObserverModifier: ViewModifier {
    let appState: VinoAppState
    let controlPlane: ControlPlaneCoordinator
    let inferenceRuntime: InferenceRuntime
    let onSyncStatus: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.captureMode) { _, _ in
                onSyncStatus()
            }
            .onChange(of: appState.recordingProfile) { _, _ in
                onSyncStatus()
            }
            .onChange(of: appState.inferenceEnabled) { _, _ in
                inferenceRuntime.setEnabled(appState.inferenceEnabled)
                onSyncStatus()
            }
            .onChange(of: appState.modelCatalog) { _, catalog in
                inferenceRuntime.refreshModels(from: catalog)
                controlPlane.broadcastCapabilities()
                onSyncStatus()
            }
            .onChange(of: appState.persistMediaEnabled) { _, _ in
                onSyncStatus()
            }
            .onChange(of: appState.remotePostURL) { _, _ in
                onSyncStatus()
            }
    }
}

private struct VinoStatusPulseObserverModifier: ViewModifier {
    let appState: VinoAppState
    let onSyncStatus: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.lastStatusMessage) { _, _ in
                onSyncStatus()
            }
            .onChange(of: appState.isRecording) { _, _ in
                onSyncStatus()
            }
            .onChange(of: appState.isConnectedToDesktop) { _, _ in
                onSyncStatus()
            }
            .onChange(of: appState.activeContext) { _, _ in
                onSyncStatus()
            }
    }
}

private struct HiddenSystemVolumeCaptureView: UIViewRepresentable {
    let monitor: VolumeButtonMonitor

    func makeUIView(context: Context) -> MPVolumeView {
        monitor.volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private final class VolumeButtonMonitor: ObservableObject {
    let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        return view
    }()

    private var volumeObservation: NSKeyValueObservation?
    private weak var volumeSlider: UISlider?
    private var baselineVolume: Float = 0.55
    private var onVolumeUp: (() -> Void)?
    private var onVolumeDown: (() -> Void)?
    private var isStarted = false
    private var isAdjustingProgrammatically = false

    func start(
        onVolumeUp: @escaping () -> Void,
        onVolumeDown: @escaping () -> Void
    ) {
        self.onVolumeUp = onVolumeUp
        self.onVolumeDown = onVolumeDown
        guard !isStarted else { return }
        isStarted = true

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.ambient, options: [.mixWithOthers])
        try? audioSession.setActive(true)

        refreshVolumeSliderIfNeeded()
        baselineVolume = normalizedVolume(audioSession.outputVolume)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.setSystemVolume(self?.baselineVolume ?? 0.55)
        }

        volumeObservation = audioSession.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            let changedVolume = change.newValue ?? AVAudioSession.sharedInstance().outputVolume
            DispatchQueue.main.async {
                self.handleObservedVolumeChange(changedVolume)
            }
        }
    }

    func stop() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        onVolumeUp = nil
        onVolumeDown = nil
        isStarted = false
    }

    private func handleObservedVolumeChange(_ changedVolume: Float) {
        guard !isAdjustingProgrammatically else { return }
        guard abs(changedVolume - baselineVolume) > 0.0001 else { return }
        let isVolumeUpEvent = changedVolume > baselineVolume

        restoreBaselineVolume()
        if isVolumeUpEvent {
            onVolumeUp?()
        } else {
            onVolumeDown?()
        }
    }

    private func restoreBaselineVolume() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            self.setSystemVolume(self.baselineVolume)
        }
    }

    private func refreshVolumeSliderIfNeeded() {
        if volumeSlider == nil {
            volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
        }
    }

    private func setSystemVolume(_ value: Float) {
        refreshVolumeSliderIfNeeded()
        guard let volumeSlider else { return }

        let clampedValue = normalizedVolume(value)
        isAdjustingProgrammatically = true
        volumeSlider.setValue(clampedValue, animated: false)
        volumeSlider.sendActions(for: .valueChanged)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.isAdjustingProgrammatically = false
        }
    }

    private func normalizedVolume(_ value: Float) -> Float {
        min(max(value, 0.15), 0.85)
    }
}
