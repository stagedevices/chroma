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

        router.present(.customBuilder)
        XCTAssertEqual(router.presentedSheet, .customBuilder)

        router.dismiss()
        XCTAssertNil(router.presentedSheet)
    }

    func testSheetDetentPolicyMatchesDestinationContract() {
        XCTAssertEqual(appSheetDetentStyle(for: .modePicker), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .presetBrowser), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .settingsDiagnostics), .mediumAndLarge)
        XCTAssertEqual(appSheetDetentStyle(for: .feedbackSetup), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .recorderExport), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .tunnelVariantPicker), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .fractalPalettePicker), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .riemannPalettePicker), .mediumOnly)
        XCTAssertEqual(appSheetDetentStyle(for: .customBuilder), .mediumAndLarge)
    }

    func testSheetPresentationStyleMatchesDestinationContract() {
        XCTAssertEqual(appSheetPresentationStyle(for: .modePicker), .sheet)
        XCTAssertEqual(appSheetPresentationStyle(for: .presetBrowser), .sheet)
        XCTAssertEqual(appSheetPresentationStyle(for: .recorderExport), .sheet)
        XCTAssertEqual(appSheetPresentationStyle(for: .settingsDiagnostics), .sheet)
        XCTAssertEqual(appSheetPresentationStyle(for: .customBuilder), .sheet)

        XCTAssertEqual(appSheetPresentationStyle(for: .feedbackSetup), .popover)
        XCTAssertEqual(appSheetPresentationStyle(for: .tunnelVariantPicker), .popover)
        XCTAssertEqual(appSheetPresentationStyle(for: .fractalPalettePicker), .popover)
        XCTAssertEqual(appSheetPresentationStyle(for: .riemannPalettePicker), .popover)
    }

    func testAppViewModelTogglesPerformanceMode() {
        let appViewModel = AppViewModel(router: AppRouter())
        XCTAssertFalse(appViewModel.isPerformanceModeEnabled)

        appViewModel.togglePerformanceMode()
        XCTAssertTrue(appViewModel.isPerformanceModeEnabled)
        XCTAssertFalse(appViewModel.isChromeVisible)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonHidden)
        XCTAssertFalse(appViewModel.isRevealControlVisible)

        appViewModel.togglePerformanceMode()
        XCTAssertFalse(appViewModel.isPerformanceModeEnabled)
        XCTAssertTrue(appViewModel.isChromeVisible)
        XCTAssertFalse(appViewModel.isRevealControlVisible)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsVisible)
    }

    func testExitPerformanceModeIsOneWayAndCannotReenterFullscreen() {
        let appViewModel = AppViewModel(router: AppRouter())

        // No-op when already not in fullscreen.
        appViewModel.exitPerformanceMode()
        XCTAssertFalse(appViewModel.isPerformanceModeEnabled)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsVisible)

        // Exits cleanly when in fullscreen.
        appViewModel.enterPerformanceMode()
        XCTAssertTrue(appViewModel.isPerformanceModeEnabled)
        appViewModel.exitPerformanceMode()
        XCTAssertFalse(appViewModel.isPerformanceModeEnabled)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsVisible)
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
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsVisible)
    }

    func testPerformanceModeRevealButtonAutoHidesFully() async {
        let appViewModel = AppViewModel(
            router: AppRouter(),
            chromeHideDelayNanoseconds: 120_000_000,
            showControlsHideDelayNanoseconds: 60_000_000,
            showControlsRevealDelayNanoseconds: 10_000_000
        )

        appViewModel.togglePerformanceMode()
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonHidden)

        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonVisible)

        try? await Task.sleep(nanoseconds: 90_000_000)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonHidden)
        XCTAssertFalse(appViewModel.isRevealControlVisible)
    }

    func testCanvasTapHiddenStateShowsRevealAndSecondTapKeepsFullscreenHiddenChrome() async {
        let appViewModel = AppViewModel(
            router: AppRouter(),
            chromeHideDelayNanoseconds: 500_000_000,
            showControlsHideDelayNanoseconds: 80_000_000,
            showControlsRevealDelayNanoseconds: 10_000_000
        )

        appViewModel.togglePerformanceMode()
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonHidden)

        appViewModel.handleCanvasTap()
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonVisible)
        XCTAssertTrue(appViewModel.isRevealControlVisible)

        appViewModel.handleCanvasTap()
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonVisible)
        XCTAssertFalse(appViewModel.isChromeVisible)
    }

    func testRegisterPerformanceInteractionKeepsChromeVisibleUntilAutoHide() async {
        let appViewModel = AppViewModel(
            router: AppRouter(),
            chromeHideDelayNanoseconds: 80_000_000,
            showControlsHideDelayNanoseconds: 50_000_000,
            showControlsRevealDelayNanoseconds: 10_000_000
        )

        appViewModel.togglePerformanceMode()
        appViewModel.registerPerformanceInteraction()
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsVisible)
        XCTAssertTrue(appViewModel.isChromeVisible)

        try? await Task.sleep(nanoseconds: 110_000_000)
        XCTAssertEqual(appViewModel.performanceChromeState, .controlsHiddenShowButtonVisible)
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

        appViewModel.presentCustomPatchBuilder()
        XCTAssertEqual(router.presentedSheet, .customBuilder)
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

    func testCustomPatchSelectionAndRenameIntentsUpdateActivePatch() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.custom)
        XCTAssertTrue(sessionViewModel.showsCustomBuilderAction)

        guard let activePatch = sessionViewModel.activeCustomPatch else {
            return XCTFail("Expected seeded custom patch")
        }
        let updatedName = "Venue Chain A"
        sessionViewModel.renameActiveCustomPatch(updatedName)
        XCTAssertEqual(sessionViewModel.activeCustomPatch?.name, updatedName)
        XCTAssertEqual(sessionViewModel.customPatchLibrary.activePatchID, activePatch.id)

        sessionViewModel.selectCustomPatch(id: activePatch.id)
        XCTAssertEqual(sessionViewModel.customPatchLibrary.activePatchID, activePatch.id)
    }

    func testGlassAppearanceToggleUpdatesSessionState() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        let initialToken = sessionViewModel.appearanceTransitionToken
        XCTAssertFalse(sessionViewModel.isLightGlassAppearance)
        XCTAssertFalse(sessionViewModel.rendererSurfaceState.controls.isLightAppearance)

        sessionViewModel.toggleGlassAppearanceStyle()
        XCTAssertTrue(sessionViewModel.isLightGlassAppearance)
        XCTAssertEqual(sessionViewModel.session.outputState.glassAppearanceStyle, .light)
        XCTAssertTrue(sessionViewModel.rendererSurfaceState.controls.isLightAppearance)
        XCTAssertNotEqual(sessionViewModel.appearanceTransitionToken, initialToken)

        sessionViewModel.setGlassAppearanceStyle(.dark)
        XCTAssertFalse(sessionViewModel.isLightGlassAppearance)
        XCTAssertEqual(sessionViewModel.session.outputState.glassAppearanceStyle, .dark)
        XCTAssertFalse(sessionViewModel.rendererSurfaceState.controls.isLightAppearance)
    }

    func testPresetsForActiveModeFiltersByModeID() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        XCTAssertEqual(sessionViewModel.session.activeModeID, .colorShift)
        XCTAssertTrue(sessionViewModel.presetsForActiveMode.allSatisfy { $0.modeID == .colorShift })

        sessionViewModel.selectMode(.prismField)
        XCTAssertTrue(sessionViewModel.presetsForActiveMode.allSatisfy { $0.modeID == .prismField })
    }

    func testQuickSaveCapturesGlobalAndActiveModeValuesOnly() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "response.inputGain")!,
            value: .scalar(0.91)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.colorShift.hueResponse")!,
            value: .scalar(0.33)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.prismField.facetDensity")!,
            value: .scalar(0.44)
        )

        guard let saved = sessionViewModel.quickSaveActiveModePreset() else {
            return XCTFail("Expected quick save to return a preset")
        }

        XCTAssertEqual(saved.modeID, .colorShift)
        XCTAssertTrue(saved.values.contains(where: { $0.scope.kind == .global && $0.parameterID == "response.inputGain" }))
        XCTAssertTrue(saved.values.contains(where: { $0.scope == .mode(.colorShift) && $0.parameterID == "mode.colorShift.hueResponse" }))
        XCTAssertFalse(saved.values.contains(where: { $0.scope == .mode(.prismField) && $0.parameterID == "mode.prismField.facetDensity" }))
        XCTAssertEqual(sessionViewModel.session.activePresetID, saved.id)
    }

    func testRenameAndDeletePresetUpdateActiveMetadata() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        guard let saved = sessionViewModel.quickSaveActiveModePreset() else {
            return XCTFail("Expected quick save preset")
        }

        sessionViewModel.renamePreset(id: saved.id, newName: "  Renamed Color  ")
        XCTAssertTrue(sessionViewModel.presets.contains(where: { $0.id == saved.id && $0.name == "Renamed Color" }))
        XCTAssertEqual(sessionViewModel.session.activePresetName, "Renamed Color")

        sessionViewModel.deletePreset(id: saved.id)
        XCTAssertFalse(sessionViewModel.presets.contains(where: { $0.id == saved.id }))
        XCTAssertNil(sessionViewModel.session.activePresetID)
        XCTAssertEqual(sessionViewModel.session.activePresetName, "Unsaved Session")
    }

    func testQuickSaveAlwaysCreatesNewPreset() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel
        let initialCount = sessionViewModel.presets.count

        guard let first = sessionViewModel.quickSaveActiveModePreset() else {
            return XCTFail("Expected first quick save preset")
        }
        guard let second = sessionViewModel.quickSaveActiveModePreset() else {
            return XCTFail("Expected second quick save preset")
        }

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(sessionViewModel.presets.count, initialCount + 2)
        XCTAssertEqual(sessionViewModel.session.activePresetID, second.id)
    }

    func testActivePresetModifiedStateTracksParameterChanges() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        guard let saved = sessionViewModel.quickSaveActiveModePreset() else {
            return XCTFail("Expected quick save preset")
        }

        XCTAssertFalse(sessionViewModel.isActivePresetModified)
        XCTAssertEqual(sessionViewModel.activePresetDisplayName, saved.name)

        guard let hueResponse = sessionViewModel.parameterStore.descriptor(for: "mode.colorShift.hueResponse") else {
            return XCTFail("Expected hue response descriptor")
        }

        sessionViewModel.updateParameter(hueResponse, value: .scalar(0.12))
        XCTAssertTrue(sessionViewModel.isActivePresetModified)
        XCTAssertEqual(sessionViewModel.activePresetDisplayName, "\(saved.name) • Modified")

        guard let reloaded = sessionViewModel.presets.first(where: { $0.id == saved.id }) else {
            return XCTFail("Expected saved preset in collection")
        }
        sessionViewModel.applyPreset(reloaded)
        XCTAssertFalse(sessionViewModel.isActivePresetModified)
        XCTAssertEqual(sessionViewModel.activePresetDisplayName, reloaded.name)
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

    func testPerformanceAndCalibrationSettingsUpdateEngineState() async {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel
        guard let analysis = sessionViewModel.audioAnalysisService as? PlaceholderAudioAnalysisService else {
            return XCTFail("Expected PlaceholderAudioAnalysisService")
        }

        sessionViewModel.setPerformanceMode(.safeFPS)
        XCTAssertEqual(sessionViewModel.session.performanceSettings.mode, .safeFPS)
        XCTAssertEqual(sessionViewModel.rendererSurfaceState.controls.performanceModeIndex, 2.0, accuracy: 0.0001)

        sessionViewModel.adjustAttackThreshold(by: 1.5)
        sessionViewModel.adjustSilenceGateThreshold(by: 0.015)
        XCTAssertEqual(analysis.currentTuning.attackThresholdDB, 9.5, accuracy: 0.0001)
        XCTAssertEqual(analysis.currentTuning.silenceGateThreshold, 0.045, accuracy: 0.0001)

        await sessionViewModel.calibrateRoomNoise()
        XCTAssertEqual(sessionViewModel.session.audioCalibrationSettings.attackThresholdDB, 8.0, accuracy: 0.0001)
        XCTAssertEqual(sessionViewModel.session.audioCalibrationSettings.silenceGateThreshold, 0.03, accuracy: 0.0001)
    }

    func testRiemannNavigationControlsWriteModeScopedValues() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.riemannCorridor)
        XCTAssertFalse(sessionViewModel.riemannNavigationIsFreeFlight)
        XCTAssertEqual(sessionViewModel.riemannSteeringStrength, 0.62, accuracy: 0.0001)

        sessionViewModel.setRiemannNavigationMode(freeFlight: true)
        sessionViewModel.setRiemannSteeringStrength(0.84)

        XCTAssertTrue(sessionViewModel.riemannNavigationIsFreeFlight)
        XCTAssertEqual(sessionViewModel.riemannSteeringStrength, 0.84, accuracy: 0.0001)
    }

    func testModeDefaultsSaveApplyAndResetForCurrentMode() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        let inputGain = sessionViewModel.parameterStore.descriptor(for: "response.inputGain")!
        let hueResponse = sessionViewModel.parameterStore.descriptor(for: "mode.colorShift.hueResponse")!

        sessionViewModel.updateParameter(inputGain, value: .scalar(0.95))
        sessionViewModel.updateParameter(hueResponse, value: .scalar(0.21))
        sessionViewModel.setCurrentModeAsDefault()

        sessionViewModel.updateParameter(inputGain, value: .scalar(1.21))
        sessionViewModel.updateParameter(hueResponse, value: .scalar(0.82))

        sessionViewModel.selectMode(.prismField)
        sessionViewModel.selectMode(.colorShift)

        XCTAssertEqual(
            sessionViewModel.parameterStore.value(for: "response.inputGain", scope: .global)?.scalarValue ?? -1,
            0.95,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            sessionViewModel.parameterStore.value(for: "mode.colorShift.hueResponse", scope: .mode(.colorShift))?.scalarValue ?? -1,
            0.21,
            accuracy: 0.0001
        )

        sessionViewModel.resetCurrentModeDefaults()
        XCTAssertEqual(
            sessionViewModel.parameterStore.value(for: "response.inputGain", scope: .global)?.scalarValue ?? -1,
            0.72,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            sessionViewModel.parameterStore.value(for: "mode.colorShift.hueResponse", scope: .mode(.colorShift))?.scalarValue ?? -1,
            0.66,
            accuracy: 0.0001
        )
    }

    func testSessionRecoveryAutosaveAndPanicReset() async {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel
        guard let recovery = sessionViewModel.sessionRecoveryService as? PlaceholderSessionRecoveryService else {
            return XCTFail("Expected PlaceholderSessionRecoveryService")
        }

        XCTAssertNil(recovery.loadSnapshot())
        let gainDescriptor = sessionViewModel.parameterStore.descriptor(for: "response.inputGain")!
        sessionViewModel.updateParameter(gainDescriptor, value: .scalar(1.07))

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let saved = recovery.loadSnapshot()
        XCTAssertNotNil(saved)
        XCTAssertTrue(
            saved?.parameterAssignments.contains(where: {
                $0.parameterID == "response.inputGain" && $0.scope == .global
            }) ?? false
        )

        await sessionViewModel.resetToCleanState()
        XCTAssertNil(recovery.loadSnapshot())
        XCTAssertEqual(sessionViewModel.session.activeModeID, .colorShift)
    }

    func testModePickerHeroPresentationMetadataCoversAllModes() {
        let presentationMap = modePickerHeroPresentationMap()
        XCTAssertEqual(Set(presentationMap.keys), Set(VisualModeID.allCases))

        for modeID in VisualModeID.allCases {
            let presentation = modePickerHeroPresentation(for: modeID)
            XCTAssertFalse(presentation.systemImage.isEmpty)
            XCTAssertFalse(presentation.tagline.isEmpty)
            XCTAssertFalse(presentation.behaviorTags.isEmpty)
        }
    }

    func testModePickerDraftStateStartsAtActiveMode() {
        let state = ModePickerDraftState(activeModeID: .fractalCaustics)
        XCTAssertEqual(state.initialModeID, .fractalCaustics)
        XCTAssertEqual(state.activeModeAfterDismissWithoutApply(), .fractalCaustics)
        XCTAssertEqual(state.activeModeAfterApply(), .fractalCaustics)
    }

    func testModePickerDraftStatePreviewDoesNotCommitWithoutApply() {
        var state = ModePickerDraftState(activeModeID: .colorShift)
        state.preview(.tunnelCels)
        XCTAssertEqual(state.activeModeAfterDismissWithoutApply(), .colorShift)
        XCTAssertEqual(state.activeModeAfterApply(), .tunnelCels)
    }

    func testPresetPickerDraftStateStartsAtActivePresetWhenAvailable() {
        let first = Preset(name: "First", modeID: .colorShift, values: [])
        let second = Preset(name: "Second", modeID: .colorShift, values: [])
        let state = PresetPickerDraftState(activePresetID: second.id, presets: [first, second])
        XCTAssertEqual(state.initialPresetID, second.id)
        XCTAssertEqual(state.activePresetAfterDismissWithoutApply(), second.id)
        XCTAssertEqual(state.activePresetAfterApply(), second.id)
    }

    func testPresetPickerDraftStateFallsBackToFirstWhenActiveMissing() {
        let first = Preset(name: "First", modeID: .colorShift, values: [])
        let second = Preset(name: "Second", modeID: .colorShift, values: [])
        var state = PresetPickerDraftState(activePresetID: UUID(), presets: [first, second])

        XCTAssertEqual(state.activePresetAfterApply(), first.id)

        state.preview(second.id)
        XCTAssertEqual(state.activePresetAfterDismissWithoutApply(), state.initialPresetID)
        XCTAssertEqual(state.activePresetAfterApply(), second.id)
    }

    func testPalettePickerPresentationCatalogContainsEightDistinctEntries() {
        let catalog = chromaPalettePickerPresentationCatalog()
        XCTAssertEqual(catalog.count, 8)
        XCTAssertEqual(Set(catalog.map(\.index)).count, 8)
        XCTAssertTrue(catalog.allSatisfy { !$0.name.isEmpty && !$0.systemImage.isEmpty && $0.swatchHues.count == 4 })
    }

    func testTunnelVariantPickerPresentationCatalogContainsThreeEntries() {
        let catalog = tunnelVariantPickerPresentationCatalog()
        XCTAssertEqual(catalog.map(\.index), [0, 1, 2])
        XCTAssertTrue(catalog.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty && !$0.systemImage.isEmpty })
    }

    func testAboutLinkCatalogContainsExpectedHTTPSLinks() {
        let links = chromaAboutLinkCatalog()
        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(
            links.map(\.urlString),
            [
                "https://stagedevices.github.io/chroma",
                "https://stagedevices.github.io/chroma/privacy",
                "https://stagedevices.github.io/chroma/support",
            ]
        )
        XCTAssertTrue(links.allSatisfy { $0.urlString.hasPrefix("https://") })
    }

    func testAboutVersionStringFormatterUsesStableFallbacks() {
        XCTAssertEqual(chromaAboutVersionString(infoDictionary: nil), "Version unavailable")
        XCTAssertEqual(chromaAboutVersionString(infoDictionary: ["CFBundleShortVersionString": "2.1.0"]), "2.1.0")
        XCTAssertEqual(chromaAboutVersionString(infoDictionary: ["CFBundleVersion": "84"]), "Build 84")
        XCTAssertEqual(
            chromaAboutVersionString(
                infoDictionary: [
                    "CFBundleShortVersionString": "2.1.0",
                    "CFBundleVersion": "84",
                ]
            ),
            "2.1.0 (84)"
        )
    }
}
