import CoreGraphics
import Foundation

struct AppleDiffusionModelInfo: Equatable, Sendable {
    let pipelineName: String
    let width: Int
    let height: Int
    let supportsImageToImage: Bool
}

struct AppleDiffusionRequest: Equatable, Sendable {
    let prompt: String
    let negativePrompt: String
    let seed: UInt32
    let stepCount: Int
    let guidanceScale: Float
}

struct AppleDiffusionResult: Sendable {
    let image: CGImage
    let durationSeconds: Double
}

protocol AppleDiffusionGenerating: Sendable {
    func loadPipeline(at url: URL) async throws -> AppleDiffusionModelInfo
    func generate(_ request: AppleDiffusionRequest) async throws -> AppleDiffusionResult
}
