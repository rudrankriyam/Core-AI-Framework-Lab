struct CoreAIPipelineEndpoint: Codable, Hashable, Identifiable, Sendable {
    struct ID: Hashable, Sendable {
        let nodeID: String
        let portName: String
    }

    var nodeID: String
    var portName: String

    var id: ID { ID(nodeID: nodeID, portName: portName) }

    var diagnosticDescription: String { "\(nodeID).\(portName)" }
}
