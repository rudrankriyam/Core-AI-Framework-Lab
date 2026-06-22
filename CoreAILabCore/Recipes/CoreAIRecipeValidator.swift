import Foundation

enum CoreAIRecipeValidator {
    static func validate(_ recipe: CoreAIRecipeAuthoringManifest) throws {
        let issues = issues(in: recipe)
        guard issues.isEmpty else {
            throw CoreAIRecipeValidationError(issues: issues)
        }
    }

    static func issues(in recipe: CoreAIRecipeAuthoringManifest) -> [CoreAIRecipeValidationIssue] {
        var issues: [CoreAIRecipeValidationIssue] = []
        if recipe.schemaVersion != CoreAIRecipeAuthoringManifest.currentSchemaVersion {
            issues.append(issue(
                .unsupportedSchemaVersion,
                at: "schemaVersion",
                "Recipe schema version \(recipe.schemaVersion) is unsupported."
            ))
        }
        if !isIdentifier(recipe.id) {
            issues.append(issue(.invalidIdentifier, at: "id", "Recipe ID is invalid."))
        }
        if recipe.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.missingValue, at: "displayName", "Recipe name is required."))
        }
        if recipe.source.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.missingValue, at: "source.location", "PyTorch source is required."))
        }
        if recipe.module.modulePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.missingValue, at: "module.modulePath", "Python module path is required."))
        }
        if recipe.module.typeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.missingValue, at: "module.typeName", "PyTorch module type is required."))
        }

        _ = namesAndDuplicateIssues(
            recipe.exampleInputs.map(\.id),
            location: "exampleInputs.id",
            issues: &issues
        )
        let inputNames = namesAndDuplicateIssues(
            recipe.exampleInputs.map(\.name),
            location: "exampleInputs",
            issues: &issues
        )
        for input in recipe.exampleInputs {
            let location = "exampleInputs.\(input.id)"
            if !isIdentifier(input.id) || !isIdentifier(input.name) {
                issues.append(issue(
                    .invalidIdentifier,
                    at: location,
                    "Example-input IDs and names must be safe identifiers."
                ))
            }
            switch input.kind {
            case .tensor:
                if input.scalarType.isEmpty || input.shape.isEmpty || input.shape.contains(where: { $0 < 1 }) {
                    issues.append(issue(
                        .invalidExampleInput,
                        at: location,
                        "Tensor examples require a scalar type and positive shape dimensions."
                    ))
                }
            case .scalar:
                if input.scalarType.isEmpty || input.literalValue.isEmpty {
                    issues.append(issue(
                        .invalidExampleInput,
                        at: location,
                        "Scalar examples require a scalar type and literal value."
                    ))
                }
            case .boolean, .text:
                if input.literalValue.isEmpty {
                    issues.append(issue(
                        .invalidExampleInput,
                        at: location,
                        "Boolean and text examples require a literal value."
                    ))
                }
            }
        }

        var dimensionKeys = Set<String>()
        _ = namesAndDuplicateIssues(
            recipe.dynamicDimensions.map(\.id),
            location: "dynamicDimensions.id",
            issues: &issues
        )
        for dimension in recipe.dynamicDimensions {
            let location = "dynamicDimensions.\(dimension.id)"
            if !isIdentifier(dimension.id) {
                issues.append(issue(
                    .invalidIdentifier,
                    at: location,
                    "Dynamic-dimension ID is invalid."
                ))
            }
            guard let input = recipe.exampleInputs.first(where: {
                $0.name == dimension.inputName
            }) else {
                issues.append(issue(
                    .unknownReference,
                    at: location,
                    "Dynamic dimension references an unknown example input."
                ))
                continue
            }
            let key = "\(dimension.inputName):\(dimension.axis)"
            if !dimensionKeys.insert(key).inserted {
                issues.append(issue(
                    .duplicateValue,
                    at: location,
                    "An input axis can have only one dynamic-dimension rule."
                ))
            }
            if input.kind != .tensor
                || !input.shape.indices.contains(dimension.axis)
                || !isIdentifier(dimension.symbol)
                || dimension.minimum < 1
                || dimension.maximum < dimension.minimum {
                issues.append(issue(
                    .invalidDynamicDimension,
                    at: location,
                    "Dynamic dimensions require a tensor axis, safe symbol, and positive ordered bounds."
                ))
            }
        }

        _ = namesAndDuplicateIssues(
            recipe.stateBindings.map(\.id),
            location: "stateBindings.id",
            issues: &issues
        )
        let stateNames = namesAndDuplicateIssues(
            recipe.stateBindings.map(\.name),
            location: "stateBindings",
            issues: &issues
        )
        for state in recipe.stateBindings where !isIdentifier(state.id)
            || !isIdentifier(state.name)
            || !isIdentifier(state.inputName)
            || !isIdentifier(state.outputName) {
            issues.append(issue(
                .invalidState,
                at: "stateBindings.\(state.id)",
                "State names and their input/output bindings must be safe identifiers."
            ))
        }

        _ = namesAndDuplicateIssues(
            recipe.externalizationRules.map(\.id),
            location: "externalizationRules.id",
            issues: &issues
        )
        for rule in recipe.externalizationRules {
            if !isIdentifier(rule.id)
                || rule.modulePath.isEmpty
                || rule.minimumBytes < 0
                || !isIdentifier(rule.resourceName) {
                issues.append(issue(
                    .invalidExternalization,
                    at: "externalizationRules.\(rule.id)",
                    "Externalization rules require a module path, nonnegative threshold, and safe resource name."
                ))
            }
        }

        _ = namesAndDuplicateIssues(
            recipe.functionEntrypoints.map(\.id),
            location: "functionEntrypoints.id",
            issues: &issues
        )
        _ = namesAndDuplicateIssues(
            recipe.functionEntrypoints.map(\.name),
            location: "functionEntrypoints",
            issues: &issues
        )
        for function in recipe.functionEntrypoints {
            let location = "functionEntrypoints.\(function.id)"
            if !isIdentifier(function.id)
                || !isIdentifier(function.name)
                || function.moduleMethod.isEmpty
                || function.outputNames.isEmpty
                || function.outputNames.contains(where: { !isIdentifier($0) }) {
                issues.append(issue(
                    .invalidEntrypoint,
                    at: location,
                    "Function entrypoints require safe names, a module method, and at least one safe output."
                ))
            }
            for name in function.inputNames where !inputNames.contains(name) {
                issues.append(issue(
                    .unknownReference,
                    at: "\(location).inputNames.\(name)",
                    "Function input \(name) has no matching example input."
                ))
            }
            for name in function.stateNames where !stateNames.contains(name) {
                issues.append(issue(
                    .unknownReference,
                    at: "\(location).stateNames.\(name)",
                    "Function state \(name) has no matching state binding."
                ))
            }
        }

        _ = namesAndDuplicateIssues(
            recipe.unsupportedOperations.map(\.id),
            location: "unsupportedOperations.id",
            issues: &issues
        )
        for finding in recipe.unsupportedOperations {
            if !isIdentifier(finding.id)
                || finding.operatorName.isEmpty
                || finding.modulePath.isEmpty
                || finding.sourceFile.isEmpty
                || finding.sourceLine < 1 {
                issues.append(issue(
                    .incompleteAttribution,
                    at: "unsupportedOperations.\(finding.id)",
                    "Unsupported operations require operator, module, source file, and source line attribution."
                ))
            }
        }

        issues.append(contentsOf: CoreAIPipelineValidator.issues(in: recipe.pipeline).map {
            issue(
                .invalidPipeline,
                at: "pipeline.\($0.location)",
                $0.message
            )
        })

        var seenIssues = Set<CoreAIRecipeValidationIssue>()
        return issues.filter { seenIssues.insert($0).inserted }.sorted {
            if $0.location != $1.location { return $0.location < $1.location }
            if $0.code.rawValue != $1.code.rawValue {
                return $0.code.rawValue < $1.code.rawValue
            }
            return $0.message < $1.message
        }
    }

    @discardableResult
    private static func namesAndDuplicateIssues(
        _ names: [String],
        location: String,
        issues: inout [CoreAIRecipeValidationIssue]
    ) -> Set<String> {
        var uniqueNames = Set<String>()
        for name in names where !uniqueNames.insert(name).inserted {
            issues.append(issue(
                .duplicateValue,
                at: "\(location).\(name)",
                "Name \(name) appears more than once."
            ))
        }
        return uniqueNames
    }

    private static func isIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first)
        else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "_-./")
        )
        return value.unicodeScalars.allSatisfy(allowed.contains)
            && !value.contains("..")
            && !value.hasPrefix("/")
            && !value.hasSuffix("/")
    }

    private static func issue(
        _ code: CoreAIRecipeValidationIssue.Code,
        at location: String,
        _ message: String
    ) -> CoreAIRecipeValidationIssue {
        CoreAIRecipeValidationIssue(code: code, location: location, message: message)
    }
}
