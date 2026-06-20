import Foundation

struct CoreAIConversionProcessResult: Sendable {
    let exitCode: Int32
    let duration: Duration
    let artifacts: [CoreAIConversionArtifact]
    let logURL: URL
}
