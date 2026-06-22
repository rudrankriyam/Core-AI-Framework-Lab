import Foundation

struct CoreAIBenchmarkToolchain: Codable, Sendable, Equatable {
    let xcodeVersionCode: String?
    let xcodeBuild: String?
    let sdkName: String?
    let sdkBuild: String?
    let compilerIdentifier: String?
    let swiftCompilerVersionConstraint: String
    let swiftLanguageMode: String

    static var current: Self {
        let metadata = Bundle.main.infoDictionary ?? [:]
        return Self(
            xcodeVersionCode: value(for: "DTXcode", in: metadata),
            xcodeBuild: value(for: "DTXcodeBuild", in: metadata),
            sdkName: value(for: "DTSDKName", in: metadata),
            sdkBuild: value(for: "DTSDKBuild", in: metadata),
            compilerIdentifier: value(for: "DTCompiler", in: metadata),
            swiftCompilerVersionConstraint: compilerVersionConstraint,
            swiftLanguageMode: "6"
        )
    }

    private static var compilerVersionConstraint: String {
        #if compiler(>=6.4)
        ">=6.4"
        #elseif compiler(>=6.3)
        ">=6.3,<6.4"
        #elseif compiler(>=6.2)
        ">=6.2,<6.3"
        #else
        "<6.2"
        #endif
    }

    private static func value(
        for key: String,
        in metadata: [String: Any]
    ) -> String? {
        switch metadata[key] {
        case let value as String where !value.isEmpty:
            value
        case let value as NSNumber:
            value.stringValue
        default:
            nil
        }
    }
}
