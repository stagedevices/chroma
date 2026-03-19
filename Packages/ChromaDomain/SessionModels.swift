import Foundation

public struct ChromaSession: Codable, Equatable {
    public var activeModeID: VisualModeID
    public var activePresetID: UUID?
    public var activePresetName: String
    public var morphState: VisualMorphState
    public var outputState: OutputSessionState
    public var availableDisplayTargets: [DisplayTarget]
    public var activeExportProfileID: String

    public init(
        activeModeID: VisualModeID,
        activePresetID: UUID?,
        activePresetName: String,
        morphState: VisualMorphState,
        outputState: OutputSessionState,
        availableDisplayTargets: [DisplayTarget],
        activeExportProfileID: String
    ) {
        self.activeModeID = activeModeID
        self.activePresetID = activePresetID
        self.activePresetName = activePresetName
        self.morphState = morphState
        self.outputState = outputState
        self.availableDisplayTargets = availableDisplayTargets
        self.activeExportProfileID = activeExportProfileID
    }

    public static func initial() -> ChromaSession {
        let outputState = OutputSessionState(
            selectedDisplayTargetID: "device",
            isMirrorEnabled: false,
            hidesOperatorChrome: false,
            noImageInSilence: false,
            blackFloor: 0.86,
            isColorFeedbackEnabled: false
        )
        return ChromaSession(
            activeModeID: .colorShift,
            activePresetID: nil,
            activePresetName: "Unsaved Session",
            morphState: VisualMorphState(),
            outputState: outputState,
            availableDisplayTargets: ParameterCatalog.defaultDisplayTargets,
            activeExportProfileID: ParameterCatalog.exportProfiles[0].id
        )
    }
}
