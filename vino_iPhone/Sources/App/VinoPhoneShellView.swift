import SwiftUI
import CoreImage
import UIKit

public struct VinoPhoneShellView: View {
    @StateObject private var appState = VinoAppState()
    @StateObject private var cameraController = CameraSessionController()
    @StateObject private var ipMonitor = IPAddressMonitor()
    @StateObject private var controlPlane = ControlPlaneCoordinator()
    @StateObject private var inferenceRuntime = InferenceRuntime()
    @State private var previewMirrorRelay = PreviewFrameRelay()

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
                    previewMirrorRelay: previewMirrorRelay,
                    onSyncStatus: syncStatus
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
                controlPlane: controlPlane
            )
        }
    }

    private func syncStatus() {
        controlPlane.publishStatus(
            appState: appState,
            settings: cameraController.settings,
            ipAddresses: ipMonitor.addresses
        )
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
    private let minInterval: CFAbsoluteTime = 0.35
    private let maxDimension: CGFloat = 480
    private let jpegQuality: CGFloat = 0.42

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
    let previewMirrorRelay: PreviewFrameRelay
    let onSyncStatus: () -> Void

    func body(content: Content) -> some View {
        content
            .task {
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
