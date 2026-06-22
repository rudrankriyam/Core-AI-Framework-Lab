import Foundation

struct CoreAICapacityManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let maximumInputTokens: Int?
    let maximumGeneratedTokens: Int?
    let maximumContextTokens: Int?
    let requiresStopSignal: Bool
    let parameters: [String: Int]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        maximumInputTokens: Int? = nil,
        maximumGeneratedTokens: Int? = nil,
        maximumContextTokens: Int? = nil,
        requiresStopSignal: Bool = false,
        parameters: [String: Int] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.maximumInputTokens = maximumInputTokens
        self.maximumGeneratedTokens = maximumGeneratedTokens
        self.maximumContextTokens = maximumContextTokens
        self.requiresStopSignal = requiresStopSignal
        self.parameters = parameters
    }

    func validate(path: String = "capacity") throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "\(path).schemaVersion"
        )
        try validatePositive(maximumInputTokens, path: "\(path).maximumInputTokens")
        try validatePositive(
            maximumGeneratedTokens,
            path: "\(path).maximumGeneratedTokens"
        )
        try validatePositive(
            maximumContextTokens,
            path: "\(path).maximumContextTokens"
        )
        if let maximumInputTokens,
           let maximumContextTokens,
           maximumInputTokens >= maximumContextTokens {
            throw CoreAIManifestValidationError.invalidValue(
                path: "\(path).maximumInputTokens",
                reason: "it must be lower than maximumContextTokens"
            )
        }
        for (name, value) in parameters {
            try CoreAIManifestValidator.requireNonempty(
                name,
                path: "\(path).parameters.key"
            )
            guard value >= 0 else {
                throw CoreAIManifestValidationError.invalidValue(
                    path: "\(path).parameters.\(name)",
                    reason: "it must be zero or greater"
                )
            }
        }
    }

    func requiredParameter(named name: String, path: String = "capacity") throws -> Int {
        guard let value = parameters[name] else {
            throw CoreAIManifestValidationError.missingValue(
                path: "\(path).parameters.\(name)"
            )
        }
        return value
    }

    private func validatePositive(_ value: Int?, path: String) throws {
        guard let value else { return }
        guard value > 0 else {
            throw CoreAIManifestValidationError.invalidValue(
                path: path,
                reason: "it must be greater than zero"
            )
        }
    }
}
