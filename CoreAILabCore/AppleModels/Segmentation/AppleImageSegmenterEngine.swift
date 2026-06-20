import CoreAIImageSegmenter
import CoreGraphics
import Foundation

protocol AppleImageSegmenting: Sendable {
    func loadModel(at url: URL) async throws
    func segment(
        image: CGImage,
        query: AppleSegmentationQuery
    ) async throws -> AppleSegmentationResult
}

actor AppleImageSegmenterEngine: AppleImageSegmenting {
    private var segmenter: SendableImageSegmenter?

    func loadModel(at url: URL) async throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let loaded = try await ImageSegmenter(resourcesAt: url.path)
        segmenter = SendableImageSegmenter(value: loaded)
    }

    func segment(
        image: CGImage,
        query: AppleSegmentationQuery
    ) async throws -> AppleSegmentationResult {
        guard let segmenter else {
            throw AppleSegmentationError.modelNotLoaded
        }

        let response: SegmentationResponse
        switch query {
        case .point(let x, let y):
            response = try await segmenter.value.segment(
                image: image,
                pointQuery: PointQuery(
                    points: [.init(x: x, y: y, label: .foreground)]
                )
            )
        case .text(let prompt):
            response = try await segmenter.value.segment(
                image: image,
                prompt: prompt
            )
        }

        var renderedImage = image
        if let probabilityMap = response.probabilityMap,
           let semanticOverlay = SegmentationVisualization.renderSemanticOverlay(
               onto: renderedImage,
               map: probabilityMap
           ) {
            renderedImage = semanticOverlay
        }
        if let instanceOverlay = SegmentationVisualization.renderInstanceMasks(
            onto: renderedImage,
            segments: response.segments
        ) {
            renderedImage = instanceOverlay
        }

        return AppleSegmentationResult(
            renderedImage: renderedImage,
            segmentCount: response.segments.count,
            scores: response.segments.map(\.score)
        )
    }
}

private struct SendableImageSegmenter: @unchecked Sendable {
    let value: ImageSegmenter
}
