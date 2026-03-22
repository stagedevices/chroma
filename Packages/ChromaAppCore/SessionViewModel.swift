import Foundation
import SwiftUI
import Combine

@MainActor
public final class SessionViewModel: ObservableObject {
    private static let colorShiftHueCenterTrimID = "mode.colorShift.hueCenterTrim"
    private static let includeMicAudioDefaultsKey = "session.recorder.includeMicAudio"
    private static let exportResolutionDefaultsKey = "session.export.resolutionPreset"
    private static let exportFrameRateDefaultsKey = "session.export.frameRate"
    private static let exportCodecDefaultsKey = "session.export.videoCodec"
    private static let sessionAutosaveDebounceNS: UInt64 = 650_000_000
    private static let quickSaveTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    @Published public private(set) var session: ChromaSession
    @Published public private(set) var availableModes: [VisualModeDescriptor]
    @Published public private(set) var presets: [Preset]
    @Published public private(set) var customPatchLibrary: CustomPatchLibrary
    @Published public private(set) var diagnosticsSnapshot: DiagnosticsSnapshot
    @Published public private(set) var supportedExportCodecs: Set<ExportVideoCodec>
    @Published public private(set) var performanceSets: [PerformanceSet]
    @Published public private(set) var latestAudioMeterFrame: AudioMeterFrame
    @Published public private(set) var latestAudioFeatureFrame: AudioFeatureFrame
    @Published public private(set) var audioAuthorizationStatus: AudioInputAuthorizationStatus
    @Published public private(set) var availableAudioInputSources: [AudioInputSourceDescriptor]
    @Published public private(set) var selectedAudioInputSourceID: String?
    @Published public private(set) var cameraFeedbackAuthorizationStatus: CameraFeedbackAuthorizationStatus
    @Published public private(set) var isColorFeedbackRunning: Bool
    @Published public private(set) var cameraFeedbackStatusMessage: String?
    @Published public private(set) var isActivePresetModified: Bool
    @Published public private(set) var recorderCaptureState: RecorderCaptureState
    @Published public private(set) var recorderStatusMessage: String?
    @Published public private(set) var appearanceTransitionToken: UUID
    @Published public private(set) var isCalibratingInput: Bool
    @Published public private(set) var calibrationStatusMessage: String?
    @Published public private(set) var modeDefaultsStatusMessage: String?
    @Published public private(set) var sessionRecoveryStatusMessage: String?
    @Published public private(set) var thermalFallbackIsActive: Bool
    @Published public var includeMicAudioInExport: Bool
    @Published public private(set) var midiConnectedDevices: [MIDIDeviceDescriptor] = []
    @Published public private(set) var midiTempoState: MIDITempoState?
    @Published public private(set) var isMIDIActive: Bool = false
    @Published public private(set) var isPlaybackActive: Bool = false
    @Published public private(set) var playbackNowPlayingTitle: String?
    @Published public private(set) var playbackNowPlayingArtist: String?
    @Published public private(set) var cueEngineActiveCueIndex: Int?
    @Published public private(set) var isCueEngineRunning: Bool = false

    public let parameterStore: ParameterStore
    public let audioInputService: AudioInputService
    public let inputCalibrationService: InputCalibrationService
    public let audioAnalysisService: AudioAnalysisService
    public let cameraFeedbackService: CameraFeedbackService
    public let rendererService: RendererService
    public let renderCoordinator: RenderCoordinator
    public let presetService: PresetService
    public let modeDefaultsService: ModeDefaultsService
    public let sessionRecoveryService: SessionRecoveryService
    public let customPatchService: CustomPatchService
    public let recorderService: RecorderService
    public let diagnosticsService: DiagnosticsService
    public let externalDisplayCoordinator: ExternalDisplayCoordinator
    public let setlistService: SetlistService
    public let midiService: MIDIService
    public let playbackService: PlaybackService
    public let cueExecutionEngine: CueExecutionEngine

    private let surfaceStateMapper: RendererSurfaceStateMapper
    private let audioStatusFormatter: AudioStatusFormatter
    private var cancellables: Set<AnyCancellable>
    private var isAudioPipelineActive: Bool
    private var lastAudioPipelineError: String?
    private var activePresetBaselineValues: [ScopedParameterValue]?
    private var activePresetBaselineModeID: VisualModeID?
    private var autosaveTask: Task<Void, Never>?
    private var performanceModeOverride: PerformanceMode?
    private var patchUndoStack: [CustomPatch] = []
    private var patchRedoStack: [CustomPatch] = []
    private var midiAttackIDCounter: UInt64 = 0
    private var midiClockTimestamps: [Date] = []
    private var lastMIDINoteOnFrame: AudioFeatureFrame?
    private static let maxUndoDepth = 40
    @Published public private(set) var patchClipboard: CustomPatchClipboard?
    @Published public private(set) var canUndoPatch: Bool = false
    @Published public private(set) var canRedoPatch: Bool = false
    
    private static let factoryPresetNamesByMode: [VisualModeID: Set<String>] = [
        .colorShift: ["Stage Color"],
        .prismField: ["Prism Nocturne"],
        .tunnelCels: ["Tunnel Drive"],
        .fractalCaustics: ["Fractal Aurora"],
        .riemannCorridor: ["Mandelbrot Boundary Run"],
        .custom: ["Breathing Fractal", "Particle Nebula", "Crystal Lattice"],
    ]

    public init(
        session: ChromaSession,
        parameterStore: ParameterStore,
        audioInputService: AudioInputService,
        inputCalibrationService: InputCalibrationService,
        audioAnalysisService: AudioAnalysisService,
        cameraFeedbackService: CameraFeedbackService,
        rendererService: RendererService,
        renderCoordinator: RenderCoordinator,
        presetService: PresetService,
        modeDefaultsService: ModeDefaultsService,
        sessionRecoveryService: SessionRecoveryService,
        customPatchService: CustomPatchService,
        recorderService: RecorderService,
        diagnosticsService: DiagnosticsService,
        externalDisplayCoordinator: ExternalDisplayCoordinator,
        setlistService: SetlistService,
        midiService: MIDIService,
        playbackService: PlaybackService,
        cueExecutionEngine: CueExecutionEngine,
        presets: [Preset],
        performanceSets: [PerformanceSet]
    ) {
        let restoredExportSettings = Self.loadExportCaptureSettings(defaultValue: session.exportCaptureSettings)
        self.session = session
        self.availableModes = ParameterCatalog.modes
        self.parameterStore = parameterStore
        self.audioInputService = audioInputService
        self.inputCalibrationService = inputCalibrationService
        self.audioAnalysisService = audioAnalysisService
        self.cameraFeedbackService = cameraFeedbackService
        self.rendererService = rendererService
        self.renderCoordinator = renderCoordinator
        self.presetService = presetService
        self.modeDefaultsService = modeDefaultsService
        self.sessionRecoveryService = sessionRecoveryService
        self.customPatchService = customPatchService
        self.recorderService = recorderService
        self.diagnosticsService = diagnosticsService
        self.externalDisplayCoordinator = externalDisplayCoordinator
        self.setlistService = setlistService
        self.midiService = midiService
        self.playbackService = playbackService
        self.cueExecutionEngine = cueExecutionEngine
        self.presets = presets

        // Remove stale custom mode presets that predate the customPatchID linkage
        let staleCustomPresetIDs = presets
            .filter { $0.modeID == .custom && $0.customPatchID == nil }
            .map(\.id)
        if !staleCustomPresetIDs.isEmpty {
            for staleID in staleCustomPresetIDs {
                try? presetService.deletePreset(id: staleID)
            }
            self.presets = presetService.loadPresets()
        }

        var loadedCustomPatchLibrary = customPatchService.loadLibrary()
        if loadedCustomPatchLibrary.patches.isEmpty {
            loadedCustomPatchLibrary = .seededDefault()
            try? customPatchService.saveLibrary(loadedCustomPatchLibrary)
        } else {
            // Remove legacy scaffold and replace factory presets with current versions
            let scaffoldID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
            let wasScaffoldActive = loadedCustomPatchLibrary.activePatchID == scaffoldID
            loadedCustomPatchLibrary.patches.removeAll { $0.id == scaffoldID }

            let factoryPatches = CustomPatch.factoryPresets()
            let factoryIDs = Set(factoryPatches.map(\.id))

            // Remove old versions of factory presets, then add current versions
            loadedCustomPatchLibrary.patches.removeAll { factoryIDs.contains($0.id) }
            loadedCustomPatchLibrary.patches.append(contentsOf: factoryPatches)

            if wasScaffoldActive || loadedCustomPatchLibrary.activePatchID == nil {
                loadedCustomPatchLibrary.activePatchID = factoryPatches.first?.id
            }
            try? customPatchService.saveLibrary(loadedCustomPatchLibrary)
        }
        self.customPatchLibrary = loadedCustomPatchLibrary
        self.supportedExportCodecs = recorderService.supportedVideoCodecs
        self.performanceSets = performanceSets
        self.latestAudioMeterFrame = audioInputService.latestMeterFrame
        self.latestAudioFeatureFrame = audioAnalysisService.latestFrame
        self.audioAuthorizationStatus = audioInputService.authorizationStatus
        self.availableAudioInputSources = audioInputService.availableInputSources
        self.selectedAudioInputSourceID = audioInputService.selectedInputSourceID
        self.cameraFeedbackAuthorizationStatus = cameraFeedbackService.authorizationStatus
        self.isColorFeedbackRunning = cameraFeedbackService.isRunning
        self.cameraFeedbackStatusMessage = nil
        self.isActivePresetModified = false
        self.recorderCaptureState = recorderService.captureState
        self.recorderStatusMessage = recorderService.statusMessage
        self.appearanceTransitionToken = UUID()
        self.isCalibratingInput = false
        self.calibrationStatusMessage = nil
        self.modeDefaultsStatusMessage = nil
        self.sessionRecoveryStatusMessage = nil
        self.thermalFallbackIsActive = false
        self.includeMicAudioInExport = Self.loadIncludeMicAudioPreference()
        self.surfaceStateMapper = RendererSurfaceStateMapper()
        self.audioStatusFormatter = AudioStatusFormatter()
        self.cancellables = []
        self.isAudioPipelineActive = false
        self.lastAudioPipelineError = nil
        self.activePresetBaselineValues = nil
        self.activePresetBaselineModeID = nil
        self.diagnosticsSnapshot = diagnosticsService.currentSnapshot(
            rendererSummary: rendererService.diagnosticsSummary,
            audioStatus: audioStatusFormatter.idleStatus()
        )

        self.session.exportCaptureSettings = restoredExportSettings
        if !self.supportedExportCodecs.contains(self.session.exportCaptureSettings.codec),
           let fallbackCodec = Self.preferredSupportedCodec(from: self.supportedExportCodecs) {
            self.session.exportCaptureSettings.codec = fallbackCodec
        }
        persistExportCaptureSettings()

        bindAudioStreams()
        bindCameraFeedbackStream()
        bindRecorderStreams()
        bindExternalDisplayStreams()
        bindThermalStateChanges()
        bindMIDIStreams()
        bindPlaybackStreams()
        bindCueEngine()
        refreshAudioInputs()
        applyPerformanceModeOverrideIfNeeded()
        syncAudioAnalysisTuning()
        syncCameraFeedbackStatus()
        rendererService.updateCameraFeedbackFrame(cameraFeedbackService.latestFrame)
        self.session.availableDisplayTargets = externalDisplayCoordinator.availableTargets()
        externalDisplayCoordinator.selectDisplayTarget(id: self.session.outputState.selectedDisplayTargetID)
        self.session.outputState.selectedDisplayTargetID = externalDisplayCoordinator.selectedTargetID
        if self.session.activePresetID != nil {
            capturePresetBaseline(modeID: self.session.activeModeID)
        }
        syncRendererState()
    }

    public var activeModeDescriptor: VisualModeDescriptor {
        ParameterCatalog.modeDescriptor(for: session.activeModeID)
    }

    public var activeDisplayTarget: DisplayTarget? {
        session.availableDisplayTargets.first(where: { $0.id == session.outputState.selectedDisplayTargetID })
    }

    public var isLightGlassAppearance: Bool {
        session.outputState.glassAppearanceStyle == .light
    }

    public var exportCaptureSettings: ExportCaptureSettings {
        session.exportCaptureSettings
    }

    public var effectivePerformanceMode: PerformanceMode {
        performanceModeOverride ?? session.performanceSettings.mode
    }

    public var riemannNavigationIsFreeFlight: Bool {
        let raw = parameterStore.value(
            for: "mode.riemannCorridor.navigationMode",
            scope: .mode(.riemannCorridor)
        )?.scalarValue ?? 0
        return raw >= 0.5
    }

    public var riemannSteeringStrength: Double {
        parameterStore.value(
            for: "mode.riemannCorridor.steeringStrength",
            scope: .mode(.riemannCorridor)
        )?.scalarValue ?? 0.62
    }

    public var quickControlDescriptors: [ParameterDescriptor] {
        let descriptorIDs = ParameterCatalog.quickControlParameterIDs(for: session.activeModeID)
        return descriptorIDs.compactMap { parameterStore.descriptor(for: $0) }
    }

    public var primarySurfaceControlDescriptors: [ParameterDescriptor] {
        let descriptorIDs = ParameterCatalog.surfaceControlParameterIDs(for: session.activeModeID)
        return descriptorIDs.compactMap { parameterStore.descriptor(for: $0) }
    }

    public var presetsForActiveMode: [Preset] {
        presets.filter { $0.modeID == session.activeModeID }
    }
    
    public var userCreatedPresetCountForActiveMode: Int {
        userCreatedPresetCount(for: session.activeModeID)
    }

    public var freePresetSaveLimitReached: Bool {
        userCreatedPresetCountForActiveMode >= 1
    }

    public func isFactoryPreset(_ preset: Preset) -> Bool {
        Self.factoryPresetNamesByMode[preset.modeID]?.contains(preset.name) ?? false
    }

    public var customPatches: [CustomPatch] {
        customPatchLibrary.patches
    }

    public var activeCustomPatch: CustomPatch? {
        guard let activePatchID = customPatchLibrary.activePatchID else {
            return customPatchLibrary.patches.first
        }
        return customPatchLibrary.patches.first(where: { $0.id == activePatchID }) ?? customPatchLibrary.patches.first
    }

    public var activePresetDisplayName: String {
        guard isActivePresetModified, session.activePresetID != nil else {
            return session.activePresetName
        }
        return "\(session.activePresetName) • Modified"
    }

    public var rendererSurfaceState: RendererSurfaceState {
        var state = surfaceStateMapper.map(
            session: session,
            parameterStore: parameterStore,
            latestFeatureFrame: latestAudioFeatureFrame.timestamp == .distantPast ? nil : latestAudioFeatureFrame,
            performanceModeOverride: effectivePerformanceMode
        )
        if session.activeModeID == .custom, let patch = activeCustomPatch {
            let result = PatchCompiler.compile(patch)
            state.patchProgram = result.program
        }
        return state
    }

    public var showsColorFeedbackAction: Bool {
        session.activeModeID == .colorShift
    }

    public var showsTunnelVariantAction: Bool {
        session.activeModeID == .tunnelCels
    }

    public var showsFractalPaletteAction: Bool {
        session.activeModeID == .fractalCaustics
    }

    public var showsRiemannPaletteAction: Bool {
        session.activeModeID == .riemannCorridor
    }

    public var showsCustomBuilderAction: Bool {
        session.activeModeID == .custom
    }

    public var tunnelVariantLabel: String {
        let current = tunnelVariantIndex
        switch current {
        case 0:
            return "Cel Cards"
        case 1:
            return "Prism Shards"
        default:
            return "Glyph Slabs"
        }
    }

    public var fractalPaletteLabel: String {
        switch fractalPaletteIndex {
        case 0: return "Aurora"
        case 1: return "Solar"
        case 2: return "Abyss"
        case 3: return "Neon"
        case 4: return "Infra"
        case 5: return "Glass"
        case 6: return "Mono"
        default: return "Prism"
        }
    }

    public var tunnelVariantSelectionIndex: Int {
        tunnelVariantIndex
    }

    public var fractalPaletteSelectionIndex: Int {
        fractalPaletteIndex
    }

    public var riemannPaletteSelectionIndex: Int {
        riemannPaletteIndex
    }

    public var riemannPaletteLabel: String {
        switch riemannPaletteIndex {
        case 0: return "Aurora"
        case 1: return "Solar"
        case 2: return "Abyss"
        case 3: return "Neon"
        case 4: return "Infra"
        case 5: return "Glass"
        case 6: return "Mono"
        default: return "Prism"
        }
    }

    public func parameterValue(for descriptor: ParameterDescriptor) -> ParameterValue {
        parameterStore.value(for: descriptor.id, scope: descriptor.scope) ?? descriptor.defaultValue
    }

    public func updateParameter(_ descriptor: ParameterDescriptor, value: ParameterValue) {
        parameterStore.setValue(value, for: descriptor.id, scope: descriptor.scope)
        switch descriptor.id {
        case "output.blackFloor":
            session.outputState.blackFloor = value.scalarValue ?? session.outputState.blackFloor
        case "output.noImageInSilence":
            session.outputState.noImageInSilence = value.toggleValue ?? session.outputState.noImageInSilence
        case "response.inputGain":
            syncAudioAnalysisTuning()
        default:
            break
        }
        modeDefaultsStatusMessage = nil
        calibrationStatusMessage = nil
        sessionRecoveryStatusMessage = nil
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public var colorShiftHueCenterShift: Double {
        parameterStore.value(
            for: Self.colorShiftHueCenterTrimID,
            scope: .mode(.colorShift)
        )?.scalarValue ?? 0
    }

    public func adjustColorShiftHueCenter(by delta: Double) {
        guard let descriptor = parameterStore.descriptor(for: Self.colorShiftHueCenterTrimID) else { return }
        let next = wrappedUnit(colorShiftHueCenterShift + delta)
        parameterStore.setValue(.scalar(next), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
    }

    public func selectMode(_ modeID: VisualModeID) {
        session.activeModeID = modeID
        if modeID != .colorShift {
            stopColorFeedbackCapture()
        }
        applyModeDefaultsIfAvailable(for: modeID)
        modeDefaultsStatusMessage = nil
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func applyPreset(_ preset: Preset) {
        session.activePresetID = preset.id
        session.activePresetName = preset.name
        session.activeModeID = preset.modeID
        parameterStore.apply(preset.values)
        capturePresetBaseline(modeID: preset.modeID)
        if preset.modeID != .colorShift {
            stopColorFeedbackCapture()
        }
        if preset.modeID == .custom, let patchID = preset.customPatchID {
            selectCustomPatch(id: patchID)
        }
        syncRendererState()
        scheduleSessionAutosave()
    }

    @discardableResult
    public func quickSaveActiveModePreset() -> Preset? {
        let modeDescriptor = ParameterCatalog.modeDescriptor(for: session.activeModeID)
        let timestamp = Self.quickSaveTimestampFormatter.string(from: Date())
        let defaultName = "\(modeDescriptor.name) \(timestamp)"
        let preset = Preset(
            name: defaultName,
            modeID: session.activeModeID,
            values: snapshotForActiveModePreset()
        )
        do {
            try presetService.save(preset: preset)
            refreshPresetsFromStore()
            session.activePresetID = preset.id
            session.activePresetName = preset.name
            capturePresetBaseline(modeID: session.activeModeID)
            syncRendererState()
            scheduleSessionAutosave()
            return preset
        } catch {
            return nil
        }
    }

    public func renamePreset(id: UUID, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard var preset = presets.first(where: { $0.id == id }) else { return }

        preset.name = trimmedName
        do {
            try presetService.save(preset: preset)
            refreshPresetsFromStore()
            if session.activePresetID == id {
                session.activePresetName = trimmedName
            }
            syncPresetDirtyState()
            syncRendererState()
            scheduleSessionAutosave()
        } catch {
            return
        }
    }

    public func deletePreset(id: UUID) {
        do {
            try presetService.deletePreset(id: id)
            refreshPresetsFromStore()
            if session.activePresetID == id {
                session.activePresetID = nil
                session.activePresetName = "Unsaved Session"
                clearPresetBaseline()
            }
            syncPresetDirtyState()
            syncRendererState()
            scheduleSessionAutosave()
        } catch {
            return
        }
    }

    // MARK: - Cue Set Management

    public func createPerformanceSet(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let set = PerformanceSet(name: trimmed)
        do {
            try setlistService.saveSet(set)
            refreshPerformanceSetsFromStore()
        } catch { }
    }

    public func renamePerformanceSet(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var set = performanceSets.first(where: { $0.id == id }) else { return }
        set.name = trimmed
        do {
            try setlistService.saveSet(set)
            refreshPerformanceSetsFromStore()
        } catch { }
    }

    public func deletePerformanceSet(id: UUID) {
        do {
            try setlistService.deleteSet(id: id)
            refreshPerformanceSetsFromStore()
        } catch { }
    }

    public func addCue(
        to setID: UUID,
        name: String,
        presetID: UUID?,
        delayFromPrevious: TimeInterval = 0,
        transitionDuration: TimeInterval = 0
    ) {
        guard var set = performanceSets.first(where: { $0.id == setID }) else { return }
        let cue = PerformanceCue(
            name: name,
            presetID: presetID,
            delayFromPrevious: delayFromPrevious,
            transitionDuration: transitionDuration
        )
        set.cues.append(cue)
        do {
            try setlistService.saveSet(set)
            refreshPerformanceSetsFromStore()
        } catch { }
    }

    public func addCueFromActivePreset(to setID: UUID) {
        guard let activePresetID = session.activePresetID else { return }
        let presetName = session.activePresetName
        addCue(to: setID, name: presetName, presetID: activePresetID)
    }

    public func updateCue(in setID: UUID, cue: PerformanceCue) {
        guard var set = performanceSets.first(where: { $0.id == setID }) else { return }
        guard let index = set.cues.firstIndex(where: { $0.id == cue.id }) else { return }
        set.cues[index] = cue
        do {
            try setlistService.saveSet(set)
            refreshPerformanceSetsFromStore()
        } catch { }
    }

    public func deleteCue(from setID: UUID, cueID: UUID) {
        guard var set = performanceSets.first(where: { $0.id == setID }) else { return }
        set.cues.removeAll(where: { $0.id == cueID })
        do {
            try setlistService.saveSet(set)
            refreshPerformanceSetsFromStore()
        } catch { }
    }

    public func reorderCues(in setID: UUID, fromOffsets: IndexSet, toOffset: Int) {
        guard var set = performanceSets.first(where: { $0.id == setID }) else { return }
        set.cues.move(fromOffsets: fromOffsets, toOffset: toOffset)
        do {
            try setlistService.saveSet(set)
            refreshPerformanceSetsFromStore()
        } catch { }
    }

    public func fireCue(_ cue: PerformanceCue) {
        guard let presetID = cue.presetID,
              let preset = presets.first(where: { $0.id == presetID }) else { return }
        applyPreset(preset)
    }

    public func cycleTunnelVariant() {
        guard session.activeModeID == .tunnelCels else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.tunnelCels.variant") else { return }

        let next = (tunnelVariantIndex + 1) % 3
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func setTunnelVariant(index: Int) {
        guard session.activeModeID == .tunnelCels else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.tunnelCels.variant") else { return }

        let clamped = min(max(index, 0), 2)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func cycleFractalPaletteVariant() {
        guard session.activeModeID == .fractalCaustics else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.fractalCaustics.paletteVariant") else { return }

        let next = (fractalPaletteIndex + 1) % 8
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func setFractalPaletteVariant(index: Int) {
        guard session.activeModeID == .fractalCaustics else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.fractalCaustics.paletteVariant") else { return }

        let clamped = min(max(index, 0), 7)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func cycleRiemannPaletteVariant() {
        guard session.activeModeID == .riemannCorridor else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.paletteVariant") else { return }

        let next = (riemannPaletteIndex + 1) % 8
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func setRiemannPaletteVariant(index: Int) {
        guard session.activeModeID == .riemannCorridor else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.paletteVariant") else { return }

        let clamped = min(max(index, 0), 7)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func selectCustomPatch(id: UUID) {
        guard customPatchLibrary.patches.contains(where: { $0.id == id }) else { return }
        guard customPatchLibrary.activePatchID != id else { return }
        customPatchLibrary.activePatchID = id
        persistCustomPatchLibrary()
    }

    public func renameActiveCustomPatch(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard var activePatch = activeCustomPatch else { return }
        guard activePatch.name != trimmed else { return }

        activePatch.name = trimmed
        activePatch.updatedAt = .now
        guard let patchIndex = customPatchLibrary.patches.firstIndex(where: { $0.id == activePatch.id }) else { return }
        customPatchLibrary.patches[patchIndex] = activePatch
        customPatchLibrary.activePatchID = activePatch.id
        persistCustomPatchLibrary()
    }

    public func addNodeToActiveCustomPatch(kind: CustomPatchNodeKind, at position: CustomPatchPoint) {
        guard var patch = activeCustomPatch else { return }
        let existingCount = patch.nodes.filter { $0.kind == kind }.count
        let title = existingCount == 0 ? kind.displayName : "\(kind.displayName) \(existingCount + 1)"
        let node = CustomPatchNode(kind: kind, title: title, position: position)
        patch.nodes.append(node)
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    public func deleteNodeFromActiveCustomPatch(nodeID: UUID) {
        guard var patch = activeCustomPatch else { return }
        patch.nodes.removeAll(where: { $0.id == nodeID })
        patch.connections.removeAll(where: { $0.fromNodeID == nodeID || $0.toNodeID == nodeID })
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    public func moveNodeInActiveCustomPatch(nodeID: UUID, to position: CustomPatchPoint) {
        guard var patch = activeCustomPatch else { return }
        guard let index = patch.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        patch.nodes[index].position = position
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    public func addConnectionToActiveCustomPatch(
        fromNodeID: UUID, fromPort: String, toNodeID: UUID, toPort: String
    ) {
        guard var patch = activeCustomPatch else { return }
        let alreadyConnected = patch.connections.contains(where: {
            $0.toNodeID == toNodeID && $0.toPort == toPort
        })
        guard !alreadyConnected else { return }
        let connection = CustomPatchConnection(
            fromNodeID: fromNodeID, fromPort: fromPort, toNodeID: toNodeID, toPort: toPort
        )
        patch.connections.append(connection)
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    public func removeConnectionFromActiveCustomPatch(connectionID: UUID) {
        guard var patch = activeCustomPatch else { return }
        patch.connections.removeAll(where: { $0.id == connectionID })
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    public func updateNodeParameterInActiveCustomPatch(nodeID: UUID, parameterName: String, value: Double) {
        guard var patch = activeCustomPatch else { return }
        guard let nodeIndex = patch.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        guard let paramIndex = patch.nodes[nodeIndex].parameters.firstIndex(where: { $0.name == parameterName }) else { return }
        let param = patch.nodes[nodeIndex].parameters[paramIndex]
        patch.nodes[nodeIndex].parameters[paramIndex].value = Swift.min(Swift.max(value, param.min), param.max)
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    public func updateViewportInActiveCustomPatch(viewport: CustomPatchViewport) {
        guard var patch = activeCustomPatch else { return }
        patch.viewport = viewport
        commitActivePatch(patch)
    }

    private func commitActivePatch(_ patch: CustomPatch, pushUndo: Bool = true) {
        if pushUndo, let current = activeCustomPatch {
            patchUndoStack.append(current)
            if patchUndoStack.count > Self.maxUndoDepth {
                patchUndoStack.removeFirst()
            }
            patchRedoStack.removeAll()
            syncUndoRedoState()
        }
        guard let index = customPatchLibrary.patches.firstIndex(where: { $0.id == patch.id }) else { return }
        customPatchLibrary.patches[index] = patch
        customPatchLibrary.activePatchID = patch.id
        persistCustomPatchLibrary()
        syncRendererState()
    }

    // MARK: - Undo / Redo

    public func undoPatchEdit() {
        guard let previous = patchUndoStack.popLast() else { return }
        if let current = activeCustomPatch {
            patchRedoStack.append(current)
        }
        guard let index = customPatchLibrary.patches.firstIndex(where: { $0.id == previous.id }) else { return }
        customPatchLibrary.patches[index] = previous
        customPatchLibrary.activePatchID = previous.id
        persistCustomPatchLibrary()
        syncRendererState()
        syncUndoRedoState()
    }

    public func redoPatchEdit() {
        guard let next = patchRedoStack.popLast() else { return }
        if let current = activeCustomPatch {
            patchUndoStack.append(current)
        }
        guard let index = customPatchLibrary.patches.firstIndex(where: { $0.id == next.id }) else { return }
        customPatchLibrary.patches[index] = next
        customPatchLibrary.activePatchID = next.id
        persistCustomPatchLibrary()
        syncRendererState()
        syncUndoRedoState()
    }

    private func syncUndoRedoState() {
        canUndoPatch = !patchUndoStack.isEmpty
        canRedoPatch = !patchRedoStack.isEmpty
    }

    // MARK: - Copy / Paste

    public func copyNodesFromActiveCustomPatch(nodeIDs: Set<UUID>) {
        guard let patch = activeCustomPatch else { return }
        let selectedNodes = patch.nodes.filter { nodeIDs.contains($0.id) }
        guard !selectedNodes.isEmpty else { return }
        let internalConnections = patch.connections.filter {
            nodeIDs.contains($0.fromNodeID) && nodeIDs.contains($0.toNodeID)
        }
        patchClipboard = CustomPatchClipboard(nodes: selectedNodes, connections: internalConnections)
    }

    public func pasteNodesIntoActiveCustomPatch(offset: CustomPatchPoint = CustomPatchPoint(x: 40, y: 40)) {
        guard let clipboard = patchClipboard, !clipboard.nodes.isEmpty else { return }
        guard var patch = activeCustomPatch else { return }

        var idMap: [UUID: UUID] = [:]
        var newNodes: [CustomPatchNode] = []
        for node in clipboard.nodes {
            let newID = UUID()
            idMap[node.id] = newID
            var copy = node
            copy.id = newID
            copy.title = "\(node.title) copy"
            copy.position = CustomPatchPoint(x: node.position.x + offset.x, y: node.position.y + offset.y)
            newNodes.append(copy)
        }

        var newConnections: [CustomPatchConnection] = []
        for conn in clipboard.connections {
            guard let newFrom = idMap[conn.fromNodeID], let newTo = idMap[conn.toNodeID] else { continue }
            newConnections.append(CustomPatchConnection(
                fromNodeID: newFrom, fromPort: conn.fromPort, toNodeID: newTo, toPort: conn.toPort
            ))
        }

        patch.nodes.append(contentsOf: newNodes)
        patch.connections.append(contentsOf: newConnections)
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    // MARK: - Node Grouping

    public func groupNodesInActiveCustomPatch(nodeIDs: Set<UUID>, name: String) {
        guard var patch = activeCustomPatch else { return }
        guard nodeIDs.count >= 2 else { return }
        let validIDs = nodeIDs.filter { id in patch.nodes.contains(where: { $0.id == id }) }
        guard validIDs.count >= 2 else { return }
        let colorIndex = patch.groups.count % CustomPatchGroup.groupColors.count
        let group = CustomPatchGroup(name: name, nodeIDs: Set(validIDs), colorIndex: colorIndex)
        patch.groups.append(group)
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    public func ungroupInActiveCustomPatch(groupID: UUID) {
        guard var patch = activeCustomPatch else { return }
        patch.groups.removeAll(where: { $0.id == groupID })
        patch.updatedAt = .now
        commitActivePatch(patch)
    }

    // MARK: - Patch Export / Import

    public func exportActiveCustomPatch() -> Data? {
        guard let patch = activeCustomPatch else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(patch)
    }

    public func importCustomPatch(from data: Data) -> Bool {
        guard let patch = try? JSONDecoder().decode(CustomPatch.self, from: data) else { return false }
        var importedPatch = patch
        importedPatch.id = UUID()
        importedPatch.name = "\(patch.name) (Imported)"
        importedPatch.updatedAt = .now
        customPatchLibrary.patches.append(importedPatch)
        customPatchLibrary.activePatchID = importedPatch.id
        persistCustomPatchLibrary()
        syncRendererState()
        return true
    }

    public func duplicateActiveCustomPatch() {
        guard let patch = activeCustomPatch else { return }
        var duplicate = patch
        duplicate.id = UUID()
        duplicate.name = "\(patch.name) Copy"
        duplicate.updatedAt = .now
        // Remap all node and connection IDs to avoid collisions
        var nodeIDMap: [UUID: UUID] = [:]
        for i in 0..<duplicate.nodes.count {
            let newID = UUID()
            nodeIDMap[duplicate.nodes[i].id] = newID
            duplicate.nodes[i].id = newID
        }
        for i in 0..<duplicate.connections.count {
            duplicate.connections[i].id = UUID()
            if let newFrom = nodeIDMap[duplicate.connections[i].fromNodeID] {
                duplicate.connections[i].fromNodeID = newFrom
            }
            if let newTo = nodeIDMap[duplicate.connections[i].toNodeID] {
                duplicate.connections[i].toNodeID = newTo
            }
        }
        for i in 0..<duplicate.groups.count {
            duplicate.groups[i].id = UUID()
            duplicate.groups[i].nodeIDs = Set(duplicate.groups[i].nodeIDs.compactMap { nodeIDMap[$0] })
        }
        customPatchLibrary.patches.append(duplicate)
        customPatchLibrary.activePatchID = duplicate.id
        persistCustomPatchLibrary()
        syncRendererState()
    }

    public func selectDisplayTarget(id: String) {
        externalDisplayCoordinator.selectDisplayTarget(id: id)
        session.outputState.selectedDisplayTargetID = externalDisplayCoordinator.selectedTargetID
        session.availableDisplayTargets = externalDisplayCoordinator.targets
        scheduleSessionAutosave()
    }
    
    public func reconcileRecoveredProAccess(hasProAccess: Bool) {
        guard !hasProAccess else { return }

        var didChange = false

        if ProEntitlement.requiresPro(.mode(session.activeModeID)) {
            session.activeModeID = .colorShift
            session.activePresetID = nil
            session.activePresetName = "Unsaved Session"
            applyModeDefaultsIfAvailable(for: .colorShift)
            clearPresetBaseline()
            didChange = true
        }

        if let sourceModeID = session.morphState.sourceModeID,
           ProEntitlement.requiresPro(.mode(sourceModeID)) {
            session.morphState = VisualMorphState()
            didChange = true
        }

        if let destinationModeID = session.morphState.destinationModeID,
           ProEntitlement.requiresPro(.mode(destinationModeID)) {
            session.morphState = VisualMorphState()
            didChange = true
        }

        if let activePresetID = session.activePresetID,
           let activePreset = presets.first(where: { $0.id == activePresetID }),
           ProEntitlement.requiresPro(.mode(activePreset.modeID)) {
            session.activePresetID = nil
            session.activePresetName = "Unsaved Session"
            clearPresetBaseline()
            didChange = true
        }

        if session.outputState.selectedDisplayTargetID == "external" {
            externalDisplayCoordinator.selectDisplayTarget(id: "device")
            session.outputState.selectedDisplayTargetID = externalDisplayCoordinator.selectedTargetID
            session.availableDisplayTargets = externalDisplayCoordinator.targets
            didChange = true
        }

        guard didChange else { return }

        if session.activeModeID != .colorShift {
            stopColorFeedbackCapture()
        }
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func toggleGlassAppearanceStyle() {
        setGlassAppearanceStyle(isLightGlassAppearance ? .dark : .light)
    }

    public func setGlassAppearanceStyle(_ style: GlassAppearanceStyle) {
        guard session.outputState.glassAppearanceStyle != style else { return }
        session.outputState.glassAppearanceStyle = style
        appearanceTransitionToken = UUID()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func setExportResolutionPreset(_ preset: ExportResolutionPreset) {
        session.exportCaptureSettings.resolutionPreset = preset
        persistExportCaptureSettings()
        scheduleSessionAutosave()
    }

    public func setExportFrameRate(_ frameRate: ExportFrameRate) {
        session.exportCaptureSettings.frameRate = frameRate
        persistExportCaptureSettings()
        scheduleSessionAutosave()
    }

    public func setExportVideoCodec(_ codec: ExportVideoCodec) {
        guard supportedExportCodecs.contains(codec) else { return }
        session.exportCaptureSettings.codec = codec
        persistExportCaptureSettings()
        scheduleSessionAutosave()
    }

    public func isExportCodecSupported(_ codec: ExportVideoCodec) -> Bool {
        supportedExportCodecs.contains(codec)
    }

    public func setIncludeMicAudioInExport(_ isEnabled: Bool) {
        includeMicAudioInExport = isEnabled
        Self.persistIncludeMicAudioPreference(isEnabled)
        scheduleSessionAutosave()
    }

    public func setPerformanceMode(_ mode: PerformanceMode) {
        guard session.performanceSettings.mode != mode else { return }
        session.performanceSettings.mode = mode
        applyPerformanceModeOverrideIfNeeded()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func setThermalAwareFallbackEnabled(_ isEnabled: Bool) {
        guard session.performanceSettings.thermalAwareFallbackEnabled != isEnabled else { return }
        session.performanceSettings.thermalAwareFallbackEnabled = isEnabled
        applyPerformanceModeOverrideIfNeeded()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func calibrateRoomNoise() async {
        guard !isCalibratingInput else { return }
        isCalibratingInput = true
        calibrationStatusMessage = "Calibrating room noise…"

        do {
            let result = try await inputCalibrationService.beginCalibration()
            session.audioCalibrationSettings.attackThresholdDB = result.attackThresholdDB
            session.audioCalibrationSettings.silenceGateThreshold = result.silenceGateThreshold
            calibrationStatusMessage = String(
                format: "Calibrated: %.1f dB attack • %.3f silence gate",
                result.attackThresholdDB,
                result.silenceGateThreshold
            )
            syncAudioAnalysisTuning()
            syncRendererState()
            scheduleSessionAutosave()
        } catch {
            calibrationStatusMessage = "Calibration canceled"
        }

        isCalibratingInput = false
    }

    public func cancelCalibration() {
        inputCalibrationService.cancelCalibration()
        isCalibratingInput = false
        calibrationStatusMessage = "Calibration canceled"
    }

    public func adjustAttackThreshold(by deltaDB: Double) {
        let current = session.audioCalibrationSettings.attackThresholdDB
        session.audioCalibrationSettings.attackThresholdDB = min(max(current + deltaDB, 2), 24)
        calibrationStatusMessage = nil
        syncAudioAnalysisTuning()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func adjustSilenceGateThreshold(by delta: Double) {
        let current = session.audioCalibrationSettings.silenceGateThreshold
        session.audioCalibrationSettings.silenceGateThreshold = min(max(current + delta, 0.005), 0.20)
        calibrationStatusMessage = nil
        syncAudioAnalysisTuning()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func setRiemannNavigationMode(freeFlight: Bool) {
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.navigationMode") else { return }
        parameterStore.setValue(.scalar(freeFlight ? 1 : 0), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func setRiemannSteeringStrength(_ value: Double) {
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.steeringStrength") else { return }
        let clamped = min(max(value, 0), 1)
        parameterStore.setValue(.scalar(clamped), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func adjustRiemannSteeringStrength(by delta: Double) {
        setRiemannSteeringStrength(riemannSteeringStrength + delta)
    }

    public func setCurrentModeAsDefault() {
        let modeID = session.activeModeID
        let values = modeDefaultSnapshot(for: modeID)
        do {
            try modeDefaultsService.saveDefaults(values, for: modeID)
            modeDefaultsStatusMessage = "Saved defaults for \(ParameterCatalog.modeDescriptor(for: modeID).name)"
            scheduleSessionAutosave()
        } catch {
            modeDefaultsStatusMessage = "Failed to save mode defaults"
        }
    }

    public func resetCurrentModeDefaults() {
        let modeID = session.activeModeID
        let resetAssignments = modeDefaultsService.defaults(for: modeID) ?? modeDefaultCatalogDefaults(for: modeID)
        do {
            try modeDefaultsService.removeDefaults(for: modeID)
            for assignment in resetAssignments {
                parameterStore.resetValue(for: assignment.parameterID, scope: assignment.scope)
            }
            modeDefaultsStatusMessage = "Reset defaults for \(ParameterCatalog.modeDescriptor(for: modeID).name)"
            syncPresetDirtyState()
            syncRendererState()
            scheduleSessionAutosave()
        } catch {
            modeDefaultsStatusMessage = "Failed to reset mode defaults"
        }
    }

    public func setSessionAutoSaveEnabled(_ isEnabled: Bool) {
        guard session.sessionRecoverySettings.autoSaveEnabled != isEnabled else { return }
        session.sessionRecoverySettings.autoSaveEnabled = isEnabled
        if !isEnabled {
            autosaveTask?.cancel()
            autosaveTask = nil
            sessionRecoveryStatusMessage = "Session auto-save disabled"
        } else {
            scheduleSessionAutosave()
            sessionRecoveryStatusMessage = "Session auto-save enabled"
        }
        syncRendererState()
    }

    public func setRestoreOnLaunchEnabled(_ isEnabled: Bool) {
        guard session.sessionRecoverySettings.restoreOnLaunchEnabled != isEnabled else { return }
        session.sessionRecoverySettings.restoreOnLaunchEnabled = isEnabled
        if session.sessionRecoverySettings.autoSaveEnabled {
            scheduleSessionAutosave()
        } else {
            persistSessionRecoverySnapshotImmediately()
        }
        sessionRecoveryStatusMessage = isEnabled
            ? "Restore on launch enabled"
            : "Restore on launch disabled"
    }

    public func resetToCleanState() async {
        if case .recording = recorderCaptureState {
            await stopRecorderCapture()
        } else if case .starting = recorderCaptureState {
            await stopRecorderCapture()
        }

        stopColorFeedbackCapture()
        autosaveTask?.cancel()
        autosaveTask = nil

        session = ChromaSession.initial()
        parameterStore.load([])
        refreshPresetsFromStore()
        clearPresetBaseline()
        modeDefaultsStatusMessage = nil
        calibrationStatusMessage = nil
        sessionRecoveryStatusMessage = "Session reset to clean state"

        session.availableDisplayTargets = externalDisplayCoordinator.availableTargets()
        externalDisplayCoordinator.selectDisplayTarget(id: "device")
        session.outputState.selectedDisplayTargetID = externalDisplayCoordinator.selectedTargetID

        do {
            try sessionRecoveryService.clearSnapshot()
        } catch {
            sessionRecoveryStatusMessage = "Reset complete, but failed to clear recovery snapshot"
        }

        applyPerformanceModeOverrideIfNeeded()
        syncAudioAnalysisTuning()
        syncCameraFeedbackStatus()
        syncRendererState()
        scheduleSessionAutosave()
    }

    public func startRecorderCapture() async {
        let request = RecorderCaptureRequest(
            settings: session.exportCaptureSettings,
            includeMicAudio: includeMicAudioInExport
        )

        if let frameSink = recorderService as? RendererFrameCaptureSink {
            rendererService.setFrameCaptureSink(frameSink)
        }

        do {
            try await recorderService.startCapture(request: request)
        } catch {
            rendererService.setFrameCaptureSink(nil)
            recorderCaptureState = .failed(error.localizedDescription)
        }
    }

    public func stopRecorderCapture() async {
        rendererService.setFrameCaptureSink(nil)
        await recorderService.stopCapture()
    }

    public func refreshDiagnostics() {
        diagnosticsSnapshot = diagnosticsService.currentSnapshot(
            rendererSummary: rendererService.diagnosticsSummary,
            audioStatus: currentAudioStatus
        )
    }

    public func refreshAudioInputs() {
        audioInputService.refreshInputSources()
        audioAuthorizationStatus = audioInputService.authorizationStatus
        availableAudioInputSources = audioInputService.availableInputSources
        selectedAudioInputSourceID = audioInputService.selectedInputSourceID
        refreshDiagnostics()
    }

    public func selectAudioInputSource(id: String) {
        do {
            try audioInputService.selectInputSource(id: id)
            refreshAudioInputs()
        } catch {
            lastAudioPipelineError = "Audio input selection failed: \(error.localizedDescription)"
            refreshDiagnostics()
        }
    }

    public func restartRealtimeAudioPipeline() async {
        stopRealtimeAudioPipeline()
        await startRealtimeAudioPipeline()
    }

    public func startRealtimeAudioPipeline() async {
        guard !isAudioPipelineActive else { return }
        do {
            try await audioInputService.startCapture()
            try await audioAnalysisService.startAnalysis()
            isAudioPipelineActive = true
            lastAudioPipelineError = nil
            refreshAudioInputs()
            refreshDiagnostics()
        } catch {
            isAudioPipelineActive = false
            refreshAudioInputs()
            lastAudioPipelineError = "Audio pipeline failed: \(error.localizedDescription)"
            diagnosticsSnapshot = diagnosticsService.currentSnapshot(
                rendererSummary: rendererService.diagnosticsSummary,
                audioStatus: currentAudioStatus
            )
        }
    }

    public func stopRealtimeAudioPipeline() {
        guard isAudioPipelineActive else { return }
        audioAnalysisService.stopAnalysis()
        audioInputService.stopCapture()
        isAudioPipelineActive = false
        refreshAudioInputs()
        refreshDiagnostics()
    }

    public func startColorFeedbackCapture() async {
        guard session.activeModeID == .colorShift else {
            cameraFeedbackStatusMessage = "Feedback is only available in Color Shift."
            syncCameraFeedbackStatus()
            syncRendererState()
            return
        }

        do {
            try await cameraFeedbackService.startFrontCapture()
            session.outputState.isColorFeedbackEnabled = true
            cameraFeedbackStatusMessage = nil
        } catch {
            session.outputState.isColorFeedbackEnabled = false
            cameraFeedbackStatusMessage = "Feedback setup failed: \(error.localizedDescription)"
        }

        syncCameraFeedbackStatus()
        syncRendererState()
    }

    public func stopColorFeedbackCapture() {
        cameraFeedbackService.stopCapture()
        session.outputState.isColorFeedbackEnabled = false
        rendererService.updateCameraFeedbackFrame(nil)
        syncCameraFeedbackStatus()
        syncRendererState()
        scheduleSessionAutosave()
    }

    private func syncRendererState() {
        rendererService.update(surfaceState: rendererSurfaceState)
        diagnosticsSnapshot = diagnosticsService.currentSnapshot(
            rendererSummary: rendererService.diagnosticsSummary,
            audioStatus: currentAudioStatus
        )
    }

    private func bindAudioStreams() {
        audioInputService.meterPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meterFrame in
                guard let self else { return }
                latestAudioMeterFrame = meterFrame
                diagnosticsSnapshot = diagnosticsService.currentSnapshot(
                    rendererSummary: rendererService.diagnosticsSummary,
                    audioStatus: currentAudioStatus
                )
            }
            .store(in: &cancellables)

        audioAnalysisService.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] featureFrame in
                guard let self else { return }
                latestAudioFeatureFrame = featureFrame
                syncRendererState()
            }
            .store(in: &cancellables)
    }

    // MARK: - MIDI bindings

    private func bindMIDIStreams() {
        midiService.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleMIDIEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleMIDIEvent(_ event: MIDIEvent) {
        switch event.kind {
        case .noteOn(let note, let velocity, _):
            midiAttackIDCounter += 1
            let frame = AudioFeatureFrame(
                timestamp: event.timestamp,
                amplitude: Double(velocity) / 127.0,
                lowBandEnergy: Double(velocity) / 127.0 * 0.8,
                midBandEnergy: Double(velocity) / 127.0 * 0.6,
                highBandEnergy: Double(velocity) / 127.0 * 0.4,
                transientStrength: Double(velocity) / 127.0 * 0.7,
                pitchHz: MIDINoteUtility.noteToHz(note),
                pitchConfidence: 1.0,
                stablePitchClass: MIDINoteUtility.pitchClass(note),
                stablePitchCents: MIDINoteUtility.centsDeviation,
                isAttack: true,
                attackStrength: Double(velocity) / 127.0,
                attackID: midiAttackIDCounter,
                attackDbOverFloor: Double(velocity) / 127.0 * 30
            )
            lastMIDINoteOnFrame = frame
            latestAudioFeatureFrame = frame
            syncRendererState()

        case .noteOff(let note, _):
            let frame = AudioFeatureFrame(
                timestamp: event.timestamp,
                amplitude: 0,
                lowBandEnergy: 0,
                midBandEnergy: 0,
                highBandEnergy: 0,
                transientStrength: 0,
                pitchHz: MIDINoteUtility.noteToHz(note),
                pitchConfidence: 0.5,
                stablePitchClass: MIDINoteUtility.pitchClass(note),
                stablePitchCents: MIDINoteUtility.centsDeviation,
                isAttack: false,
                attackStrength: 0,
                attackID: midiAttackIDCounter,
                attackDbOverFloor: 0
            )
            lastMIDINoteOnFrame = nil
            latestAudioFeatureFrame = frame
            syncRendererState()

        case .clock:
            trackMIDIClock(event.timestamp)

        case .start:
            midiTempoState = MIDITempoState(bpm: midiTempoState?.bpm ?? 120, beat: 0, isPlaying: true)
            midiClockTimestamps.removeAll()

        case .stop:
            midiTempoState?.isPlaying = false

        case .continue:
            midiTempoState?.isPlaying = true

        case .controlChange:
            break // CC mapping is a future extension
        }

        // Update device list on any event (lightweight check)
        if midiConnectedDevices != midiService.connectedDevices {
            midiConnectedDevices = midiService.connectedDevices
        }
        isMIDIActive = midiService.isActive
    }

    private func trackMIDIClock(_ timestamp: Date) {
        midiClockTimestamps.append(timestamp)
        if midiClockTimestamps.count > 25 {
            midiClockTimestamps.removeFirst(midiClockTimestamps.count - 25)
        }
        guard midiClockTimestamps.count >= 7 else { return }
        let first = midiClockTimestamps.first!
        let last = midiClockTimestamps.last!
        let intervals = midiClockTimestamps.count - 1
        let totalSeconds = last.timeIntervalSince(first)
        let avgTickSeconds = totalSeconds / Double(intervals)
        let beatSeconds = avgTickSeconds * 24.0 // 24 ppqn
        guard beatSeconds > 0 else { return }
        let bpm = 60.0 / beatSeconds
        let beat = (midiTempoState?.beat ?? 0) + (1.0 / 24.0)
        midiTempoState = MIDITempoState(bpm: bpm, beat: beat, isPlaying: true)
    }

    public func startMIDI() {
        midiService.start()
        isMIDIActive = true
        midiConnectedDevices = midiService.connectedDevices
    }

    public func stopMIDI() {
        midiService.stop()
        isMIDIActive = false
        midiConnectedDevices = []
        midiTempoState = nil
    }

    // MARK: - Playback bindings

    private func bindPlaybackStreams() {
        playbackService.samplePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sampleFrame in
                guard let self, self.isPlaybackActive else { return }
                // When playback is active, feed playback samples to analysis
                // by updating the latest sample data — the analysis service
                // processes this through its existing pipeline
            }
            .store(in: &cancellables)
    }

    public func startPlayback(url: URL) async throws {
        try await playbackService.play(url: url)
        isPlaybackActive = true
        playbackNowPlayingTitle = playbackService.nowPlayingTitle
        playbackNowPlayingArtist = playbackService.nowPlayingArtist
    }

    public func pausePlayback() {
        playbackService.pause()
        isPlaybackActive = false
    }

    public func resumePlayback() {
        playbackService.resume()
        isPlaybackActive = true
    }

    public func stopPlayback() {
        playbackService.stop()
        isPlaybackActive = false
        playbackNowPlayingTitle = nil
        playbackNowPlayingArtist = nil
    }

    // MARK: - Cue engine bindings

    private func bindCueEngine() {
        cueExecutionEngine.cueAdvancePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cue in
                self?.fireCue(cue)
            }
            .store(in: &cancellables)

        cueExecutionEngine.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCueEngineRunning)

        cueExecutionEngine.$activeCueIndex
            .receive(on: DispatchQueue.main)
            .assign(to: &$cueEngineActiveCueIndex)
    }

    public func loadCueSet(_ set: PerformanceSet) {
        cueExecutionEngine.load(set: set)
    }

    public func startCueEngine() {
        cueExecutionEngine.start()
    }

    public func advanceCue() {
        cueExecutionEngine.advanceToNext()
    }

    public func stopCueEngine() {
        cueExecutionEngine.stop()
    }

    private var tunnelVariantIndex: Int {
        let value = parameterStore.value(for: "mode.tunnelCels.variant", scope: .mode(.tunnelCels))?.scalarValue ?? 0
        return min(max(Int(value.rounded()), 0), 2)
    }

    private var fractalPaletteIndex: Int {
        let value = parameterStore.value(for: "mode.fractalCaustics.paletteVariant", scope: .mode(.fractalCaustics))?.scalarValue ?? 0
        return min(max(Int(value.rounded()), 0), 7)
    }

    private var riemannPaletteIndex: Int {
        let value = parameterStore.value(for: "mode.riemannCorridor.paletteVariant", scope: .mode(.riemannCorridor))?.scalarValue ?? 0
        return min(max(Int(value.rounded()), 0), 7)
    }

    private func bindCameraFeedbackStream() {
        cameraFeedbackService.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                rendererService.updateCameraFeedbackFrame(frame)
                syncCameraFeedbackStatus()
                refreshDiagnostics()
            }
            .store(in: &cancellables)
    }

    private func bindRecorderStreams() {
        recorderService.captureStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                recorderCaptureState = state
                switch state {
                case .starting, .recording:
                    if let frameSink = recorderService as? RendererFrameCaptureSink {
                        rendererService.setFrameCaptureSink(frameSink)
                    }
                case .idle, .finalizing, .completed, .failed:
                    rendererService.setFrameCaptureSink(nil)
                }
                refreshDiagnostics()
            }
            .store(in: &cancellables)

        recorderService.statusMessagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.recorderStatusMessage = message
            }
            .store(in: &cancellables)
    }

    private func bindExternalDisplayStreams() {
        externalDisplayCoordinator.targetsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] targets in
                guard let self else { return }
                session.availableDisplayTargets = targets
            }
            .store(in: &cancellables)

        externalDisplayCoordinator.selectedTargetIDPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedTargetID in
                guard let self else { return }
                session.outputState.selectedDisplayTargetID = selectedTargetID
            }
            .store(in: &cancellables)
    }

    private func persistCustomPatchLibrary() {
        do {
            try customPatchService.saveLibrary(customPatchLibrary)
            customPatchLibrary = customPatchService.loadLibrary()
        } catch {
            return
        }
    }

    private func refreshPresetsFromStore() {
        presets = presetService.loadPresets()
    }

    private func refreshPerformanceSetsFromStore() {
        performanceSets = setlistService.loadSets()
    }

    private func snapshotForActiveModePreset() -> [ScopedParameterValue] {
        snapshotForPresetComparison(modeID: session.activeModeID)
    }

    private func snapshotForPresetComparison(modeID: VisualModeID) -> [ScopedParameterValue] {
        parameterStore.snapshot().filter { assignment in
            switch assignment.scope.kind {
            case .global:
                return true
            case .mode:
                return assignment.scope.modeID == modeID
            }
        }
    }

    private func capturePresetBaseline(modeID: VisualModeID) {
        activePresetBaselineModeID = modeID
        activePresetBaselineValues = snapshotForPresetComparison(modeID: modeID)
        isActivePresetModified = false
    }

    private func clearPresetBaseline() {
        activePresetBaselineModeID = nil
        activePresetBaselineValues = nil
        isActivePresetModified = false
    }
    
    private func userCreatedPresetCount(for modeID: VisualModeID) -> Int {
        presets
            .filter { $0.modeID == modeID }
            .filter { !(Self.factoryPresetNamesByMode[modeID]?.contains($0.name) ?? false) }
            .count
    }

    private func syncPresetDirtyState() {
        guard session.activePresetID != nil else {
            clearPresetBaseline()
            return
        }

        guard
            let baselineModeID = activePresetBaselineModeID,
            let baselineValues = activePresetBaselineValues
        else {
            isActivePresetModified = true
            return
        }

        guard session.activeModeID == baselineModeID else {
            isActivePresetModified = true
            return
        }

        isActivePresetModified = snapshotForPresetComparison(modeID: baselineModeID) != baselineValues
    }

    private func bindThermalStateChanges() {
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyPerformanceModeOverrideIfNeeded()
                self?.syncRendererState()
            }
            .store(in: &cancellables)
    }

    private func applyPerformanceModeOverrideIfNeeded() {
        let thermalState = ProcessInfo.processInfo.thermalState
        let shouldForceSafe =
            session.performanceSettings.thermalAwareFallbackEnabled &&
            (thermalState == .serious || thermalState == .critical)
        performanceModeOverride = shouldForceSafe ? .safeFPS : nil
        thermalFallbackIsActive = shouldForceSafe
    }

    private func applyModeDefaultsIfAvailable(for modeID: VisualModeID) {
        guard let defaults = modeDefaultsService.defaults(for: modeID), !defaults.isEmpty else { return }
        parameterStore.apply(defaults)
    }

    private func modeDefaultSnapshot(for modeID: VisualModeID) -> [ScopedParameterValue] {
        let descriptorIDs = Set(ParameterCatalog.surfaceControlParameterIDs(for: modeID))
        var assignments: [ScopedParameterValue] = []
        assignments.reserveCapacity(descriptorIDs.count)

        for parameterID in descriptorIDs.sorted() {
            guard let descriptor = parameterStore.descriptor(for: parameterID) else { continue }
            let value = parameterStore.value(for: descriptor.id, scope: descriptor.scope) ?? descriptor.defaultValue
            assignments.append(
                ScopedParameterValue(
                    parameterID: descriptor.id,
                    scope: descriptor.scope,
                    value: value
                )
            )
        }

        return assignments
    }

    private func modeDefaultCatalogDefaults(for modeID: VisualModeID) -> [ScopedParameterValue] {
        let descriptorIDs = Set(ParameterCatalog.surfaceControlParameterIDs(for: modeID))
        return descriptorIDs
            .sorted()
            .compactMap { parameterID in
                guard let descriptor = parameterStore.descriptor(for: parameterID) else { return nil }
                return ScopedParameterValue(
                    parameterID: descriptor.id,
                    scope: descriptor.scope,
                    value: descriptor.defaultValue
                )
            }
    }

    private func scheduleSessionAutosave() {
        guard session.sessionRecoverySettings.autoSaveEnabled else { return }
        autosaveTask?.cancel()
        let snapshot = SessionRecoverySnapshot(
            session: session,
            parameterAssignments: parameterStore.snapshot(),
            savedAt: .now
        )
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Self.sessionAutosaveDebounceNS)
            guard !Task.isCancelled else { return }
            do {
                try self.sessionRecoveryService.saveSnapshot(snapshot)
            } catch {
                self.sessionRecoveryStatusMessage = "Session auto-save failed"
            }
        }
    }

    private func persistSessionRecoverySnapshotImmediately() {
        let snapshot = SessionRecoverySnapshot(
            session: session,
            parameterAssignments: parameterStore.snapshot(),
            savedAt: .now
        )
        do {
            try sessionRecoveryService.saveSnapshot(snapshot)
        } catch {
            sessionRecoveryStatusMessage = "Session recovery save failed"
        }
    }

    private func syncAudioAnalysisTuning() {
        let responseInputGain = parameterStore.value(
            for: "response.inputGain",
            scope: .global
        )?.scalarValue ?? 0.72
        // Map UI response gain into detector gain in dB around the tuned default baseline.
        let inputGainDB = (responseInputGain - 0.72) * 16
        let clampedAttackThreshold = min(max(session.audioCalibrationSettings.attackThresholdDB, 2), 24)
        let clampedSilenceGate = min(max(session.audioCalibrationSettings.silenceGateThreshold, 0.005), 0.20)
        session.audioCalibrationSettings.attackThresholdDB = clampedAttackThreshold
        session.audioCalibrationSettings.silenceGateThreshold = clampedSilenceGate

        audioAnalysisService.updateTuning(
            AudioAnalysisTuning(
                attackThresholdDB: clampedAttackThreshold,
                attackHysteresisDB: 2,
                attackCooldownMS: 70,
                inputGainDB: inputGainDB,
                silenceGateThreshold: clampedSilenceGate
            )
        )
    }

    private static func loadIncludeMicAudioPreference() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: includeMicAudioDefaultsKey) != nil else {
            return true
        }
        return defaults.bool(forKey: includeMicAudioDefaultsKey)
    }

    private static func persistIncludeMicAudioPreference(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: includeMicAudioDefaultsKey)
    }

    private static func loadExportCaptureSettings(defaultValue: ExportCaptureSettings) -> ExportCaptureSettings {
        let defaults = UserDefaults.standard

        let resolution: ExportResolutionPreset = {
            guard let raw = defaults.string(forKey: exportResolutionDefaultsKey),
                  let parsed = ExportResolutionPreset(rawValue: raw) else {
                return defaultValue.resolutionPreset
            }
            return parsed
        }()

        let frameRate: ExportFrameRate = {
            let stored = defaults.integer(forKey: exportFrameRateDefaultsKey)
            guard stored != 0, let parsed = ExportFrameRate(rawValue: stored) else {
                return defaultValue.frameRate
            }
            return parsed
        }()

        let codec: ExportVideoCodec = {
            guard let raw = defaults.string(forKey: exportCodecDefaultsKey),
                  let parsed = ExportVideoCodec(rawValue: raw) else {
                return defaultValue.codec
            }
            return parsed
        }()

        return ExportCaptureSettings(
            resolutionPreset: resolution,
            frameRate: frameRate,
            codec: codec
        )
    }

    private func persistExportCaptureSettings() {
        let defaults = UserDefaults.standard
        defaults.set(session.exportCaptureSettings.resolutionPreset.rawValue, forKey: Self.exportResolutionDefaultsKey)
        defaults.set(session.exportCaptureSettings.frameRate.rawValue, forKey: Self.exportFrameRateDefaultsKey)
        defaults.set(session.exportCaptureSettings.codec.rawValue, forKey: Self.exportCodecDefaultsKey)
    }

    private static func preferredSupportedCodec(from supported: Set<ExportVideoCodec>) -> ExportVideoCodec? {
        for codec in [ExportVideoCodec.hevc, .h264, .proRes422] where supported.contains(codec) {
            return codec
        }
        return supported.first
    }

    private var currentAudioStatus: String {
        if let lastAudioPipelineError {
            return lastAudioPipelineError
        }
        guard isAudioPipelineActive else {
            return audioStatusFormatter.idleStatus()
        }
        return audioStatusFormatter.liveStatus(
            meterFrame: latestAudioMeterFrame,
            featureFrame: latestAudioFeatureFrame
        )
    }

    private func syncCameraFeedbackStatus() {
        cameraFeedbackAuthorizationStatus = cameraFeedbackService.authorizationStatus
        isColorFeedbackRunning = cameraFeedbackService.isRunning
    }

    private func wrappedUnit(_ value: Double) -> Double {
        let wrapped = value - floor(value)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }
}
