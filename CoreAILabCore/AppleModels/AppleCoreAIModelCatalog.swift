import Foundation

enum AppleCoreAIModelCatalog {
    static func load(bundle: Bundle = .main) throws -> AppleCoreAIModelCatalogDocument {
        guard let url = resourceURL(in: bundle) else {
            throw AppleCoreAIModelCatalogError.missingResource
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> AppleCoreAIModelCatalogDocument {
        try JSONDecoder().decode(AppleCoreAIModelCatalogDocument.self, from: data)
    }

    private static func resourceURL(in bundle: Bundle) -> URL? {
        bundle.url(
            forResource: "apple-coreai-models",
            withExtension: "json",
            subdirectory: "AppleModels"
        ) ?? bundle.url(
            forResource: "apple-coreai-models",
            withExtension: "json"
        )
    }
}
