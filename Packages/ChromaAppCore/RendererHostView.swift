import SwiftUI
import MetalKit
import UIKit

public struct RendererHostView: View {
    public let rendererService: RendererService
    public let renderCoordinator: RenderCoordinator
    public let surfaceState: RendererSurfaceState

    public init(rendererService: RendererService, renderCoordinator: RenderCoordinator, surfaceState: RendererSurfaceState) {
        self.rendererService = rendererService
        self.renderCoordinator = renderCoordinator
        self.surfaceState = surfaceState
    }

    public var body: some View {
        MetalRendererContainer(
            rendererService: rendererService,
            renderCoordinator: renderCoordinator,
            surfaceState: surfaceState
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .accessibilityIdentifier("performance-canvas")
    }
}

private struct MetalRendererContainer: UIViewRepresentable {
    let rendererService: RendererService
    let renderCoordinator: RenderCoordinator
    let surfaceState: RendererSurfaceState

    func makeCoordinator() -> Coordinator {
        Coordinator(rendererService: rendererService, renderCoordinator: renderCoordinator, surfaceState: surfaceState)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.backgroundColor = .black
        view.layer.backgroundColor = UIColor.black.cgColor
        context.coordinator.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.backgroundColor = .black
        uiView.layer.backgroundColor = UIColor.black.cgColor
        context.coordinator.update(surfaceState: surfaceState)
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let rendererService: RendererService
        let renderCoordinator: RenderCoordinator
        private let surfaceID = UUID()
        private var surfaceState: RendererSurfaceState

        init(rendererService: RendererService, renderCoordinator: RenderCoordinator, surfaceState: RendererSurfaceState) {
            self.rendererService = rendererService
            self.renderCoordinator = renderCoordinator
            self.surfaceState = surfaceState
        }

        func attach(view: MTKView) {
            renderCoordinator.attachSurface(identifier: surfaceID)
            rendererService.configure(view: view)
            rendererService.update(surfaceState: surfaceState)
            view.delegate = self
        }

        func update(surfaceState: RendererSurfaceState) {
            self.surfaceState = surfaceState
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
    }
}
