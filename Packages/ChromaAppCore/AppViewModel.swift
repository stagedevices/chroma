import Foundation
import SwiftUI
import Combine

public enum PerformanceChromeState: Equatable {
    case controlsVisible
    case controlsHiddenShowButtonVisible
    case controlsHiddenShowButtonHidden
}

@MainActor
public final class AppViewModel: ObservableObject {
    public let router: AppRouter

    @Published public var isPerformanceModeEnabled: Bool
    @Published public private(set) var performanceChromeState: PerformanceChromeState

    public var isChromeVisible: Bool {
        !isPerformanceModeEnabled || performanceChromeState == .controlsVisible
    }

    public var isRevealControlVisible: Bool {
        isPerformanceModeEnabled && performanceChromeState == .controlsHiddenShowButtonVisible
    }

    private var chromeAutoHideTask: Task<Void, Never>?
    private var showControlsAutoHideTask: Task<Void, Never>?
    private var showControlsRevealTask: Task<Void, Never>?
    private let chromeHideDelayNanoseconds: UInt64
    private let showControlsHideDelayNanoseconds: UInt64
    private let showControlsRevealDelayNanoseconds: UInt64

    public init(
        router: AppRouter,
        isPerformanceModeEnabled: Bool = false,
        chromeHideDelayNanoseconds: UInt64 = 3_500_000_000,
        showControlsHideDelayNanoseconds: UInt64 = 1_800_000_000,
        showControlsRevealDelayNanoseconds: UInt64 = 80_000_000
    ) {
        self.router = router
        self.isPerformanceModeEnabled = isPerformanceModeEnabled
        self.performanceChromeState = .controlsVisible
        self.chromeHideDelayNanoseconds = chromeHideDelayNanoseconds
        self.showControlsHideDelayNanoseconds = showControlsHideDelayNanoseconds
        self.showControlsRevealDelayNanoseconds = showControlsRevealDelayNanoseconds
    }

    public func togglePerformanceMode() {
        if isPerformanceModeEnabled {
            exitPerformanceMode()
        } else {
            enterPerformanceMode()
        }
    }

    public func enterPerformanceMode() {
        guard !isPerformanceModeEnabled else { return }
        cancelPendingPerformanceTasks()
        withAnimation(.easeInOut(duration: 0.22)) {
            isPerformanceModeEnabled = true
            performanceChromeState = .controlsHiddenShowButtonHidden
        }
        scheduleShowControlsRevealThenHide()
    }

    public func exitPerformanceMode() {
        guard isPerformanceModeEnabled else { return }
        cancelPendingPerformanceTasks()
        withAnimation(.easeInOut(duration: 0.22)) {
            isPerformanceModeEnabled = false
            performanceChromeState = .controlsVisible
        }
    }

    public func hidePerformanceChrome() {
        guard isPerformanceModeEnabled else { return }
        cancelPendingPerformanceTasks()
        withAnimation(.easeInOut(duration: 0.20)) {
            performanceChromeState = .controlsHiddenShowButtonVisible
        }
        scheduleShowControlsAutoHide()
    }

    public func revealPerformanceChrome() {
        guard isPerformanceModeEnabled else {
            withAnimation(.easeInOut(duration: 0.22)) {
                performanceChromeState = .controlsVisible
            }
            return
        }

        cancelPendingPerformanceTasks()
        if performanceChromeState == .controlsHiddenShowButtonVisible {
            withAnimation(.easeOut(duration: 0.14)) {
                performanceChromeState = .controlsHiddenShowButtonHidden
            }
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            performanceChromeState = .controlsVisible
        }
        scheduleChromeAutoHide()
    }

    public func handleCanvasTap() {
        guard isPerformanceModeEnabled else { return }

        switch performanceChromeState {
        case .controlsVisible:
            scheduleChromeHide()
        case .controlsHiddenShowButtonVisible:
            scheduleShowControlsAutoHide()
        case .controlsHiddenShowButtonHidden:
            showRevealControlTemporarily()
        }
    }

    public func registerPerformanceInteraction() {
        guard isPerformanceModeEnabled else { return }
        revealPerformanceChrome()
    }

    public func presentModePicker() {
        registerPerformanceInteraction()
        router.present(.modePicker)
    }

    public func presentFeedbackSetup() {
        registerPerformanceInteraction()
        router.present(.feedbackSetup)
    }

    public func presentPresetBrowser() {
        registerPerformanceInteraction()
        router.present(.presetBrowser)
    }

    public func presentRecorderExport() {
        registerPerformanceInteraction()
        router.present(.recorderExport)
    }

    public func presentSettingsDiagnostics() {
        registerPerformanceInteraction()
        router.present(.settingsDiagnostics)
    }

    public func presentTunnelVariantPicker() {
        registerPerformanceInteraction()
        router.present(.tunnelVariantPicker)
    }

    public func presentFractalPalettePicker() {
        registerPerformanceInteraction()
        router.present(.fractalPalettePicker)
    }

    public func presentRiemannPalettePicker() {
        registerPerformanceInteraction()
        router.present(.riemannPalettePicker)
    }

    public func presentCustomPatchBuilder() {
        registerPerformanceInteraction()
        router.present(.customBuilder)
    }

    private func showRevealControlTemporarily() {
        guard isPerformanceModeEnabled else { return }
        cancelPendingPerformanceTasks()
        withAnimation(.easeOut(duration: 0.18)) {
            performanceChromeState = .controlsHiddenShowButtonVisible
        }
        scheduleShowControlsAutoHide()
    }

    private func scheduleChromeHide() {
        scheduleChromeAutoHide()
    }

    private func scheduleChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        let delay = chromeHideDelayNanoseconds
        chromeAutoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.isPerformanceModeEnabled else { return }
            self.hidePerformanceChrome()
        }
    }

    private func scheduleShowControlsAutoHide() {
        showControlsAutoHideTask?.cancel()
        let delay = showControlsHideDelayNanoseconds
        showControlsAutoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard
                let self,
                !Task.isCancelled,
                self.isPerformanceModeEnabled,
                self.performanceChromeState == .controlsHiddenShowButtonVisible
            else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                self.performanceChromeState = .controlsHiddenShowButtonHidden
            }
        }
    }

    private func scheduleShowControlsRevealThenHide() {
        showControlsRevealTask?.cancel()
        let delay = showControlsRevealDelayNanoseconds
        showControlsRevealTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.isPerformanceModeEnabled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                self.performanceChromeState = .controlsHiddenShowButtonVisible
            }
            self.scheduleShowControlsAutoHide()
        }
    }

    private func cancelPendingPerformanceTasks() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
        showControlsAutoHideTask?.cancel()
        showControlsAutoHideTask = nil
        showControlsRevealTask?.cancel()
        showControlsRevealTask = nil
    }
}
