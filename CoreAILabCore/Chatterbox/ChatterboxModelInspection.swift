import Foundation

struct ChatterboxAssetInspection: Identifiable, Sendable, Equatable {
    let stage: ChatterboxPipelineStage
    let sourceURL: URL
    let functionNames: [String]
    let sizeInBytes: Int64

    var id: ChatterboxPipelineStage {
        stage
    }

    var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: sizeInBytes,
            countStyle: .file
        )
    }
}

struct ChatterboxModelInspection: Sendable, Equatable {
    let assets: [ChatterboxAssetInspection]
    let author: String
    let license: String
    let deviceArchitectureName: String
    let contractValidation: ChatterboxContractValidation

    var totalSizeInBytes: Int64 {
        assets.reduce(0) { $0 + $1.sizeInBytes }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(
            fromByteCount: totalSizeInBytes,
            countStyle: .file
        )
    }

    var totalFunctionCount: Int {
        assets.reduce(0) { $0 + $1.functionNames.count }
    }
}
