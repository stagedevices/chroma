import Foundation
import Combine

@MainActor
public final class SessionViewModel: ObservableObject {
    private static let colorShiftHueCenterTrimID = "mode.colorShift.hueCenterTrim"
    private static let includeMicAudioDefaultsKey = "session.recorder.includeMicAudio"
    private static let exportResolutionDefaultsKey = "session.export.resolutionPreset"
    private static let exportFrameRateDefaultsKey = "session.export.frameRate"
    private static let exportCodecDefaultsKey = "session.export.videoCodec"
    private static let quickSaveTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
    @Published public private(set) var session: ChromaSession
    @Published public private(set) var availableModes: [VisualModeDescriptor]
    @Published public private(set) var presets: [Preset]
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
    @Published public var includeMicAudioInExport: Bool

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
    private var activePresetBaselineValues: [ScopedParameterValue]?
    private var activePresetBaselineModeID: VisualModeID?

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
        self.recorderService = recorderService
        self.diagnosticsService = diagnosticsService
        self.externalDisplayCoordinator = externalDisplayCoordinator
        self.setlistService = setlistService
        self.presets = presets
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
        refreshAudioInputs()
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

    public var activePresetDisplayName: String {
        guard isActivePresetModified, session.activePresetID != nil else {
            return session.activePresetName
        }
        return "\(session.activePresetName) • Modified"
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
        syncPresetDirtyState()
        syncRendererState()
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
        syncPresetDirtyState()
        syncRendererState()
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
        syncRendererState()
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
        } catch {
            return
        }
    }

    public func cycleTunnelVariant() {
        guard session.activeModeID == .tunnelCels else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.tunnelCels.variant") else { return }

        let next = (tunnelVariantIndex + 1) % 3
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
    }

    public func setTunnelVariant(index: Int) {
        guard session.activeModeID == .tunnelCels else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.tunnelCels.variant") else { return }

        let clamped = min(max(index, 0), 2)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
    }

    public func cycleFractalPaletteVariant() {
        guard session.activeModeID == .fractalCaustics else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.fractalCaustics.paletteVariant") else { return }

        let next = (fractalPaletteIndex + 1) % 8
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
    }

    public func setFractalPaletteVariant(index: Int) {
        guard session.activeModeID == .fractalCaustics else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.fractalCaustics.paletteVariant") else { return }

        let clamped = min(max(index, 0), 7)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
    }

    public func cycleRiemannPaletteVariant() {
        guard session.activeModeID == .riemannCorridor else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.paletteVariant") else { return }

        let next = (riemannPaletteIndex + 1) % 8
        parameterStore.setValue(.scalar(Double(next)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
    }

    public func setRiemannPaletteVariant(index: Int) {
        guard session.activeModeID == .riemannCorridor else { return }
        guard let descriptor = parameterStore.descriptor(for: "mode.riemannCorridor.paletteVariant") else { return }

        let clamped = min(max(index, 0), 7)
        parameterStore.setValue(.scalar(Double(clamped)), for: descriptor.id, scope: descriptor.scope)
        syncPresetDirtyState()
        syncRendererState()
    }

    public func selectDisplayTarget(id: String) {
        externalDisplayCoordinator.selectDisplayTarget(id: id)
        session.outputState.selectedDisplayTargetID = externalDisplayCoordinator.selectedTargetID
        session.availableDisplayTargets = externalDisplayCoordinator.targets
    }

    public func toggleGlassAppearanceStyle() {
        setGlassAppearanceStyle(isLightGlassAppearance ? .dark : .light)
    }

    public func setGlassAppearanceStyle(_ style: GlassAppearanceStyle) {
        guard session.outputState.glassAppearanceStyle != style else { return }
        session.outputState.glassAppearanceStyle = style
        appearanceTransitionToken = UUID()
        syncRendererState()
    }

    public func setExportResolutionPreset(_ preset: ExportResolutionPreset) {
        session.exportCaptureSettings.resolutionPreset = preset
        persistExportCaptureSettings()
    }

    public func setExportFrameRate(_ frameRate: ExportFrameRate) {
        session.exportCaptureSettings.frameRate = frameRate
        persistExportCaptureSettings()
    }

    public func setExportVideoCodec(_ codec: ExportVideoCodec) {
        guard supportedExportCodecs.contains(codec) else { return }
        session.exportCaptureSettings.codec = codec
        persistExportCaptureSettings()
    }

    public func isExportCodecSupported(_ codec: ExportVideoCodec) -> Bool {
        supportedExportCodecs.contains(codec)
    }

    public func setIncludeMicAudioInExport(_ isEnabled: Bool) {
        includeMicAudioInExport = isEnabled
        Self.persistIncludeMicAudioPreference(isEnabled)
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

    private func refreshPresetsFromStore() {
        presets = presetService.loadPresets()
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
