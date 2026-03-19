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
            cameraFeedbackService: cameraFeedbackService
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
            cameraFeedbackService: cameraFeedbackService
        )
    }

    @MainActor
    private static func makeBootstrap(
        rendererService: RendererService,
        audioInputService: AudioInputService,
        audioAnalysisService: AudioAnalysisService,
        cameraFeedbackService: CameraFeedbackService
    ) -> ChromaAppBootstrap {
        let router = AppRouter()
        let parameterStore = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let inputCalibrationService = PlaceholderInputCalibrationService()
        let renderCoordinator = DefaultRenderCoordinator()
        let presetService = PlaceholderPresetService(
            storedPresets: [
                Preset(
                    name: "Stage Color",
                    modeID: .colorShift,
                    values: [
                        ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.84)),
                        ScopedParameterValue(parameterID: "mode.colorShift.hueResponse", scope: .mode(.colorShift), value: .scalar(0.72)),
                        ScopedParameterValue(parameterID: "mode.colorShift.hueRange", scope: .mode(.colorShift), value: .scalar(0.78)),
                    ]
                ),
            ]
        )
        let recorderService = PlaceholderRecorderService()
        let diagnosticsService = PlaceholderDiagnosticsService()
        let externalDisplayCoordinator = PlaceholderExternalDisplayCoordinator()
        let setlistService = PlaceholderSetlistService()
        let presets = presetService.loadPresets()
        let performanceSets = setlistService.loadSets()
        let sessionViewModel = SessionViewModel(
            session: ChromaSession.initial(),
            parameterStore: parameterStore,
            audioInputService: audioInputService,
            inputCalibrationService: inputCalibrationService,
            audioAnalysisService: audioAnalysisService,
            cameraFeedbackService: cameraFeedbackService,
            rendererService: rendererService,
            renderCoordinator: renderCoordinator,
            presetService: presetService,
            recorderService: recorderService,
            diagnosticsService: diagnosticsService,
            externalDisplayCoordinator: externalDisplayCoordinator,
            setlistService: setlistService,
            presets: presets,
            performanceSets: performanceSets
        )
        let appViewModel = AppViewModel(router: router)
        return ChromaAppBootstrap(appViewModel: appViewModel, sessionViewModel: sessionViewModel)
    }
}
