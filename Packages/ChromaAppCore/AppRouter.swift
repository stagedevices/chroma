import Foundation
import Combine

public enum AppSheetDestination: String, Identifiable {
    case modePicker
    case feedbackSetup
    case presetBrowser
    case recorderExport
    case settingsDiagnostics

    public var id: String { rawValue }
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
