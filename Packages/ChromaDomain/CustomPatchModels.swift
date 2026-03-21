import Foundation

// MARK: - Port Type System

public enum PatchPortType: String, Codable, Sendable, CaseIterable {
    case signal
    case color
    case field
    case trigger
    case vector
}

public struct PatchPortDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var type: PatchPortType

    public init(name: String, type: PatchPortType) {
        self.name = name
        self.type = type
    }
}

public struct PatchNodeParameter: Codable, Equatable, Sendable {
    public var name: String
    public var displayName: String
    public var value: Double
    public var defaultValue: Double
    public var min: Double
    public var max: Double

    public init(name: String, displayName: String, value: Double, defaultValue: Double, min: Double, max: Double) {
        self.name = name
        self.displayName = displayName
        self.value = value
        self.defaultValue = defaultValue
        self.min = min
        self.max = max
    }
}

// MARK: - Node Kind

public enum CustomPatchNodeKind: String, CaseIterable, Codable, Sendable {
    // Phase 1: core pipeline
    case audioIn
    case spectrum
    case oscillator
    case transform
    case blend
    case output
    // Phase 2: source nodes
    case pitch
    case lfo
    case noise
    case constant
    case time
    // Phase 2: processing nodes
    case math
    case envelope
    case smooth
    case threshold
    case sampleAndHold
    case mix
    case remap
    // Phase 3: visual generator nodes
    case solid
    case gradient
    case oscillator2D
    case particles
    case hsvAdjust
    case transform2D
    // Phase 5: advanced visual nodes + feedback
    case fractal
    case voronoi
    case feedback
    case blur
    case displace
    case mirror
    case tile
    case cameraIn

    public var displayName: String {
        switch self {
        case .audioIn: return "Audio In"
        case .spectrum: return "Spectrum"
        case .oscillator: return "Oscillator"
        case .transform: return "Transform"
        case .blend: return "Blend"
        case .output: return "Output"
        case .pitch: return "Pitch"
        case .lfo: return "LFO"
        case .noise: return "Noise"
        case .constant: return "Constant"
        case .time: return "Time"
        case .math: return "Math"
        case .envelope: return "Envelope"
        case .smooth: return "Smooth"
        case .threshold: return "Threshold"
        case .sampleAndHold: return "S&H"
        case .mix: return "Mix"
        case .remap: return "Remap"
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        case .oscillator2D: return "Osc 2D"
        case .particles: return "Particles"
        case .hsvAdjust: return "HSV Adjust"
        case .transform2D: return "Transform 2D"
        case .fractal: return "Fractal"
        case .voronoi: return "Voronoi"
        case .feedback: return "Feedback"
        case .blur: return "Blur"
        case .displace: return "Displace"
        case .mirror: return "Mirror"
        case .tile: return "Tile"
        case .cameraIn: return "Camera In"
        }
    }

    public var isSignalOnly: Bool {
        switch self {
        case .oscillator, .transform, .blend, .output,
             .solid, .gradient, .oscillator2D, .particles, .hsvAdjust, .transform2D,
             .fractal, .voronoi, .feedback, .blur, .displace, .mirror, .tile, .cameraIn:
            return false
        default:
            return true
        }
    }

    public var inputPortDescriptors: [PatchPortDescriptor] {
        switch self {
        case .audioIn, .pitch, .lfo, .noise, .constant, .time:
            return []
        case .spectrum:
            return [PatchPortDescriptor(name: "signal", type: .signal)]
        case .oscillator:
            return [PatchPortDescriptor(name: "drive", type: .signal)]
        case .transform:
            return [
                PatchPortDescriptor(name: "field", type: .field),
                PatchPortDescriptor(name: "amount", type: .signal),
            ]
        case .blend:
            return [
                PatchPortDescriptor(name: "a", type: .field),
                PatchPortDescriptor(name: "b", type: .field),
                PatchPortDescriptor(name: "mix", type: .signal),
            ]
        case .output:
            return [PatchPortDescriptor(name: "color", type: .field)]
        case .math:
            return [
                PatchPortDescriptor(name: "a", type: .signal),
                PatchPortDescriptor(name: "b", type: .signal),
            ]
        case .envelope:
            return [PatchPortDescriptor(name: "trigger", type: .trigger)]
        case .smooth:
            return [PatchPortDescriptor(name: "signal", type: .signal)]
        case .threshold:
            return [PatchPortDescriptor(name: "signal", type: .signal)]
        case .sampleAndHold:
            return [
                PatchPortDescriptor(name: "signal", type: .signal),
                PatchPortDescriptor(name: "trigger", type: .trigger),
            ]
        case .mix:
            return [
                PatchPortDescriptor(name: "a", type: .signal),
                PatchPortDescriptor(name: "b", type: .signal),
                PatchPortDescriptor(name: "mix", type: .signal),
            ]
        case .remap:
            return [PatchPortDescriptor(name: "signal", type: .signal)]
        case .solid:
            return [
                PatchPortDescriptor(name: "r", type: .signal),
                PatchPortDescriptor(name: "g", type: .signal),
                PatchPortDescriptor(name: "b", type: .signal),
            ]
        case .gradient:
            return [
                PatchPortDescriptor(name: "position", type: .signal),
                PatchPortDescriptor(name: "spread", type: .signal),
            ]
        case .oscillator2D:
            return [
                PatchPortDescriptor(name: "drive", type: .signal),
                PatchPortDescriptor(name: "speed", type: .signal),
            ]
        case .particles:
            return [
                PatchPortDescriptor(name: "trigger", type: .trigger),
                PatchPortDescriptor(name: "intensity", type: .signal),
            ]
        case .hsvAdjust:
            return [
                PatchPortDescriptor(name: "field", type: .field),
                PatchPortDescriptor(name: "hue", type: .signal),
                PatchPortDescriptor(name: "saturation", type: .signal),
                PatchPortDescriptor(name: "brightness", type: .signal),
            ]
        case .transform2D:
            return [
                PatchPortDescriptor(name: "field", type: .field),
                PatchPortDescriptor(name: "rotate", type: .signal),
                PatchPortDescriptor(name: "scale", type: .signal),
            ]
        case .fractal:
            return [
                PatchPortDescriptor(name: "real", type: .signal),
                PatchPortDescriptor(name: "imag", type: .signal),
            ]
        case .voronoi:
            return [PatchPortDescriptor(name: "drive", type: .signal)]
        case .feedback:
            return [PatchPortDescriptor(name: "field", type: .field)]
        case .blur:
            return [
                PatchPortDescriptor(name: "field", type: .field),
                PatchPortDescriptor(name: "radius", type: .signal),
            ]
        case .displace:
            return [
                PatchPortDescriptor(name: "field", type: .field),
                PatchPortDescriptor(name: "map", type: .field),
                PatchPortDescriptor(name: "amount", type: .signal),
            ]
        case .mirror:
            return [PatchPortDescriptor(name: "field", type: .field)]
        case .tile:
            return [
                PatchPortDescriptor(name: "field", type: .field),
                PatchPortDescriptor(name: "scale", type: .signal),
            ]
        case .cameraIn:
            return []
        }
    }

    public var outputPortDescriptors: [PatchPortDescriptor] {
        switch self {
        case .audioIn:
            return [
                PatchPortDescriptor(name: "signal", type: .signal),
                PatchPortDescriptor(name: "attack", type: .trigger),
            ]
        case .spectrum:
            return [
                PatchPortDescriptor(name: "low", type: .signal),
                PatchPortDescriptor(name: "mid", type: .signal),
                PatchPortDescriptor(name: "high", type: .signal),
            ]
        case .oscillator:
            return [PatchPortDescriptor(name: "field", type: .field)]
        case .transform:
            return [PatchPortDescriptor(name: "field", type: .field)]
        case .blend:
            return [PatchPortDescriptor(name: "color", type: .field)]
        case .output:
            return []
        case .pitch:
            return [
                PatchPortDescriptor(name: "confidence", type: .signal),
                PatchPortDescriptor(name: "pitch", type: .signal),
            ]
        case .lfo, .noise, .constant, .time:
            return [PatchPortDescriptor(name: "signal", type: .signal)]
        case .math:
            return [PatchPortDescriptor(name: "result", type: .signal)]
        case .envelope, .smooth, .sampleAndHold, .remap:
            return [PatchPortDescriptor(name: "signal", type: .signal)]
        case .threshold:
            return [PatchPortDescriptor(name: "trigger", type: .trigger)]
        case .mix:
            return [PatchPortDescriptor(name: "result", type: .signal)]
        case .solid, .gradient, .oscillator2D, .particles:
            return [PatchPortDescriptor(name: "field", type: .field)]
        case .hsvAdjust, .transform2D:
            return [PatchPortDescriptor(name: "field", type: .field)]
        case .fractal, .voronoi, .feedback, .blur, .displace, .mirror, .tile, .cameraIn:
            return [PatchPortDescriptor(name: "field", type: .field)]
        }
    }

    public var defaultParameters: [PatchNodeParameter] {
        switch self {
        case .audioIn:
            return [
                PatchNodeParameter(name: "gain", displayName: "Gain", value: 0.72, defaultValue: 0.72, min: 0, max: 2),
            ]
        case .spectrum:
            return [
                PatchNodeParameter(name: "smoothing", displayName: "Smoothing", value: 0.38, defaultValue: 0.38, min: 0, max: 1),
            ]
        case .oscillator:
            return [
                PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.56, defaultValue: 0.56, min: 0, max: 4),
                PatchNodeParameter(name: "phase", displayName: "Phase", value: 0, defaultValue: 0, min: 0, max: 1),
            ]
        case .transform:
            return [
                PatchNodeParameter(name: "amount", displayName: "Amount", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            ]
        case .blend:
            return [
                PatchNodeParameter(name: "mix", displayName: "Mix", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            ]
        case .output:
            return [
                PatchNodeParameter(name: "blackFloor", displayName: "Black Floor", value: 0.90, defaultValue: 0.90, min: 0, max: 1),
            ]
        case .pitch:
            return [
                PatchNodeParameter(name: "sensitivity", displayName: "Sensitivity", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            ]
        case .lfo:
            return [
                PatchNodeParameter(name: "rate", displayName: "Rate", value: 1.0, defaultValue: 1.0, min: 0.01, max: 20),
                PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
                PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 1.0, defaultValue: 1.0, min: 0, max: 1),
            ]
        case .noise:
            return [
                PatchNodeParameter(name: "rate", displayName: "Rate", value: 1.0, defaultValue: 1.0, min: 0.01, max: 10),
                PatchNodeParameter(name: "smoothing", displayName: "Smoothing", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            ]
        case .constant:
            return [
                PatchNodeParameter(name: "value", displayName: "Value", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            ]
        case .time:
            return [
                PatchNodeParameter(name: "rate", displayName: "Rate", value: 1.0, defaultValue: 1.0, min: 0.01, max: 10),
                PatchNodeParameter(name: "mode", displayName: "Mode", value: 0, defaultValue: 0, min: 0, max: 1),
            ]
        case .math:
            return [
                PatchNodeParameter(name: "operation", displayName: "Operation", value: 0, defaultValue: 0, min: 0, max: 5),
            ]
        case .envelope:
            return [
                PatchNodeParameter(name: "attack", displayName: "Attack", value: 0.05, defaultValue: 0.05, min: 0.001, max: 2),
                PatchNodeParameter(name: "decay", displayName: "Decay", value: 0.2, defaultValue: 0.2, min: 0.001, max: 2),
                PatchNodeParameter(name: "sustain", displayName: "Sustain", value: 0.6, defaultValue: 0.6, min: 0, max: 1),
                PatchNodeParameter(name: "release", displayName: "Release", value: 0.4, defaultValue: 0.4, min: 0.001, max: 4),
            ]
        case .smooth:
            return [
                PatchNodeParameter(name: "smoothing", displayName: "Smoothing", value: 0.8, defaultValue: 0.8, min: 0, max: 0.999),
            ]
        case .threshold:
            return [
                PatchNodeParameter(name: "threshold", displayName: "Threshold", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
                PatchNodeParameter(name: "hysteresis", displayName: "Hysteresis", value: 0.05, defaultValue: 0.05, min: 0, max: 0.5),
            ]
        case .sampleAndHold:
            return [
                PatchNodeParameter(name: "gain", displayName: "Gain", value: 1.0, defaultValue: 1.0, min: 0, max: 2),
            ]
        case .mix:
            return [
                PatchNodeParameter(name: "mix", displayName: "Mix", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            ]
        case .remap:
            return [
                PatchNodeParameter(name: "inputMin", displayName: "In Min", value: 0, defaultValue: 0, min: 0, max: 1),
                PatchNodeParameter(name: "inputMax", displayName: "In Max", value: 1, defaultValue: 1, min: 0, max: 1),
                PatchNodeParameter(name: "outputMin", displayName: "Out Min", value: 0, defaultValue: 0, min: 0, max: 1),
                PatchNodeParameter(name: "outputMax", displayName: "Out Max", value: 1, defaultValue: 1, min: 0, max: 1),
                PatchNodeParameter(name: "curve", displayName: "Curve", value: 0, defaultValue: 0, min: 0, max: 3),
            ]
        case .solid:
            return [
                PatchNodeParameter(name: "r", displayName: "Red", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
                PatchNodeParameter(name: "g", displayName: "Green", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
                PatchNodeParameter(name: "b", displayName: "Blue", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            ]
        case .gradient:
            return [
                PatchNodeParameter(name: "mode", displayName: "Mode", value: 0, defaultValue: 0, min: 0, max: 2),
                PatchNodeParameter(name: "hueA", displayName: "Hue A", value: 0.55, defaultValue: 0.55, min: 0, max: 1),
                PatchNodeParameter(name: "hueB", displayName: "Hue B", value: 0.85, defaultValue: 0.85, min: 0, max: 1),
            ]
        case .oscillator2D:
            return [
                PatchNodeParameter(name: "scaleX", displayName: "Scale X", value: 6, defaultValue: 6, min: 1, max: 40),
                PatchNodeParameter(name: "scaleY", displayName: "Scale Y", value: 4, defaultValue: 4, min: 1, max: 40),
                PatchNodeParameter(name: "hue", displayName: "Hue", value: 0.6, defaultValue: 0.6, min: 0, max: 1),
            ]
        case .particles:
            return [
                PatchNodeParameter(name: "lifetime", displayName: "Lifetime", value: 1.2, defaultValue: 1.2, min: 0.1, max: 5),
                PatchNodeParameter(name: "size", displayName: "Size", value: 0.04, defaultValue: 0.04, min: 0.005, max: 0.2),
                PatchNodeParameter(name: "count", displayName: "Count", value: 32, defaultValue: 32, min: 4, max: 128),
            ]
        case .hsvAdjust:
            return [
                PatchNodeParameter(name: "hueShift", displayName: "Hue Shift", value: 0, defaultValue: 0, min: 0, max: 1),
                PatchNodeParameter(name: "satMul", displayName: "Sat Mul", value: 1, defaultValue: 1, min: 0, max: 2),
                PatchNodeParameter(name: "valMul", displayName: "Val Mul", value: 1, defaultValue: 1, min: 0, max: 2),
            ]
        case .transform2D:
            return [
                PatchNodeParameter(name: "translateX", displayName: "Translate X", value: 0, defaultValue: 0, min: -1, max: 1),
                PatchNodeParameter(name: "translateY", displayName: "Translate Y", value: 0, defaultValue: 0, min: -1, max: 1),
                PatchNodeParameter(name: "rotation", displayName: "Rotation", value: 0, defaultValue: 0, min: 0, max: 1),
                PatchNodeParameter(name: "scale", displayName: "Scale", value: 1, defaultValue: 1, min: 0.1, max: 4),
            ]
        case .fractal:
            return [
                PatchNodeParameter(name: "iterations", displayName: "Iterations", value: 24, defaultValue: 24, min: 4, max: 64),
                PatchNodeParameter(name: "zoom", displayName: "Zoom", value: 1.5, defaultValue: 1.5, min: 0.5, max: 4),
                PatchNodeParameter(name: "colorCycles", displayName: "Color Cycles", value: 3, defaultValue: 3, min: 1, max: 8),
            ]
        case .voronoi:
            return [
                PatchNodeParameter(name: "cellCount", displayName: "Cell Count", value: 8, defaultValue: 8, min: 2, max: 32),
                PatchNodeParameter(name: "jitter", displayName: "Jitter", value: 0.8, defaultValue: 0.8, min: 0, max: 1),
            ]
        case .feedback:
            return [
                PatchNodeParameter(name: "decay", displayName: "Decay", value: 0.92, defaultValue: 0.92, min: 0, max: 1),
                PatchNodeParameter(name: "blur", displayName: "Blur", value: 0.3, defaultValue: 0.3, min: 0, max: 1),
            ]
        case .blur:
            return [
                PatchNodeParameter(name: "radius", displayName: "Radius", value: 4, defaultValue: 4, min: 0, max: 20),
                PatchNodeParameter(name: "passes", displayName: "Passes", value: 2, defaultValue: 2, min: 1, max: 4),
            ]
        case .displace:
            return [
                PatchNodeParameter(name: "amount", displayName: "Amount", value: 0.1, defaultValue: 0.1, min: 0, max: 1),
            ]
        case .mirror:
            return [
                PatchNodeParameter(name: "foldCount", displayName: "Folds", value: 4, defaultValue: 4, min: 1, max: 16),
                PatchNodeParameter(name: "angle", displayName: "Angle", value: 0, defaultValue: 0, min: 0, max: 1),
            ]
        case .tile:
            return [
                PatchNodeParameter(name: "repeatX", displayName: "Repeat X", value: 2, defaultValue: 2, min: 1, max: 16),
                PatchNodeParameter(name: "repeatY", displayName: "Repeat Y", value: 2, defaultValue: 2, min: 1, max: 16),
            ]
        case .cameraIn:
            return [
                PatchNodeParameter(name: "mirror", displayName: "Mirror", value: 1, defaultValue: 1, min: 0, max: 1),
            ]
        }
    }
}

// MARK: - Node

public struct CustomPatchNode: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: CustomPatchNodeKind
    public var title: String
    public var position: CustomPatchPoint
    public var parameters: [PatchNodeParameter]

    public var inputPorts: [String] { kind.inputPortDescriptors.map(\.name) }
    public var outputPorts: [String] { kind.outputPortDescriptors.map(\.name) }

    public init(
        id: UUID = UUID(),
        kind: CustomPatchNodeKind,
        title: String,
        position: CustomPatchPoint,
        parameters: [PatchNodeParameter]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.position = position
        self.parameters = parameters ?? kind.defaultParameters
    }
}

extension CustomPatchNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, position, parameters
        case inspectorHints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(CustomPatchNodeKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        position = try container.decode(CustomPatchPoint.self, forKey: .position)

        if let params = try container.decodeIfPresent([PatchNodeParameter].self, forKey: .parameters) {
            parameters = params
        } else if let hints = try container.decodeIfPresent([String: Double].self, forKey: .inspectorHints) {
            let defaults = kind.defaultParameters
            parameters = defaults.map { defaultParam in
                var param = defaultParam
                if let hintValue = hints[param.name] {
                    param.value = hintValue
                }
                return param
            }
        } else {
            parameters = kind.defaultParameters
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(position, forKey: .position)
        try container.encode(parameters, forKey: .parameters)
    }
}

// MARK: - Connection

public struct CustomPatchConnection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var fromNodeID: UUID
    public var fromPort: String
    public var toNodeID: UUID
    public var toPort: String

    public init(
        id: UUID = UUID(),
        fromNodeID: UUID,
        fromPort: String,
        toNodeID: UUID,
        toPort: String
    ) {
        self.id = id
        self.fromNodeID = fromNodeID
        self.fromPort = fromPort
        self.toNodeID = toNodeID
        self.toPort = toPort
    }
}

// MARK: - Group

public struct CustomPatchGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var nodeIDs: Set<UUID>
    public var colorIndex: Int

    public init(id: UUID = UUID(), name: String, nodeIDs: Set<UUID>, colorIndex: Int = 0) {
        self.id = id
        self.name = name
        self.nodeIDs = nodeIDs
        self.colorIndex = colorIndex
    }

    public static let groupColors: [String] = [
        "orange", "blue", "green", "purple", "red", "teal", "pink", "yellow"
    ]
}

// MARK: - Patch

public struct CustomPatch: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var nodes: [CustomPatchNode]
    public var connections: [CustomPatchConnection]
    public var groups: [CustomPatchGroup]
    public var viewport: CustomPatchViewport
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        nodes: [CustomPatchNode],
        connections: [CustomPatchConnection],
        groups: [CustomPatchGroup] = [],
        viewport: CustomPatchViewport = CustomPatchViewport(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.nodes = nodes
        self.connections = connections
        self.groups = groups
        self.viewport = viewport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        nodes = try container.decode([CustomPatchNode].self, forKey: .nodes)
        connections = try container.decode([CustomPatchConnection].self, forKey: .connections)
        groups = try container.decodeIfPresent([CustomPatchGroup].self, forKey: .groups) ?? []
        viewport = try container.decode(CustomPatchViewport.self, forKey: .viewport)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, nodes, connections, groups, viewport, createdAt, updatedAt
    }

    public static func seedScaffold() -> CustomPatch {
        let nodeIDs = (
            audioIn: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            spectrum: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            oscillator: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
            blend: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
            output: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID()
        )
        let now = Date(timeIntervalSince1970: 1_763_628_400)
        return CustomPatch(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA") ?? UUID(),
            name: "Default Scaffold",
            nodes: [
                CustomPatchNode(
                    id: nodeIDs.audioIn,
                    kind: .audioIn,
                    title: "Audio In",
                    position: CustomPatchPoint(x: 96, y: 172),
                    parameters: [
                        PatchNodeParameter(name: "gain", displayName: "Gain", value: 0.72, defaultValue: 0.72, min: 0, max: 2),
                    ]
                ),
                CustomPatchNode(
                    id: nodeIDs.spectrum,
                    kind: .spectrum,
                    title: "Band Split",
                    position: CustomPatchPoint(x: 286, y: 172),
                    parameters: [
                        PatchNodeParameter(name: "smoothing", displayName: "Smoothing", value: 0.38, defaultValue: 0.38, min: 0, max: 1),
                    ]
                ),
                CustomPatchNode(
                    id: nodeIDs.oscillator,
                    kind: .oscillator,
                    title: "Vector Oscillator",
                    position: CustomPatchPoint(x: 486, y: 136),
                    parameters: [
                        PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.56, defaultValue: 0.56, min: 0, max: 4),
                        PatchNodeParameter(name: "phase", displayName: "Phase", value: 0, defaultValue: 0, min: 0, max: 1),
                    ]
                ),
                CustomPatchNode(
                    id: nodeIDs.blend,
                    kind: .blend,
                    title: "Chromatic Blend",
                    position: CustomPatchPoint(x: 486, y: 250),
                    parameters: [
                        PatchNodeParameter(name: "mix", displayName: "Mix", value: 0.50, defaultValue: 0.50, min: 0, max: 1),
                    ]
                ),
                CustomPatchNode(
                    id: nodeIDs.output,
                    kind: .output,
                    title: "Stage Output",
                    position: CustomPatchPoint(x: 690, y: 196),
                    parameters: [
                        PatchNodeParameter(name: "blackFloor", displayName: "Black Floor", value: 0.90, defaultValue: 0.90, min: 0, max: 1),
                    ]
                ),
            ],
            connections: [
                CustomPatchConnection(
                    id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB") ?? UUID(),
                    fromNodeID: nodeIDs.audioIn,
                    fromPort: "signal",
                    toNodeID: nodeIDs.spectrum,
                    toPort: "signal"
                ),
                CustomPatchConnection(
                    id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC") ?? UUID(),
                    fromNodeID: nodeIDs.spectrum,
                    fromPort: "mid",
                    toNodeID: nodeIDs.oscillator,
                    toPort: "drive"
                ),
                CustomPatchConnection(
                    id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD") ?? UUID(),
                    fromNodeID: nodeIDs.oscillator,
                    fromPort: "field",
                    toNodeID: nodeIDs.blend,
                    toPort: "a"
                ),
                CustomPatchConnection(
                    id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE") ?? UUID(),
                    fromNodeID: nodeIDs.blend,
                    fromPort: "color",
                    toNodeID: nodeIDs.output,
                    toPort: "color"
                ),
            ],
            viewport: CustomPatchViewport(zoom: 1.0, offsetX: 0, offsetY: 0),
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Factory Presets

    public static func factoryPresets() -> [CustomPatch] {
        let now = Date(timeIntervalSince1970: 1_763_628_400)
        return [
            factoryBreathingFractal(now: now),
            factoryParticleNebula(now: now),
            factoryCrystalLattice(now: now),
        ]
    }

    // MARK: Breathing Fractal
    // Organic Julia-set fractal that drifts autonomously via LFOs and becomes
    // audio-reactive when mic input is present. Slow LFO breathing on the real axis,
    // faster LFO shimmer on the imaginary axis, audio spectrum adds on top.
    // Feedback trails create temporal memory; hue cycles continuously.

    private static func factoryBreathingFractal(now: Date) -> CustomPatch {
        // Audio path (additive, not required)
        let audioIn = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000001")!, kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: -400, y: 0))
        let spectrum = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000002")!, kind: .spectrum, title: "Spectrum", position: CustomPatchPoint(x: -200, y: 0))
        // Autonomous LFO breathing drives the fractal even without audio
        let lfoReal = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000003")!, kind: .lfo, title: "Breathe LFO", position: CustomPatchPoint(x: -200, y: -140), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.15, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 0.6, defaultValue: 1.0, min: 0, max: 1),
        ])
        let lfoImag = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000004")!, kind: .lfo, title: "Shimmer LFO", position: CustomPatchPoint(x: -200, y: -60), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.23, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 0.4, defaultValue: 1.0, min: 0, max: 1),
        ])
        // Mix LFO base with audio spectrum (add) so fractal always animates
        let mixReal = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000005")!, kind: .math, title: "Add Real", position: CustomPatchPoint(x: 50, y: -100), parameters: [
            PatchNodeParameter(name: "operation", displayName: "Operation", value: 0, defaultValue: 0, min: 0, max: 5),
        ])
        let mixImag = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000006")!, kind: .math, title: "Add Imag", position: CustomPatchPoint(x: 50, y: -20), parameters: [
            PatchNodeParameter(name: "operation", displayName: "Operation", value: 0, defaultValue: 0, min: 0, max: 5),
        ])
        let fractal = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000007")!, kind: .fractal, title: "Fractal", position: CustomPatchPoint(x: 260, y: -60), parameters: [
            PatchNodeParameter(name: "iterations", displayName: "Iterations", value: 32, defaultValue: 24, min: 4, max: 64),
            PatchNodeParameter(name: "zoom", displayName: "Zoom", value: 2.0, defaultValue: 1.5, min: 0.5, max: 4),
            PatchNodeParameter(name: "colorCycles", displayName: "Color Cycles", value: 4, defaultValue: 3, min: 1, max: 8),
        ])
        let blend = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000008")!, kind: .blend, title: "Blend", position: CustomPatchPoint(x: 460, y: -30), parameters: [
            PatchNodeParameter(name: "mix", displayName: "Mix", value: 0.3, defaultValue: 0.5, min: 0, max: 1),
        ])
        let feedback = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-000000000009")!, kind: .feedback, title: "Feedback", position: CustomPatchPoint(x: 460, y: 100), parameters: [
            PatchNodeParameter(name: "decay", displayName: "Decay", value: 0.92, defaultValue: 0.92, min: 0, max: 1),
            PatchNodeParameter(name: "blur", displayName: "Blur", value: 0.12, defaultValue: 0.3, min: 0, max: 1),
        ])
        // Slow hue rotation LFO so colors cycle even without audio
        let lfoHue = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-00000000000A")!, kind: .lfo, title: "Hue LFO", position: CustomPatchPoint(x: 460, y: -160), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.06, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 1.0, defaultValue: 1.0, min: 0, max: 1),
        ])
        let hsvAdjust = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-00000000000B")!, kind: .hsvAdjust, title: "HSV Adjust", position: CustomPatchPoint(x: 660, y: -30))
        let output = CustomPatchNode(id: UUID(uuidString: "FA000001-0001-0001-0001-00000000000C")!, kind: .output, title: "Output", position: CustomPatchPoint(x: 860, y: -30))

        let nodes = [audioIn, spectrum, lfoReal, lfoImag, mixReal, mixImag, fractal, blend, feedback, lfoHue, hsvAdjust, output]
        let connections = [
            // Audio analysis path
            CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: spectrum.id, toPort: "signal"),
            // LFO base + audio spectrum sum → fractal parameters
            CustomPatchConnection(fromNodeID: lfoReal.id, fromPort: "signal", toNodeID: mixReal.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "low", toNodeID: mixReal.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: lfoImag.id, fromPort: "signal", toNodeID: mixImag.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "high", toNodeID: mixImag.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: mixReal.id, fromPort: "result", toNodeID: fractal.id, toPort: "real"),
            CustomPatchConnection(fromNodeID: mixImag.id, fromPort: "result", toNodeID: fractal.id, toPort: "imag"),
            // Fractal + feedback → blend → output
            CustomPatchConnection(fromNodeID: fractal.id, fromPort: "field", toNodeID: blend.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: feedback.id, fromPort: "field", toNodeID: blend.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: feedback.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: hsvAdjust.id, toPort: "field"),
            // Slow hue rotation
            CustomPatchConnection(fromNodeID: lfoHue.id, fromPort: "signal", toNodeID: hsvAdjust.id, toPort: "hue"),
            CustomPatchConnection(fromNodeID: hsvAdjust.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]
        let groups = [
            CustomPatchGroup(id: UUID(uuidString: "FA000001-0001-0001-0001-A00000000001")!, name: "Audio Analysis", nodeIDs: [audioIn.id, spectrum.id], colorIndex: 1),
            CustomPatchGroup(id: UUID(uuidString: "FA000001-0001-0001-0001-A00000000002")!, name: "LFO Animation", nodeIDs: [lfoReal.id, lfoImag.id, mixReal.id, mixImag.id], colorIndex: 3),
            CustomPatchGroup(id: UUID(uuidString: "FA000001-0001-0001-0001-A00000000003")!, name: "Fractal Core", nodeIDs: [fractal.id, blend.id, feedback.id], colorIndex: 0),
        ]
        return CustomPatch(
            id: UUID(uuidString: "FA000001-0001-0001-0001-FFFFFFFFFFFF")!,
            name: "Breathing Fractal",
            nodes: nodes, connections: connections, groups: groups,
            createdAt: now, updatedAt: now
        )
    }

    // MARK: Particle Nebula
    // Voronoi cells pulse autonomously via LFO; blurred and displaced through
    // feedback for nebula-cloud trails. Audio attacks inject extra particle bursts
    // and audio amplitude drives voronoi cell motion. Looks alive without audio;
    // becomes explosive with music.

    private static func factoryParticleNebula(now: Date) -> CustomPatch {
        // Audio path (additive)
        let audioIn = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000001")!, kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: -400, y: 0))
        // LFO drives voronoi continuously; audio amplitude adds on top
        let lfoDrive = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000002")!, kind: .lfo, title: "Pulse LFO", position: CustomPatchPoint(x: -400, y: -120), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.3, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 0.7, defaultValue: 1.0, min: 0, max: 1),
        ])
        let addDrive = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000003")!, kind: .math, title: "Add Drive", position: CustomPatchPoint(x: -180, y: -60), parameters: [
            PatchNodeParameter(name: "operation", displayName: "Operation", value: 0, defaultValue: 0, min: 0, max: 5),
        ])
        // LFO generates trigger pulses for particle emission (threshold converts sine to trigger)
        let lfoEmit = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000004")!, kind: .lfo, title: "Emit LFO", position: CustomPatchPoint(x: -400, y: 120), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 2.5, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 3, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 1.0, defaultValue: 1.0, min: 0, max: 1),
        ])
        let threshold = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000005")!, kind: .threshold, title: "Emit Gate", position: CustomPatchPoint(x: -180, y: 120), parameters: [
            PatchNodeParameter(name: "threshold", displayName: "Threshold", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
            PatchNodeParameter(name: "mode", displayName: "Mode", value: 0, defaultValue: 0, min: 0, max: 2),
        ])
        let particles = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000006")!, kind: .particles, title: "Particles", position: CustomPatchPoint(x: 40, y: 0), parameters: [
            PatchNodeParameter(name: "lifetime", displayName: "Lifetime", value: 3.0, defaultValue: 1.2, min: 0.1, max: 5),
            PatchNodeParameter(name: "size", displayName: "Size", value: 0.06, defaultValue: 0.04, min: 0.005, max: 0.2),
            PatchNodeParameter(name: "count", displayName: "Count", value: 96, defaultValue: 32, min: 4, max: 128),
        ])
        let voronoi = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000007")!, kind: .voronoi, title: "Voronoi", position: CustomPatchPoint(x: 40, y: 150), parameters: [
            PatchNodeParameter(name: "cellCount", displayName: "Cell Count", value: 10, defaultValue: 8, min: 2, max: 32),
            PatchNodeParameter(name: "jitter", displayName: "Jitter", value: 0.9, defaultValue: 0.8, min: 0, max: 1),
        ])
        let blur = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000008")!, kind: .blur, title: "Blur", position: CustomPatchPoint(x: 240, y: 0), parameters: [
            PatchNodeParameter(name: "radius", displayName: "Radius", value: 6, defaultValue: 4, min: 0, max: 20),
        ])
        let displace = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-000000000009")!, kind: .displace, title: "Displace", position: CustomPatchPoint(x: 440, y: 0), parameters: [
            PatchNodeParameter(name: "amount", displayName: "Amount", value: 0.10, defaultValue: 0.1, min: 0, max: 1),
        ])
        let blend = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-00000000000A")!, kind: .blend, title: "Blend", position: CustomPatchPoint(x: 640, y: 0), parameters: [
            PatchNodeParameter(name: "mix", displayName: "Mix", value: 0.35, defaultValue: 0.5, min: 0, max: 1),
        ])
        let feedback = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-00000000000B")!, kind: .feedback, title: "Feedback", position: CustomPatchPoint(x: 640, y: 130), parameters: [
            PatchNodeParameter(name: "decay", displayName: "Decay", value: 0.95, defaultValue: 0.92, min: 0, max: 1),
            PatchNodeParameter(name: "blur", displayName: "Blur", value: 0.18, defaultValue: 0.3, min: 0, max: 1),
        ])
        let lfoHue = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-00000000000C")!, kind: .lfo, title: "Hue LFO", position: CustomPatchPoint(x: 640, y: -140), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.06, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 1.0, defaultValue: 1.0, min: 0, max: 1),
        ])
        let hsvAdjust = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-00000000000D")!, kind: .hsvAdjust, title: "HSV Adjust", position: CustomPatchPoint(x: 840, y: 0))
        let output = CustomPatchNode(id: UUID(uuidString: "FA000002-0002-0002-0002-00000000000E")!, kind: .output, title: "Output", position: CustomPatchPoint(x: 1040, y: 0))

        let nodes = [audioIn, lfoDrive, addDrive, lfoEmit, threshold, particles, voronoi, blur, displace, blend, feedback, lfoHue, hsvAdjust, output]
        let connections = [
            // LFO base drive + audio amplitude → voronoi drive
            CustomPatchConnection(fromNodeID: lfoDrive.id, fromPort: "signal", toNodeID: addDrive.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: addDrive.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: addDrive.id, fromPort: "result", toNodeID: voronoi.id, toPort: "drive"),
            // LFO square wave → threshold gate → particle trigger (continuous emission)
            CustomPatchConnection(fromNodeID: lfoEmit.id, fromPort: "signal", toNodeID: threshold.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: threshold.id, fromPort: "trigger", toNodeID: particles.id, toPort: "trigger"),
            // Audio amplitude → particle intensity (brighter bursts with louder audio)
            CustomPatchConnection(fromNodeID: addDrive.id, fromPort: "result", toNodeID: particles.id, toPort: "intensity"),
            // Particles → blur → displace (warped by voronoi) → blend + feedback → HSV → output
            CustomPatchConnection(fromNodeID: particles.id, fromPort: "field", toNodeID: blur.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: blur.id, fromPort: "field", toNodeID: displace.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: voronoi.id, fromPort: "field", toNodeID: displace.id, toPort: "map"),
            CustomPatchConnection(fromNodeID: displace.id, fromPort: "field", toNodeID: blend.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: feedback.id, fromPort: "field", toNodeID: blend.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: feedback.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: blend.id, fromPort: "color", toNodeID: hsvAdjust.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: lfoHue.id, fromPort: "signal", toNodeID: hsvAdjust.id, toPort: "hue"),
            CustomPatchConnection(fromNodeID: hsvAdjust.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]
        let groups = [
            CustomPatchGroup(id: UUID(uuidString: "FA000002-0002-0002-0002-A00000000001")!, name: "Audio + LFO Drive", nodeIDs: [audioIn.id, lfoDrive.id, addDrive.id], colorIndex: 1),
            CustomPatchGroup(id: UUID(uuidString: "FA000002-0002-0002-0002-A00000000002")!, name: "Particle Emitter", nodeIDs: [lfoEmit.id, threshold.id, particles.id], colorIndex: 2),
            CustomPatchGroup(id: UUID(uuidString: "FA000002-0002-0002-0002-A00000000003")!, name: "Nebula Processing", nodeIDs: [voronoi.id, blur.id, displace.id, blend.id, feedback.id], colorIndex: 0),
        ]
        return CustomPatch(
            id: UUID(uuidString: "FA000002-0002-0002-0002-FFFFFFFFFFFF")!,
            name: "Particle Nebula",
            nodes: nodes, connections: connections, groups: groups,
            createdAt: now, updatedAt: now
        )
    }

    // MARK: Crystal Lattice
    // Geometric tiled oscillator patterns with kaleidoscope symmetry.
    // LFO provides base drive so pattern is visible without audio.
    // Audio amplitude adds brightness; S&H locks pitch on attacks for
    // quantized tile density shifts.

    private static func factoryCrystalLattice(now: Date) -> CustomPatch {
        let audioIn = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000001")!, kind: .audioIn, title: "Audio In", position: CustomPatchPoint(x: -400, y: -30))
        let spectrum = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000002")!, kind: .spectrum, title: "Spectrum", position: CustomPatchPoint(x: -200, y: -80))
        let pitch = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000003")!, kind: .pitch, title: "Pitch", position: CustomPatchPoint(x: -200, y: 80))
        // LFO provides base drive so the oscillator is always visible
        let lfoDrive = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000004")!, kind: .lfo, title: "Drive LFO", position: CustomPatchPoint(x: -200, y: -180), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.18, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 0.6, defaultValue: 1.0, min: 0, max: 1),
        ])
        let addDrive = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-00000000000F")!, kind: .math, title: "Add Drive", position: CustomPatchPoint(x: 0, y: -120), parameters: [
            PatchNodeParameter(name: "operation", displayName: "Operation", value: 0, defaultValue: 0, min: 0, max: 5),
        ])
        let remapPitch = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000005")!, kind: .remap, title: "Pitch → Scale", position: CustomPatchPoint(x: 0, y: 120), parameters: [
            PatchNodeParameter(name: "inputMin", displayName: "In Min", value: 0, defaultValue: 0, min: 0, max: 1),
            PatchNodeParameter(name: "inputMax", displayName: "In Max", value: 1, defaultValue: 1, min: 0, max: 1),
            PatchNodeParameter(name: "outputMin", displayName: "Out Min", value: 0.3, defaultValue: 0, min: 0, max: 1),
            PatchNodeParameter(name: "outputMax", displayName: "Out Max", value: 0.9, defaultValue: 1, min: 0, max: 1),
            PatchNodeParameter(name: "curve", displayName: "Curve", value: 0, defaultValue: 0, min: 0, max: 3),
        ])
        let sampleAndHold = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000006")!, kind: .sampleAndHold, title: "S&H", position: CustomPatchPoint(x: 200, y: 120))
        let constant = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000007")!, kind: .constant, title: "Scale Factor", position: CustomPatchPoint(x: 0, y: 220), parameters: [
            PatchNodeParameter(name: "value", displayName: "Value", value: 0.5, defaultValue: 0.5, min: 0, max: 1),
        ])
        let math = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000008")!, kind: .math, title: "Multiply", position: CustomPatchPoint(x: 200, y: 220), parameters: [
            PatchNodeParameter(name: "operation", displayName: "Operation", value: 1, defaultValue: 0, min: 0, max: 5),
        ])
        let lfo = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-000000000009")!, kind: .lfo, title: "Rotate LFO", position: CustomPatchPoint(x: 400, y: 160), parameters: [
            PatchNodeParameter(name: "rate", displayName: "Rate", value: 0.12, defaultValue: 1.0, min: 0.01, max: 20),
            PatchNodeParameter(name: "waveform", displayName: "Waveform", value: 0, defaultValue: 0, min: 0, max: 3),
            PatchNodeParameter(name: "amplitude", displayName: "Amplitude", value: 1.0, defaultValue: 1.0, min: 0, max: 1),
        ])
        let osc2D = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-00000000000A")!, kind: .oscillator2D, title: "Osc 2D", position: CustomPatchPoint(x: 200, y: -60), parameters: [
            PatchNodeParameter(name: "scaleX", displayName: "Scale X", value: 10, defaultValue: 6, min: 1, max: 40),
            PatchNodeParameter(name: "scaleY", displayName: "Scale Y", value: 8, defaultValue: 4, min: 1, max: 40),
            PatchNodeParameter(name: "hue", displayName: "Hue", value: 0.55, defaultValue: 0.6, min: 0, max: 1),
        ])
        let mirror = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-00000000000B")!, kind: .mirror, title: "Mirror", position: CustomPatchPoint(x: 400, y: -60), parameters: [
            PatchNodeParameter(name: "foldCount", displayName: "Folds", value: 8, defaultValue: 4, min: 1, max: 16),
            PatchNodeParameter(name: "angle", displayName: "Angle", value: 0, defaultValue: 0, min: 0, max: 1),
        ])
        let tile = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-00000000000C")!, kind: .tile, title: "Tile", position: CustomPatchPoint(x: 600, y: -40), parameters: [
            PatchNodeParameter(name: "repeatX", displayName: "Repeat X", value: 3, defaultValue: 2, min: 1, max: 16),
            PatchNodeParameter(name: "repeatY", displayName: "Repeat Y", value: 3, defaultValue: 2, min: 1, max: 16),
        ])
        let transform2D = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-00000000000D")!, kind: .transform2D, title: "Transform 2D", position: CustomPatchPoint(x: 800, y: -40))
        let output = CustomPatchNode(id: UUID(uuidString: "FA000003-0003-0003-0003-00000000000E")!, kind: .output, title: "Output", position: CustomPatchPoint(x: 1000, y: -40))

        let nodes = [audioIn, spectrum, pitch, lfoDrive, addDrive, remapPitch, sampleAndHold, constant, math, lfo, osc2D, mirror, tile, transform2D, output]
        let connections = [
            CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "signal", toNodeID: spectrum.id, toPort: "signal"),
            // LFO base drive + bass energy → osc2D drive (always visible)
            CustomPatchConnection(fromNodeID: lfoDrive.id, fromPort: "signal", toNodeID: addDrive.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "low", toNodeID: addDrive.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: addDrive.id, fromPort: "result", toNodeID: osc2D.id, toPort: "drive"),
            CustomPatchConnection(fromNodeID: spectrum.id, fromPort: "mid", toNodeID: osc2D.id, toPort: "speed"),
            // Pitch detection → S&H → multiply → tile scale
            CustomPatchConnection(fromNodeID: audioIn.id, fromPort: "attack", toNodeID: sampleAndHold.id, toPort: "trigger"),
            CustomPatchConnection(fromNodeID: pitch.id, fromPort: "pitch", toNodeID: remapPitch.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: remapPitch.id, fromPort: "signal", toNodeID: sampleAndHold.id, toPort: "signal"),
            CustomPatchConnection(fromNodeID: sampleAndHold.id, fromPort: "signal", toNodeID: math.id, toPort: "a"),
            CustomPatchConnection(fromNodeID: constant.id, fromPort: "signal", toNodeID: math.id, toPort: "b"),
            CustomPatchConnection(fromNodeID: math.id, fromPort: "result", toNodeID: tile.id, toPort: "scale"),
            // Visual chain: osc2D → mirror → tile → rotate → output
            CustomPatchConnection(fromNodeID: lfo.id, fromPort: "signal", toNodeID: transform2D.id, toPort: "rotate"),
            CustomPatchConnection(fromNodeID: osc2D.id, fromPort: "field", toNodeID: mirror.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: mirror.id, fromPort: "field", toNodeID: tile.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: tile.id, fromPort: "field", toNodeID: transform2D.id, toPort: "field"),
            CustomPatchConnection(fromNodeID: transform2D.id, fromPort: "field", toNodeID: output.id, toPort: "color"),
        ]
        let groups = [
            CustomPatchGroup(id: UUID(uuidString: "FA000003-0003-0003-0003-A00000000001")!, name: "Audio + LFO Drive", nodeIDs: [audioIn.id, spectrum.id, pitch.id, lfoDrive.id, addDrive.id], colorIndex: 1),
            CustomPatchGroup(id: UUID(uuidString: "FA000003-0003-0003-0003-A00000000002")!, name: "Pitch Lock", nodeIDs: [remapPitch.id, sampleAndHold.id, constant.id, math.id], colorIndex: 3),
            CustomPatchGroup(id: UUID(uuidString: "FA000003-0003-0003-0003-A00000000003")!, name: "Visual Chain", nodeIDs: [osc2D.id, mirror.id, tile.id, transform2D.id], colorIndex: 2),
        ]
        return CustomPatch(
            id: UUID(uuidString: "FA000003-0003-0003-0003-FFFFFFFFFFFF")!,
            name: "Crystal Lattice",
            nodes: nodes, connections: connections, groups: groups,
            createdAt: now, updatedAt: now
        )
    }
}

// MARK: - Library

public struct CustomPatchLibrary: Codable, Equatable, Sendable {
    public var activePatchID: UUID?
    public var patches: [CustomPatch]

    public init(activePatchID: UUID? = nil, patches: [CustomPatch] = []) {
        self.activePatchID = activePatchID
        self.patches = patches
    }

    public static func seededDefault() -> CustomPatchLibrary {
        let patches = CustomPatch.factoryPresets()
        return CustomPatchLibrary(activePatchID: patches.first?.id, patches: patches)
    }
}

// MARK: - Clipboard Snapshot

public struct CustomPatchClipboard: Codable, Sendable {
    public var nodes: [CustomPatchNode]
    public var connections: [CustomPatchConnection]

    public init(nodes: [CustomPatchNode], connections: [CustomPatchConnection]) {
        self.nodes = nodes
        self.connections = connections
    }
}

// MARK: - Supporting Types

public struct CustomPatchViewport: Codable, Equatable, Sendable {
    public var zoom: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(zoom: Double = 1.0, offsetX: Double = 0, offsetY: Double = 0) {
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

public struct CustomPatchPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
