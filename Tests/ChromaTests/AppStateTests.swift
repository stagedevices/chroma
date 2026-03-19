import XCTest
@testable import Chroma

@MainActor
final class AppStateTests: XCTestCase {
    func testRouterPresentsAndDismissesSheets() {
        let router = AppRouter()
        router.present(.modePicker)
        XCTAssertEqual(router.presentedSheet, .modePicker)

        router.present(.feedbackSetup)
        XCTAssertEqual(router.presentedSheet, .feedbackSetup)

        router.present(.riemannPalettePicker)
        XCTAssertEqual(router.presentedSheet, .riemannPalettePicker)

        router.dismiss()
        XCTAssertNil(router.presentedSheet)
    }

    func testSheetDetentPolicyMatchesDestinationContract() {
        XCTAssertEqual(appSheetDetentStyle(for: .modePicker), .mediumAndLarge)
        XCTAssertEqual(appSheetDetentStyle(for: .presetBrowser), .mediumAndLarge)
        XCTAssertEqual(appSheetDetentStyle(for: .settingsDiagnostics), .mediumAndLarge)
        XCTAssertEqual(appSheetDetentStyle(for: .feedbackSetup), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .recorderExport), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .tunnelVariantPicker), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .fractalPalettePicker), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .riemannPalettePicker), .mediumOnly)
    }

    func testAppViewModelTogglesPerformanceMode() {
        let appViewModel = AppViewModel(router: AppRouter())
        XCTAssertFalse(appViewModel.isPerformanceModeEnabled)

        appViewModel.togglePerformanceMode()
        XCTAssertTrue(appViewModel.isPerformanceModeEnabled)
        XCTAssertFalse(appViewModel.isChromeVisible)
        XCTAssertTrue(appViewModel.isRevealControlVisible)

        appViewModel.togglePerformanceMode()
        XCTAssertFalse(appViewModel.isPerformanceModeEnabled)
        XCTAssertTrue(appViewModel.isChromeVisible)
        XCTAssertFalse(appViewModel.isRevealControlVisible)
    }

    func testPerformanceModeChromeCanHideAndReveal() {
        let appViewModel = AppViewModel(router: AppRouter())

        appViewModel.togglePerformanceMode()
        appViewModel.hidePerformanceChrome()
        XCTAssertFalse(appViewModel.isChromeVisible)
        XCTAssertTrue(appViewModel.isRevealControlVisible)

        appViewModel.revealPerformanceChrome()
        XCTAssertTrue(appViewModel.isChromeVisible)
        XCTAssertFalse(appViewModel.isRevealControlVisible)
    }

    func testAppViewModelPresentsModeStylePickers() {
        let router = AppRouter()
        let appViewModel = AppViewModel(router: router)

        appViewModel.presentTunnelVariantPicker()
        XCTAssertEqual(router.presentedSheet, .tunnelVariantPicker)

        appViewModel.presentFractalPalettePicker()
        XCTAssertEqual(router.presentedSheet, .fractalPalettePicker)

        appViewModel.presentRiemannPalettePicker()
        XCTAssertEqual(router.presentedSheet, .riemannPalettePicker)
    }

    func testSessionTransitionsModeAndPreset() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.prismField)
        XCTAssertEqual(sessionViewModel.session.activeModeID, .prismField)
        XCTAssertEqual(sessionViewModel.rendererSurfaceState.activeModeID, .prismField)

        let preset = Preset(
            name: "Color Recall",
            modeID: .colorShift,
            values: [ScopedParameterValue(parameterID: "response.inputGain", scope: .global, value: .scalar(0.9))]
        )
        sessionViewModel.applyPreset(preset)

        XCTAssertEqual(sessionViewModel.session.activePresetName, "Color Recall")
        XCTAssertEqual(sessionViewModel.session.activeModeID, .colorShift)
        XCTAssertEqual(sessionViewModel.parameterStore.value(for: "response.inputGain", scope: .global), .scalar(0.9))
    }

    func testSessionExposesAudioInputSources() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.refreshAudioInputs()
        XCTAssertFalse(sessionViewModel.availableAudioInputSources.isEmpty)
        XCTAssertNotNil(sessionViewModel.selectedAudioInputSourceID)
    }

    func testFeedbackActionAvailableOnlyInColorShift() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        XCTAssertTrue(sessionViewModel.showsColorFeedbackAction)
        sessionViewModel.selectMode(.prismField)
        XCTAssertFalse(sessionViewModel.showsColorFeedbackAction)
    }

    func testTunnelVariantActionAvailableOnlyInTunnelCels() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        XCTAssertFalse(sessionViewModel.showsTunnelVariantAction)
        sessionViewModel.selectMode(.tunnelCels)
        XCTAssertTrue(sessionViewModel.showsTunnelVariantAction)
    }

    func testCyclingTunnelVariantUpdatesModeScopedParameter() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.tunnelCels)
        sessionViewModel.cycleTunnelVariant()
        sessionViewModel.cycleTunnelVariant()

        let current = sessionViewModel.parameterStore.value(
            for: "mode.tunnelCels.variant",
            scope: .mode(.tunnelCels)
        )?.scalarValue ?? -1
        XCTAssertEqual(current, 2, accuracy: 0.0001)
        XCTAssertEqual(sessionViewModel.tunnelVariantLabel, "Glyph Slabs")
    }

    func testSettingTunnelVariantWritesScopedValue() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.tunnelCels)
        sessionViewModel.setTunnelVariant(index: 1)

        let current = sessionViewModel.parameterStore.value(
            for: "mode.tunnelCels.variant",
            scope: .mode(.tunnelCels)
        )?.scalarValue ?? -1
        XCTAssertEqual(current, 1, accuracy: 0.0001)
        XCTAssertEqual(sessionViewModel.tunnelVariantLabel, "Prism Shards")
    }

    func testFractalPaletteActionAvailableOnlyInFractalCaustics() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        XCTAssertFalse(sessionViewModel.showsFractalPaletteAction)
        sessionViewModel.selectMode(.fractalCaustics)
        XCTAssertTrue(sessionViewModel.showsFractalPaletteAction)
    }

    func testCyclingFractalPaletteUpdatesModeScopedParameter() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.fractalCaustics)
        sessionViewModel.cycleFractalPaletteVariant()
        sessionViewModel.cycleFractalPaletteVariant()
        sessionViewModel.cycleFractalPaletteVariant()

        let current = sessionViewModel.parameterStore.value(
            for: "mode.fractalCaustics.paletteVariant",
            scope: .mode(.fractalCaustics)
        )?.scalarValue ?? -1
        XCTAssertEqual(current, 3, accuracy: 0.0001)
        XCTAssertEqual(sessionViewModel.fractalPaletteLabel, "Neon")
    }

    func testSettingFractalPaletteWritesScopedValue() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.fractalCaustics)
        sessionViewModel.setFractalPaletteVariant(index: 6)

        let current = sessionViewModel.parameterStore.value(
            for: "mode.fractalCaustics.paletteVariant",
            scope: .mode(.fractalCaustics)
        )?.scalarValue ?? -1
        XCTAssertEqual(current, 6, accuracy: 0.0001)
        XCTAssertEqual(sessionViewModel.fractalPaletteLabel, "Mono")
    }

    func testRiemannPaletteActionAvailableOnlyInRiemannCorridor() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        XCTAssertFalse(sessionViewModel.showsRiemannPaletteAction)
        sessionViewModel.selectMode(.riemannCorridor)
        XCTAssertTrue(sessionViewModel.showsRiemannPaletteAction)
    }

    func testCyclingRiemannPaletteUpdatesModeScopedParameter() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.riemannCorridor)
        sessionViewModel.cycleRiemannPaletteVariant()
        sessionViewModel.cycleRiemannPaletteVariant()
        sessionViewModel.cycleRiemannPaletteVariant()

        let current = sessionViewModel.parameterStore.value(
            for: "mode.riemannCorridor.paletteVariant",
            scope: .mode(.riemannCorridor)
        )?.scalarValue ?? -1
        XCTAssertEqual(current, 3, accuracy: 0.0001)
        XCTAssertEqual(sessionViewModel.riemannPaletteLabel, "Neon")
    }

    func testSettingRiemannPaletteWritesScopedValue() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.riemannCorridor)
        sessionViewModel.setRiemannPaletteVariant(index: 5)

        let current = sessionViewModel.parameterStore.value(
            for: "mode.riemannCorridor.paletteVariant",
            scope: .mode(.riemannCorridor)
        )?.scalarValue ?? -1
        XCTAssertEqual(current, 5, accuracy: 0.0001)
        XCTAssertEqual(sessionViewModel.riemannPaletteLabel, "Glass")
    }

    func testStartingFeedbackEnablesFlagAndLeavingColorShiftDisablesIt() async {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel
        guard let cameraService = sessionViewModel.cameraFeedbackService as? PlaceholderCameraFeedbackService else {
            return XCTFail("Expected PlaceholderCameraFeedbackService")
        }

        await sessionViewModel.startColorFeedbackCapture()
        XCTAssertTrue(sessionViewModel.session.outputState.isColorFeedbackEnabled)
        XCTAssertTrue(sessionViewModel.isColorFeedbackRunning)
        XCTAssertEqual(cameraService.startCallCount, 1)

        sessionViewModel.selectMode(.prismField)
        XCTAssertFalse(sessionViewModel.session.outputState.isColorFeedbackEnabled)
        XCTAssertFalse(sessionViewModel.isColorFeedbackRunning)
        XCTAssertGreaterThanOrEqual(cameraService.stopCallCount, 1)
    }

    func testDeniedFeedbackAuthorizationKeepsFeedbackDisabled() async {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel
        guard let cameraService = sessionViewModel.cameraFeedbackService as? PlaceholderCameraFeedbackService else {
            return XCTFail("Expected PlaceholderCameraFeedbackService")
        }

        cameraService.setAuthorizationStatusForTesting(.denied)
        await sessionViewModel.startColorFeedbackCapture()

        XCTAssertFalse(sessionViewModel.session.outputState.isColorFeedbackEnabled)
        XCTAssertFalse(sessionViewModel.isColorFeedbackRunning)
        XCTAssertEqual(sessionViewModel.cameraFeedbackAuthorizationStatus, .denied)
        XCTAssertNotNil(sessionViewModel.cameraFeedbackStatusMessage)
    }
}
