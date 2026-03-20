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

public enum AppSheetPresentationStyle: Equatable, Sendable {
    case sheet
    case popover
}

public func appSheetPresentationStyle(for destination: AppSheetDestination) -> AppSheetPresentationStyle {
    switch destination {
    case .modePicker, .presetBrowser, .recorderExport, .settingsDiagnostics:
        return .sheet
    case .feedbackSetup, .tunnelVariantPicker, .fractalPalettePicker, .riemannPalettePicker:
        return .popover
    }
}

public func appSheetDetentStyle(for destination: AppSheetDestination) -> AppSheetDetentStyle {
    switch destination {
    case .settingsDiagnostics:
        return .mediumAndLarge
    case .modePicker, .presetBrowser, .feedbackSetup, .recorderExport, .tunnelVariantPicker, .fractalPalettePicker, .riemannPalettePicker:
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
