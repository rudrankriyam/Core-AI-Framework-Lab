struct CoreAIPipelineValueContract: Codable, Hashable, Sendable {
    static let authoringDefault = Self(
        kind: .tensor,
        scalarType: "float32",
        shape: [.fixed(1)]
    )

    var kind: CoreAIPipelineValueKind
    var scalarType: String?
    var shape: [CoreAIPipelineDimension]?
    var semantic: String?

    func isCompatible(with destination: Self) -> Bool {
        guard kind == destination.kind else { return false }
        if let destinationScalarType = destination.scalarType,
           scalarType != destinationScalarType {
            return false
        }
        if let destinationSemantic = destination.semantic,
           semantic != destinationSemantic {
            return false
        }
        guard let destinationShape = destination.shape else {
            return true
        }
        guard let shape else { return false }
        guard shape.count == destinationShape.count else { return false }
        return zip(shape, destinationShape).allSatisfy { source, target in
            source.isSubset(of: target)
        }
    }
}

private extension CoreAIPipelineDimension {
    var lowerBound: Int {
        fixedSize ?? minimum ?? 1
    }

    var upperBound: Int {
        fixedSize ?? maximum ?? .max
    }

    func isSubset(of destination: Self) -> Bool {
        lowerBound >= destination.lowerBound
            && upperBound <= destination.upperBound
    }
}
