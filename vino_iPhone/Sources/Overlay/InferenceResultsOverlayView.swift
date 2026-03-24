import SwiftUI
import Vision

public struct InferenceResultsOverlayView: View {
    public let detections: [InferenceDetection]

    public init(detections: [InferenceDetection]) {
        self.detections = detections
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(detections) { detection in
                    if let boundingBox = detection.boundingBox {
                        let rect = Self.rect(for: boundingBox, in: geometry.size)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(VinoTheme.accent, lineWidth: 1.6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(VinoTheme.accent.opacity(0.08))
                                )
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)

                            Text("\(detection.modelName) · \(detection.label) · \(String(format: "%.2f", detection.confidence))")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(VinoTheme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .position(
                                    x: max(rect.minX + 80, 80),
                                    y: max(rect.minY - 12, 12)
                                )
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func rect(for normalizedRect: CGRect, in size: CGSize) -> CGRect {
        let converted = VNImageRectForNormalizedRect(
            normalizedRect,
            Int(size.width),
            Int(size.height)
        )

        return CGRect(
            x: converted.origin.x,
            y: size.height - converted.origin.y - converted.size.height,
            width: converted.size.width,
            height: converted.size.height
        )
    }
}
