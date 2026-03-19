import Foundation
import Combine

@MainActor
public final class SessionViewModel: ObservableObject {
    @Published public private(set) var session: ChromaSession
    @Published public private(set) var availableModes: [VisualModeDescriptor]
    @Published public private(set) var presets: [Preset]
    @Published public private(set) var diagnosticsSnapshot: DiagnosticsSnapshot
    @Published public private(set) var exportProfiles: [ExportProfile]
    @Published public private(set) var performanceSets: [PerformanceSet]
    @Published public private(set) var latestAudioMeterFrame: AudioMeterFrame
    @Published public private(set) var latestAudioFeatureFrame: AudioFeatureFrame
    @Published public private(set) var audioAuthorizationStatus: AudioInputAuthorizationStatus
    @Published public private(set) var availableAudioInputSources: [AudioInputSourceDescriptor]
    @Published public private(set) var selectedAudioInputSourceID: String?
    @Published public private(set) var cameraFeedbackAuthorizationStatus: CameraFeedbackAuthorizationStatus
    @Published public private(set) var isColorFeedbackRunning: Bool
    @Published public private(set) var cameraFeedbackStatusMessage: String?

    public let parameterStore: ParameterStore
    public let audioInputService: AudioInputService
    public let inputCalibrationService: InputCalibrationService
    public let audioAnalysisService: AudioAnalysisService
    public let cameraFeedbackService: CameraFeedbackService
    public let rendererService: RendererService
    public let renderCoordinator: RenderCoordinator
    public let presetService: PresetService
    public let recorderService: RecorderService
    public let diagnosticsService: DiagnosticsService
    public let externalDisplayCoordinator: ExternalDisplayCoordinator
    public let setlistService: SetlistService

    private let surfaceStateMapper: RendererSurfaceStateMapper
    private let audioStatusFormatter: AudioStatusFormatter
    private var cancellables: Set<AnyCancellable>
    private var isAudioPipelineActive: Bool
    private var lastAudioPipelineError: String?

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
        recorderService: RecorderService,
        diagnosticsService: DiagnosticsService,
        externalDisplayCoordinator: ExternalDisplayCoordinator,
        setlistService: SetlistService,
        presets: [Preset],
        performanceSets: [PerformanceSet]
    ) {
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
        self.recorderService = recorderService
        self.diagnosticsService = diagnosticsService
        self.externalDisplayCoordinator = externalDisplayCoordinator
        self.setlistService = setlistService
        self.presets = presets
        self.exportProfiles = recorderService.availableExportProfiles
        self.performanceSets = performanceSets
        self.latestAudioMeterFrame = audioInputService.latestMeterFrame
        self.latestAudioFeatureFrame = audioAnalysisService.latestFrame
        self.audioAuthorizationStatus = audioInputService.authorizationStatus
        self.availableAudioInputSources = audioInputService.availableInputSources
        self.selectedAudioInputSourceID = audioInputService.selectedInputSourceID
        self.cameraFeedbackAuthorizationStatus = cameraFeedbackService.authorizationStatus
        self.isColorFeedbackRunning = cameraFeedbackService.isRunning
        self.cameraFeedbackStatusMessage = nil
        self.surfaceStateMapper = RendererSurfaceStateMapper()
        self.audioStatusFormatter = AudioStatusFormatter()
        self.cancellables = []
        self.isAudioPipelineActive = false
        self.lastAudioPipelineError = nil
        self.diagnosticsSnapshot = diagnosticsService.currentSnapshot(
            rendererSummary: rendererService.diagnosticsSummary,
            audioStatus: audioStatusFormatter.idleStatus()
        )

        bindAudioStreams()
        bindCameraFeedbackStream()
        refreshAudioInputs()
        syncAudioAnalysisTuning()
        syncCameraFeedbackStatus()
        rendererService.updateCameraFeedbackFrame(cameraFeedbackService.latestFrame)
        syncRendererState()
    }

    public var activeModeDescriptor: VisualModeDescriptor {
        ParameterCatalog.modeDescriptor(for: session.activeModeID)
    }

    public var activeDisplayTarget: DisplayTarget? {
        session.availableDisplayTargets.first(where: { $0.id == session.outputState.selectedDisplayTargetID })
    }

    public var activeExportProfile: ExportProfile? {
        exportProfiles.first(where: { $0.id == session.activeExportProfileID })
    }

    public var quickControlDescriptors: [ParameterDescriptor] {
        let descriptorIDs = ParameterCatalog.quickControlParameterIDs(for: session.activeModeID)
        return descriptorIDs.compactMap { parameterStore.descriptor(for: $0) }
    }

    public var primarySurfaceControlDescriptors: [ParameterDescriptor] {
        let descriptorIDs = ParameterCatalog.surfaceControlParameterIDs(for: session.activeModeID)
        return descriptorIDs.compactMap { parameterStore.descriptor(for: $0) }
    }

    public var rendererSurfaceState: RendererSurfaceState {
        surfaceStateMapper.map(
            session: session,
            parameterStore: parameterStore,
            latestFeatureFrame: latestAudioFeatureFrame.timestamp == .distantPast ? nil : latestAudioFeatureFrame
        )
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
        syncRendererState()
    }

    public func selectMode(_ modeID: VisualModeID) {
        session.activeModeID = modeID
        if modeID != .colorShift {
            stopColorFeedbackCapture()
        }
        syncRendererState()
    }

    public func applyPreset(_ preset: Preset) {
        session.activePresetID = preset.id
        session.activePresetName = preset.name
        session.activeModeID = preset.modeID
        parameterStore.load(preset.values)
        if preset.modeID != .colorShift {
            stopColorFeedbackCapture()
        }
        syncRendererState()
    }

    public func cycleTunnelVariant() {
        guard session.activeModeID == .tunnelCels else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.tunnelCels.variant") else { return }

        let next = (tunnelVariantIndex + 1) % 3
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncRendererState()
    }

    public func setTunnelVariant(index: Int) {
        guard session.activeModeID == .tunnelCels else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.tunnelCels.variant") else { return }

        let clamped = min(max(index, 0), 2)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncRendererState()
    }

    public func cycleFractalPaletteVariant() {
        guard session.activeModeID == .fractalCaustics else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.fractalCaustics.paletteVariant") else { return }

        let next = (fractalPaletteIndex + 1) % 8
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncRendererState()
    }

    public func setFractalPaletteVariant(index: Int) {
        guard session.activeModeID == .fractalCaustics else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.fractalCaustics.paletteVariant") else { return }

        let clamped = min(max(index, 0), 7)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncRendererState()
    }

    public func cycleRiemannPaletteVariant() {
        guard session.activeModeID == .riemannCorridor else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.paletteVariant") else { return }

        let next = (riemannPaletteIndex + 1) % 8
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncRendererState()
    }

    public func setRiemannPaletteVariant(index: Int) {
        guard session.activeModeID == .riemannCorridor else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.paletteVariant") else { return }

        let clamped = min(max(index, 0), 7)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncRendererState()
    }

    public func selectDisplayTarget(id: String) {
        externalDisplayCoordinator.selectDisplayTarget(id: id)
        session.outputState.selectedDisplayTargetID = id
        session.availableDisplayTargets = externalDisplayCoordinator.availableTargets()
    }

    public func selectExportProfile(_ profile: ExportProfile) {
        session.activeExportProfileID = profile.id
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

    private func syncAudioAnalysisTuning() {
        let responseInputGain = parameterStore.value(
            for: "response.inputGain",
            scope: .global
        )?.scalarValue ?? 0.72
        // Map UI response gain into detector gain in dB around the tuned default baseline.
        let inputGainDB = (responseInputGain - 0.72) * 16

        audioAnalysisService.updateTuning(
            AudioAnalysisTuning(
                attackThresholdDB: 8,
                attackHysteresisDB: 2,
                attackCooldownMS: 70,
                inputGainDB: inputGainDB
            )
        )
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
}
