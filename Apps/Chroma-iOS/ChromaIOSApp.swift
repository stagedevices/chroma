import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
@MainActor
struct ChromaIOSApp: App {
    @StateObject private var appViewModel: AppViewModel
    @StateObject private var sessionViewModel: SessionViewModel
    private let isRunningTests: Bool

    init() {
        isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        Self.configureGlobalTypography()
        let bootstrap = isRunningTests ? ChromaAppBootstrap.makeTesting() : ChromaAppBootstrap.makeDefault()
        _appViewModel = StateObject(wrappedValue: bootstrap.appViewModel)
        _sessionViewModel = StateObject(wrappedValue: bootstrap.sessionViewModel)
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                Color.clear
                    .ignoresSafeArea()
            } else {
                RootShellView(appViewModel: appViewModel, sessionViewModel: sessionViewModel)
                    .font(ChromaTypography.body)
            }
        }
#if targetEnvironment(macCatalyst)
        .commands {
            ChromaCommandMenu(appViewModel: appViewModel)
        }
#endif
    }

    private static func configureGlobalTypography() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        let navTitle = UIFont(name: "Oswald-SemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
        let navLargeTitle = UIFont(name: "Oswald-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        let navAction = UIFont(name: "Oswald-Medium", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .medium)
        UINavigationBar.appearance().titleTextAttributes = [.font: navTitle]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: navLargeTitle]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: navAction], for: .normal)
#endif
    }
}

#if targetEnvironment(macCatalyst)
private struct ChromaCommandMenu: Commands {
    @ObservedObject var appViewModel: AppViewModel

    var body: some Commands {
        CommandMenu("Chroma") {
            Button("Modes") {
                appViewModel.presentModePicker()
            }
            .keyboardShortcut("m", modifiers: [.command])

            Button("Presets") {
                appViewModel.presentPresetBrowser()
            }
            .keyboardShortcut("p", modifiers: [.command])

            Button("Export") {
                appViewModel.presentRecorderExport()
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button("Settings") {
                appViewModel.presentSettingsDiagnostics()
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button(appViewModel.isPerformanceModeEnabled ? "Exit Fullscreen" : "Enter Fullscreen") {
                appViewModel.togglePerformanceMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}
#endif
