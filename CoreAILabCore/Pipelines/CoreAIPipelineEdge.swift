struct CoreAIPipelineEdge: Codable, Hashable, Identifiable, Sendable {
    struct ID: Hashable, Sendable {
        let source: CoreAIPipelineEndpoint
        let destination: CoreAIPipelineEndpoint
    }

    let source: CoreAIPipelineEndpoint
    let destination: CoreAIPipelineEndpoint

    var id: ID {
        ID(source: source, destination: destination)
    }

    var diagnosticDescription: String {
        "\(source.nodeID)[\(source.portName)]->\(destination.nodeID)[\(destination.portName)]"
    }
}
