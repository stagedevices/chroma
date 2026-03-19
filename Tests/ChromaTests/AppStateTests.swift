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

        router.dismiss()
        XCTAssertNil(router.presentedSheet)
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
