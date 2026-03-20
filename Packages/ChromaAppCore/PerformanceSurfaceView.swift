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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep a stable dark fallback behind Metal so theme transitions never wash out
        // the performance surface if frame submission stalls.
        .background(Color.black)
        .onAppear {
            sessionViewModel.refreshDiagnostics()
        }
    }
}
