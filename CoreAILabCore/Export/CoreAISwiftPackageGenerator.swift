import Foundation

struct CoreAISwiftPackageGenerator: Sendable {
    static let swiftToolsVersion = "6.4"

    struct Output: Equatable, Sendable {
        let packageManifest: String
        let resourceAccessorFileName: String
        let resourceAccessorSource: String
    }

    func generate(
        packageName: String,
        targetName: String,
        modelTypeName: String,
        assetName: String
    ) -> Output {
        let packageManifest = """
            // swift-tools-version: \(Self.swiftToolsVersion)
            import PackageDescription

            let package = Package(
                name: \(swiftLiteral(packageName)),
                platforms: [
                    .iOS(.v27),
                    .macOS(.v27),
                ],
                products: [
                    .library(
                        name: \(swiftLiteral(packageName)),
                        targets: [\(swiftLiteral(targetName))]
                    ),
                ],
                targets: [
                    .target(
                        name: \(swiftLiteral(targetName)),
                        resources: [.copy("Resources")]
                    ),
                ]
            )
            """ + "\n"

        let resourcesTypeName = modelTypeName + "Resources"
        let resourcesErrorTypeName = resourcesTypeName + "Error"
        let resourceAccessorSource = """
            import CoreAI
            import Foundation

            public enum \(resourcesErrorTypeName): LocalizedError, Sendable {
                case resourceBundleUnavailable
                case bundledAssetUnavailable(String)

                public var errorDescription: String? {
                    switch self {
                    case .resourceBundleUnavailable:
                        "The generated integration resource bundle is unavailable."
                    case .bundledAssetUnavailable(let name):
                        "The bundled Core AI asset \\(name) is unavailable."
                    }
                }
            }

            public enum \(resourcesTypeName) {
                public static let assetRelativePath = \(swiftLiteral("Resources/" + assetName))

                public static func modelURL() throws -> URL {
                    guard let resourceRoot = Bundle.module.resourceURL else {
                        throw \(resourcesErrorTypeName).resourceBundleUnavailable
                    }
                    let modelURL = resourceRoot.appending(path: assetRelativePath)
                    let values = try modelURL.resourceValues(
                        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                    )
                    guard values.isDirectory == true, values.isSymbolicLink != true else {
                        throw \(resourcesErrorTypeName).bundledAssetUnavailable(\(swiftLiteral(assetName)))
                    }
                    return modelURL
                }
            }

            public extension \(modelTypeName) {
                static func loadBundled(
                    options: SpecializationOptions? = nil,
                    cache: AIModelCache = .default,
                    cachePolicy: AIModelCache.Policy = .default
                ) async throws -> \(modelTypeName) {
                    try await load(
                        from: \(resourcesTypeName).modelURL(),
                        options: options,
                        cache: cache,
                        cachePolicy: cachePolicy
                    )
                }
            }
            """ + "\n"

        return Output(
            packageManifest: packageManifest,
            resourceAccessorFileName: resourcesTypeName + ".swift",
            resourceAccessorSource: resourceAccessorSource
        )
    }

    private func swiftLiteral(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: output += "\\\""
            case 0x5C: output += "\\\\"
            case 0x0A: output += "\\n"
            case 0x0D: output += "\\r"
            case 0x09: output += "\\t"
            case 0x00...0x1F, 0x7F:
                output += "\\u{\(String(scalar.value, radix: 16))}"
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
