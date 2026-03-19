//
//  Renderer.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//

import Foundation
import MetalKit
import QuartzCore
import Combine

/// Minimal full-screen pipeline with uniforms (time, exposure, beatPhase, RMS, aspect, strobeGuard).
final class Renderer {
    // MARK: - Types
    struct Uniforms {
        var time: Float
        var exposure: Float
        var beatPhase: Float
        var rms: Float
        var aspect: Float
        var strobeGuard: UInt32
    }

    // MARK: - State
    private(set) var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    var drawableSize: CGSize = .zero

    private let params: RenderParams

    init(params: RenderParams) { self.params = params }

    // MARK: - Setup
    func configure(for device: MTLDevice) {
        self.device = device
        self.queue = device.makeCommandQueue()

        guard let lib = device.makeDefaultLibrary() else { fatalError("Metal default library not found. Ensure Shaders.metal is in the target.") }

        let vfn = lib.makeFunction(name: "vertex_fullscreen")
        let ffn = lib.makeFunction(name: "fragment_main")

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "FullScreenPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do { pipeline = try device.makeRenderPipelineState(descriptor: desc) }
        catch { fatalError("Pipeline error: \(error)") }
    }

    // MARK: - Draw
    func draw(in view: MTKView) {
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer()
        else { return }

        let t = Float(CACurrentMediaTime() - startTime)
        let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1

        var u = Uniforms(
            time: t,
            exposure: params.exposure,
            beatPhase: params.beatPhase,
            rms: params.rms,
            aspect: aspect,
            strobeGuard: params.strobeGuard ? 1 : 0
        )
        let ubuf = device.makeBuffer(bytes: &u, length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)

        if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(pipeline)
            enc.setFragmentBuffer(ubuf, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        cmd.present(drawable)
        cmd.commit()
    }
}

/// Live parameters the renderer reads every frame.
final class RenderParams: ObservableObject {
    // HUD-controlled
    var exposure: Float = 1.0
    var strobeGuard: Bool = true

    // Audio-driven
    var beatPhase: Float = 0          // 0..1
    var rms: Float = 0
}
