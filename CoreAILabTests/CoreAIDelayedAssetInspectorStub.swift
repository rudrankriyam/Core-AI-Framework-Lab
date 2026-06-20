import Foundation
@testable import CoreAILab

actor CoreAIDelayedAssetInspectorStub: CoreAIAssetInspecting {
    func inspect(url: URL) async throws -> CoreAIModelAssetReport {
        if url.lastPathComponent == "invalid.aimodel" {
            throw CocoaError(.fileReadCorruptFile)
        }
        if url.lastPathComponent == "slow.aimodel" {
            try await Task.sleep(for: .milliseconds(100))
        }
        return CoreAIModelAssetReport(
            url: url,
            isValid: true,
            author: "Core AI Lab",
            license: "MIT",
            description: "Fixture",
            functionNames: ["main"],
            computeTypes: ["float32"]
        )
    }
}
