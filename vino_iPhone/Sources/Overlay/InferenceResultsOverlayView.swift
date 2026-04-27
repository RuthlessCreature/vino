import SwiftUI
import Vision

public struct InferenceResultsOverlayView: View {
    public let detections: [InferenceDetection]
    public let imageSize: CGSize?

    public init(detections: [InferenceDetection], imageSize: CGSize? = nil) {
        self.detections = detections
        self.imageSize = imageSize
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(detections) { detection in
                    if let boundingBox = detection.boundingBox {
                        let rect = Self.rect(for: boundingBox, in: geometry.size, imageSize: imageSize)

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

    private static func rect(for normalizedRect: CGRect, in size: CGSize, imageSize: CGSize?) -> CGRect {
        let sourceSize = displayImageSize(for: imageSize, viewportSize: size)
        let converted = VNImageRectForNormalizedRect(
            normalizedRect,
            Int(sourceSize.width),
            Int(sourceSize.height)
        )

        let flippedRect = CGRect(
            x: converted.origin.x,
            y: sourceSize.height - converted.origin.y - converted.size.height,
            width: converted.size.width,
            height: converted.size.height
        )

        let scale = max(size.width / sourceSize.width, size.height / sourceSize.height)
        let scaledWidth = sourceSize.width * scale
        let scaledHeight = sourceSize.height * scale
        let offsetX = (size.width - scaledWidth) * 0.5
        let offsetY = (size.height - scaledHeight) * 0.5

        return CGRect(
            x: flippedRect.origin.x * scale + offsetX,
            y: flippedRect.origin.y * scale + offsetY,
            width: flippedRect.width * scale,
            height: flippedRect.height * scale
        )
    }

    private static func displayImageSize(for rawImageSize: CGSize?, viewportSize: CGSize) -> CGSize {
        guard let rawImageSize, rawImageSize.width > 0, rawImageSize.height > 0 else {
            return viewportSize
        }

        if rawImageSize.width > rawImageSize.height {
            return CGSize(width: rawImageSize.height, height: rawImageSize.width)
        }

        return rawImageSize
    }
}
