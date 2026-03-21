import Foundation

// MARK: - Compiler Output Types

public struct PatchInputBinding: Codable, Equatable, Sendable {
    public var portName: String
    public var portType: PatchPortType
    public var sourceSlot: Int

    public var isConnected: Bool { sourceSlot >= 0 }

    public init(portName: String, portType: PatchPortType, sourceSlot: Int) {
        self.portName = portName
        self.portType = portType
        self.sourceSlot = sourceSlot
    }
}

public struct PatchOutputBinding: Codable, Equatable, Sendable {
    public var portName: String
    public var portType: PatchPortType
    public var slot: Int

    public init(portName: String, portType: PatchPortType, slot: Int) {
        self.portName = portName
        self.portType = portType
        self.slot = slot
    }
}

public struct PatchStep: Codable, Equatable, Sendable {
    public var nodeID: UUID
    public var kind: CustomPatchNodeKind
    public var parameters: [PatchNodeParameter]
    public var inputs: [PatchInputBinding]
    public var outputs: [PatchOutputBinding]

    public init(
        nodeID: UUID,
        kind: CustomPatchNodeKind,
        parameters: [PatchNodeParameter],
        inputs: [PatchInputBinding],
        outputs: [PatchOutputBinding]
    ) {
        self.nodeID = nodeID
        self.kind = kind
        self.parameters = parameters
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct PatchProgram: Codable, Equatable, Sendable {
    public var steps: [PatchStep]
    public var signalSlotCount: Int
    public var textureSlotCount: Int
    public var outputTextureSlot: Int

    public init(steps: [PatchStep], signalSlotCount: Int, textureSlotCount: Int, outputTextureSlot: Int) {
        self.steps = steps
        self.signalSlotCount = signalSlotCount
        self.textureSlotCount = textureSlotCount
        self.outputTextureSlot = outputTextureSlot
    }
}

// MARK: - Compile Errors

public enum PatchCompileError: Equatable, Sendable, CustomStringConvertible {
    case cycleDetected
    case noOutputNode
    case multipleOutputNodes
    case invalidPort(nodeID: UUID, portName: String, direction: String)
    case typeMismatch(connectionID: UUID, fromType: PatchPortType, toType: PatchPortType)
    case duplicateConnection(toNodeID: UUID, toPort: String)
    case unknownNode(nodeID: UUID)

    public var description: String {
        switch self {
        case .cycleDetected:
            return "Graph contains a cycle"
        case .noOutputNode:
            return "No output node found"
        case .multipleOutputNodes:
            return "Multiple output nodes found"
        case .invalidPort(_, let portName, let direction):
            return "Invalid \(direction) port: \(portName)"
        case .typeMismatch(_, let fromType, let toType):
            return "Type mismatch: \(fromType) → \(toType)"
        case .duplicateConnection(_, let toPort):
            return "Duplicate connection to port: \(toPort)"
        case .unknownNode:
            return "Connection references unknown node"
        }
    }
}

public struct PatchCompileResult: Equatable, Sendable {
    public var program: PatchProgram?
    public var errors: [PatchCompileError]

    public var isSuccess: Bool { program != nil && errors.isEmpty }

    public init(program: PatchProgram? = nil, errors: [PatchCompileError] = []) {
        self.program = program
        self.errors = errors
    }
}

// MARK: - Compiler

public enum PatchCompiler {
    public static func compile(_ patch: CustomPatch) -> PatchCompileResult {
        var errors: [PatchCompileError] = []
        let nodesByID = Dictionary(uniqueKeysWithValues: patch.nodes.map { ($0.id, $0) })

        // Validate: exactly one output node
        let outputNodes = patch.nodes.filter { $0.kind == .output }
        if outputNodes.isEmpty {
            errors.append(.noOutputNode)
            return PatchCompileResult(errors: errors)
        }
        if outputNodes.count > 1 {
            errors.append(.multipleOutputNodes)
            return PatchCompileResult(errors: errors)
        }

        // Validate connections
        var incomingByPort: [UUID: [String: CustomPatchConnection]] = [:]
        for connection in patch.connections {
            guard let fromNode = nodesByID[connection.fromNodeID] else {
                errors.append(.unknownNode(nodeID: connection.fromNodeID))
                continue
            }
            guard let toNode = nodesByID[connection.toNodeID] else {
                errors.append(.unknownNode(nodeID: connection.toNodeID))
                continue
            }

            let fromPortDesc = fromNode.kind.outputPortDescriptors.first(where: { $0.name == connection.fromPort })
            let toPortDesc = toNode.kind.inputPortDescriptors.first(where: { $0.name == connection.toPort })

            guard let fromDesc = fromPortDesc else {
                errors.append(.invalidPort(nodeID: connection.fromNodeID, portName: connection.fromPort, direction: "output"))
                continue
            }
            guard let toDesc = toPortDesc else {
                errors.append(.invalidPort(nodeID: connection.toNodeID, portName: connection.toPort, direction: "input"))
                continue
            }

            if fromDesc.type != toDesc.type {
                errors.append(.typeMismatch(connectionID: connection.id, fromType: fromDesc.type, toType: toDesc.type))
                continue
            }

            var nodePorts = incomingByPort[connection.toNodeID] ?? [:]
            if nodePorts[connection.toPort] != nil {
                errors.append(.duplicateConnection(toNodeID: connection.toNodeID, toPort: connection.toPort))
                continue
            }
            nodePorts[connection.toPort] = connection
            incomingByPort[connection.toNodeID] = nodePorts
        }

        if !errors.isEmpty {
            return PatchCompileResult(errors: errors)
        }

        // Build adjacency for topological sort
        // Feedback nodes break cycles: edges INTO feedback nodes are excluded from
        // the DAG so feedback executes as a source (outputs previous frame data).
        // After all nodes run, swapFeedbackTextures blends the current input into
        // the stored frame for next-frame output.
        var adjacency: [UUID: [UUID]] = [:]
        var inDegree: [UUID: Int] = [:]
        for node in patch.nodes {
            adjacency[node.id] = []
            inDegree[node.id] = 0
        }
        for connection in patch.connections {
            let targetIsFeedback = nodesByID[connection.toNodeID]?.kind == .feedback
            if !targetIsFeedback {
                adjacency[connection.fromNodeID]?.append(connection.toNodeID)
                inDegree[connection.toNodeID, default: 0] += 1
            }
        }

        // Kahn's algorithm for topological sort + cycle detection
        var queue: [UUID] = []
        for node in patch.nodes where inDegree[node.id, default: 0] == 0 {
            queue.append(node.id)
        }

        var sortedIDs: [UUID] = []
        var queueIndex = 0
        while queueIndex < queue.count {
            let nodeID = queue[queueIndex]
            queueIndex += 1
            sortedIDs.append(nodeID)
            for neighbor in adjacency[nodeID] ?? [] {
                inDegree[neighbor, default: 0] -= 1
                if inDegree[neighbor, default: 0] == 0 {
                    queue.append(neighbor)
                }
            }
        }

        if sortedIDs.count != patch.nodes.count {
            return PatchCompileResult(errors: [.cycleDetected])
        }

        // Allocate slots and build steps
        var nextSignalSlot = 0
        var nextTextureSlot = 0
        var outputSlotMap: [UUID: [String: (type: PatchPortType, slot: Int)]] = [:]
        var steps: [PatchStep] = []
        var outputTextureSlot = -1

        for nodeID in sortedIDs {
            guard let node = nodesByID[nodeID] else { continue }

            // Build output bindings and assign slots
            var outBindings: [PatchOutputBinding] = []
            var nodeOutputSlots: [String: (type: PatchPortType, slot: Int)] = [:]
            for port in node.kind.outputPortDescriptors {
                let slot: Int
                switch port.type {
                case .signal, .trigger, .color, .vector:
                    slot = nextSignalSlot
                    nextSignalSlot += 1
                case .field:
                    slot = nextTextureSlot
                    nextTextureSlot += 1
                }
                outBindings.append(PatchOutputBinding(portName: port.name, portType: port.type, slot: slot))
                nodeOutputSlots[port.name] = (port.type, slot)
            }
            outputSlotMap[nodeID] = nodeOutputSlots

            // Build input bindings
            var inBindings: [PatchInputBinding] = []
            for port in node.kind.inputPortDescriptors {
                let sourceSlot: Int
                if let connection = incomingByPort[nodeID]?[port.name],
                   let upstreamSlots = outputSlotMap[connection.fromNodeID],
                   let upstream = upstreamSlots[connection.fromPort] {
                    sourceSlot = upstream.slot
                } else {
                    sourceSlot = -1
                }
                inBindings.append(PatchInputBinding(portName: port.name, portType: port.type, sourceSlot: sourceSlot))
            }

            // Record output texture slot for the Output node
            if node.kind == .output {
                if let colorInput = inBindings.first(where: { $0.portName == "color" }), colorInput.isConnected {
                    outputTextureSlot = colorInput.sourceSlot
                }
            }

            steps.append(PatchStep(
                nodeID: nodeID,
                kind: node.kind,
                parameters: node.parameters,
                inputs: inBindings,
                outputs: outBindings
            ))
        }

        // Second pass: resolve feedback node input bindings.
        // Feedback nodes appear early in topological order (edges into them are
        // excluded from the DAG), so their upstream slots weren't allocated yet
        // during the first pass. Now that all slots are allocated, we can resolve
        // feedback inputs for use by swapFeedbackTextures (Phase 2).
        for i in 0..<steps.count where steps[i].kind == .feedback {
            let nodeID = steps[i].nodeID
            var resolvedInputs: [PatchInputBinding] = []
            for port in CustomPatchNodeKind.feedback.inputPortDescriptors {
                let sourceSlot: Int
                if let connection = incomingByPort[nodeID]?[port.name],
                   let upstreamSlots = outputSlotMap[connection.fromNodeID],
                   let upstream = upstreamSlots[connection.fromPort] {
                    sourceSlot = upstream.slot
                } else {
                    sourceSlot = -1
                }
                resolvedInputs.append(PatchInputBinding(portName: port.name, portType: port.type, sourceSlot: sourceSlot))
            }
            steps[i] = PatchStep(
                nodeID: steps[i].nodeID,
                kind: steps[i].kind,
                parameters: steps[i].parameters,
                inputs: resolvedInputs,
                outputs: steps[i].outputs
            )
        }

        let program = PatchProgram(
            steps: steps,
            signalSlotCount: nextSignalSlot,
            textureSlotCount: nextTextureSlot,
            outputTextureSlot: outputTextureSlot
        )
        return PatchCompileResult(program: program)
    }
}
