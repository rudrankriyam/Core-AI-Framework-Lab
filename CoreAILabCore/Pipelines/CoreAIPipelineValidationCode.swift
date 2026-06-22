enum CoreAIPipelineValidationCode: String, Codable, Sendable {
    case unsupportedSchemaVersion
    case invalidHostOperatorRegistryVersion
    case invalidIdentifier
    case duplicateNode
    case duplicatePort
    case invalidDimension
    case missingNode
    case missingPort
    case missingReference
    case invalidReference
    case invalidNodeConfiguration
    case unconnectedRequiredInput
    case duplicateEdge
    case multiplyConnectedInput
    case incompatibleValue
    case invalidBoundaryNode
    case invalidStateOwnership
    case duplicateStateOwnership
    case unseededRandomness
    case invalidLoopBound
    case missingLoopStopCondition
    case cycle
}
