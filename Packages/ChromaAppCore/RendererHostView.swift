import SwiftUI
import MetalKit
import UIKit

public struct RendererHostView: View {
    public let rendererService: RendererService
    public let renderCoordinator: RenderCoordinator
    public let surfaceState: RendererSurfaceState
    public let isLightAppearance: Bool

    public init(
        rendererService: RendererService,
        renderCoordinator: RenderCoordinator,
        surfaceState: RendererSurfaceState,
        isLightAppearance: Bool
    ) {
        self.rendererService = rendererService
        self.renderCoordinator = renderCoordinator
        self.surfaceState = surfaceState
        self.isLightAppearance = isLightAppearance
    }

    public var body: some View {
        MetalRendererContainer(
            rendererService: rendererService,
            renderCoordinator: renderCoordinator,
            surfaceState: surfaceState,
            isLightAppearance: isLightAppearance
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            surfaceState.activeModeID == .custom
                ? Color.black
                : (isLightAppearance ? Color.white : Color.black)
        )
        .ignoresSafeArea()
        .accessibilityIdentifier("performance-canvas")
    }
}

private struct MetalRendererContainer: UIViewRepresentable {
    let rendererService: RendererService
    let renderCoordinator: RenderCoordinator
    let surfaceState: RendererSurfaceState
    let isLightAppearance: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rendererService: rendererService,
            renderCoordinator: renderCoordinator,
            surfaceState: surfaceState,
            isLightAppearance: isLightAppearance
        )
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        context.coordinator.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(
            surfaceState: surfaceState,
            isLightAppearance: isLightAppearance,
            view: uiView
        )
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let rendererService: RendererService
        let renderCoordinator: RenderCoordinator
        private let surfaceID = UUID()
        private var surfaceState: RendererSurfaceState
        private var isLightAppearance: Bool

        init(
            rendererService: RendererService,
            renderCoordinator: RenderCoordinator,
            surfaceState: RendererSurfaceState,
            isLightAppearance: Bool
        ) {
            self.rendererService = rendererService
            self.renderCoordinator = renderCoordinator
            self.surfaceState = surfaceState
            self.isLightAppearance = isLightAppearance
        }

        func attach(view: MTKView) {
            renderCoordinator.attachSurface(identifier: surfaceID)
            rendererService.configure(view: view)
            applyCanvasAppearance(to: view)
            rendererService.update(surfaceState: surfaceState)
            view.delegate = self
        }

        func update(surfaceState: RendererSurfaceState, isLightAppearance: Bool, view: MTKView) {
            self.surfaceState = surfaceState
            self.isLightAppearance = isLightAppearance
            applyCanvasAppearance(to: view)
            rendererService.update(surfaceState: surfaceState)
        }

        func detach() {
            renderCoordinator.detachSurface(identifier: surfaceID)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // The MTKView draw callback will render the next frame with the new size.
            // Issuing a second draw here can submit the same drawable twice.
        }

        func draw(in view: MTKView) {
            rendererService.draw(in: view, size: view.drawableSize)
        }

        private func applyCanvasAppearance(to view: MTKView) {
            let base = surfaceState.activeModeID == .custom ? 0.0 : (isLightAppearance ? 1.0 : 0.0)
            view.clearColor = MTLClearColorMake(base, base, base, 1.0)
            let color: UIColor = surfaceState.activeModeID == .custom ? .black : (isLightAppearance ? .white : .black)
            view.backgroundColor = color
            view.layer.backgroundColor = color.cgColor
        }
    }
}
