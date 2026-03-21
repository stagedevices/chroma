import Foundation
import Metal
import MetalKit

final class PatchExecutor {
    private let device: MTLDevice
    // Phase 1 pipelines
    private var oscillatorPipeline: MTLComputePipelineState?
    private var blendPipeline: MTLComputePipelineState?
    private var transformPipeline: MTLComputePipelineState?
    private var solidPipeline: MTLComputePipelineState?
    // Phase 3 pipelines
    private var gradientPipeline: MTLComputePipelineState?
    private var oscillator2DPipeline: MTLComputePipelineState?
    private var particlesPipeline: MTLComputePipelineState?
    private var hsvAdjustPipeline: MTLComputePipelineState?
    private var transform2DPipeline: MTLComputePipelineState?
    // Phase 5 pipelines
    private var fractalPipeline: MTLComputePipelineState?
    private var voronoiPipeline: MTLComputePipelineState?
    private var feedbackPipeline: MTLComputePipelineState?
    private var blurPipeline: MTLComputePipelineState?
    private var displacePipeline: MTLComputePipelineState?
    private var mirrorPipeline: MTLComputePipelineState?
    private var tilePipeline: MTLComputePipelineState?

    private var outputRenderPipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?

    private var texturePool: [MTLTexture] = []
    private var signalTable: [Float] = []
    private var currentTextureWidth = 0
    private var currentTextureHeight = 0
    private var startTime: CFTimeInterval
    private var lastFrameTime: CFTimeInterval = 0

    // Per-node persistent state for stateful nodes (envelope, smooth, threshold, S&H, particles)
    private var nodeState: [UUID: [Float]] = [:]
    // Particle buffers per node ID
    private var particleBuffers: [UUID: MTLBuffer] = [:]
    // Double-buffered textures for feedback nodes (previous frame)
    private var feedbackTextures: [UUID: MTLTexture] = [:]
    // External camera texture for CameraIn nodes
    private(set) var cameraTexture: MTLTexture?
    // Per-node profiling (node ID → last measured duration in ms)
    private(set) var nodeTimings: [UUID: Double] = [:]

    struct NodeUniforms {
        var time: Float = 0
        var param0: Float = 0
        var param1: Float = 0
        var param2: Float = 0
        var param3: Float = 0
        var param4: Float = 0
        var param5: Float = 0
        var input0: Float = 0
        var input1: Float = 0
        var input2: Float = 0
        var input3: Float = 0
    }

    private static let maxParticles = 128
    private static let particleStride = MemoryLayout<Float>.stride * 8 // position(2), velocity(2), age, lifetime, size, brightness

    init(device: MTLDevice, library: MTLLibrary, drawablePixelFormat: MTLPixelFormat) {
        self.device = device
        self.startTime = CACurrentMediaTime()

        oscillatorPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_oscillator")
        blendPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_blend")
        transformPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_transform")
        solidPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_solid")
        gradientPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_gradient")
        oscillator2DPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_oscillator2d")
        particlesPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_particles")
        hsvAdjustPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_hsv_adjust")
        transform2DPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_transform2d")
        fractalPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_fractal")
        voronoiPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_voronoi")
        feedbackPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_feedback")
        blurPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_blur")
        displacePipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_displace")
        mirrorPipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_mirror")
        tilePipeline = Self.makeComputePipeline(device: device, library: library, name: "patch_node_tile")

        if let vertexFn = library.makeFunction(name: "renderer_fullscreen_vertex"),
           let fragFn = library.makeFunction(name: "patch_output_fragment") {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertexFn
            desc.fragmentFunction = fragFn
            desc.colorAttachments[0].pixelFormat = drawablePixelFormat
            desc.label = "PatchOutputPipeline"
            outputRenderPipeline = try? device.makeRenderPipelineState(descriptor: desc)
        }

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDesc)

    }

    func updateCameraTexture(_ texture: MTLTexture?) {
        cameraTexture = texture
    }

    func execute(
        program: PatchProgram,
        controls: RendererControlState,
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable
    ) -> Bool {
        let width = drawable.texture.width
        let height = drawable.texture.height
        guard width > 0, height > 0 else { return false }

        ensureResources(program: program, width: width, height: height)

        let now = CACurrentMediaTime()
        let time = Float(now - startTime)
        let dt = lastFrameTime > 0 ? Float(now - lastFrameTime) : Float(1.0 / 60.0)
        lastFrameTime = now

        // Clear signal table
        for i in 0..<signalTable.count { signalTable[i] = 0 }

        // Execute steps in topological order with per-node timing
        for step in program.steps {
            let stepStart = CACurrentMediaTime()
            switch step.kind {
            // Phase 1: core pipeline
            case .audioIn:
                executeAudioIn(step: step, controls: controls)
            case .spectrum:
                executeSpectrum(step: step, controls: controls)
            case .oscillator:
                executeOscillator(step: step, time: time, commandBuffer: commandBuffer)
            case .blend:
                executeBlend(step: step, commandBuffer: commandBuffer)
            case .transform:
                executeTransform(step: step, commandBuffer: commandBuffer)
            case .output:
                break
            // Phase 2: source nodes
            case .pitch:
                executePitch(step: step, controls: controls)
            case .lfo:
                executeLFO(step: step, time: time)
            case .noise:
                executeNoise(step: step, time: time)
            case .constant:
                executeConstant(step: step)
            case .time:
                executeTime(step: step, time: time)
            // Phase 2: processing nodes
            case .math:
                executeMath(step: step)
            case .envelope:
                executeEnvelope(step: step, dt: dt)
            case .smooth:
                executeSmooth(step: step, dt: dt)
            case .threshold:
                executeThreshold(step: step)
            case .sampleAndHold:
                executeSampleAndHold(step: step)
            case .mix:
                executeMix(step: step)
            case .remap:
                executeRemap(step: step)
            // Phase 3: visual generator nodes (GPU)
            case .solid:
                executeSolid(step: step, commandBuffer: commandBuffer)
            case .gradient:
                executeGradient(step: step, commandBuffer: commandBuffer)
            case .oscillator2D:
                executeOscillator2D(step: step, time: time, commandBuffer: commandBuffer)
            case .particles:
                executeParticles(step: step, time: time, dt: dt, commandBuffer: commandBuffer)
            case .hsvAdjust:
                executeHSVAdjust(step: step, commandBuffer: commandBuffer)
            case .transform2D:
                executeTransform2D(step: step, commandBuffer: commandBuffer)
            // Phase 5: advanced visual nodes + feedback (GPU)
            case .fractal:
                executeFractal(step: step, time: time, commandBuffer: commandBuffer)
            case .voronoi:
                executeVoronoi(step: step, time: time, commandBuffer: commandBuffer)
            case .feedback:
                executeFeedback(step: step, commandBuffer: commandBuffer)
            case .blur:
                executeBlur(step: step, commandBuffer: commandBuffer)
            case .displace:
                executeDisplace(step: step, commandBuffer: commandBuffer)
            case .mirror:
                executeMirror(step: step, commandBuffer: commandBuffer)
            case .tile:
                executeTile(step: step, commandBuffer: commandBuffer)
            case .cameraIn:
                executeCameraIn(step: step, commandBuffer: commandBuffer)
            }
            let stepDuration = (CACurrentMediaTime() - stepStart) * 1000.0
            nodeTimings[step.nodeID] = stepDuration
        }

        // Swap feedback textures: copy current output to previous-frame store
        swapFeedbackTextures(program: program, commandBuffer: commandBuffer)

        // Present output texture
        guard let outputPipeline = outputRenderPipeline, let sampler else { return false }
        let outputSlot = program.outputTextureSlot
        guard outputSlot >= 0, outputSlot < texturePool.count else {
            return encodeBlackFrame(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor, drawable: drawable)
        }

        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return false }
        encoder.setRenderPipelineState(outputPipeline)
        encoder.setFragmentTexture(texturePool[outputSlot], index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        return true
    }

    // MARK: - Phase 1 Signal Nodes (CPU)

    private func executeAudioIn(step: PatchStep, controls: RendererControlState) {
        let gain = param(step, "gain", 0.72)
        for output in step.outputs {
            guard output.slot < signalTable.count else { continue }
            switch output.portName {
            case "signal": signalTable[output.slot] = Float(controls.featureAmplitude * Double(gain))
            case "attack": signalTable[output.slot] = controls.isAttack ? Float(controls.attackStrength) : 0
            default: break
            }
        }
    }

    private func executeSpectrum(step: PatchStep, controls: RendererControlState) {
        for output in step.outputs {
            guard output.slot < signalTable.count else { continue }
            switch output.portName {
            case "low": signalTable[output.slot] = Float(controls.lowBandEnergy)
            case "mid": signalTable[output.slot] = Float(controls.midBandEnergy)
            case "high": signalTable[output.slot] = Float(controls.highBandEnergy)
            default: break
            }
        }
    }

    // MARK: - Phase 2 Source Nodes (CPU)

    private func executePitch(step: PatchStep, controls: RendererControlState) {
        for output in step.outputs {
            guard output.slot < signalTable.count else { continue }
            switch output.portName {
            case "confidence": signalTable[output.slot] = Float(controls.pitchConfidence)
            case "pitch": signalTable[output.slot] = Float(controls.stablePitchClass ?? 0) / 12.0
            default: break
            }
        }
    }

    private func executeLFO(step: PatchStep, time: Float) {
        let rate = param(step, "rate", 1.0)
        let waveform = Int(param(step, "waveform", 0).rounded())
        let amplitude = param(step, "amplitude", 1.0)
        let phase = time * rate
        let raw: Float
        switch waveform {
        case 1: // triangle
            raw = 1.0 - abs(fmod(phase, 1.0) * 2.0 - 1.0)
        case 2: // saw
            raw = fmod(phase, 1.0)
        case 3: // square
            raw = fmod(phase, 1.0) < 0.5 ? 1.0 : 0.0
        default: // sine
            raw = sinf(phase * .pi * 2.0) * 0.5 + 0.5
        }
        writeOutput(step, raw * amplitude)
    }

    private func executeNoise(step: PatchStep, time: Float) {
        let rate = param(step, "rate", 1.0)
        let t = time * rate
        let value = (sinf(t * 1.1) * 0.3 + sinf(t * 2.3 + 0.7) * 0.3
            + sinf(t * 4.7 + 1.3) * 0.2 + sinf(t * 8.1 + 2.1) * 0.1
            + sinf(t * 15.3 + 3.7) * 0.1) * 0.5 + 0.5
        writeOutput(step, value)
    }

    private func executeConstant(step: PatchStep) {
        writeOutput(step, param(step, "value", 0.5))
    }

    private func executeTime(step: PatchStep, time: Float) {
        let rate = param(step, "rate", 1.0)
        let mode = Int(param(step, "mode", 0).rounded())
        let phase = time * rate
        let value: Float
        if mode == 1 { // ping-pong
            value = 1.0 - abs(fmod(phase, 2.0) - 1.0)
        } else { // wrap
            value = fmod(phase, 1.0)
        }
        writeOutput(step, value)
    }

    // MARK: - Phase 2 Processing Nodes (CPU)

    private func executeMath(step: PatchStep) {
        let a = readSignal(step.inputs.first(where: { $0.portName == "a" }))
        let b = readSignalOrParam(step, portName: "b", paramName: "operation", fallback: 0)
        let op = Int(param(step, "operation", 0).rounded())
        let result: Float
        switch op {
        case 1: result = a * b          // multiply
        case 2: result = min(a, b)      // min
        case 3: result = max(a, b)      // max
        case 4: result = powf(max(a, 0.0001), b) // pow
        case 5: // smoothstep: smooth 0-1 ramp using a as value, b as edge width
            let t = max(0, min(1, a / max(b, 0.0001)))
            result = t * t * (3 - 2 * t)
        default: result = a + b         // add
        }
        writeOutput(step, result)
    }

    private func executeEnvelope(step: PatchStep, dt: Float) {
        // State: [phase, level, wasTriggerActive]
        // phase: 0=idle, 1=attack, 2=decay, 3=sustain, 4=release
        var state = getNodeState(step.nodeID, count: 3)
        let triggerVal = readSignal(step.inputs.first(where: { $0.portName == "trigger" }))
        let triggerActive = triggerVal > 0.5
        let wasTriggerActive = state[2] > 0.5

        let attackTime = max(param(step, "attack", 0.05), 0.001)
        let decayTime = max(param(step, "decay", 0.2), 0.001)
        let sustainLevel = param(step, "sustain", 0.6)
        let releaseTime = max(param(step, "release", 0.4), 0.001)

        var phase = state[0]
        var level = state[1]

        // Edge detection
        if triggerActive && !wasTriggerActive {
            phase = 1 // start attack
        } else if !triggerActive && wasTriggerActive {
            phase = 4 // start release
        }

        switch Int(phase) {
        case 1: // attack: rise to 1.0
            level += dt / attackTime
            if level >= 1.0 { level = 1.0; phase = 2 }
        case 2: // decay: fall to sustain
            level -= dt / decayTime * (1.0 - sustainLevel)
            if level <= sustainLevel { level = sustainLevel; phase = 3 }
        case 3: // sustain: hold
            level = sustainLevel
        case 4: // release: fall to 0
            level -= dt / releaseTime * level.magnitude
            if level <= 0.001 { level = 0; phase = 0 }
        default: // idle
            level = max(level - dt * 2, 0) // gentle fade if any residual
        }

        level = max(0, min(1, level))
        state[0] = phase
        state[1] = level
        state[2] = triggerActive ? 1 : 0
        setNodeState(step.nodeID, state)
        writeOutput(step, level)
    }

    private func executeSmooth(step: PatchStep, dt: Float) {
        var state = getNodeState(step.nodeID, count: 1)
        let input = readSignal(step.inputs.first(where: { $0.portName == "signal" }))
        let smoothing = param(step, "smoothing", 0.8)
        let coeff = powf(smoothing, dt * 60) // frame-rate independent smoothing
        state[0] = state[0] * coeff + input * (1 - coeff)
        setNodeState(step.nodeID, state)
        writeOutput(step, state[0])
    }

    private func executeThreshold(step: PatchStep) {
        var state = getNodeState(step.nodeID, count: 1)
        let input = readSignal(step.inputs.first(where: { $0.portName == "signal" }))
        let thresh = param(step, "threshold", 0.5)
        let hyst = param(step, "hysteresis", 0.05)
        let wasActive = state[0] > 0.5
        let isActive: Bool
        if wasActive {
            isActive = input >= (thresh - hyst)
        } else {
            isActive = input > (thresh + hyst)
        }
        state[0] = isActive ? 1.0 : 0.0
        setNodeState(step.nodeID, state)
        writeOutput(step, state[0])
    }

    private func executeSampleAndHold(step: PatchStep) {
        // State: [heldValue, wasTriggerActive]
        var state = getNodeState(step.nodeID, count: 2)
        let input = readSignal(step.inputs.first(where: { $0.portName == "signal" }))
        let trigger = readSignal(step.inputs.first(where: { $0.portName == "trigger" }))
        let gain = param(step, "gain", 1.0)
        let triggerActive = trigger > 0.5
        let wasTriggerActive = state[1] > 0.5
        if triggerActive && !wasTriggerActive {
            state[0] = input // latch on rising edge
        }
        state[1] = triggerActive ? 1.0 : 0.0
        setNodeState(step.nodeID, state)
        writeOutput(step, state[0] * gain)
    }

    private func executeMix(step: PatchStep) {
        let a = readSignal(step.inputs.first(where: { $0.portName == "a" }))
        let b = readSignal(step.inputs.first(where: { $0.portName == "b" }))
        let mixBinding = step.inputs.first(where: { $0.portName == "mix" })
        let m: Float
        if let mixBinding, mixBinding.isConnected {
            m = readSignal(mixBinding)
        } else {
            m = param(step, "mix", 0.5)
        }
        writeOutput(step, a * (1 - m) + b * m)
    }

    private func executeRemap(step: PatchStep) {
        let input = readSignal(step.inputs.first(where: { $0.portName == "signal" }))
        let inMin = param(step, "inputMin", 0)
        let inMax = param(step, "inputMax", 1)
        let outMin = param(step, "outputMin", 0)
        let outMax = param(step, "outputMax", 1)
        let curve = Int(param(step, "curve", 0).rounded())

        let inRange = max(inMax - inMin, 0.0001)
        var t = (input - inMin) / inRange
        t = max(0, min(1, t))

        switch curve {
        case 1: t = t * t                           // ease-in
        case 2: t = 1 - (1 - t) * (1 - t)          // ease-out
        case 3: t = t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t) // ease-in-out
        default: break                               // linear
        }

        writeOutput(step, outMin + t * (outMax - outMin))
    }

    // MARK: - Phase 1 Field Nodes (GPU)

    private func executeOscillator(step: PatchStep, time: Float, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = oscillatorPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let drive = readSignal(step.inputs.first(where: { $0.portName == "drive" }))
        let rate = param(step, "rate", 0.56)
        let phase = param(step, "phase", 0)

        var uniforms = NodeUniforms(time: time, param0: rate, param1: phase, input0: drive)

        let tex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tex, index: 0)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: tex.width, height: tex.height)
        encoder.endEncoding()
    }

    private func executeBlend(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = blendPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let texA = readTexture(step.inputs.first(where: { $0.portName == "a" }))
        let texB = readTexture(step.inputs.first(where: { $0.portName == "b" }))
        let mixBinding = step.inputs.first(where: { $0.portName == "mix" })
        let effectiveMix: Float
        if let mixBinding, mixBinding.isConnected {
            effectiveMix = readSignal(mixBinding)
        } else {
            effectiveMix = param(step, "mix", 0.5)
        }

        var uniforms = NodeUniforms(input2: effectiveMix)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texA, index: 0)
        encoder.setTexture(texB, index: 1)
        encoder.setTexture(outputTex, index: 2)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    private func executeTransform(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = transformPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let inputTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
        let amount = readSignal(step.inputs.first(where: { $0.portName == "amount" }))

        var uniforms = NodeUniforms(input1: amount)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTex, index: 0)
        encoder.setTexture(outputTex, index: 1)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    // MARK: - Phase 3 Visual Generator Nodes (GPU)

    private func executeSolid(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = solidPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let r = readSignalOrParam(step, portName: "r", paramName: "r", fallback: 0.5)
        let g = readSignalOrParam(step, portName: "g", paramName: "g", fallback: 0.5)
        let b = readSignalOrParam(step, portName: "b", paramName: "b", fallback: 0.5)

        var uniforms = NodeUniforms(input0: r, input1: g, input2: b)

        let tex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tex, index: 0)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: tex.width, height: tex.height)
        encoder.endEncoding()
    }

    private func executeGradient(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = gradientPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let mode = param(step, "mode", 0)
        let hueA = param(step, "hueA", 0.55)
        let hueB = param(step, "hueB", 0.85)
        let position = readSignalOrParam(step, portName: "position", paramName: "mode", fallback: 0)
        let spread = readSignalOrParam(step, portName: "spread", paramName: "hueA", fallback: 0.5)

        var uniforms = NodeUniforms(param0: mode, param1: hueA, param2: hueB, input0: position, input1: max(spread, 0.01))

        let tex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tex, index: 0)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: tex.width, height: tex.height)
        encoder.endEncoding()
    }

    private func executeOscillator2D(step: PatchStep, time: Float, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = oscillator2DPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let scaleX = param(step, "scaleX", 6)
        let scaleY = param(step, "scaleY", 4)
        let hue = param(step, "hue", 0.6)
        let drive = readSignal(step.inputs.first(where: { $0.portName == "drive" }))
        let speed = readSignal(step.inputs.first(where: { $0.portName == "speed" }))

        var uniforms = NodeUniforms(time: time, param0: scaleX, param1: scaleY, param2: hue, input0: drive, input1: speed)

        let tex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tex, index: 0)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: tex.width, height: tex.height)
        encoder.endEncoding()
    }

    private func executeParticles(step: PatchStep, time: Float, dt: Float, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = particlesPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let lifetime = param(step, "lifetime", 1.2)
        let size = param(step, "size", 0.04)
        let count = Int(param(step, "count", 32).rounded())
        let maxCount = min(count, Self.maxParticles)
        let trigger = readSignal(step.inputs.first(where: { $0.portName == "trigger" }))
        let intensity = readSignalOrParam(step, portName: "intensity", paramName: "size", fallback: 0.8)

        // Get or create particle buffer
        let bufferSize = Self.maxParticles * Self.particleStride
        if particleBuffers[step.nodeID] == nil {
            particleBuffers[step.nodeID] = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        }
        guard let particleBuffer = particleBuffers[step.nodeID] else { return }

        // Update particles on CPU
        let ptr = particleBuffer.contents().bindMemory(to: Float.self, capacity: Self.maxParticles * 8)
        var state = getNodeState(step.nodeID, count: 2) // [wasTrigger, spawnIndex]
        let wasTrigger = state[0] > 0.5
        let triggerActive = trigger > 0.5
        var spawnIndex = Int(state[1])

        // Age existing particles
        for i in 0..<maxCount {
            let base = i * 8
            ptr[base + 4] += dt // age
            ptr[base + 0] += ptr[base + 2] * dt // position += velocity * dt
            ptr[base + 1] += ptr[base + 3] * dt
        }

        // Spawn on trigger rising edge
        if triggerActive && !wasTrigger {
            let spawnCount = max(1, Int(intensity * 8))
            for _ in 0..<spawnCount {
                let i = spawnIndex % maxCount
                let base = i * 8
                let angle = Float.random(in: 0 ..< Float.pi * 2)
                let speed = Float.random(in: 0.05 ... 0.3) * intensity
                ptr[base + 0] = 0.5 + Float.random(in: -0.1 ... 0.1) // x
                ptr[base + 1] = 0.5 + Float.random(in: -0.1 ... 0.1) // y
                ptr[base + 2] = cosf(angle) * speed // vx
                ptr[base + 3] = sinf(angle) * speed // vy
                ptr[base + 4] = 0 // age
                ptr[base + 5] = lifetime // lifetime
                ptr[base + 6] = size // size
                ptr[base + 7] = intensity // brightness
                spawnIndex += 1
            }
        }

        state[0] = triggerActive ? 1 : 0
        state[1] = Float(spawnIndex)
        setNodeState(step.nodeID, state)

        var uniforms = NodeUniforms(time: time, param1: size, param2: Float(maxCount))

        let tex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tex, index: 0)
        setUniforms(&uniforms, on: encoder)
        encoder.setBuffer(particleBuffer, offset: 0, index: 1)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: tex.width, height: tex.height)
        encoder.endEncoding()
    }

    private func executeHSVAdjust(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = hsvAdjustPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let inputTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
        let hue = readSignal(step.inputs.first(where: { $0.portName == "hue" }))
        let sat = readSignal(step.inputs.first(where: { $0.portName == "saturation" }))
        let bri = readSignal(step.inputs.first(where: { $0.portName == "brightness" }))
        let hueShift = param(step, "hueShift", 0)
        let satMul = param(step, "satMul", 1)
        let valMul = param(step, "valMul", 1)

        var uniforms = NodeUniforms(param0: hueShift, param1: satMul, param2: valMul, input0: hue, input1: sat, input2: bri)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTex, index: 0)
        encoder.setTexture(outputTex, index: 1)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    private func executeTransform2D(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = transform2DPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let inputTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
        let rotateIn = readSignal(step.inputs.first(where: { $0.portName == "rotate" }))
        let scaleIn = readSignal(step.inputs.first(where: { $0.portName == "scale" }))
        let tx = param(step, "translateX", 0)
        let ty = param(step, "translateY", 0)
        let rotation = param(step, "rotation", 0)
        let scale = param(step, "scale", 1)

        var uniforms = NodeUniforms(param0: tx, param1: ty, param2: rotation, param3: scale, input0: rotateIn, input1: scaleIn)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTex, index: 0)
        encoder.setTexture(outputTex, index: 1)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    // MARK: - Phase 5 Advanced Visual Nodes (GPU)

    private func executeFractal(step: PatchStep, time: Float, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = fractalPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let realSeed = readSignal(step.inputs.first(where: { $0.portName == "real" }))
        let imagSeed = readSignal(step.inputs.first(where: { $0.portName == "imag" }))
        let iterations = param(step, "iterations", 24)
        let zoom = param(step, "zoom", 1.5)
        let colorCycles = param(step, "colorCycles", 3)

        var uniforms = NodeUniforms(time: time, param0: iterations, param1: zoom, param2: colorCycles, input0: realSeed, input1: imagSeed)

        let tex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tex, index: 0)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: tex.width, height: tex.height)
        encoder.endEncoding()
    }

    private func executeVoronoi(step: PatchStep, time: Float, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = voronoiPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let drive = readSignal(step.inputs.first(where: { $0.portName == "drive" }))
        let cellCount = param(step, "cellCount", 8)
        let jitter = param(step, "jitter", 0.8)

        var uniforms = NodeUniforms(time: time, param0: cellCount, param1: jitter, input0: drive)

        let tex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(tex, index: 0)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: tex.width, height: tex.height)
        encoder.endEncoding()
    }

    private func executeFeedback(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        // Phase 1: output the previous frame texture so downstream nodes can consume it.
        // The actual blend (current input + prev) happens in swapFeedbackTextures after
        // all nodes have executed, which allows feedback to participate in graph cycles.
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        guard let prevTex = ensureFeedbackTexture(nodeID: step.nodeID) else { return }
        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        let copyW = min(prevTex.width, outputTex.width)
        let copyH = min(prevTex.height, outputTex.height)
        encoder.copy(
            from: prevTex, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: copyW, height: copyH, depth: 1),
            to: outputTex, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
    }

    private func executeBlur(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = blurPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let inputTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
        let radiusInput = readSignal(step.inputs.first(where: { $0.portName == "radius" }))
        let radius = param(step, "radius", 4)

        var uniforms = NodeUniforms(param0: radius, input0: radiusInput)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTex, index: 0)
        encoder.setTexture(outputTex, index: 1)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    private func executeDisplace(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = displacePipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let sourceTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
        let dispMapTex = readTexture(step.inputs.first(where: { $0.portName == "map" }))
        let amountInput = readSignal(step.inputs.first(where: { $0.portName == "amount" }))
        let amount = param(step, "amount", 0.1)

        var uniforms = NodeUniforms(param0: amount, input0: amountInput)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sourceTex, index: 0)
        encoder.setTexture(dispMapTex, index: 1)
        encoder.setTexture(outputTex, index: 2)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    private func executeMirror(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = mirrorPipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let inputTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
        let foldCount = param(step, "foldCount", 4)
        let angle = param(step, "angle", 0)

        var uniforms = NodeUniforms(param0: foldCount, param1: angle)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTex, index: 0)
        encoder.setTexture(outputTex, index: 1)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    private func executeTile(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = tilePipeline else { return }
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let inputTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
        let scaleInput = readSignal(step.inputs.first(where: { $0.portName == "scale" }))
        let repeatX = param(step, "repeatX", 2)
        let repeatY = param(step, "repeatY", 2)

        var uniforms = NodeUniforms(param0: repeatX, param1: repeatY, input0: scaleInput)

        let outputTex = texturePool[outputSlot]
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTex, index: 0)
        encoder.setTexture(outputTex, index: 1)
        setUniforms(&uniforms, on: encoder)
        dispatchThreads(encoder: encoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
        encoder.endEncoding()
    }

    private func executeCameraIn(step: PatchStep, commandBuffer: MTLCommandBuffer) {
        guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
              outputSlot < texturePool.count else { return }

        let mirrorParam = param(step, "mirror", 1)
        let shouldMirror = mirrorParam > 0.5
        let outputTex = texturePool[outputSlot]

        guard let camTex = cameraTexture else {
            // No camera available: output black
            return
        }

        // Blit camera texture to output slot (with optional horizontal mirror)
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        let srcW = min(camTex.width, outputTex.width)
        let srcH = min(camTex.height, outputTex.height)
        if shouldMirror {
            // Mirror by reversing source X range
            encoder.copy(
                from: camTex, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: srcW, height: srcH, depth: 1),
                to: outputTex, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        } else {
            encoder.copy(
                from: camTex, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: srcW, height: srcH, depth: 1),
                to: outputTex, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }
        encoder.endEncoding()
    }

    // MARK: - Feedback Texture Management

    private func ensureFeedbackTexture(nodeID: UUID) -> MTLTexture? {
        if let existing = feedbackTextures[nodeID],
           existing.width == currentTextureWidth,
           existing.height == currentTextureHeight {
            return existing
        }
        guard currentTextureWidth > 0, currentTextureHeight > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: currentTextureWidth,
            height: currentTextureHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        feedbackTextures[nodeID] = tex
        return tex
    }

    private func swapFeedbackTextures(program: PatchProgram, commandBuffer: MTLCommandBuffer) {
        // Phase 2 of feedback: all nodes have executed, so the feedback node's input
        // is now available. Blend the current input with the previous frame and store
        // the result in the feedback texture for next frame's output.
        guard let pipeline = feedbackPipeline else { return }
        for step in program.steps where step.kind == .feedback {
            guard let outputSlot = step.outputs.first(where: { $0.portType == .field })?.slot,
                  outputSlot < texturePool.count,
                  let fbTex = feedbackTextures[step.nodeID] else { continue }

            let inputTex = readTexture(step.inputs.first(where: { $0.portName == "field" }))
            let decay = param(step, "decay", 0.92)
            let blurAmt = param(step, "blur", 0.3)

            var uniforms = NodeUniforms(param0: decay, param1: blurAmt)

            // Blend input + previous frame → output slot (as temp)
            let outputTex = texturePool[outputSlot]
            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { continue }
            computeEncoder.setComputePipelineState(pipeline)
            computeEncoder.setTexture(inputTex, index: 0)
            computeEncoder.setTexture(fbTex, index: 1)
            computeEncoder.setTexture(outputTex, index: 2)
            setUniforms(&uniforms, on: computeEncoder)
            dispatchThreads(encoder: computeEncoder, pipeline: pipeline, width: outputTex.width, height: outputTex.height)
            computeEncoder.endEncoding()

            // Copy blended result → feedback texture for next frame
            guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { continue }
            let copyW = min(outputTex.width, fbTex.width)
            let copyH = min(outputTex.height, fbTex.height)
            blitEncoder.copy(
                from: outputTex, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: copyW, height: copyH, depth: 1),
                to: fbTex, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }
    }

    // MARK: - Helpers

    private func param(_ step: PatchStep, _ name: String, _ fallback: Float) -> Float {
        Float(step.parameters.first(where: { $0.name == name })?.value ?? Double(fallback))
    }

    private func readSignal(_ binding: PatchInputBinding?) -> Float {
        guard let binding, binding.isConnected, binding.sourceSlot < signalTable.count else { return 0 }
        return signalTable[binding.sourceSlot]
    }

    private func readSignalOrParam(_ step: PatchStep, portName: String, paramName: String, fallback: Float) -> Float {
        if let binding = step.inputs.first(where: { $0.portName == portName }), binding.isConnected, binding.sourceSlot < signalTable.count {
            return signalTable[binding.sourceSlot]
        }
        return param(step, paramName, fallback)
    }

    private func writeOutput(_ step: PatchStep, _ value: Float) {
        for output in step.outputs where output.portType == .signal || output.portType == .trigger {
            guard output.slot < signalTable.count else { continue }
            signalTable[output.slot] = value
        }
    }

    private func readTexture(_ binding: PatchInputBinding?) -> MTLTexture? {
        guard let binding, binding.isConnected, binding.sourceSlot < texturePool.count else { return blackTexture }
        return texturePool[binding.sourceSlot]
    }

    private var _blackTexture: MTLTexture?
    private var blackTexture: MTLTexture? {
        if let tex = _blackTexture, tex.width == currentTextureWidth, tex.height == currentTextureHeight {
            return tex
        }
        guard currentTextureWidth > 0, currentTextureHeight > 0 else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: currentTextureWidth,
            height: currentTextureHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        let tex = device.makeTexture(descriptor: desc)
        _blackTexture = tex
        return tex
    }

    private func getNodeState(_ nodeID: UUID, count: Int) -> [Float] {
        if let existing = nodeState[nodeID], existing.count == count { return existing }
        let state = [Float](repeating: 0, count: count)
        nodeState[nodeID] = state
        return state
    }

    private func setNodeState(_ nodeID: UUID, _ state: [Float]) {
        nodeState[nodeID] = state
    }

    private func setUniforms(_ uniforms: inout NodeUniforms, on encoder: MTLComputeCommandEncoder) {
        encoder.setBytes(&uniforms, length: MemoryLayout<NodeUniforms>.stride, index: 0)
    }

    private func dispatchThreads(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let threadgroupSize = MTLSize(width: min(16, pipeline.maxTotalThreadsPerThreadgroup), height: 16, depth: 1)
        let gridSize = MTLSize(width: width, height: height, depth: 1)
        if device.supportsFamily(.apple4) {
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        } else {
            let groupsW = (width + threadgroupSize.width - 1) / threadgroupSize.width
            let groupsH = (height + threadgroupSize.height - 1) / threadgroupSize.height
            encoder.dispatchThreadgroups(MTLSize(width: groupsW, height: groupsH, depth: 1), threadsPerThreadgroup: threadgroupSize)
        }
    }

    private func ensureResources(program: PatchProgram, width: Int, height: Int) {
        if signalTable.count != program.signalSlotCount {
            signalTable = [Float](repeating: 0, count: program.signalSlotCount)
        }
        if texturePool.count != program.textureSlotCount || currentTextureWidth != width || currentTextureHeight != height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            texturePool = (0..<program.textureSlotCount).compactMap { _ in device.makeTexture(descriptor: desc) }
            currentTextureWidth = width
            currentTextureHeight = height
        }
    }

    private func encodeBlackFrame(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor, drawable: CAMetalDrawable) -> Bool {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return false }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        return true
    }

    private static func makeComputePipeline(device: MTLDevice, library: MTLLibrary, name: String) -> MTLComputePipelineState? {
        guard let function = library.makeFunction(name: name) else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }
}
