struct CoreAIPipelineEndpoint: Codable, Hashable, Identifiable, Sendable {
    var nodeID: String
    var portName: String

    var id: String { "\(nodeID).\(portName)" }
}
