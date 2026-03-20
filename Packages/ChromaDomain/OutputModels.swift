import Foundation

public enum DisplayTargetKind: String, Codable {
    case deviceScreen
    case externalDisplay
}

public struct DisplayTarget: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var kind: DisplayTargetKind
    public var isAvailable: Bool
    public var supportsFullscreen: Bool

    public init(id: String, name: String, kind: DisplayTargetKind, isAvailable: Bool, supportsFullscreen: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isAvailable = isAvailable
        self.supportsFullscreen = supportsFullscreen
    }
}

public enum ExportResolutionPreset: String, CaseIterable, Codable, Equatable, Sendable {
    case p720
    case p1080
    case p2160

    public var longEdge: Int {
        switch self {
        case .p720:
            return 1_280
        case .p1080:
            return 1_920
        case .p2160:
            return 3_840
        }
    }

    public var label: String {
        switch self {
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        case .p2160:
            return "4K"
        }
    }
}

public enum ExportFrameRate: Int, CaseIterable, Codable, Equatable, Sendable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60

    public var label: String {
        "\(rawValue)"
    }
}

public enum ExportVideoCodec: String, CaseIterable, Codable, Equatable, Sendable {
    case hevc
    case h264
    case proRes422

    public var label: String {
        switch self {
        case .hevc:
            return "HEVC"
        case .h264:
            return "H.264"
        case .proRes422:
            return "ProRes 422"
        }
    }
}

public struct ExportCaptureSettings: Codable, Equatable, Sendable {
    public var resolutionPreset: ExportResolutionPreset
    public var frameRate: ExportFrameRate
    public var codec: ExportVideoCodec

    public init(
        resolutionPreset: ExportResolutionPreset,
        frameRate: ExportFrameRate,
        codec: ExportVideoCodec
    ) {
        self.resolutionPreset = resolutionPreset
        self.frameRate = frameRate
        self.codec = codec
    }

    public static let `default` = ExportCaptureSettings(
        resolutionPreset: .p1080,
        frameRate: .fps60,
        codec: .hevc
    )

    public static func legacyMapped(fromExportProfileID profileID: String?) -> ExportCaptureSettings {
        guard let profileID else { return .default }
        switch profileID {
        case "capture-1080p":
            return ExportCaptureSettings(resolutionPreset: .p1080, frameRate: .fps60, codec: .hevc)
        case "rehearsal-prores":
            return ExportCaptureSettings(resolutionPreset: .p1080, frameRate: .fps30, codec: .proRes422)
        default:
            return .default
        }
    }
}

public enum GlassAppearanceStyle: String, Codable, Equatable, Sendable {
    case dark
    case light
}

public struct OutputSessionState: Codable, Equatable {
    public var selectedDisplayTargetID: String
    public var isMirrorEnabled: Bool
    public var hidesOperatorChrome: Bool
    public var noImageInSilence: Bool
    public var blackFloor: Double
    public var isColorFeedbackEnabled: Bool
    public var glassAppearanceStyle: GlassAppearanceStyle

    public init(
        selectedDisplayTargetID: String,
        isMirrorEnabled: Bool,
        hidesOperatorChrome: Bool,
        noImageInSilence: Bool,
        blackFloor: Double,
        isColorFeedbackEnabled: Bool,
        glassAppearanceStyle: GlassAppearanceStyle
    ) {
        self.selectedDisplayTargetID = selectedDisplayTargetID
        self.isMirrorEnabled = isMirrorEnabled
        self.hidesOperatorChrome = hidesOperatorChrome
        self.noImageInSilence = noImageInSilence
        self.blackFloor = blackFloor
        self.isColorFeedbackEnabled = isColorFeedbackEnabled
        self.glassAppearanceStyle = glassAppearanceStyle
    }

    private enum CodingKeys: String, CodingKey {
        case selectedDisplayTargetID
        case isMirrorEnabled
        case hidesOperatorChrome
        case noImageInSilence
        case blackFloor
        case isColorFeedbackEnabled
        case glassAppearanceStyle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedDisplayTargetID = try container.decode(String.self, forKey: .selectedDisplayTargetID)
        isMirrorEnabled = try container.decode(Bool.self, forKey: .isMirrorEnabled)
        hidesOperatorChrome = try container.decode(Bool.self, forKey: .hidesOperatorChrome)
        noImageInSilence = try container.decode(Bool.self, forKey: .noImageInSilence)
        blackFloor = try container.decode(Double.self, forKey: .blackFloor)
        isColorFeedbackEnabled = try container.decode(Bool.self, forKey: .isColorFeedbackEnabled)
        glassAppearanceStyle = try container.decodeIfPresent(GlassAppearanceStyle.self, forKey: .glassAppearanceStyle) ?? .dark
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedDisplayTargetID, forKey: .selectedDisplayTargetID)
        try container.encode(isMirrorEnabled, forKey: .isMirrorEnabled)
        try container.encode(hidesOperatorChrome, forKey: .hidesOperatorChrome)
        try container.encode(noImageInSilence, forKey: .noImageInSilence)
        try container.encode(blackFloor, forKey: .blackFloor)
        try container.encode(isColorFeedbackEnabled, forKey: .isColorFeedbackEnabled)
        try container.encode(glassAppearanceStyle, forKey: .glassAppearanceStyle)
    }
}

public struct ExportProfile: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var resolutionLabel: String
    public var frameRate: Int
    public var codec: String

    public init(id: String, name: String, resolutionLabel: String, frameRate: Int, codec: String) {
        self.id = id
        self.name = name
        self.resolutionLabel = resolutionLabel
        self.frameRate = frameRate
        self.codec = codec
    }
}
