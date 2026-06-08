import CoreAI
import Foundation

struct CoreAIModelAssetReport: Sendable, Equatable {
    let url: URL
    let isValid: Bool
    let author: String
    let license: String
    let description: String
    let functionNames: [String]
    let computeTypes: [String]
}

enum CoreAIModelAssetInspector {
    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func inspect(url: URL, includingStatistics: Bool = false) throws -> CoreAIModelAssetReport {
        let isValid = AIModelAsset.isValid(at: url)
        let asset = try AIModelAsset(contentsOf: url)
        let summary = try asset.summary(includingStatistics: includingStatistics)

        return CoreAIModelAssetReport(
            url: url,
            isValid: isValid,
            author: asset.metadata.author,
            license: asset.metadata.license,
            description: asset.metadata.description,
            functionNames: summary?.functions.map(\.name) ?? [],
            computeTypes: summary?.computeTypes ?? []
        )
    }
}

