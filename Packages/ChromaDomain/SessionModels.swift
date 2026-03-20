import Foundation

public struct ChromaSession: Codable, Equatable {
    public var activeModeID: VisualModeID
    public var activePresetID: UUID?
    public var activePresetName: String
    public var morphState: VisualMorphState
    public var outputState: OutputSessionState
    public var availableDisplayTargets: [DisplayTarget]
    public var exportCaptureSettings: ExportCaptureSettings

    public init(
        activeModeID: VisualModeID,
        activePresetID: UUID?,
        activePresetName: String,
        morphState: VisualMorphState,
        outputState: OutputSessionState,
        availableDisplayTargets: [DisplayTarget],
        exportCaptureSettings: ExportCaptureSettings
    ) {
        self.activeModeID = activeModeID
        self.activePresetID = activePresetID
        self.activePresetName = activePresetName
        self.morphState = morphState
        self.outputState = outputState
        self.availableDisplayTargets = availableDisplayTargets
        self.exportCaptureSettings = exportCaptureSettings
    }

    public static func initial() -> ChromaSession {
        let outputState = OutputSessionState(
            selectedDisplayTargetID: "device",
            isMirrorEnabled: false,
            hidesOperatorChrome: false,
            noImageInSilence: false,
            blackFloor: 0.86,
            isColorFeedbackEnabled: false,
            glassAppearanceStyle: .dark
        )
        return ChromaSession(
            activeModeID: .colorShift,
            activePresetID: nil,
            activePresetName: "Unsaved Session",
            morphState: VisualMorphState(),
            outputState: outputState,
            availableDisplayTargets: ParameterCatalog.defaultDisplayTargets,
            exportCaptureSettings: .default
        )
    }

    private enum CodingKeys: String, CodingKey {
        case activeModeID
        case activePresetID
        case activePresetName
        case morphState
        case outputState
        case availableDisplayTargets
        case exportCaptureSettings
        case activeExportProfileID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeModeID = try container.decode(VisualModeID.self, forKey: .activeModeID)
        activePresetID = try container.decodeIfPresent(UUID.self, forKey: .activePresetID)
        activePresetName = try container.decode(String.self, forKey: .activePresetName)
        morphState = try container.decode(VisualMorphState.self, forKey: .morphState)
        outputState = try container.decode(OutputSessionState.self, forKey: .outputState)
        availableDisplayTargets = try container.decode([DisplayTarget].self, forKey: .availableDisplayTargets)
        if let decodedSettings = try container.decodeIfPresent(ExportCaptureSettings.self, forKey: .exportCaptureSettings) {
            exportCaptureSettings = decodedSettings
        } else {
            let legacyProfileID = try container.decodeIfPresent(String.self, forKey: .activeExportProfileID)
            exportCaptureSettings = ExportCaptureSettings.legacyMapped(fromExportProfileID: legacyProfileID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeModeID, forKey: .activeModeID)
        try container.encodeIfPresent(activePresetID, forKey: .activePresetID)
        try container.encode(activePresetName, forKey: .activePresetName)
        try container.encode(morphState, forKey: .morphState)
        try container.encode(outputState, forKey: .outputState)
        try container.encode(availableDisplayTargets, forKey: .availableDisplayTargets)
        try container.encode(exportCaptureSettings, forKey: .exportCaptureSettings)
    }
}
