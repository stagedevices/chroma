//
//  MetalView.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//

import Foundation
import SwiftUI
import MetalKit


struct MetalView: UIViewRepresentable {
    final class Coordinator: NSObject, MTKViewDelegate {
        var renderer: Renderer
        init(renderer: Renderer) { self.renderer = renderer }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { renderer.drawableSize = size }
        func draw(in view: MTKView) { renderer.draw(in: view) }
    }

    private let renderer: Renderer
    init(params: RenderParams) { self.renderer = Renderer(params: params) }

    func makeCoordinator() -> Coordinator { Coordinator(renderer: renderer) }

    // ⬇️ fix label here
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        guard let device = v.device else { fatalError("Metal unavailable") }
        v.colorPixelFormat = .bgra8Unorm
        v.clearColor = MTLClearColorMake(0, 0, 0, 1)
        v.preferredFramesPerSecond = 60
        v.isPaused = false
        v.enableSetNeedsDisplay = false
        v.framebufferOnly = true
        context.coordinator.renderer.configure(for: device)
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ uiView: MTKView, context: Context) { }
}
