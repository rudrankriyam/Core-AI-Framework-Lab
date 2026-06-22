import CryptoKit
import Foundation

struct CoreAIConversionJobRequestIdentity: Codable, Equatable, Sendable {
    let modelIdentifier: String
    let modelName: String
    let executablePath: String
    let arguments: [String]
    let workingDirectoryPath: String
    let outputDirectoryPath: String

    init(modelIdentifier: String, request: CoreAIConversionRequest) throws {
        try self.init(
            modelIdentifier: modelIdentifier,
            modelName: request.modelName,
            executablePath: request.command.executableURL.standardizedFileURL.path,
            arguments: request.command.arguments,
            workingDirectoryPath: request.command.workingDirectoryURL.standardizedFileURL.path,
            outputDirectoryPath: request.outputDirectoryURL.standardizedFileURL.path
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            modelIdentifier: container.decode(String.self, forKey: .modelIdentifier),
            modelName: container.decode(String.self, forKey: .modelName),
            executablePath: container.decode(String.self, forKey: .executablePath),
            arguments: container.decode([String].self, forKey: .arguments),
            workingDirectoryPath: container.decode(String.self, forKey: .workingDirectoryPath),
            outputDirectoryPath: container.decode(String.self, forKey: .outputDirectoryPath)
        )
    }

    private init(
        modelIdentifier: String,
        modelName: String,
        executablePath: String,
        arguments: [String],
        workingDirectoryPath: String,
        outputDirectoryPath: String
    ) throws {
        guard !modelIdentifier.isEmpty, !modelName.isEmpty else {
            throw CoreAIConversionJobStoreError.incompleteIdentity("model")
        }
        guard executablePath.hasPrefix("/"),
              workingDirectoryPath.hasPrefix("/"),
              outputDirectoryPath.hasPrefix("/") else {
            throw CoreAIConversionJobStoreError.incompleteIdentity("absolute command path")
        }
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectoryPath = workingDirectoryPath
        self.outputDirectoryPath = outputDirectoryPath
    }

    private enum CodingKeys: String, CodingKey {
        case modelIdentifier
        case modelName
        case executablePath
        case arguments
        case workingDirectoryPath
        case outputDirectoryPath
    }
}

struct CoreAIConversionEnvironmentIdentity: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let xcodeBuildVersion: String
    let sdkBuildVersion: String
    let recipeRepositoryRevision: String
    let sourceTreeSHA256: String
    let lockfileSHA256: String
    let executableSHA256: String
    let executableVersion: String
    let relevantEnvironment: [String: String]

    init(
        xcodeBuildVersion: String,
        sdkBuildVersion: String,
        recipeRepositoryRevision: String,
        sourceTreeSHA256: String,
        lockfileSHA256: String,
        executableSHA256: String,
        executableVersion: String,
        relevantEnvironment: [String: String]
    ) throws {
        guard !xcodeBuildVersion.isEmpty else {
            throw CoreAIConversionJobStoreError.incompleteIdentity("Xcode build")
        }
        guard !sdkBuildVersion.isEmpty else {
            throw CoreAIConversionJobStoreError.incompleteIdentity("SDK build")
        }
        guard recipeRepositoryRevision.utf8.count >= 40 else {
            throw CoreAIConversionJobStoreError.incompleteIdentity("recipe revision")
        }
        for (name, digest) in [
            ("source tree", sourceTreeSHA256),
            ("lockfile", lockfileSHA256),
            ("executable", executableSHA256),
        ] where !Self.isSHA256(digest) {
            throw CoreAIConversionJobStoreError.incompleteIdentity("\(name) digest")
        }
        guard !executableVersion.isEmpty else {
            throw CoreAIConversionJobStoreError.incompleteIdentity("executable version")
        }
        guard relevantEnvironment.keys.allSatisfy({ !$0.isEmpty }) else {
            throw CoreAIConversionJobStoreError.incompleteIdentity("environment key")
        }

        schemaVersion = Self.currentSchemaVersion
        self.xcodeBuildVersion = xcodeBuildVersion
        self.sdkBuildVersion = sdkBuildVersion
        self.recipeRepositoryRevision = recipeRepositoryRevision
        self.sourceTreeSHA256 = sourceTreeSHA256.lowercased()
        self.lockfileSHA256 = lockfileSHA256.lowercased()
        self.executableSHA256 = executableSHA256.lowercased()
        self.executableVersion = executableVersion
        self.relevantEnvironment = relevantEnvironment
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoreAIConversionJobStoreError.unsupportedSchema(schemaVersion)
        }
        try self.init(
            xcodeBuildVersion: container.decode(String.self, forKey: .xcodeBuildVersion),
            sdkBuildVersion: container.decode(String.self, forKey: .sdkBuildVersion),
            recipeRepositoryRevision: container.decode(
                String.self,
                forKey: .recipeRepositoryRevision
            ),
            sourceTreeSHA256: container.decode(String.self, forKey: .sourceTreeSHA256),
            lockfileSHA256: container.decode(String.self, forKey: .lockfileSHA256),
            executableSHA256: container.decode(String.self, forKey: .executableSHA256),
            executableVersion: container.decode(String.self, forKey: .executableVersion),
            relevantEnvironment: container.decode(
                [String: String].self,
                forKey: .relevantEnvironment
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case xcodeBuildVersion
        case sdkBuildVersion
        case recipeRepositoryRevision
        case sourceTreeSHA256
        case lockfileSHA256
        case executableSHA256
        case executableVersion
        case relevantEnvironment
    }

    private static func isSHA256(_ value: String) -> Bool {
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return value.utf8.count == 64
            && value.unicodeScalars.allSatisfy(hexadecimal.contains)
    }
}

struct CoreAIConversionJobIdentity: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let request: CoreAIConversionJobRequestIdentity
    let environment: CoreAIConversionEnvironmentIdentity

    init(
        request: CoreAIConversionJobRequestIdentity,
        environment: CoreAIConversionEnvironmentIdentity
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.request = request
        self.environment = environment
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CoreAIConversionJobStoreError.unsupportedSchema(schemaVersion)
        }
        self.init(
            request: try container.decode(CoreAIConversionJobRequestIdentity.self, forKey: .request),
            environment: try container.decode(
                CoreAIConversionEnvironmentIdentity.self,
                forKey: .environment
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case request
        case environment
    }

    var fingerprint: CoreAIConversionJobFingerprint {
        CoreAIConversionJobFingerprint(
            requestSHA256: Self.digest(
                [
                    "coreai-conversion-request-v1",
                    request.modelIdentifier,
                    request.modelName,
                    request.executablePath,
                    String(request.arguments.count),
                ] + request.arguments + [
                    request.workingDirectoryPath,
                    request.outputDirectoryPath,
                ]
            ),
            environmentSHA256: Self.digest(
                [
                    "coreai-conversion-environment-v\(environment.schemaVersion)",
                    environment.xcodeBuildVersion,
                    environment.sdkBuildVersion,
                    environment.recipeRepositoryRevision,
                    environment.sourceTreeSHA256,
                    environment.lockfileSHA256,
                    environment.executableSHA256,
                    environment.executableVersion,
                    String(environment.relevantEnvironment.count),
                ] + environment.relevantEnvironment.keys.sorted(by: Self.utf8Precedes).flatMap { key in
                    [key, environment.relevantEnvironment[key] ?? ""]
                }
            )
        )
    }

    private static func digest(_ components: [String]) -> String {
        var hasher = SHA256()
        for component in components {
            let data = Data(component.utf8)
            hasher.update(data: Data("\(data.count):".utf8))
            hasher.update(data: data)
        }
        return CoreAIHexadecimal.lowercase(hasher.finalize())
    }

    private static func utf8Precedes(_ first: String, _ second: String) -> Bool {
        Array(first.utf8).lexicographicallyPrecedes(Array(second.utf8))
    }
}

struct CoreAIConversionJobFingerprint: Codable, Equatable, Sendable {
    let requestSHA256: String
    let environmentSHA256: String

    init(requestSHA256: String, environmentSHA256: String) {
        self.requestSHA256 = requestSHA256
        self.environmentSHA256 = environmentSHA256
    }
}
