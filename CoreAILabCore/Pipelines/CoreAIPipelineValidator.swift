import Foundation

enum CoreAIPipelineValidator {
    static func validate(_ manifest: CoreAIPipelineManifest) throws {
        let issues = issues(in: manifest)
        guard issues.isEmpty else {
            throw CoreAIPipelineValidationError(issues: issues)
        }
    }

    static func issues(in manifest: CoreAIPipelineManifest) -> [CoreAIPipelineValidationIssue] {
        var issues: [CoreAIPipelineValidationIssue] = []
        if manifest.schemaVersion != CoreAIPipelineManifest.currentSchemaVersion {
            issues.append(issue(
                .unsupportedSchemaVersion,
                at: "schemaVersion",
                "Pipeline schema version \(manifest.schemaVersion) is unsupported."
            ))
        }
        if !isValidIdentifier(manifest.id) {
            issues.append(issue(.invalidIdentifier, at: "id", "Pipeline ID is invalid."))
        }
        if manifest.hostOperatorRegistryVersion < 1 {
            issues.append(issue(
                .invalidHostOperatorRegistryVersion,
                at: "hostOperatorRegistryVersion",
                "Host-operator registry version must be positive."
            ))
        }

        var nodesByID: [String: CoreAIPipelineNode] = [:]
        for node in manifest.nodes {
            if !isValidIdentifier(node.id) {
                issues.append(issue(
                    .invalidIdentifier,
                    at: "nodes.\(node.id)",
                    "Node ID \(node.id) is invalid."
                ))
            }
            if nodesByID.updateValue(node, forKey: node.id) != nil {
                issues.append(issue(
                    .duplicateNode,
                    at: "nodes.\(node.id)",
                    "Node ID \(node.id) appears more than once."
                ))
            }
            issues.append(contentsOf: portIssues(node: node))
            issues.append(contentsOf: semanticIssues(node: node))
        }

        var seenEdges = Set<CoreAIPipelineEdge>()
        var connectedInputs = Set<CoreAIPipelineEndpoint>()
        var adjacency = Dictionary(uniqueKeysWithValues: nodesByID.keys.map { ($0, Set<String>()) })
        var indegree = Dictionary(uniqueKeysWithValues: nodesByID.keys.map { ($0, 0) })

        for edge in manifest.edges {
            let edgeDescription = edge.diagnosticDescription
            if !seenEdges.insert(edge).inserted {
                issues.append(issue(
                    .duplicateEdge,
                    at: "edges.\(edgeDescription)",
                    "Edge \(edgeDescription) appears more than once."
                ))
            }
            guard let sourceNode = nodesByID[edge.source.nodeID] else {
                issues.append(issue(
                    .missingNode,
                    at: "edges.\(edgeDescription)",
                    "Source node \(edge.source.nodeID) does not exist."
                ))
                continue
            }
            guard let destinationNode = nodesByID[edge.destination.nodeID] else {
                issues.append(issue(
                    .missingNode,
                    at: "edges.\(edgeDescription)",
                    "Destination node \(edge.destination.nodeID) does not exist."
                ))
                continue
            }
            guard let sourcePort = sourceNode.outputs.first(where: {
                $0.name == edge.source.portName
            }) else {
                issues.append(issue(
                    .missingPort,
                    at: "edges.\(edgeDescription)",
                    "Source port \(edge.source.portName) does not exist on \(sourceNode.id)."
                ))
                continue
            }
            guard let destinationPort = destinationNode.inputs.first(where: {
                $0.name == edge.destination.portName
            }) else {
                issues.append(issue(
                    .missingPort,
                    at: "edges.\(edgeDescription)",
                    "Destination port \(edge.destination.portName) does not exist on \(destinationNode.id)."
                ))
                continue
            }
            if !connectedInputs.insert(edge.destination).inserted {
                issues.append(issue(
                    .multiplyConnectedInput,
                    at: "edges.\(edgeDescription)",
                    "Input \(edge.destination.nodeID).\(edge.destination.portName) has multiple sources."
                ))
            }
            if sourcePort.isOptional && !destinationPort.isOptional {
                issues.append(issue(
                    .incompatibleValue,
                    at: "edges.\(edgeDescription)",
                    "An optional output cannot satisfy a required input."
                ))
            }
            if !sourcePort.value.isCompatible(with: destinationPort.value) {
                issues.append(issue(
                    .incompatibleValue,
                    at: "edges.\(edgeDescription)",
                    "Edge \(edgeDescription) connects incompatible value contracts."
                ))
            }
            if adjacency[sourceNode.id]?.insert(destinationNode.id).inserted == true {
                indegree[destinationNode.id, default: 0] += 1
            }
        }

        for node in nodesByID.values {
            var requiredPortNames = Set(
                node.inputs.lazy.filter { !$0.isOptional }.map(\.name)
            )
            if node.kind == .seededRandom,
               node.fixedSeed == nil,
               let seedInputPort = node.seedInputPort {
                requiredPortNames.insert(seedInputPort)
            }
            if node.kind == .boundedLoop,
               let stopConditionInputPort = node.stopConditionInputPort {
                requiredPortNames.insert(stopConditionInputPort)
            }
            for portName in requiredPortNames.sorted() {
                let endpoint = CoreAIPipelineEndpoint(
                    nodeID: node.id,
                    portName: portName
                )
                if !connectedInputs.contains(endpoint) {
                    issues.append(issue(
                        .unconnectedRequiredInput,
                        at: "nodes.\(node.id).inputs.\(portName)",
                        "Required input \(node.id).\(portName) is not connected."
                    ))
                }
            }
        }

        issues.append(contentsOf: stateOwnershipIssues(nodesByID: nodesByID))
        if containsCycle(adjacency: adjacency, indegree: indegree) {
            issues.append(issue(.cycle, at: "edges", "Pipeline graph contains a cycle."))
        }
        var seenIssues = Set<CoreAIPipelineValidationIssue>()
        return issues.filter { seenIssues.insert($0).inserted }.sorted {
            if $0.location != $1.location { return $0.location < $1.location }
            if $0.code.rawValue != $1.code.rawValue {
                return $0.code.rawValue < $1.code.rawValue
            }
            return $0.message < $1.message
        }
    }

    private static func portIssues(node: CoreAIPipelineNode) -> [CoreAIPipelineValidationIssue] {
        var issues: [CoreAIPipelineValidationIssue] = []
        for (direction, ports) in [("inputs", node.inputs), ("outputs", node.outputs)] {
            var names = Set<String>()
            for port in ports {
                let location = "nodes.\(node.id).\(direction).\(port.name)"
                if !isValidIdentifier(port.name) {
                    issues.append(issue(
                        .invalidIdentifier,
                        at: location,
                        "Port name \(port.name) is invalid."
                    ))
                }
                if !names.insert(port.name).inserted {
                    issues.append(issue(
                        .duplicatePort,
                        at: location,
                        "Port \(port.name) appears more than once on node \(node.id)."
                    ))
                }
                for (index, dimension) in (port.value.shape ?? []).enumerated() {
                    if !isValid(dimension: dimension) {
                        issues.append(issue(
                            .invalidDimension,
                            at: "\(location).shape.\(index)",
                            "Dimension \(index) has an invalid fixed or dynamic range."
                        ))
                    }
                }
            }
        }
        return issues
    }

    private static func semanticIssues(node: CoreAIPipelineNode) -> [CoreAIPipelineValidationIssue] {
        var issues = configurationIssues(node: node)
        if node.kind == .input, !node.inputs.isEmpty {
            issues.append(issue(
                .invalidBoundaryNode,
                at: "nodes.\(node.id)",
                "Input nodes cannot declare input ports."
            ))
        }
        if node.kind == .output, !node.outputs.isEmpty {
            issues.append(issue(
                .invalidBoundaryNode,
                at: "nodes.\(node.id)",
                "Output nodes cannot declare output ports."
            ))
        }
        if [.assetFunction, .hostOperator].contains(node.kind) {
            guard let reference = node.reference, !reference.isEmpty else {
                issues.append(issue(
                    .missingReference,
                    at: "nodes.\(node.id).reference",
                    "\(node.kind.rawValue) node \(node.id) requires a reference."
                ))
                return issues
            }
            if !isValidIdentifier(reference) {
                issues.append(issue(
                    .invalidReference,
                    at: "nodes.\(node.id).reference",
                    "Executable reference \(reference) is not a safe logical identifier."
                ))
            }
        }
        if node.kind == .seededRandom {
            let hasFixedSeed = node.fixedSeed != nil
            let hasSeedInput = node.seedInputPort != nil
            if hasFixedSeed == hasSeedInput {
                issues.append(issue(
                    .unseededRandomness,
                    at: "nodes.\(node.id)",
                    "Seeded-random nodes require exactly one fixed seed or seed input port."
                ))
            } else if let seedInputPort = node.seedInputPort {
                guard let seedInput = node.inputs.first(where: {
                    $0.name == seedInputPort
                }) else {
                    issues.append(issue(
                        .missingPort,
                        at: "nodes.\(node.id).seedInputPort",
                        "Seed input port \(seedInputPort) does not exist."
                    ))
                    return issues
                }
                if seedInput.isOptional
                    || seedInput.value.kind != .scalar
                    || seedInput.value.shape != nil
                    || !integerScalarTypes.contains(seedInput.value.scalarType ?? "") {
                    issues.append(issue(
                        .unseededRandomness,
                        at: "nodes.\(node.id).inputs.\(seedInputPort)",
                        "A seed input must be a required integer scalar."
                    ))
                }
            }
        }
        if node.kind == .boundedLoop {
            if !(1...1_000_000).contains(node.maximumIterations ?? 0) {
                issues.append(issue(
                    .invalidLoopBound,
                    at: "nodes.\(node.id).maximumIterations",
                    "Bounded loops require 1 through 1,000,000 maximum iterations."
                ))
            }
            guard let stopPort = node.stopConditionInputPort,
                  let stopInput = node.inputs.first(where: { $0.name == stopPort }) else {
                issues.append(issue(
                    .missingLoopStopCondition,
                    at: "nodes.\(node.id).stopConditionInputPort",
                    "Bounded loops require an existing stop-condition input port."
                ))
                return issues
            }
            if stopInput.isOptional
                || stopInput.value.kind != .scalar
                || stopInput.value.scalarType != "bool"
                || stopInput.value.shape != nil {
                issues.append(issue(
                    .incompatibleValue,
                    at: "nodes.\(node.id).inputs.\(stopPort)",
                    "A loop stop condition must be a required Bool scalar."
                ))
            }
        }
        return issues
    }

    private static func configurationIssues(
        node: CoreAIPipelineNode
    ) -> [CoreAIPipelineValidationIssue] {
        let allowedFields: Set<String> = switch node.kind {
        case .assetFunction, .hostOperator:
            ["reference"]
        case .state:
            ["stateKey", "ownerNodeID"]
        case .seededRandom:
            ["fixedSeed", "seedInputPort"]
        case .boundedLoop:
            ["maximumIterations", "stopConditionInputPort"]
        case .input, .output:
            []
        }
        let configuredFields: [(name: String, isPresent: Bool)] = [
            ("reference", node.reference != nil),
            ("stateKey", node.stateKey != nil),
            ("ownerNodeID", node.ownerNodeID != nil),
            ("fixedSeed", node.fixedSeed != nil),
            ("seedInputPort", node.seedInputPort != nil),
            ("maximumIterations", node.maximumIterations != nil),
            ("stopConditionInputPort", node.stopConditionInputPort != nil)
        ]
        return configuredFields.compactMap { field in
            guard field.isPresent, !allowedFields.contains(field.name) else {
                return nil
            }
            return issue(
                .invalidNodeConfiguration,
                at: "nodes.\(node.id).\(field.name)",
                "\(node.kind.rawValue) nodes cannot configure \(field.name)."
            )
        }
    }

    private static func stateOwnershipIssues(
        nodesByID: [String: CoreAIPipelineNode]
    ) -> [CoreAIPipelineValidationIssue] {
        var issues: [CoreAIPipelineValidationIssue] = []
        var stateOwners: [String: String] = [:]
        for node in nodesByID.values.sorted(by: { $0.id < $1.id })
        where node.kind == .state {
            guard let stateKey = node.stateKey,
                  isValidIdentifier(stateKey),
                  let ownerNodeID = node.ownerNodeID,
                  ownerNodeID != node.id,
                  let ownerNode = nodesByID[ownerNodeID],
                  ![.input, .output, .state].contains(ownerNode.kind) else {
                issues.append(issue(
                    .invalidStateOwnership,
                    at: "nodes.\(node.id)",
                    "State node \(node.id) requires a valid key and an executable owner."
                ))
                continue
            }
            if let existingOwner = stateOwners.updateValue(ownerNodeID, forKey: stateKey) {
                issues.append(issue(
                    .duplicateStateOwnership,
                    at: "nodes.\(node.id).stateKey",
                    "State \(stateKey) is declared more than once for \(existingOwner) and \(ownerNodeID)."
                ))
            }
        }
        return issues
    }

    private static let integerScalarTypes: Set<String> = [
        "int8", "int16", "int32", "int64",
        "uint8", "uint16", "uint32", "uint64"
    ]

    private static func containsCycle(
        adjacency: [String: Set<String>],
        indegree: [String: Int]
    ) -> Bool {
        var indegree = indegree
        var queue = indegree.compactMap { $0.value == 0 ? $0.key : nil }.sorted()
        var visited = 0
        while let node = queue.first {
            queue.removeFirst()
            visited += 1
            for destination in (adjacency[node] ?? []).sorted() {
                indegree[destination, default: 0] -= 1
                if indegree[destination] == 0 {
                    queue.append(destination)
                }
            }
        }
        return visited != indegree.count
    }

    private static func isValid(dimension: CoreAIPipelineDimension) -> Bool {
        if let fixedSize = dimension.fixedSize {
            return fixedSize > 0
                && dimension.name == nil
                && dimension.minimum == nil
                && dimension.maximum == nil
        }
        guard let name = dimension.name,
              isValidIdentifier(name),
              dimension.minimum.map({ $0 > 0 }) ?? true,
              dimension.maximum.map({ $0 > 0 }) ?? true else {
            return false
        }
        if let minimum = dimension.minimum, let maximum = dimension.maximum {
            return minimum <= maximum
        }
        return true
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
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
        _ code: CoreAIPipelineValidationCode,
        at location: String,
        _ message: String
    ) -> CoreAIPipelineValidationIssue {
        CoreAIPipelineValidationIssue(code: code, location: location, message: message)
    }
}
