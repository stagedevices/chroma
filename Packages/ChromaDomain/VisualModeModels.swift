import Foundation

public enum VisualModeID: String, CaseIterable, Codable, Identifiable, Sendable {
    case colorShift
    case prismField
    case tunnelCels
    case fractalCaustics
    case riemannCorridor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .colorShift:
            return "Color Shift"
        case .prismField:
            return "Prism Field"
        case .tunnelCels:
            return "Tunnel Cels"
        case .fractalCaustics:
            return "Fractal Caustics"
        case .riemannCorridor:
            return "Mandelbrot"
        }
    }
    
    public var shortSummary: String {
        switch self {
        case .colorShift:
            return "Amplitude-weighted hue motion with stage-black composition."
        case .prismField:
            return "Refraction-driven surfaces with dense motion."
        case .tunnelCels:
            return "Attack-spawned cel objects in a stage tunnel."
        case .fractalCaustics:
            return "Orbit-trap Julia caustics with attack pulses."
        case .riemannCorridor:
            return "Audio-flown Mandelbrot traversal with contour-rich domain coloring."
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case Self.colorShift.rawValue:
            self = .colorShift
        case Self.prismField.rawValue:
            self = .prismField
        case Self.tunnelCels.rawValue:
            self = .tunnelCels
        case Self.fractalCaustics.rawValue:
            self = .fractalCaustics
        case Self.riemannCorridor.rawValue:
            self = .riemannCorridor
        case "spectralBloom", "attackParticleHalo", "monochromePulse":
            self = .colorShift
        default:
            self = .colorShift
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct VisualModeDescriptor: Identifiable, Codable, Equatable {
    public let id: VisualModeID
    public var name: String
    public var summary: String
    public var supportsMorphing: Bool

    public init(id: VisualModeID, name: String, summary: String, supportsMorphing: Bool) {
        self.id = id
        self.name = name
        self.summary = summary
        self.supportsMorphing = supportsMorphing
    }
}

public struct VisualMorphState: Codable, Equatable {
    public var sourceModeID: VisualModeID?
    public var destinationModeID: VisualModeID?
    public var progress: Double

    public init(sourceModeID: VisualModeID? = nil, destinationModeID: VisualModeID? = nil, progress: Double = 0) {
        self.sourceModeID = sourceModeID
        self.destinationModeID = destinationModeID
        self.progress = progress
    }
}
