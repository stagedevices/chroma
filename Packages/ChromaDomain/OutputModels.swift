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

public struct OutputSessionState: Codable, Equatable {
    public var selectedDisplayTargetID: String
    public var isMirrorEnabled: Bool
    public var hidesOperatorChrome: Bool
    public var noImageInSilence: Bool
    public var blackFloor: Double
    public var isColorFeedbackEnabled: Bool

    public init(
        selectedDisplayTargetID: String,
        isMirrorEnabled: Bool,
        hidesOperatorChrome: Bool,
        noImageInSilence: Bool,
        blackFloor: Double,
        isColorFeedbackEnabled: Bool
    ) {
        self.selectedDisplayTargetID = selectedDisplayTargetID
        self.isMirrorEnabled = isMirrorEnabled
        self.hidesOperatorChrome = hidesOperatorChrome
        self.noImageInSilence = noImageInSilence
        self.blackFloor = blackFloor
        self.isColorFeedbackEnabled = isColorFeedbackEnabled
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
