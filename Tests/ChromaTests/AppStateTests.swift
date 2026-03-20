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

    func testSheetPresentationStyleMatchesDestinationContract() {
        XCTAssertEqual(appSheetPresentationStyle(for: .modePicker), .sheet)
        XCTAssertEqual(appSheetPresentationStyle(for: .presetBrowser), .sheet)
        XCTAssertEqual(appSheetPresentationStyle(for: .recorderExport), .sheet)
        XCTAssertEqual(appSheetPresentationStyle(for: .settingsDiagnostics), .sheet)

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

    func testGlassAppearanceToggleUpdatesSessionState() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        let initialToken = sessionViewModel.appearanceTransitionToken
        XCTAssertFalse(sessionViewModel.isLightGlassAppearance)

        sessionViewModel.toggleGlassAppearanceStyle()
        XCTAssertTrue(sessionViewModel.isLightGlassAppearance)
        XCTAssertEqual(sessionViewModel.session.outputState.glassAppearanceStyle, .light)
        XCTAssertNotEqual(sessionViewModel.appearanceTransitionToken, initialToken)

        sessionViewModel.setGlassAppearanceStyle(.dark)
        XCTAssertFalse(sessionViewModel.isLightGlassAppearance)
        XCTAssertEqual(sessionViewModel.session.outputState.glassAppearanceStyle, .dark)
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
}
