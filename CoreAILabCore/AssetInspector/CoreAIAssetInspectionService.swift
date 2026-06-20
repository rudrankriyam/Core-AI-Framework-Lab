import Foundation

protocol CoreAIAssetInspecting: Sendable {
    func inspect(url: URL) async throws -> CoreAIModelAssetReport
}

actor CoreAIAssetInspectionService: CoreAIAssetInspecting {
    func inspect(url: URL) async throws -> CoreAIModelAssetReport {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try CoreAIModelAssetInspector.inspect(
            url: url,
            includingStatistics: true
        )
    }
}
