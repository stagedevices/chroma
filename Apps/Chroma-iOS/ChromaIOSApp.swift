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
    }

    private static func configureGlobalTypography() {
#if canImport(UIKit)
        let navTitle = UIFont(name: "Oswald-SemiBold", size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .semibold)
        let navLargeTitle = UIFont(name: "Oswald-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        let navAction = UIFont(name: "Oswald-Medium", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .medium)
        UINavigationBar.appearance().titleTextAttributes = [.font: navTitle]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: navLargeTitle]
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: navAction], for: .normal)
#endif
    }
}
