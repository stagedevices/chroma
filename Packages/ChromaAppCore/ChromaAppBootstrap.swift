import Foundation

public struct ChromaAppBootstrap {
    public var appViewModel: AppViewModel
    public var sessionViewModel: SessionViewModel

    public init(appViewModel: AppViewModel, sessionViewModel: SessionViewModel) {
        self.appViewModel = appViewModel
        self.sessionViewModel = sessionViewModel
    }

    @MainActor
    public static func makeDefault() -> ChromaAppBootstrap {
        let audioInputService = LiveAudioInputService()
        let audioAnalysisService = LiveAudioAnalysisService(
            meterPublisher: audioInputService.meterPublisher,
            samplePublisher: audioInputService.samplePublisher
        )
        let cameraFeedbackService: CameraFeedbackService
        #if targetEnvironment(macCatalyst)
        cameraFeedbackService = PlaceholderCameraFeedbackService(authorizationStatus: .unavailable)
        #else
        cameraFeedbackService = LiveCameraFeedbackService()
        #endif
        return makeBootstrap(
            rendererService: MetalRendererService(),
            audioInputService: audioInputService,
            audioAnalysisService: audioAnalysisService,
            cameraFeedbackService: cameraFeedbackService,
            storeKitEnabled: true
        )
    }

    @MainActor
    public static func makeTesting() -> ChromaAppBootstrap {
        let audioInputService = PlaceholderAudioInputService()
        let audioAnalysisService = PlaceholderAudioAnalysisService()
        let cameraFeedbackService = PlaceholderCameraFeedbackService(authorizationStatus: .authorized)
        return makeBootstrap(
            rendererService: HeadlessRendererService(),
            audioInputService: audioInputService,
            audioAnalysisService: audioAnalysisService,
            cameraFeedbackService: cameraFeedbackService,
            storeKitEnabled: false
        )
    }

    @MainActor
    private static func makeBootstrap(
        rendererService: RendererService,
        audioInputService: AudioInputService,
        audioAnalysisService: AudioAnalysisService,
        cameraFeedbackService: CameraFeedbackService,
        storeKitEnabled: Bool
    ) -> ChromaAppBootstrap {
        let router = AppRouter()
        let billingStore = BillingStore(storeKitEnabled: storeKitEnabled)
        let parameterStore = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let inputCalibrationService: InputCalibrationService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderInputCalibrationService()
            }
#endif
            return LiveInputCalibrationService(meterPublisher: audioInputService.meterPublisher)
        }()
        let renderCoordinator = DefaultRenderCoordinator()
        let presetService: PresetService = {
            let seededPresets = Self.modeStarterSeedPresets
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderPresetService(storedPresets: seededPresets)
            }
#endif
            return DiskPresetService(seedPresets: seededPresets)
        }()
        let modeDefaultsService: ModeDefaultsService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderModeDefaultsService()
            }
#endif
            return DiskModeDefaultsService()
        }()
        let sessionRecoveryService: SessionRecoveryService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderSessionRecoveryService()
            }
#endif
            return DiskSessionRecoveryService()
        }()
        let customPatchService: CustomPatchService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderCustomPatchService()
            }
#endif
            return DiskCustomPatchService()
        }()
        let recorderService: RecorderService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderRecorderService()
            }
#endif
            return LiveRecorderService(audioSamplePublisher: audioInputService.samplePublisher)
        }()
        let diagnosticsService = PlaceholderDiagnosticsService()
        let externalDisplayCoordinator: ExternalDisplayCoordinator = {
#if targetEnvironment(macCatalyst)
            return PlaceholderExternalDisplayCoordinator()
#else
            return LiveExternalDisplayCoordinator()
#endif
        }()
        let setlistService: SetlistService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderSetlistService()
            }
#endif
            return DiskSetlistService()
        }()
        let midiService: MIDIService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderMIDIService()
            }
#endif
            return LiveMIDIService()
        }()
        let playbackService: PlaybackService = {
#if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return PlaceholderPlaybackService()
            }
#endif
            return LivePlaybackService(engine: audioInputService.audioEngine)
        }()
        let cueExecutionEngine = CueExecutionEngine()
        let presets = presetService.loadPresets()
        let performanceSets = setlistService.loadSets()
        let recoveredSnapshot = sessionRecoveryService.loadSnapshot()
        let recoveredSession = recoveredSnapshot?.session
        let shouldRestore = recoveredSession?.sessionRecoverySettings.restoreOnLaunchEnabled ?? false
        let initialSession = shouldRestore ? (recoveredSession ?? ChromaSession.initial()) : ChromaSession.initial()
        if shouldRestore, let assignments = recoveredSnapshot?.parameterAssignments {
            parameterStore.load(assignments)
        }
        let sessionViewModel = SessionViewModel(
            session: initialSession,
            parameterStore: parameterStore,
            audioInputService: audioInputService,
            inputCalibrationService: inputCalibrationService,
            audioAnalysisService: audioAnalysisService,
            cameraFeedbackService: cameraFeedbackService,
            rendererService: rendererService,
            renderCoordinator: renderCoordinator,
            presetService: presetService,
            modeDefaultsService: modeDefaultsService,
            sessionRecoveryService: sessionRecoveryService,
            customPatchService: customPatchService,
            recorderService: recorderService,
            diagnosticsService: diagnosticsService,
            externalDisplayCoordinator: externalDisplayCoordinator,
            setlistService: setlistService,
            midiService: midiService,
            playbackService: playbackService,
            cueExecutionEngine: cueExecutionEngine,
            presets: presets,
            performanceSets: performanceSets
        )
        let appViewModel = AppViewModel(router: router, billingStore: billingStore)
        return ChromaAppBootstrap(appViewModel: appViewModel, sessionViewModel: sessionViewModel)
    }

    private static var modeStarterSeedPresets: [Preset] {
        [
            stageColorSeedPreset,
            prismNocturneSeedPreset,
            tunnelDriveSeedPreset,
            fractalAuroraSeedPreset,
            mandelbrotBoundarySeedPreset,
            customBreathingFractalSeedPreset,
            customParticleNebulaSeedPreset,
            customCrystalLatticeSeedPreset,
        ]
    }

    private static var stageColorSeedPreset: Preset {
        Preset(
            name: "Stage Color",
            modeID: .colorShift,
            values: [
                ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.84)),
                ScopedParameterValue(parameterID: "response.smoothing", scope: .global, value: .scalar(0.36)),
                ScopedParameterValue(parameterID: "mode.colorShift.hueResponse", scope: .mode(.colorShift), value: .scalar(0.72)),
                ScopedParameterValue(
                    parameterID: "mode.colorShift.hueRange",
                    scope: .mode(.colorShift),
                    value: .hueRange(min: 0.13, max: 0.87, outside: false)
                ),
                ScopedParameterValue(parameterID: "mode.colorShift.excitementMode", scope: .mode(.colorShift), value: .scalar(0.0)),
            ]
        )
    }

    private static var prismNocturneSeedPreset: Preset {
        Preset(
            name: "Prism Nocturne",
            modeID: .prismField,
            values: [
                ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.82)),
                ScopedParameterValue(parameterID: "response.smoothing", scope: .global, value: .scalar(0.34)),
                ScopedParameterValue(parameterID: "output.blackFloor", scope: .global, value: .scalar(0.90)),
                ScopedParameterValue(parameterID: "mode.prismField.facetDensity", scope: .mode(.prismField), value: .scalar(0.68)),
                ScopedParameterValue(parameterID: "mode.prismField.dispersion", scope: .mode(.prismField), value: .scalar(0.74)),
            ]
        )
    }

    private static var tunnelDriveSeedPreset: Preset {
        Preset(
            name: "Tunnel Drive",
            modeID: .tunnelCels,
            values: [
                ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.88)),
                ScopedParameterValue(parameterID: "response.smoothing", scope: .global, value: .scalar(0.28)),
                ScopedParameterValue(parameterID: "output.blackFloor", scope: .global, value: .scalar(0.87)),
                ScopedParameterValue(parameterID: "mode.tunnelCels.shapeScale", scope: .mode(.tunnelCels), value: .scalar(0.62)),
                ScopedParameterValue(parameterID: "mode.tunnelCels.depthSpeed", scope: .mode(.tunnelCels), value: .scalar(0.74)),
                ScopedParameterValue(parameterID: "mode.tunnelCels.releaseTail", scope: .mode(.tunnelCels), value: .scalar(0.52)),
                ScopedParameterValue(parameterID: "mode.tunnelCels.variant", scope: .mode(.tunnelCels), value: .scalar(1.0)),
            ]
        )
    }

    private static var fractalAuroraSeedPreset: Preset {
        Preset(
            name: "Fractal Aurora",
            modeID: .fractalCaustics,
            values: [
                ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.76)),
                ScopedParameterValue(parameterID: "response.smoothing", scope: .global, value: .scalar(0.40)),
                ScopedParameterValue(parameterID: "output.blackFloor", scope: .global, value: .scalar(0.91)),
                ScopedParameterValue(parameterID: "mode.fractalCaustics.detail", scope: .mode(.fractalCaustics), value: .scalar(0.73)),
                ScopedParameterValue(parameterID: "mode.fractalCaustics.flowRate", scope: .mode(.fractalCaustics), value: .scalar(0.49)),
                ScopedParameterValue(parameterID: "mode.fractalCaustics.attackBloom", scope: .mode(.fractalCaustics), value: .scalar(0.69)),
                ScopedParameterValue(parameterID: "mode.fractalCaustics.paletteVariant", scope: .mode(.fractalCaustics), value: .scalar(3.0)),
            ]
        )
    }

    private static var mandelbrotBoundarySeedPreset: Preset {
        Preset(
            name: "Mandelbrot Boundary Run",
            modeID: .riemannCorridor,
            values: [
                ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.72)),
                ScopedParameterValue(parameterID: "response.smoothing", scope: .global, value: .scalar(0.33)),
                ScopedParameterValue(parameterID: "output.blackFloor", scope: .global, value: .scalar(0.93)),
                ScopedParameterValue(parameterID: "mode.riemannCorridor.detail", scope: .mode(.riemannCorridor), value: .scalar(0.82)),
                ScopedParameterValue(parameterID: "mode.riemannCorridor.flowRate", scope: .mode(.riemannCorridor), value: .scalar(0.44)),
                ScopedParameterValue(parameterID: "mode.riemannCorridor.zeroBloom", scope: .mode(.riemannCorridor), value: .scalar(0.36)),
                ScopedParameterValue(parameterID: "mode.riemannCorridor.paletteVariant", scope: .mode(.riemannCorridor), value: .scalar(4.0)),
            ]
        )
    }

    private static var customBreathingFractalSeedPreset: Preset {
        Preset(
            id: UUID(uuidString: "FB000001-0001-0001-0001-FFFFFFFFFFFF")!,
            name: "Breathing Fractal",
            modeID: .custom,
            values: [],
            customPatchID: UUID(uuidString: "FA000001-0001-0001-0001-FFFFFFFFFFFF")!
        )
    }

    private static var customParticleNebulaSeedPreset: Preset {
        Preset(
            id: UUID(uuidString: "FB000002-0002-0002-0002-FFFFFFFFFFFF")!,
            name: "Particle Nebula",
            modeID: .custom,
            values: [],
            customPatchID: UUID(uuidString: "FA000002-0002-0002-0002-FFFFFFFFFFFF")!
        )
    }

    private static var customCrystalLatticeSeedPreset: Preset {
        Preset(
            id: UUID(uuidString: "FB000003-0003-0003-0003-FFFFFFFFFFFF")!,
            name: "Crystal Lattice",
            modeID: .custom,
            values: [],
            customPatchID: UUID(uuidString: "FA000003-0003-0003-0003-FFFFFFFFFFFF")!
        )
    }
}
