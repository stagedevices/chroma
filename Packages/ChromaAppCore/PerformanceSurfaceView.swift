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
            surfaceState: sessionViewModel.rendererSurfaceState
        )
        .background(sessionViewModel.isLightGlassAppearance ? Color.white : Color.black)
        .onAppear {
            sessionViewModel.refreshDiagnostics()
        }
    }
}
