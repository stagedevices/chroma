import Foundation
import Combine

public enum AppSheetDestination: String, Identifiable {
    case modePicker
    case feedbackSetup
    case presetBrowser
    case recorderExport
    case settingsDiagnostics
    case tunnelVariantPicker
    case fractalPalettePicker
    case riemannPalettePicker

    public var id: String { rawValue }
}

public enum AppSheetDetentStyle: Equatable, Sendable {
    case mediumOnly
    case mediumAndLarge
}

public func appSheetDetentStyle(for destination: AppSheetDestination) -> AppSheetDetentStyle {
    switch destination {
    case .modePicker, .presetBrowser, .settingsDiagnostics:
        return .mediumAndLarge
    case .feedbackSetup, .recorderExport, .tunnelVariantPicker, .fractalPalettePicker, .riemannPalettePicker:
        return .mediumOnly
    }
}

@MainActor
public final class AppRouter: ObservableObject {
    @Published public var presentedSheet: AppSheetDestination?

    public init(presentedSheet: AppSheetDestination? = nil) {
        self.presentedSheet = presentedSheet
    }

    public func present(_ destination: AppSheetDestination) {
        presentedSheet = destination
    }

    public func dismiss() {
        presentedSheet = nil
    }
}
