import CoreAIObjectDetector
import CoreGraphics
import Foundation

protocol AppleObjectDetecting: Sendable {
    func loadModel(at url: URL) async throws
    func detect(in image: CGImage) async throws -> [AppleObjectDetection]
}

actor AppleObjectDetectorEngine: AppleObjectDetecting {
    private var detector: SendableObjectDetector?

    func loadModel(at url: URL) async throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        detector = SendableObjectDetector(
            value: try await ObjectDetector(resourcesAt: url.path)
        )
    }

    func detect(in image: CGImage) async throws -> [AppleObjectDetection] {
        guard let detector else {
            throw AppleObjectDetectionError.modelNotLoaded
        }
        return try await detector.value.detect(image: image).enumerated().map { index, detection in
            AppleObjectDetection(
                id: index,
                boundingBox: detection.boundingBox,
                label: detection.label,
                confidence: detection.confidence
            )
        }
    }
}

// ObjectDetector is a value wrapper around Core AI runtime handles, and its
// inference function supports concurrent calls. Keep that unchecked boundary
// local instead of adding a retroactive conformance to Apple's public type.
private struct SendableObjectDetector: @unchecked Sendable {
    let value: ObjectDetector
}
