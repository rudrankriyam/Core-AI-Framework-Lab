import Foundation

enum CoreAIDeviceShapeLimits {
    // Parser and sizing safety ceilings, not claims about any device's capacity.
    static let maximumShapeCount = 64
    static let maximumRank = 16
    static let maximumDimension = 1_048_576
    static let maximumContextTokens = 1_048_576
    static let maximumElementsPerShape = 268_435_456
    static let maximumTotalElements = 536_870_912

    static func validate(
        contextTokens: Int?,
        staticInputShapes: [String: [Int]],
        path: String
    ) throws {
        if let contextTokens {
            guard (1...maximumContextTokens).contains(contextTokens) else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: "\(path).contextTokens",
                    reason: "it must be between 1 and \(maximumContextTokens)"
                )
            }
        }
        guard staticInputShapes.count <= maximumShapeCount else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).staticInputShapes",
                reason: "at most \(maximumShapeCount) shapes are supported"
            )
        }

        var totalElements = 0
        for (name, dimensions) in staticInputShapes {
            try CoreAIManifestValidator.requireNonempty(
                name,
                path: "\(path).staticInputShapes.key"
            )
            guard (1...maximumRank).contains(dimensions.count) else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: "\(path).staticInputShapes.\(name)",
                    reason: "rank must be between 1 and \(maximumRank)"
                )
            }
            var elementCount = 1
            for dimension in dimensions {
                guard (1...maximumDimension).contains(dimension) else {
                    throw CoreAIDeviceEvidenceError.invalidValue(
                        path: "\(path).staticInputShapes.\(name)",
                        reason: "every dimension must be between 1 and \(maximumDimension)"
                    )
                }
                let product = elementCount.multipliedReportingOverflow(
                    by: dimension
                )
                guard !product.overflow else {
                    throw CoreAIDeviceEvidenceError.arithmeticOverflow(
                        path: "\(path).staticInputShapes.\(name)"
                    )
                }
                guard product.partialValue <= maximumElementsPerShape else {
                    throw CoreAIDeviceEvidenceError.invalidValue(
                        path: "\(path).staticInputShapes.\(name)",
                        reason: "it exceeds the \(maximumElementsPerShape)-element safety ceiling"
                    )
                }
                elementCount = product.partialValue
            }
            let sum = totalElements.addingReportingOverflow(elementCount)
            guard !sum.overflow else {
                throw CoreAIDeviceEvidenceError.arithmeticOverflow(
                    path: "\(path).staticInputShapes"
                )
            }
            guard sum.partialValue <= maximumTotalElements else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: "\(path).staticInputShapes",
                    reason: "the total exceeds the \(maximumTotalElements)-element safety ceiling"
                )
            }
            totalElements = sum.partialValue
        }
    }
}
