import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppViewModel: ObservableObject {
    public let router: AppRouter

    @Published public var isPerformanceModeEnabled: Bool
    @Published public private(set) var isChromeVisible: Bool
    @Published public private(set) var isRevealControlVisible: Bool

    private var performanceHideTask: Task<Void, Never>?
    private let chromeHideDelayNanoseconds: UInt64 = 4_000_000_000
    private let revealControlHideDelayNanoseconds: UInt64 = 3_000_000_000

    public init(router: AppRouter, isPerformanceModeEnabled: Bool = false) {
        self.router = router
        self.isPerformanceModeEnabled = isPerformanceModeEnabled
        self.isChromeVisible = true
        self.isRevealControlVisible = false
    }

    public func togglePerformanceMode() {
        if isPerformanceModeEnabled {
            cancelScheduledHide()
            isPerformanceModeEnabled = false
            withAnimation(.easeInOut(duration: 0.22)) {
                isChromeVisible = true
                isRevealControlVisible = false
            }
        } else {
            isPerformanceModeEnabled = true
            hidePerformanceChrome()
        }
    }

    public func hidePerformanceChrome() {
        guard isPerformanceModeEnabled else { return }
        cancelScheduledHide()
        withAnimation(.easeInOut(duration: 0.22)) {
            isChromeVisible = false
            isRevealControlVisible = true
        }
        scheduleRevealControlHide()
    }

    public func revealPerformanceChrome() {
        guard isPerformanceModeEnabled else {
            withAnimation(.easeInOut(duration: 0.22)) {
                isChromeVisible = true
                isRevealControlVisible = false
            }
            return
        }

        cancelScheduledHide()
        withAnimation(.easeInOut(duration: 0.22)) {
            isChromeVisible = true
            isRevealControlVisible = false
        }
        scheduleChromeHide()
    }

    public func handleCanvasTap() {
        guard isPerformanceModeEnabled else { return }
        if isChromeVisible {
            scheduleChromeHide()
        } else {
            cancelScheduledHide()
            withAnimation(.easeInOut(duration: 0.22)) {
                isRevealControlVisible = true
            }
            scheduleRevealControlHide()
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

    private func scheduleChromeHide() {
        cancelScheduledHide()
        let delay = chromeHideDelayNanoseconds
        performanceHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.isPerformanceModeEnabled else { return }
            self.hidePerformanceChrome()
        }
    }

    private func scheduleRevealControlHide() {
        cancelScheduledHide()
        let delay = revealControlHideDelayNanoseconds
        performanceHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.isPerformanceModeEnabled, !self.isChromeVisible else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.isRevealControlVisible = false
            }
        }
    }

    private func cancelScheduledHide() {
        performanceHideTask?.cancel()
        performanceHideTask = nil
    }
}
