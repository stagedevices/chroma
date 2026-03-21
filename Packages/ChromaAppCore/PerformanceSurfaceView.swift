import SwiftUI

public struct PerformanceSurfaceView: View {
    @ObservedObject private var sessionViewModel: SessionViewModel

    public init(sessionViewModel: SessionViewModel) {
        self.sessionViewModel = sessionViewModel
    }

    public var body: some View {
        RendererHostView(
            rendererService: sessionViewModel.rendererService,
            renderCoordinator: sessionViewModel.renderCoordinator,
            surfaceState: sessionViewModel.rendererSurfaceState,
            isLightAppearance: sessionViewModel.isLightGlassAppearance
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep a stable fallback behind Metal so theme transitions never wash out
        // the performance surface if frame submission stalls.
        .background(
            sessionViewModel.session.activeModeID == .custom
                ? Color.black
                : (sessionViewModel.isLightGlassAppearance ? Color.white : Color.black)
        )
        .onAppear {
            sessionViewModel.refreshDiagnostics()
        }
    }
}
