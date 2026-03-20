import Foundation

public enum PerformanceMode: String, Codable, Equatable, CaseIterable, Sendable {
    case auto
    case highQuality
    case safeFPS

    public var label: String {
        switch self {
        case .auto:
            return "Auto"
        case .highQuality:
            return "High Quality"
        case .safeFPS:
            return "Safe FPS"
        }
    }
}

public struct PerformanceSettings: Codable, Equatable, Sendable {
    public var mode: PerformanceMode
    public var thermalAwareFallbackEnabled: Bool

    public init(
        mode: PerformanceMode = .auto,
        thermalAwareFallbackEnabled: Bool = true
    ) {
        self.mode = mode
        self.thermalAwareFallbackEnabled = thermalAwareFallbackEnabled
    }
}

public struct AudioCalibrationSettings: Codable, Equatable, Sendable {
    public var attackThresholdDB: Double
    public var silenceGateThreshold: Double

    public init(
        attackThresholdDB: Double = 8,
        silenceGateThreshold: Double = 0.03
    ) {
        self.attackThresholdDB = attackThresholdDB
        self.silenceGateThreshold = silenceGateThreshold
    }
}

public struct SessionRecoverySettings: Codable, Equatable, Sendable {
    public var autoSaveEnabled: Bool
    public var restoreOnLaunchEnabled: Bool

    public init(
        autoSaveEnabled: Bool = true,
        restoreOnLaunchEnabled: Bool = true
    ) {
        self.autoSaveEnabled = autoSaveEnabled
        self.restoreOnLaunchEnabled = restoreOnLaunchEnabled
    }
}

public struct ChromaSession: Codable, Equatable {
    public var activeModeID: VisualModeID
    public var activePresetID: UUID?
    public var activePresetName: String
    public var morphState: VisualMorphState
    public var outputState: OutputSessionState
    public var performanceSettings: PerformanceSettings
    public var audioCalibrationSettings: AudioCalibrationSettings
    public var sessionRecoverySettings: SessionRecoverySettings
    public var availableDisplayTargets: [DisplayTarget]
    public var exportCaptureSettings: ExportCaptureSettings

    public init(
        activeModeID: VisualModeID,
        activePresetID: UUID?,
        activePresetName: String,
        morphState: VisualMorphState,
        outputState: OutputSessionState,
        performanceSettings: PerformanceSettings,
        audioCalibrationSettings: AudioCalibrationSettings,
        sessionRecoverySettings: SessionRecoverySettings,
        availableDisplayTargets: [DisplayTarget],
        exportCaptureSettings: ExportCaptureSettings
    ) {
        self.activeModeID = activeModeID
        self.activePresetID = activePresetID
        self.activePresetName = activePresetName
        self.morphState = morphState
        self.outputState = outputState
        self.performanceSettings = performanceSettings
        self.audioCalibrationSettings = audioCalibrationSettings
        self.sessionRecoverySettings = sessionRecoverySettings
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
            performanceSettings: PerformanceSettings(),
            audioCalibrationSettings: AudioCalibrationSettings(),
            sessionRecoverySettings: SessionRecoverySettings(),
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
        case performanceSettings
        case audioCalibrationSettings
        case sessionRecoverySettings
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
        performanceSettings = try container.decodeIfPresent(PerformanceSettings.self, forKey: .performanceSettings) ?? PerformanceSettings()
        audioCalibrationSettings = try container.decodeIfPresent(AudioCalibrationSettings.self, forKey: .audioCalibrationSettings) ?? AudioCalibrationSettings()
        sessionRecoverySettings = try container.decodeIfPresent(SessionRecoverySettings.self, forKey: .sessionRecoverySettings) ?? SessionRecoverySettings()
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
        try container.encode(performanceSettings, forKey: .performanceSettings)
        try container.encode(audioCalibrationSettings, forKey: .audioCalibrationSettings)
        try container.encode(sessionRecoverySettings, forKey: .sessionRecoverySettings)
        try container.encode(availableDisplayTargets, forKey: .availableDisplayTargets)
        try container.encode(exportCaptureSettings, forKey: .exportCaptureSettings)
    }
}
