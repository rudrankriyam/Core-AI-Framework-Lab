import UniformTypeIdentifiers

extension UTType {
    static let coreAIModelAsset = UTType(
        filenameExtension: "aimodel",
        conformingTo: .package
    ) ?? .package
}
