import Foundation

struct CoreAISwiftInvocationGenerator: Sendable {
    struct Output: Equatable, Sendable {
        let typeName: String
        let fileName: String
        let source: String
    }

    func generate(
        assetName: String,
        contracts: [CoreAIFunctionContract],
        specializationConfiguration: CoreAISpecializationConfiguration = .init(
            profile: .automatic
        )
    ) -> Output {
        let typeName = typeIdentifier(for: assetName) + "CoreAIModel"
        let errorTypeName = typeName + "Error"
        let supported = contracts
            .filter(\.supportsGeneratedRuntime)
            .sorted { $0.name < $1.name }
        let methods = methodIdentifiers(for: supported.map(\.name))
        let methodSource = supported.map { contract in
            let methodName = methods[contract.name] ?? "runFunction"
            return """
                public func \(methodName)(inputs: [String: NDArray]) async throws -> InferenceFunction.Outputs {
                    guard let function = try model.loadFunction(named: \(swiftLiteral(contract.name))) else {
                        throw \(errorTypeName).functionUnavailable(\(swiftLiteral(contract.name)))
                    }
                    return try await function.run(inputs: inputs)
                }
            """
        }.joined(separator: "\n\n")

        let source = """
            import CoreAI
            import Foundation

            public enum \(errorTypeName): LocalizedError {
                case functionUnavailable(String)

                public var errorDescription: String? {
                    switch self {
                    case .functionUnavailable(let name):
                        "Core AI function \\(name) is unavailable."
                    }
                }
            }

            public actor \(typeName) {
                private let model: AIModel

                private static var defaultSpecializationOptions: SpecializationOptions {
                    var options = \(specializationExpression(specializationConfiguration.profile))
                    options.expectFrequentReshapes = \(specializationConfiguration.expectFrequentReshapes)
                    return options
                }

                private init(model: AIModel) {
                    self.model = model
                }

                public static func load(
                    from modelURL: URL,
                    options: SpecializationOptions? = nil,
                    cache: AIModelCache = .default,
                    cachePolicy: AIModelCache.Policy = .default
                ) async throws -> \(typeName) {
                    let model = try await AIModel.specialize(
                        contentsOf: modelURL,
                        options: options ?? defaultSpecializationOptions,
                        cache: cache,
                        cachePolicy: cachePolicy
                    )
                    return \(typeName)(model: model)
                }

            \(indent(methodSource, spaces: 4))
            }
            """

        return Output(
            typeName: typeName,
            fileName: "\(typeName).swift",
            source: source + "\n"
        )
    }

    func typeIdentifier(for value: String) -> String {
        let words = asciiWords(in: (value as NSString).deletingPathExtension)
        var identifier = words.map(capitalizedASCII).joined()
        if identifier.isEmpty {
            identifier = "Model"
        }
        if identifier.first?.isNumber == true {
            identifier = "Model" + identifier
        }
        if Self.reservedWords.contains(identifier) {
            identifier += "Model"
        }
        return identifier
    }

    func methodIdentifiers(for functionNames: [String]) -> [String: String] {
        var counts: [String: Int] = [:]
        var result: [String: String] = [:]
        for name in functionNames.sorted() {
            let words = asciiWords(in: name)
            var base: String
            if let first = words.first {
                base = first.lowercased() + words.dropFirst().map(capitalizedASCII).joined()
            } else {
                base = "runFunction"
            }
            if base.first?.isNumber == true || Self.reservedWords.contains(base) {
                base = "run" + capitalizedASCII(base)
            }
            let count = (counts[base] ?? 0) + 1
            counts[base] = count
            result[name] = count == 1 ? base : "\(base)_\(count)"
        }
        return result
    }

    private func asciiWords(in value: String) -> [String] {
        value.unicodeScalars.split { scalar in
            !((65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value))
        }.map(String.init)
    }

    private func capitalizedASCII(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
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

    private func indent(_ value: String, spaces: Int) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : prefix + $0 }
            .joined(separator: "\n")
    }

    private func specializationExpression(_ profile: CoreAISpecializationProfile) -> String {
        switch profile {
        case .automatic:
            ".default"
        case .cpuOnly:
            ".cpuOnly"
        case .preferGPU:
            "SpecializationOptions(preferredComputeUnitKind: .gpu)"
        case .preferNeuralEngine:
            "SpecializationOptions(preferredComputeUnitKind: .neuralEngine)"
        }
    }

    private static let reservedWords: Set<String> = [
        "actor", "associatedtype", "as", "break", "case", "catch", "class",
        "continue", "default", "defer", "deinit", "do", "else", "enum",
        "extension", "fallthrough", "false", "fileprivate", "for", "func",
        "guard", "if", "import", "in", "init", "inout", "internal", "is",
        "any", "borrowing", "consuming", "convenience", "didSet", "distributed",
        "dynamic", "get", "indirect", "infix", "isolated", "lazy", "let", "macro",
        "mutating", "nil", "nonisolated", "nonmutating", "open", "operator",
        "optional", "override", "package", "postfix", "precedencegroup", "prefix",
        "private", "protocol", "public", "repeat", "required", "rethrows", "return",
        "self", "Self", "sending", "set", "some", "static", "struct", "subscript",
        "super", "switch", "throw", "throws", "true", "try", "typealias", "var",
        "weak", "where", "while", "willSet",
    ]
}
