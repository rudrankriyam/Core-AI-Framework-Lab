import Foundation

actor CoreAIAssetInspectionService {
    func inspect(url: URL) throws -> CoreAIModelAssetReport {
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
