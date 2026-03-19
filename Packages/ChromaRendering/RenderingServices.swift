import Foundation
import Metal
import MetalKit
import QuartzCore
import CoreVideo
import simd

public protocol RendererService: AnyObject {
    var diagnosticsSummary: RendererDiagnosticsSummary { get }
    var currentSurfaceState: RendererSurfaceState { get }

    func configure(view: MTKView)
    func update(activeModeID: VisualModeID)
    func update(surfaceState: RendererSurfaceState)
    func updateCameraFeedbackFrame(_ frame: CameraFeedbackFrame?)
    func draw(in view: MTKView, size: CGSize)
}

public protocol RenderCoordinator: AnyObject {
    func attachSurface(identifier: UUID)
    func detachSurface(identifier: UUID)
}

public final class DefaultRenderCoordinator: RenderCoordinator {
    public private(set) var attachedSurfaceIDs: Set<UUID> = []

    public init() {
    }

    public func attachSurface(identifier: UUID) {
        attachedSurfaceIDs.insert(identifier)
    }

    public func detachSurface(identifier: UUID) {
        attachedSurfaceIDs.remove(identifier)
    }
}

public final class HeadlessRendererService: RendererService {
    public private(set) var currentSurfaceState: RendererSurfaceState
    public private(set) var diagnosticsSummary: RendererDiagnosticsSummary

    public init(activeModeID: VisualModeID = .colorShift) {
        let state = RendererSurfaceState(activeModeID: activeModeID)
        currentSurfaceState = state
        diagnosticsSummary = RendererDiagnosticsSummary.placeholder(modeID: activeModeID)
    }

    public func configure(view: MTKView) {
        diagnosticsSummary.readinessStatus = .idle
        diagnosticsSummary.statusMessage = "Headless renderer configured"
        diagnosticsSummary.resolutionLabel = resolutionLabel(for: view.drawableSize)
    }

    public func update(activeModeID: VisualModeID) {
        currentSurfaceState.activeModeID = activeModeID
        diagnosticsSummary.activeModeSummary = activeModeID.displayName
    }

    public func update(surfaceState: RendererSurfaceState) {
        currentSurfaceState = surfaceState
        diagnosticsSummary.activeModeSummary = surfaceState.activeModeID.displayName
    }

    public func updateCameraFeedbackFrame(_ frame: CameraFeedbackFrame?) {
        _ = frame
    }

    public func draw(in view: MTKView, size: CGSize) {
        diagnosticsSummary.resolutionLabel = resolutionLabel(for: size)
    }
}

public final class MetalRendererService: RendererService {
    public private(set) var currentSurfaceState: RendererSurfaceState
    public private(set) var diagnosticsSummary: RendererDiagnosticsSummary

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var pipelineStates: RendererPipelineStates?
    private var spectralTargets: SpectralRenderTargets?
    private var attackParticleTargets: AttackParticleRenderTargets?
    private var colorFeedbackTargets: ColorFeedbackRenderTargets?
    private var prismTargets: PrismRenderTargets?
    private var tunnelTargets: TunnelRenderTargets?
    private var fractalTargets: FractalRenderTargets?
    private var riemannTargets: RiemannRenderTargets?
    private var linearSampler: MTLSamplerState?

    private var startTime: CFTimeInterval
    private var lastFrameTimestamp: CFTimeInterval?
    private var smoothedFrameTimeMS: Double = 0
    private var droppedFrameCount = 0
    private var slowFrameStreak = 0

    private var lastPipelineRetryTime: CFTimeInterval?
    private var inFlightDrawableID: ObjectIdentifier?
    private var consecutiveCommandBufferErrors = 0

    private var ringPool = SpectralRingPool(capacity: kMaxSpectralRings)
    private var ringGPUData = [SpectralRingGPUData](repeating: .zero, count: kMaxSpectralRings)
    private var attackParticlePool = AttackParticlePool(capacity: kMaxAttackParticles)
    private var attackParticleGPUData = [AttackParticleGPUData](repeating: .zero, count: kMaxAttackParticles)
    private var attackParticleGPUBuffer: MTLBuffer?
    private var spectralQuality = SpectralQualityProfile.cinematicHeavy
    private var attackParticleQuality = AttackParticleQualityProfile.cinematicHeavy
    private var prismQuality = PrismQualityProfile.cinematicHeavy
    private var tunnelQuality = TunnelQualityProfile.cinematicHeavy
    private var fractalQuality = FractalQualityProfile.cinematicHeavy
    private var riemannQuality = RiemannQualityProfile.cinematicHeavy
    private var forceRadialFallbackUntil: CFTimeInterval?
    private var colorShiftHuePhase: Float = 0
    private var colorShiftSaturation: Float = 0.84
    private var lastColorShiftHueUpdateTime: CFTimeInterval?
    private var latestCameraFeedbackFrame: CameraFeedbackFrame?
    private var cameraTextureCache: CVMetalTextureCache?
    private var inFlightCameraTextureRef: CVMetalTexture?
    private var prismImpulsePool = PrismImpulsePool(capacity: kMaxPrismImpulses)
    private var prismImpulseGPUData = [PrismImpulseGPUData](repeating: .zero, count: kMaxPrismImpulses)
    private var tunnelShapePool = TunnelShapePool(capacity: kMaxTunnelShapes)
    private var tunnelShapeGPUData = [TunnelShapeGPUData](repeating: .zero, count: kMaxTunnelShapes)
    private var fractalPulsePool = FractalPulsePool(capacity: kMaxFractalPulses)
    private var fractalPulseGPUData = [FractalPulseGPUData](repeating: .zero, count: kMaxFractalPulses)
    private var fractalFlowPhase: Float = 0
    private var lastFractalFlowUpdateTime: CFTimeInterval?
    private var riemannAccentPool = RiemannAccentPool(capacity: kMaxRiemannAccents)
    private var riemannAccentGPUData = [RiemannAccentGPUData](repeating: .zero, count: kMaxRiemannAccents)
    private var riemannFlowPhase: Float = 0
    private var riemannCameraCenter = SIMD2<Float>(-0.8, 0.0)
    private var riemannCameraZoom: Float = 1.0
    private var riemannCameraHeading: Float = 0
    private var riemannRouteTargetCenter = SIMD2<Float>(-0.8, 0.0)
    private var riemannRouteTargetZoom: Float = 1.0
    private var riemannLastRouteAttackID: UInt64 = 0
    private var riemannLastRouteUpdateTime: CFTimeInterval = 0
    private var lastRiemannFlowUpdateTime: CFTimeInterval?
    private var riemannSmoothedSteering = SIMD2<Float>(0, 0)
    private var riemannSmoothedIntensity: Float = 0

    public init(activeModeID: VisualModeID = .colorShift) {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        if let device {
            var createdCache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &createdCache)
            cameraTextureCache = createdCache
        } else {
            cameraTextureCache = nil
        }
        currentSurfaceState = RendererSurfaceState(activeModeID: activeModeID)
        diagnosticsSummary = RendererDiagnosticsSummary.placeholder(modeID: activeModeID)
        startTime = CACurrentMediaTime()

        if device == nil {
            diagnosticsSummary.readinessStatus = .unavailable
            diagnosticsSummary.statusMessage = "Metal device unavailable"
        } else if commandQueue == nil {
            diagnosticsSummary.readinessStatus = .failed
            diagnosticsSummary.statusMessage = "Unable to create command queue"
        } else {
            diagnosticsSummary.statusMessage = "Metal service initialized"
        }
    }

    public func configure(view: MTKView) {
        guard let device else {
            view.device = nil
            view.clearColor = MTLClearColorMake(0, 0, 0, 1)
            view.isPaused = true
            diagnosticsSummary.readinessStatus = .unavailable
            diagnosticsSummary.statusMessage = "Metal device unavailable"
            return
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = false
        view.autoResizeDrawable = true
        view.isOpaque = true
        view.drawableSize = view.bounds.size

        do {
            pipelineStates = try pipelineStateBundle(for: device, drawablePixelFormat: view.colorPixelFormat)
            linearSampler = makeLinearSampler(device: device)
            diagnosticsSummary.readinessStatus = .ready
            diagnosticsSummary.statusMessage = hasAnyMultiPassPipeline
                ? "Metal surface ready"
                : "Metal surface ready (radial fallback)"
        } catch {
            pipelineStates = nil
            diagnosticsSummary.readinessStatus = .failed
            diagnosticsSummary.statusMessage = "Pipeline error: \(error.localizedDescription)"
        }

        diagnosticsSummary.resolutionLabel = resolutionLabel(for: view.drawableSize)
        diagnosticsSummary.activeModeSummary = currentSurfaceState.activeModeID.displayName
    }

    public func update(activeModeID: VisualModeID) {
        let previousMode = currentSurfaceState.activeModeID
        currentSurfaceState.activeModeID = activeModeID
        diagnosticsSummary.activeModeSummary = activeModeID.displayName
        if previousMode != activeModeID {
            handleModeTransition(from: previousMode, to: activeModeID)
        }
    }

    public func update(surfaceState: RendererSurfaceState) {
        let previousMode = currentSurfaceState.activeModeID
        currentSurfaceState = RendererSurfaceState(activeModeID: surfaceState.activeModeID, controls: surfaceState.controls.clamped())
        diagnosticsSummary.activeModeSummary = currentSurfaceState.activeModeID.displayName
        if previousMode != currentSurfaceState.activeModeID {
            handleModeTransition(from: previousMode, to: currentSurfaceState.activeModeID)
        }
    }

    public func updateCameraFeedbackFrame(_ frame: CameraFeedbackFrame?) {
        latestCameraFeedbackFrame = frame
    }

    public func draw(in view: MTKView, size: CGSize) {
        diagnosticsSummary.resolutionLabel = resolutionLabel(for: size)

        guard let commandQueue else {
            droppedFrameCount += 1
            diagnosticsSummary.droppedFrameCount = droppedFrameCount
            return
        }

        let now = CACurrentMediaTime()
        ensurePipelineStateIfNeeded(device: view.device, pixelFormat: view.colorPixelFormat, now: now)
        updateFrameTiming(now: now)

        guard
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            droppedFrameCount += 1
            diagnosticsSummary.droppedFrameCount = droppedFrameCount
            return
        }

        let drawableID = ObjectIdentifier(drawable as AnyObject)
        if inFlightDrawableID == drawableID {
            droppedFrameCount += 1
            diagnosticsSummary.droppedFrameCount = droppedFrameCount
            diagnosticsSummary.statusMessage = "Skipping duplicate drawable submission"
            return
        }

        guard let pipelineStates else {
            presentFallbackFrame(
                commandQueue: commandQueue,
                renderPassDescriptor: renderPassDescriptor,
                drawable: drawable,
                drawableID: drawableID,
                time: now
            )
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            droppedFrameCount += 1
            diagnosticsSummary.droppedFrameCount = droppedFrameCount
            return
        }

        let elapsed = Float(now - startTime)
        updateColorShiftHuePhase(now: now, state: currentSurfaceState)
        updateFractalFlowPhase(now: now, state: currentSurfaceState)
        updateRiemannFlowPhase(now: now, state: currentSurfaceState)
        tuneQualityForDrawableSize(size, modeID: currentSurfaceState.activeModeID)
        var uniforms = makeUniforms(
            time: elapsed,
            drawableSize: size,
            state: currentSurfaceState,
            ringCount: 0,
            shimmerSampleCount: spectralQuality.shimmerSampleCount,
            particleCount: 0,
            attackTrailSampleCount: attackParticleQuality.trailSampleCount,
            prismFacetSampleCount: prismQuality.facetSampleCount,
            prismDispersionSampleCount: prismQuality.dispersionSampleCount,
            prismImpulseCount: 0,
            tunnelShapeCount: 0,
            tunnelTrailSampleCount: tunnelQuality.trailSampleCount,
            tunnelDispersionSampleCount: tunnelQuality.dispersionSampleCount,
            fractalOrbitSampleCount: fractalQuality.orbitSampleCount,
            fractalTrapSampleCount: fractalQuality.trapSampleCount,
            fractalPulseCount: 0,
            fractalFlowPhase: fractalFlowPhase,
            riemannTermCount: riemannQuality.termCount,
            riemannTrapSampleCount: riemannQuality.trapSampleCount,
            riemannAccentCount: 0,
            riemannFlowPhase: riemannFlowPhase,
            riemannCameraCenter: riemannCameraCenter,
            riemannCameraZoom: riemannCameraZoom,
            riemannCameraHeading: riemannCameraHeading
        )

        let radialFallbackActive = forceRadialFallbackUntil.map { now < $0 } ?? false
        let selectedPath = rendererPassSelection(
            modeID: currentSurfaceState.activeModeID,
            colorFeedbackEnabled: currentSurfaceState.controls.colorFeedbackEnabled,
            hasColorFeedbackPipeline: pipelineStates.colorFeedback != nil,
            hasPrismPipeline: pipelineStates.prism != nil,
            hasTunnelPipeline: pipelineStates.tunnel != nil,
            hasFractalPipeline: pipelineStates.fractal != nil,
            hasRiemannPipeline: pipelineStates.riemann != nil,
            hasCameraFeedbackFrame: latestCameraFeedbackFrame != nil,
            radialFallbackActive: radialFallbackActive
        )

        if selectedPath == .colorFeedback,
           let feedbackPipelines = pipelineStates.colorFeedback,
           let sampler = linearSampler,
           let device,
           let frame = latestCameraFeedbackFrame,
           let cameraTextureBundle = makeCameraTexture(from: frame),
           var feedbackTargets = ensureColorFeedbackTargets(for: size, device: device),
           encodeColorFeedbackPasses(
               commandBuffer: commandBuffer,
               drawableRenderPassDescriptor: renderPassDescriptor,
               drawable: drawable,
               sampler: sampler,
               pipelines: feedbackPipelines,
               targets: &feedbackTargets,
               uniforms: &uniforms,
               cameraTexture: cameraTextureBundle.texture
           ) {
            colorFeedbackTargets = feedbackTargets
            prepareCommandBufferForCommit(commandBuffer, drawableID: drawableID, retainedCameraTexture: cameraTextureBundle.backing)
            commandBuffer.commit()
            return
        }

        if selectedPath == .prism,
           let prismPipelines = pipelineStates.prism,
           let sampler = linearSampler,
           let device,
           let targets = ensurePrismTargets(for: size, device: device) {
            spawnPrismImpulseIfNeeded(controls: currentSurfaceState.controls, elapsedTime: elapsed)
            let impulseCount = updatePrismImpulseGPUData(
                elapsedTime: elapsed,
                impulseLimit: prismQuality.activeImpulseLimit
            )
            uniforms.prismImpulseCount = impulseCount
            uniforms.prismFacetSampleCount = prismQuality.facetSampleCount
            uniforms.prismDispersionSampleCount = prismQuality.dispersionSampleCount

            if encodePrismPasses(
                commandBuffer: commandBuffer,
                drawableRenderPassDescriptor: renderPassDescriptor,
                drawable: drawable,
                sampler: sampler,
                pipelines: prismPipelines,
                targets: targets,
                uniforms: &uniforms
            ) {
                prismTargets = targets
                prepareCommandBufferForCommit(commandBuffer, drawableID: drawableID)
                commandBuffer.commit()
                return
            }

            _ = degradePrismQuality(reason: "prism encode failure")
        }

        if selectedPath == .tunnel,
           let tunnelPipelines = pipelineStates.tunnel,
           let sampler = linearSampler,
           let device,
           let targets = ensureTunnelTargets(for: size, device: device) {
            spawnTunnelShapeIfNeeded(controls: currentSurfaceState.controls, elapsedTime: elapsed)
            let shapeCount = updateTunnelShapeGPUData(
                controls: currentSurfaceState.controls,
                elapsedTime: elapsed,
                shapeLimit: tunnelQuality.activeShapeLimit
            )
            uniforms.tunnelShapeCount = shapeCount
            uniforms.tunnelTrailSampleCount = tunnelQuality.trailSampleCount
            uniforms.tunnelDispersionSampleCount = tunnelQuality.dispersionSampleCount

            if encodeTunnelPasses(
                commandBuffer: commandBuffer,
                drawableRenderPassDescriptor: renderPassDescriptor,
                drawable: drawable,
                sampler: sampler,
                pipelines: tunnelPipelines,
                targets: targets,
                uniforms: &uniforms
            ) {
                tunnelTargets = targets
                prepareCommandBufferForCommit(commandBuffer, drawableID: drawableID)
                commandBuffer.commit()
                return
            }

            _ = degradeTunnelQuality(reason: "tunnel encode failure")
        }

        if selectedPath == .fractal,
           let fractalPipelines = pipelineStates.fractal,
           let sampler = linearSampler,
           let device,
           let targets = ensureFractalTargets(for: size, device: device) {
            spawnFractalPulseIfNeeded(controls: currentSurfaceState.controls, elapsedTime: elapsed)
            let pulseCount = updateFractalPulseGPUData(
                elapsedTime: elapsed,
                pulseLimit: fractalQuality.activePulseLimit
            )
            uniforms.fractalPulseCount = pulseCount
            uniforms.fractalOrbitSampleCount = fractalQuality.orbitSampleCount
            uniforms.fractalTrapSampleCount = fractalQuality.trapSampleCount

            if encodeFractalPasses(
                commandBuffer: commandBuffer,
                drawableRenderPassDescriptor: renderPassDescriptor,
                drawable: drawable,
                sampler: sampler,
                pipelines: fractalPipelines,
                targets: targets,
                uniforms: &uniforms
            ) {
                fractalTargets = targets
                prepareCommandBufferForCommit(commandBuffer, drawableID: drawableID)
                commandBuffer.commit()
                return
            }

            _ = degradeFractalQuality(reason: "fractal encode failure")
        }

        if selectedPath == .riemann,
           let riemannPipelines = pipelineStates.riemann,
           let sampler = linearSampler,
           let device,
           let targets = ensureRiemannTargets(for: size, device: device) {
            spawnRiemannAccentIfNeeded(controls: currentSurfaceState.controls, elapsedTime: elapsed)
            let accentCount = updateRiemannAccentGPUData(
                elapsedTime: elapsed,
                accentLimit: riemannQuality.activeAccentLimit
            )
            uniforms.riemannAccentCount = accentCount
            uniforms.riemannTermCount = riemannQuality.termCount
            uniforms.riemannTrapSampleCount = riemannQuality.trapSampleCount

            if encodeRiemannPasses(
                commandBuffer: commandBuffer,
                drawableRenderPassDescriptor: renderPassDescriptor,
                drawable: drawable,
                sampler: sampler,
                pipelines: riemannPipelines,
                targets: targets,
                uniforms: &uniforms
            ) {
                riemannTargets = targets
                prepareCommandBufferForCommit(commandBuffer, drawableID: drawableID)
                commandBuffer.commit()
                return
            }

            _ = degradeRiemannQuality(reason: "riemann encode failure")
        }

        guard encodeRadialPass(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            pipelineState: pipelineStates.radial,
            uniforms: &uniforms
        ) else {
            droppedFrameCount += 1
            diagnosticsSummary.droppedFrameCount = droppedFrameCount
            diagnosticsSummary.statusMessage = "Radial pass encode failed"
            return
        }

        commandBuffer.present(drawable)

        prepareCommandBufferForCommit(commandBuffer, drawableID: drawableID)
        commandBuffer.commit()
    }

    private func pipelineStateBundle(for device: MTLDevice, drawablePixelFormat: MTLPixelFormat) throws -> RendererPipelineStates {
        let library = try makeShaderLibrary(device: device)
        let radial = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_radial_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaRadialPipeline"
        )

        let spectral = try? makeSpectralPipelineStates(
            device: device,
            library: library,
            drawablePixelFormat: drawablePixelFormat
        )
        let attackParticle = try? makeAttackParticlePipelineStates(
            device: device,
            library: library,
            drawablePixelFormat: drawablePixelFormat
        )
        let colorFeedback = try? makeColorFeedbackPipelineStates(
            device: device,
            library: library,
            drawablePixelFormat: drawablePixelFormat
        )
        let prism = try? makePrismPipelineStates(
            device: device,
            library: library,
            drawablePixelFormat: drawablePixelFormat
        )
        let tunnel = try? makeTunnelPipelineStates(
            device: device,
            library: library,
            drawablePixelFormat: drawablePixelFormat
        )
        let fractal = try? makeFractalPipelineStates(
            device: device,
            library: library,
            drawablePixelFormat: drawablePixelFormat
        )
        let riemann = try? makeRiemannPipelineStates(
            device: device,
            library: library,
            drawablePixelFormat: drawablePixelFormat
        )
        return RendererPipelineStates(
            radial: radial,
            spectral: spectral,
            attackParticle: attackParticle,
            colorFeedback: colorFeedback,
            prism: prism,
            tunnel: tunnel,
            fractal: fractal,
            riemann: riemann
        )
    }

    private func makeSpectralPipelineStates(
        device: MTLDevice,
        library: MTLLibrary,
        drawablePixelFormat: MTLPixelFormat
    ) throws -> SpectralPipelineStates {
        let ringField = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_spectral_ring_field_fragment",
            colorPixelFormat: kSpectralIntermediatePixelFormat,
            label: "ChromaSpectralRingFieldPipeline"
        )
        let lens = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_spectral_lens_fragment",
            colorPixelFormat: kSpectralIntermediatePixelFormat,
            label: "ChromaSpectralLensPipeline"
        )
        let shimmer = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_spectral_shimmer_fragment",
            colorPixelFormat: kSpectralIntermediatePixelFormat,
            label: "ChromaSpectralShimmerPipeline"
        )
        let composite = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_spectral_composite_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaSpectralCompositePipeline"
        )

        return SpectralPipelineStates(ringField: ringField, lens: lens, shimmer: shimmer, composite: composite)
    }

    private func makeAttackParticlePipelineStates(
        device: MTLDevice,
        library: MTLLibrary,
        drawablePixelFormat: MTLPixelFormat
    ) throws -> AttackParticlePipelineStates {
        let particleField = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_attack_particle_field_fragment",
            colorPixelFormat: kAttackIntermediatePixelFormat,
            label: "ChromaAttackParticleFieldPipeline"
        )
        let trail = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_attack_trail_fragment",
            colorPixelFormat: kAttackIntermediatePixelFormat,
            label: "ChromaAttackTrailPipeline"
        )
        let composite = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_attack_composite_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaAttackCompositePipeline"
        )

        return AttackParticlePipelineStates(particleField: particleField, trail: trail, composite: composite)
    }

    private func makeColorFeedbackPipelineStates(
        device: MTLDevice,
        library: MTLLibrary,
        drawablePixelFormat: MTLPixelFormat
    ) throws -> ColorFeedbackPipelineStates {
        let contour = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_feedback_contour_fragment",
            colorPixelFormat: kColorFeedbackIntermediatePixelFormat,
            label: "ChromaColorFeedbackContourPipeline"
        )
        let evolve = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_feedback_evolve_fragment",
            colorPixelFormat: kColorFeedbackIntermediatePixelFormat,
            label: "ChromaColorFeedbackEvolvePipeline"
        )
        let present = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_feedback_present_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaColorFeedbackPresentPipeline"
        )

        return ColorFeedbackPipelineStates(contour: contour, evolve: evolve, present: present)
    }

    private func makePrismPipelineStates(
        device: MTLDevice,
        library: MTLLibrary,
        drawablePixelFormat: MTLPixelFormat
    ) throws -> PrismPipelineStates {
        let facetField = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_prism_facet_field_fragment",
            colorPixelFormat: kPrismIntermediatePixelFormat,
            label: "ChromaPrismFacetFieldPipeline"
        )
        let dispersion = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_prism_dispersion_fragment",
            colorPixelFormat: kPrismIntermediatePixelFormat,
            label: "ChromaPrismDispersionPipeline"
        )
        let accents = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_prism_attack_accents_fragment",
            colorPixelFormat: kPrismIntermediatePixelFormat,
            label: "ChromaPrismAccentsPipeline"
        )
        let composite = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_prism_composite_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaPrismCompositePipeline"
        )

        return PrismPipelineStates(
            facetField: facetField,
            dispersion: dispersion,
            accents: accents,
            composite: composite
        )
    }

    private func makeTunnelPipelineStates(
        device: MTLDevice,
        library: MTLLibrary,
        drawablePixelFormat: MTLPixelFormat
    ) throws -> TunnelPipelineStates {
        let field = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_tunnel_field_fragment",
            colorPixelFormat: kTunnelIntermediatePixelFormat,
            label: "ChromaTunnelFieldPipeline"
        )
        let shapes = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_tunnel_shapes_fragment",
            colorPixelFormat: kTunnelIntermediatePixelFormat,
            label: "ChromaTunnelShapesPipeline"
        )
        let composite = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_tunnel_composite_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaTunnelCompositePipeline"
        )

        return TunnelPipelineStates(
            field: field,
            shapes: shapes,
            composite: composite
        )
    }

    private func makeFractalPipelineStates(
        device: MTLDevice,
        library: MTLLibrary,
        drawablePixelFormat: MTLPixelFormat
    ) throws -> FractalPipelineStates {
        let field = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_fractal_field_fragment",
            colorPixelFormat: kFractalIntermediatePixelFormat,
            label: "ChromaFractalFieldPipeline"
        )
        let accents = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_fractal_accents_fragment",
            colorPixelFormat: kFractalIntermediatePixelFormat,
            label: "ChromaFractalAccentsPipeline"
        )
        let composite = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_fractal_composite_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaFractalCompositePipeline"
        )

        return FractalPipelineStates(
            field: field,
            accents: accents,
            composite: composite
        )
    }

    private func makeRiemannPipelineStates(
        device: MTLDevice,
        library: MTLLibrary,
        drawablePixelFormat: MTLPixelFormat
    ) throws -> RiemannPipelineStates {
        let field = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_riemann_field_fragment",
            colorPixelFormat: kRiemannIntermediatePixelFormat,
            label: "ChromaRiemannFieldPipeline"
        )
        let accents = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_riemann_accents_fragment",
            colorPixelFormat: kRiemannIntermediatePixelFormat,
            label: "ChromaRiemannAccentsPipeline"
        )
        let composite = try makePipelineState(
            device: device,
            library: library,
            vertexFunctionName: "renderer_fullscreen_vertex",
            fragmentFunctionName: "renderer_riemann_composite_fragment",
            colorPixelFormat: drawablePixelFormat,
            label: "ChromaRiemannCompositePipeline"
        )

        return RiemannPipelineStates(
            field: field,
            accents: accents,
            composite: composite
        )
    }

    private func makePipelineState(
        device: MTLDevice,
        library: MTLLibrary,
        vertexFunctionName: String,
        fragmentFunctionName: String,
        colorPixelFormat: MTLPixelFormat,
        label: String
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            throw RendererBuildError.missingVertexFunction
        }
        guard let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            throw RendererBuildError.missingFragmentFunction(fragmentFunctionName)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.label = label
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let bundledLibrary = try? device.makeDefaultLibrary(bundle: .main) {
            return bundledLibrary
        }
        if let bundledURL = Bundle.main.url(forResource: "default", withExtension: "metallib"),
           let bundledFileLibrary = try? device.makeLibrary(URL: bundledURL) {
            return bundledFileLibrary
        }
        if let defaultLibrary = device.makeDefaultLibrary() {
            return defaultLibrary
        }
        for bundle in Bundle.allBundles where bundle != .main {
            guard let candidateURL = bundle.url(forResource: "default", withExtension: "metallib") else {
                continue
            }
            if let bundleLibrary = try? device.makeLibrary(URL: candidateURL) {
                return bundleLibrary
            }
        }
        return try device.makeLibrary(source: fallbackShaderSource, options: nil)
    }

    private func makeLinearSampler(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.label = "ChromaLinearSampler"
        return device.makeSamplerState(descriptor: descriptor)
    }

    private var hasAnyMultiPassPipeline: Bool {
        guard let pipelineStates else { return false }
        return pipelineStates.spectral != nil ||
            pipelineStates.attackParticle != nil ||
            pipelineStates.colorFeedback != nil ||
            pipelineStates.prism != nil ||
            pipelineStates.tunnel != nil ||
            pipelineStates.fractal != nil ||
            pipelineStates.riemann != nil
    }

    private func ensurePipelineStateIfNeeded(device: MTLDevice?, pixelFormat: MTLPixelFormat, now: CFTimeInterval) {
        guard pipelineStates == nil, let device else { return }

        if let lastPipelineRetryTime, (now - lastPipelineRetryTime) < 0.5 {
            return
        }
        lastPipelineRetryTime = now

        do {
            pipelineStates = try pipelineStateBundle(for: device, drawablePixelFormat: pixelFormat)
            diagnosticsSummary.readinessStatus = .ready
            diagnosticsSummary.statusMessage = hasAnyMultiPassPipeline
                ? "Metal surface ready"
                : "Metal surface ready (radial fallback)"
        } catch {
            diagnosticsSummary.readinessStatus = .failed
            diagnosticsSummary.statusMessage = "Pipeline retry failed: \(error.localizedDescription)"
        }
    }

    private func ensureSpectralTargets(for size: CGSize, device: MTLDevice) -> SpectralRenderTargets? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)

        if let existing = spectralTargets, existing.width == width, existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: kSpectralIntermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard
            let ringField = device.makeTexture(descriptor: descriptor),
            let lensField = device.makeTexture(descriptor: descriptor),
            let shimmerField = device.makeTexture(descriptor: descriptor)
        else {
            spectralTargets = nil
            return nil
        }

        ringField.label = "ChromaSpectralRingField"
        lensField.label = "ChromaSpectralLensField"
        shimmerField.label = "ChromaSpectralShimmerField"

        let created = SpectralRenderTargets(
            width: width,
            height: height,
            ringField: ringField,
            lensField: lensField,
            shimmerField: shimmerField
        )
        spectralTargets = created
        return created
    }

    private func ensureAttackParticleTargets(for size: CGSize, device: MTLDevice) -> AttackParticleRenderTargets? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)

        if let existing = attackParticleTargets, existing.width == width, existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: kAttackIntermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard
            let particleField = device.makeTexture(descriptor: descriptor),
            let trailField = device.makeTexture(descriptor: descriptor)
        else {
            attackParticleTargets = nil
            return nil
        }

        particleField.label = "ChromaAttackParticleField"
        trailField.label = "ChromaAttackTrailField"

        let created = AttackParticleRenderTargets(
            width: width,
            height: height,
            particleField: particleField,
            trailField: trailField
        )
        attackParticleTargets = created
        return created
    }

    private func ensureColorFeedbackTargets(for size: CGSize, device: MTLDevice) -> ColorFeedbackRenderTargets? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)

        if let existing = colorFeedbackTargets, existing.width == width, existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: kColorFeedbackIntermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard
            let contourField = device.makeTexture(descriptor: descriptor),
            let feedbackA = device.makeTexture(descriptor: descriptor),
            let feedbackB = device.makeTexture(descriptor: descriptor)
        else {
            colorFeedbackTargets = nil
            return nil
        }

        contourField.label = "ChromaColorFeedbackContourField"
        feedbackA.label = "ChromaColorFeedbackA"
        feedbackB.label = "ChromaColorFeedbackB"

        let created = ColorFeedbackRenderTargets(
            width: width,
            height: height,
            contourField: contourField,
            feedbackA: feedbackA,
            feedbackB: feedbackB,
            useAAsHistory: true
        )
        colorFeedbackTargets = created
        return created
    }

    private func ensurePrismTargets(for size: CGSize, device: MTLDevice) -> PrismRenderTargets? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)

        if let existing = prismTargets, existing.width == width, existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: kPrismIntermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard
            let facetField = device.makeTexture(descriptor: descriptor),
            let dispersionField = device.makeTexture(descriptor: descriptor),
            let accentField = device.makeTexture(descriptor: descriptor)
        else {
            prismTargets = nil
            return nil
        }

        facetField.label = "ChromaPrismFacetField"
        dispersionField.label = "ChromaPrismDispersionField"
        accentField.label = "ChromaPrismAccentField"

        let created = PrismRenderTargets(
            width: width,
            height: height,
            facetField: facetField,
            dispersionField: dispersionField,
            accentField: accentField
        )
        prismTargets = created
        return created
    }

    private func ensureTunnelTargets(for size: CGSize, device: MTLDevice) -> TunnelRenderTargets? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)

        if let existing = tunnelTargets, existing.width == width, existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: kTunnelIntermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard
            let field = device.makeTexture(descriptor: descriptor),
            let shapes = device.makeTexture(descriptor: descriptor)
        else {
            tunnelTargets = nil
            return nil
        }

        field.label = "ChromaTunnelField"
        shapes.label = "ChromaTunnelShapes"

        let created = TunnelRenderTargets(
            width: width,
            height: height,
            field: field,
            shapes: shapes
        )
        tunnelTargets = created
        return created
    }

    private func ensureFractalTargets(for size: CGSize, device: MTLDevice) -> FractalRenderTargets? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)

        if let existing = fractalTargets, existing.width == width, existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: kFractalIntermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard
            let field = device.makeTexture(descriptor: descriptor),
            let accents = device.makeTexture(descriptor: descriptor)
        else {
            fractalTargets = nil
            return nil
        }

        field.label = "ChromaFractalField"
        accents.label = "ChromaFractalAccents"

        let created = FractalRenderTargets(
            width: width,
            height: height,
            field: field,
            accents: accents
        )
        fractalTargets = created
        return created
    }

    private func ensureRiemannTargets(for size: CGSize, device: MTLDevice) -> RiemannRenderTargets? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)

        if let existing = riemannTargets, existing.width == width, existing.height == height {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: kRiemannIntermediatePixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]

        guard
            let field = device.makeTexture(descriptor: descriptor),
            let accents = device.makeTexture(descriptor: descriptor)
        else {
            riemannTargets = nil
            return nil
        }

        field.label = "ChromaRiemannField"
        accents.label = "ChromaRiemannAccents"

        let created = RiemannRenderTargets(
            width: width,
            height: height,
            field: field,
            accents: accents
        )
        riemannTargets = created
        return created
    }

    private func makeOffscreenPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        return descriptor
    }

    private func encodeSpectralPasses(
        commandBuffer: MTLCommandBuffer,
        drawableRenderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        sampler: MTLSamplerState,
        pipelines: SpectralPipelineStates,
        targets: SpectralRenderTargets,
        uniforms: inout RendererFrameUniforms
    ) -> Bool {
        guard
            let ringEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: makeOffscreenPassDescriptor(texture: targets.ringField))
        else {
            return false
        }
        ringEncoder.setRenderPipelineState(pipelines.ringField)
        ringEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        ringEncoder.setFragmentBytes(ringGPUData, length: MemoryLayout<SpectralRingGPUData>.stride * kMaxSpectralRings, index: 1)
        ringEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        ringEncoder.endEncoding()

        guard
            let lensEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: makeOffscreenPassDescriptor(texture: targets.lensField))
        else {
            return false
        }
        lensEncoder.setRenderPipelineState(pipelines.lens)
        lensEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        lensEncoder.setFragmentTexture(targets.ringField, index: 0)
        lensEncoder.setFragmentSamplerState(sampler, index: 0)
        lensEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        lensEncoder.endEncoding()

        guard
            let shimmerEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: makeOffscreenPassDescriptor(texture: targets.shimmerField))
        else {
            return false
        }
        shimmerEncoder.setRenderPipelineState(pipelines.shimmer)
        shimmerEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        shimmerEncoder.setFragmentTexture(targets.lensField, index: 0)
        shimmerEncoder.setFragmentTexture(targets.ringField, index: 1)
        shimmerEncoder.setFragmentSamplerState(sampler, index: 0)
        shimmerEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        shimmerEncoder.endEncoding()

        drawableRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        drawableRenderPassDescriptor.colorAttachments[0].storeAction = .store
        drawableRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard
            let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableRenderPassDescriptor)
        else {
            return false
        }
        compositeEncoder.setRenderPipelineState(pipelines.composite)
        compositeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        compositeEncoder.setFragmentTexture(targets.ringField, index: 0)
        compositeEncoder.setFragmentTexture(targets.lensField, index: 1)
        compositeEncoder.setFragmentTexture(targets.shimmerField, index: 2)
        compositeEncoder.setFragmentSamplerState(sampler, index: 0)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()

        commandBuffer.present(drawable)
        return true
    }

    private func encodeAttackParticlePasses(
        commandBuffer: MTLCommandBuffer,
        drawableRenderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        sampler: MTLSamplerState,
        pipelines: AttackParticlePipelineStates,
        targets: AttackParticleRenderTargets,
        particleBuffer: MTLBuffer,
        uniforms: inout RendererFrameUniforms
    ) -> Bool {
        guard
            let particleEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: makeOffscreenPassDescriptor(texture: targets.particleField))
        else {
            return false
        }
        particleEncoder.setRenderPipelineState(pipelines.particleField)
        particleEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        particleEncoder.setFragmentBuffer(particleBuffer, offset: 0, index: 1)
        particleEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        particleEncoder.endEncoding()

        guard
            let trailEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: makeOffscreenPassDescriptor(texture: targets.trailField))
        else {
            return false
        }
        trailEncoder.setRenderPipelineState(pipelines.trail)
        trailEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        trailEncoder.setFragmentTexture(targets.particleField, index: 0)
        trailEncoder.setFragmentSamplerState(sampler, index: 0)
        trailEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        trailEncoder.endEncoding()

        drawableRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        drawableRenderPassDescriptor.colorAttachments[0].storeAction = .store
        drawableRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard
            let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableRenderPassDescriptor)
        else {
            return false
        }
        compositeEncoder.setRenderPipelineState(pipelines.composite)
        compositeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        compositeEncoder.setFragmentTexture(targets.particleField, index: 0)
        compositeEncoder.setFragmentTexture(targets.trailField, index: 1)
        compositeEncoder.setFragmentSamplerState(sampler, index: 0)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()

        commandBuffer.present(drawable)
        return true
    }

    private func encodeColorFeedbackPasses(
        commandBuffer: MTLCommandBuffer,
        drawableRenderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        sampler: MTLSamplerState,
        pipelines: ColorFeedbackPipelineStates,
        targets: inout ColorFeedbackRenderTargets,
        uniforms: inout RendererFrameUniforms,
        cameraTexture: MTLTexture
    ) -> Bool {
        guard
            let contourEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.contourField)
            )
        else {
            return false
        }
        contourEncoder.setRenderPipelineState(pipelines.contour)
        contourEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        contourEncoder.setFragmentTexture(cameraTexture, index: 0)
        contourEncoder.setFragmentSamplerState(sampler, index: 0)
        contourEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        contourEncoder.endEncoding()

        let historyTexture = targets.useAAsHistory ? targets.feedbackA : targets.feedbackB
        let currentTexture = targets.useAAsHistory ? targets.feedbackB : targets.feedbackA

        guard
            let evolveEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: currentTexture)
            )
        else {
            return false
        }
        evolveEncoder.setRenderPipelineState(pipelines.evolve)
        evolveEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        evolveEncoder.setFragmentTexture(historyTexture, index: 0)
        evolveEncoder.setFragmentTexture(targets.contourField, index: 1)
        evolveEncoder.setFragmentSamplerState(sampler, index: 0)
        evolveEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        evolveEncoder.endEncoding()

        drawableRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        drawableRenderPassDescriptor.colorAttachments[0].storeAction = .store
        drawableRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard
            let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableRenderPassDescriptor)
        else {
            return false
        }
        presentEncoder.setRenderPipelineState(pipelines.present)
        presentEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        presentEncoder.setFragmentTexture(currentTexture, index: 0)
        presentEncoder.setFragmentSamplerState(sampler, index: 0)
        presentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        presentEncoder.endEncoding()

        targets.useAAsHistory.toggle()
        commandBuffer.present(drawable)
        return true
    }

    private func encodePrismPasses(
        commandBuffer: MTLCommandBuffer,
        drawableRenderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        sampler: MTLSamplerState,
        pipelines: PrismPipelineStates,
        targets: PrismRenderTargets,
        uniforms: inout RendererFrameUniforms
    ) -> Bool {
        guard
            let facetEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.facetField)
            )
        else {
            return false
        }
        facetEncoder.setRenderPipelineState(pipelines.facetField)
        facetEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        facetEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        facetEncoder.endEncoding()

        guard
            let dispersionEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.dispersionField)
            )
        else {
            return false
        }
        dispersionEncoder.setRenderPipelineState(pipelines.dispersion)
        dispersionEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        dispersionEncoder.setFragmentTexture(targets.facetField, index: 0)
        dispersionEncoder.setFragmentSamplerState(sampler, index: 0)
        dispersionEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        dispersionEncoder.endEncoding()

        guard
            let accentsEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.accentField)
            )
        else {
            return false
        }
        accentsEncoder.setRenderPipelineState(pipelines.accents)
        accentsEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        accentsEncoder.setFragmentBytes(
            prismImpulseGPUData,
            length: MemoryLayout<PrismImpulseGPUData>.stride * kMaxPrismImpulses,
            index: 1
        )
        accentsEncoder.setFragmentTexture(targets.facetField, index: 0)
        accentsEncoder.setFragmentTexture(targets.dispersionField, index: 1)
        accentsEncoder.setFragmentSamplerState(sampler, index: 0)
        accentsEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        accentsEncoder.endEncoding()

        drawableRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        drawableRenderPassDescriptor.colorAttachments[0].storeAction = .store
        drawableRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard
            let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableRenderPassDescriptor)
        else {
            return false
        }
        compositeEncoder.setRenderPipelineState(pipelines.composite)
        compositeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        compositeEncoder.setFragmentTexture(targets.facetField, index: 0)
        compositeEncoder.setFragmentTexture(targets.dispersionField, index: 1)
        compositeEncoder.setFragmentTexture(targets.accentField, index: 2)
        compositeEncoder.setFragmentSamplerState(sampler, index: 0)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()

        commandBuffer.present(drawable)
        return true
    }

    private func encodeTunnelPasses(
        commandBuffer: MTLCommandBuffer,
        drawableRenderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        sampler: MTLSamplerState,
        pipelines: TunnelPipelineStates,
        targets: TunnelRenderTargets,
        uniforms: inout RendererFrameUniforms
    ) -> Bool {
        guard
            let fieldEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.field)
            )
        else {
            return false
        }
        fieldEncoder.setRenderPipelineState(pipelines.field)
        fieldEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        fieldEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        fieldEncoder.endEncoding()

        guard
            let shapeEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.shapes)
            )
        else {
            return false
        }
        shapeEncoder.setRenderPipelineState(pipelines.shapes)
        shapeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        shapeEncoder.setFragmentBytes(
            tunnelShapeGPUData,
            length: MemoryLayout<TunnelShapeGPUData>.stride * kMaxTunnelShapes,
            index: 1
        )
        shapeEncoder.setFragmentTexture(targets.field, index: 0)
        shapeEncoder.setFragmentSamplerState(sampler, index: 0)
        shapeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        shapeEncoder.endEncoding()

        drawableRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        drawableRenderPassDescriptor.colorAttachments[0].storeAction = .store
        drawableRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard
            let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableRenderPassDescriptor)
        else {
            return false
        }
        compositeEncoder.setRenderPipelineState(pipelines.composite)
        compositeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        compositeEncoder.setFragmentTexture(targets.field, index: 0)
        compositeEncoder.setFragmentTexture(targets.shapes, index: 1)
        compositeEncoder.setFragmentSamplerState(sampler, index: 0)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()

        commandBuffer.present(drawable)
        return true
    }

    private func encodeFractalPasses(
        commandBuffer: MTLCommandBuffer,
        drawableRenderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        sampler: MTLSamplerState,
        pipelines: FractalPipelineStates,
        targets: FractalRenderTargets,
        uniforms: inout RendererFrameUniforms
    ) -> Bool {
        guard
            let fieldEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.field)
            )
        else {
            return false
        }
        fieldEncoder.setRenderPipelineState(pipelines.field)
        fieldEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        fieldEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        fieldEncoder.endEncoding()

        guard
            let accentEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.accents)
            )
        else {
            return false
        }
        accentEncoder.setRenderPipelineState(pipelines.accents)
        accentEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        accentEncoder.setFragmentBytes(
            fractalPulseGPUData,
            length: MemoryLayout<FractalPulseGPUData>.stride * kMaxFractalPulses,
            index: 1
        )
        accentEncoder.setFragmentTexture(targets.field, index: 0)
        accentEncoder.setFragmentSamplerState(sampler, index: 0)
        accentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        accentEncoder.endEncoding()

        drawableRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        drawableRenderPassDescriptor.colorAttachments[0].storeAction = .store
        drawableRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard
            let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableRenderPassDescriptor)
        else {
            return false
        }
        compositeEncoder.setRenderPipelineState(pipelines.composite)
        compositeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        compositeEncoder.setFragmentTexture(targets.field, index: 0)
        compositeEncoder.setFragmentTexture(targets.accents, index: 1)
        compositeEncoder.setFragmentSamplerState(sampler, index: 0)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()

        commandBuffer.present(drawable)
        return true
    }

    private func encodeRiemannPasses(
        commandBuffer: MTLCommandBuffer,
        drawableRenderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        sampler: MTLSamplerState,
        pipelines: RiemannPipelineStates,
        targets: RiemannRenderTargets,
        uniforms: inout RendererFrameUniforms
    ) -> Bool {
        guard
            let fieldEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.field)
            )
        else {
            return false
        }
        fieldEncoder.setRenderPipelineState(pipelines.field)
        fieldEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        fieldEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        fieldEncoder.endEncoding()

        guard
            let accentEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: makeOffscreenPassDescriptor(texture: targets.accents)
            )
        else {
            return false
        }
        accentEncoder.setRenderPipelineState(pipelines.accents)
        accentEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        accentEncoder.setFragmentBytes(
            riemannAccentGPUData,
            length: MemoryLayout<RiemannAccentGPUData>.stride * kMaxRiemannAccents,
            index: 1
        )
        accentEncoder.setFragmentTexture(targets.field, index: 0)
        accentEncoder.setFragmentSamplerState(sampler, index: 0)
        accentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        accentEncoder.endEncoding()

        drawableRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        drawableRenderPassDescriptor.colorAttachments[0].storeAction = .store
        drawableRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard
            let compositeEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawableRenderPassDescriptor)
        else {
            return false
        }
        compositeEncoder.setRenderPipelineState(pipelines.composite)
        compositeEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        compositeEncoder.setFragmentTexture(targets.field, index: 0)
        compositeEncoder.setFragmentTexture(targets.accents, index: 1)
        compositeEncoder.setFragmentSamplerState(sampler, index: 0)
        compositeEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        compositeEncoder.endEncoding()

        commandBuffer.present(drawable)
        return true
    }

    private func makeCameraTexture(from frame: CameraFeedbackFrame) -> (texture: MTLTexture, backing: CVMetalTexture)? {
        guard
            let cameraTextureCache,
            frame.width > 0,
            frame.height > 0
        else {
            return nil
        }

        var cvTexture: CVMetalTexture?
        let createStatus = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cameraTextureCache,
            frame.pixelBuffer,
            nil,
            .bgra8Unorm,
            frame.width,
            frame.height,
            0,
            &cvTexture
        )
        guard
            createStatus == kCVReturnSuccess,
            let cvTexture,
            let texture = CVMetalTextureGetTexture(cvTexture)
        else {
            return nil
        }

        return (texture: texture, backing: cvTexture)
    }

    private func ensureAttackParticleBuffer(device: MTLDevice) -> MTLBuffer? {
        let requiredLength = MemoryLayout<AttackParticleGPUData>.stride * kMaxAttackParticles
        if let attackParticleGPUBuffer, attackParticleGPUBuffer.length >= requiredLength {
            return attackParticleGPUBuffer
        }

        let buffer = device.makeBuffer(length: requiredLength, options: .storageModeShared)
        buffer?.label = "Chroma.AttackParticleGPUBuffer"
        attackParticleGPUBuffer = buffer
        return buffer
    }

    private func uploadAttackParticleGPUData(to buffer: MTLBuffer) {
        attackParticleGPUData.withUnsafeBytes { rawBytes in
            guard let sourceAddress = rawBytes.baseAddress else { return }
            let byteCount = min(rawBytes.count, buffer.length)
            buffer.contents().copyMemory(from: sourceAddress, byteCount: byteCount)
        }
    }

    private func encodeRadialPass(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        pipelineState: MTLRenderPipelineState,
        uniforms: inout RendererFrameUniforms
    ) -> Bool {
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return false
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RendererFrameUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func spawnRingIfNeeded(controls: RendererControlState, elapsedTime: Float) {
        guard controls.isAttack else { return }

        _ = ringPool.insertIfNewAttack(attackID: controls.attackID) {
            let sector = spectralBloomSectorIndex(
                attackID: controls.attackID,
                lowBandEnergy: controls.lowBandEnergy,
                midBandEnergy: controls.midBandEnergy,
                highBandEnergy: controls.highBandEnergy,
                sectorCount: 12
            )

            let jitterA = spectralHash01(controls.attackID ^ 0x9E37_79B9_7F4A_7C15)
            let jitterB = spectralHash01(controls.attackID ^ 0xD1B5_4A32_D192_ED03)
            let jitterC = spectralHash01(controls.attackID ^ 0x94D0_49BB_1331_11EB)

            let sectorAngle = (Float(sector) + ((jitterA * 0.64) - 0.32)) * ((2 * .pi) / 12)
            let spawnRadius = 0.03 + (jitterB * 0.08)
            let baseCenter = SIMD2<Float>(Float(controls.centerOffset.x), Float(controls.centerOffset.y))
            let centerOffset = SIMD2<Float>(cos(sectorAngle), sin(sectorAngle)) * spawnRadius

            let dominantEnergy = Float(max(controls.lowBandEnergy, max(controls.midBandEnergy, controls.highBandEnergy)))
            let attackStrength = Float(controls.attackStrength)
            let intensity = 0.40 + (attackStrength * 0.90) + (dominantEnergy * 0.35)
            let baseRadius = 0.012 + (jitterC * 0.020)
            let width = max(0.010, 0.030 - (attackStrength * 0.010))
            let decay = Float(controls.ringDecay)
            let lifetime = mix(0.55, 2.4, decay)
            let sectorWeight = min(max(0.25 + (dominantEnergy * 0.75), 0), 1)
            let hueShift = (Float(sector) / 12.0) + ((jitterA - 0.5) * 0.18)

            return SpectralRingEvent(
                attackID: controls.attackID,
                birthTime: elapsedTime,
                center: baseCenter + centerOffset,
                baseRadius: baseRadius,
                width: width,
                intensity: intensity,
                hueShift: hueShift,
                decay: decay,
                lifetime: lifetime,
                sector: UInt32(sector),
                sectorWeight: sectorWeight,
                isActive: true
            )
        }
    }

    private func updateRingGPUData(elapsedTime: Float, ringLimit: Int) -> UInt32 {
        let activeLimit = max(1, min(ringLimit, kMaxSpectralRings))
        var activeCount = 0

        for index in ringPool.events.indices {
            let event = ringPool.events[index]
            guard event.isActive else { continue }

            let age = elapsedTime - event.birthTime
            if age < 0 || age >= event.lifetime {
                ringPool.events[index].isActive = false
                continue
            }

            let lifeProgress = age / max(event.lifetime, 0.0001)
            let decayCurve = pow(max(1 - lifeProgress, 0), max(0.25, event.decay * 1.35))
            let intensity = event.intensity * decayCurve
            if intensity <= 0.0015 {
                ringPool.events[index].isActive = false
                continue
            }

            if activeCount < activeLimit {
                let radius = event.baseRadius + (lifeProgress * (0.20 + (event.intensity * 0.28)))
                let width = max(event.width * (1 + (lifeProgress * 0.75)), 0.004)
                ringGPUData[activeCount] = SpectralRingGPUData(
                    positionRadiusWidthIntensity: SIMD4<Float>(event.center.x, event.center.y, radius, width),
                    hueDecaySectorActive: SIMD4<Float>(event.hueShift, event.decay, Float(event.sector), intensity * event.sectorWeight)
                )
                activeCount += 1
            }
        }

        if activeCount < ringGPUData.count {
            for index in activeCount ..< ringGPUData.count {
                ringGPUData[index] = .zero
            }
        }

        return UInt32(activeCount)
    }

    private func spawnAttackParticleBurstIfNeeded(controls: RendererControlState, elapsedTime: Float) {
        guard controls.isAttack else { return }

        let burstDensity = Float(controls.burstDensity)
        let attackStrength = Float(controls.attackStrength)
        let burstCount = Int(mix(10, 58, min(max((burstDensity * 0.7) + (attackStrength * 0.3), 0.0), 1.0)))
        let center = SIMD2<Float>(Float(controls.centerOffset.x), Float(controls.centerOffset.y))
        let dominantEnergy = Float(max(controls.lowBandEnergy, max(controls.midBandEnergy, controls.highBandEnergy)))
        let sector = attackParticleSectorIndex(
            attackID: controls.attackID,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy,
            sectorCount: 12
        )
        let sectorAngle = (Float(sector) + 0.5) * ((2 * .pi) / 12)
        let baseDirection = SIMD2<Float>(cos(sectorAngle), sin(sectorAngle))
        let trailDecay = Float(controls.trailDecay)
        let lensSheen = Float(controls.lensSheen)

        _ = attackParticlePool.insertBurstIfNewAttack(attackID: controls.attackID, count: burstCount) { burstIndex in
            let seedBase = controls.attackID ^ (UInt64(burstIndex) &* 0x9E37_79B9_7F4A_7C15)
            let jitterA = (spectralHash01(seedBase ^ 0xD1B5_4A32_D192_ED03) * 2) - 1
            let jitterB = spectralHash01(seedBase ^ 0x94D0_49BB_1331_11EB)
            let jitterC = spectralHash01(seedBase ^ 0x27D4_EB2F_1656_67C5)

            let angle = sectorAngle + (jitterA * (0.44 + (0.30 * lensSheen)))
            let spreadDirection = SIMD2<Float>(cos(angle), sin(angle))
            let blendedDirection = simd_normalize((spreadDirection * 0.68) + (baseDirection * 0.32))
            let speed = mix(0.18, 1.06, jitterB) * mix(0.55, 1.45, attackStrength)
            let velocity = blendedDirection * speed

            let spawnRadius = 0.012 + (jitterC * 0.050)
            let origin = center + (blendedDirection * spawnRadius)
            let size = mix(0.010, 0.046, jitterB)
            let intensity = 0.32 + (attackStrength * 0.88) + (dominantEnergy * 0.42) + (jitterC * 0.22)
            let lifetime = mix(0.55, 2.3, trailDecay) * mix(0.72, 1.32, jitterB)
            let hueShift = (Float(sector) / 12.0) + ((jitterA * 0.10) + (jitterC * 0.08))

            return AttackParticleEvent(
                attackID: controls.attackID,
                birthTime: elapsedTime,
                origin: origin,
                velocity: velocity,
                size: size,
                intensity: intensity,
                hueShift: hueShift,
                trailDecay: trailDecay,
                lifetime: lifetime,
                sector: UInt32(sector),
                isActive: true
            )
        }
    }

    private func updateAttackParticleGPUData(elapsedTime: Float, particleLimit: Int) -> UInt32 {
        let activeLimit = max(1, min(particleLimit, kMaxAttackParticles))
        var activeCount = 0

        for index in attackParticlePool.events.indices {
            let event = attackParticlePool.events[index]
            guard event.isActive else { continue }

            let age = elapsedTime - event.birthTime
            if age < 0 || age >= event.lifetime {
                attackParticlePool.events[index].isActive = false
                continue
            }

            let lifeProgress = age / max(event.lifetime, 0.0001)
            let decayCurve = pow(max(1 - lifeProgress, 0), max(0.4, (event.trailDecay * 1.45) + 0.2))
            let intensity = event.intensity * decayCurve
            if intensity <= 0.0018 {
                attackParticlePool.events[index].isActive = false
                continue
            }

            if activeCount < activeLimit {
                let drift = SIMD2<Float>(-event.velocity.y, event.velocity.x) * ((lifeProgress - 0.5) * 0.08)
                let position = event.origin + (event.velocity * age) + drift
                let size = max(event.size * (1 + (lifeProgress * 1.5)), 0.004)
                attackParticleGPUData[activeCount] = AttackParticleGPUData(
                    positionSizeIntensity: SIMD4<Float>(position.x, position.y, size, intensity),
                    velocityHueTrail: SIMD4<Float>(event.velocity.x, event.velocity.y, event.hueShift, event.trailDecay)
                )
                activeCount += 1
            }
        }

        if activeCount < attackParticleGPUData.count {
            for index in activeCount ..< attackParticleGPUData.count {
                attackParticleGPUData[index] = .zero
            }
        }

        return UInt32(activeCount)
    }

    private func spawnPrismImpulseIfNeeded(controls: RendererControlState, elapsedTime: Float) {
        guard controls.isAttack else { return }

        let sector = prismFieldSectorIndex(
            attackID: controls.attackID,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy,
            sectorCount: 12
        )
        let dominantEnergy = Float(max(controls.lowBandEnergy, max(controls.midBandEnergy, controls.highBandEnergy)))
        let attackStrength = Float(controls.attackStrength)
        let facetDensity = Float(controls.prismFacetDensity)
        let dispersion = Float(controls.prismDispersion)
        let centerOffset = SIMD2<Float>(Float(controls.centerOffset.x), Float(controls.centerOffset.y))

        _ = prismImpulsePool.insertIfNewAttack(attackID: controls.attackID) {
            let jitterA = (spectralHash01(controls.attackID ^ 0xA24B_AED4_963E_E407) * 2) - 1
            let jitterB = spectralHash01(controls.attackID ^ 0x9FB2_1C65_1E98_DF25)
            let jitterC = spectralHash01(controls.attackID ^ 0xD6E8_FEB8_6659_FD93)
            let sectorAngle = (Float(sector) + (jitterA * 0.42)) * ((2 * .pi) / 12)
            let spawnDistance = 0.08 + (jitterB * 0.50)
            let origin = centerOffset + (SIMD2<Float>(cos(sectorAngle), sin(sectorAngle)) * spawnDistance)
            let directionAngle = sectorAngle + (jitterA * (0.24 + (dispersion * 0.34)))
            let direction = simd_normalize(SIMD2<Float>(cos(directionAngle), sin(directionAngle)))
            let intensity = 0.35 + (attackStrength * 0.88) + (dominantEnergy * 0.48) + (jitterC * 0.22)
            let width = mix(0.018, 0.092, min(max((facetDensity * 0.7) + (jitterB * 0.3), 0), 1))
            let lifetime = mix(0.52, 2.10, min(max((dispersion * 0.62) + (attackStrength * 0.38), 0), 1))
            let decay = mix(0.62, 0.94, min(max(dispersion, 0), 1))
            let hueShift = (Float(sector) / 12.0) + (jitterA * 0.09)

            return PrismImpulseEvent(
                attackID: controls.attackID,
                birthTime: elapsedTime,
                origin: origin,
                direction: direction,
                width: width,
                intensity: intensity,
                decay: decay,
                lifetime: lifetime,
                hueShift: hueShift,
                sector: UInt32(sector),
                isActive: true
            )
        }
    }

    private func updatePrismImpulseGPUData(elapsedTime: Float, impulseLimit: Int) -> UInt32 {
        let activeLimit = max(1, min(impulseLimit, kMaxPrismImpulses))
        var activeCount = 0

        for index in prismImpulsePool.events.indices {
            let event = prismImpulsePool.events[index]
            guard event.isActive else { continue }

            let age = elapsedTime - event.birthTime
            if age < 0 || age >= event.lifetime {
                prismImpulsePool.events[index].isActive = false
                continue
            }

            let lifeProgress = age / max(event.lifetime, 0.0001)
            let decayCurve = pow(max(1 - lifeProgress, 0), max(0.30, event.decay * 1.2))
            let intensity = event.intensity * decayCurve
            if intensity <= 0.0015 {
                prismImpulsePool.events[index].isActive = false
                continue
            }

            if activeCount < activeLimit {
                let travel = mix(0.02, 0.34, lifeProgress)
                let position = event.origin + (event.direction * travel)
                let radius = max(event.width * (1 + (lifeProgress * 1.8)), 0.006)
                prismImpulseGPUData[activeCount] = PrismImpulseGPUData(
                    positionRadiusIntensity: SIMD4<Float>(position.x, position.y, radius, intensity),
                    directionHueDecay: SIMD4<Float>(event.direction.x, event.direction.y, event.hueShift, event.decay)
                )
                activeCount += 1
            }
        }

        if activeCount < prismImpulseGPUData.count {
            for index in activeCount ..< prismImpulseGPUData.count {
                prismImpulseGPUData[index] = .zero
            }
        }

        return UInt32(activeCount)
    }

    private func spawnTunnelShapeIfNeeded(controls: RendererControlState, elapsedTime: Float) {
        guard controls.isAttack else { return }

        let sector = tunnelCelsSectorIndex(
            attackID: controls.attackID,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy,
            sectorCount: 12
        )
        let dominantEnergy = Float(max(controls.lowBandEnergy, max(controls.midBandEnergy, controls.highBandEnergy)))
        let attackStrength = Float(controls.attackStrength)
        let shapeScale = Float(controls.tunnelShapeScale)
        let depthSpeed = Float(controls.tunnelDepthSpeed)
        let releaseTail = Float(controls.tunnelReleaseTail)
        let variant = UInt32(min(max(Int(controls.tunnelVariant.rounded()), 0), 2))
        let center = SIMD2<Float>(Float(controls.centerOffset.x), Float(controls.centerOffset.y))

        _ = tunnelShapePool.insertIfNewAttack(attackID: controls.attackID) {
            let jitterA = (spectralHash01(controls.attackID ^ 0xEED4_F5D1_8A1B_28F1) * 2) - 1
            let jitterB = spectralHash01(controls.attackID ^ 0x4CF5_AD43_2745_937F)
            let jitterC = spectralHash01(controls.attackID ^ 0xC3A5_C85C_97CB_3127)
            let sectorAngle = (Float(sector) + 0.5) * ((2 * .pi) / 12)
            let ringDirection = SIMD2<Float>(cos(sectorAngle), sin(sectorAngle))
            let squareEdge = ringDirection / max(max(abs(ringDirection.x), abs(ringDirection.y)), 0.0001)
            let tangent = simd_normalize(SIMD2<Float>(-squareEdge.y, squareEdge.x))
            let laneSpread = mix(0.20, 0.56, min(max((shapeScale * 0.66) + (jitterB * 0.34), 0), 1))
            let laneJitter = jitterA * mix(0.02, 0.08, 1 - min(max(shapeScale, 0), 1))
            let laneOrigin = center + (squareEdge * laneSpread) + (tangent * laneJitter)
            let axisSeed = simd_normalize(squareEdge + (tangent * (jitterA * 0.45)))
            let forwardSpeed = mix(0.16, 1.55, min(max((depthSpeed * 0.74) + (dominantEnergy * 0.26), 0), 1))
            let depthOffset = 0.08 + (jitterC * 0.40)
            let baseScale = mix(0.16, 1.10, min(max((shapeScale * 0.64) + (jitterB * 0.36), 0), 1))
            let hueShift = (Float(sector) / 12.0) + (jitterA * 0.08)
            let sustainLevel = min(max(0.42 + (attackStrength * 0.35), 0.22), 0.96)
            let decayShape = 0.85 + (jitterC * 0.70)
            let releaseDuration = mix(0.25, 2.50, min(max(releaseTail, 0), 1))

            return TunnelShapeEvent(
                attackID: controls.attackID,
                birthTime: elapsedTime,
                laneOrigin: laneOrigin,
                forwardSpeed: forwardSpeed,
                depthOffset: depthOffset,
                baseScale: baseScale,
                hueShift: hueShift,
                sustainLevel: sustainLevel,
                decayShape: decayShape,
                releaseDuration: releaseDuration,
                axisSeed: axisSeed,
                variant: variant,
                lastAboveTimestamp: elapsedTime,
                releaseStartTimestamp: -1,
                isActive: true
            )
        }
    }

    private func updateTunnelShapeGPUData(
        controls: RendererControlState,
        elapsedTime: Float,
        shapeLimit: Int
    ) -> UInt32 {
        let activeLimit = max(1, min(shapeLimit, kMaxTunnelShapes))
        let sustainOnThreshold: Float = 0.10

        let maxBand = Float(max(controls.lowBandEnergy, max(controls.midBandEnergy, controls.highBandEnergy)))
        let sidechainEnergy = min(max((Float(controls.featureAmplitude) * 0.58) + (maxBand * 0.30) + (Float(controls.attackStrength) * 0.12), 0), 1)

        var activeCount = 0

        for index in tunnelShapePool.events.indices {
            var event = tunnelShapePool.events[index]
            guard event.isActive else { continue }

            let age = elapsedTime - event.birthTime
            if age < 0 {
                continue
            }

            if sidechainEnergy >= sustainOnThreshold {
                event.lastAboveTimestamp = elapsedTime
                if event.releaseStartTimestamp >= 0 {
                    event.releaseStartTimestamp = -1
                }
            } else if event.releaseStartTimestamp < 0,
                      shouldStartTunnelRelease(
                          sidechainEnergy: sidechainEnergy,
                          lastAboveTimestamp: event.lastAboveTimestamp,
                          elapsedTime: elapsedTime
                      ) {
                event.releaseStartTimestamp = elapsedTime
            }

            let envelopeResult = tunnelShapeEnvelopeValue(
                age: age,
                sustainLevel: event.sustainLevel,
                releaseStartTimestamp: event.releaseStartTimestamp,
                elapsedTime: elapsedTime,
                releaseDuration: event.releaseDuration
            )
            let envelope = envelopeResult.value
            if envelopeResult.isExpired {
                event.isActive = false
            }

            if !event.isActive || envelope <= 0.001 {
                event.isActive = false
                tunnelShapePool.events[index] = event
                continue
            }

            if activeCount < activeLimit {
                let travel = age * event.forwardSpeed
                let depth = 0.22 + event.depthOffset + (travel * 1.18)
                if depth > 6.8 {
                    event.isActive = false
                    tunnelShapePool.events[index] = event
                    continue
                }

                let decayMix = min(max((age - 0.035) / max(0.140, 0.0001), 0), 1)
                let shapeScale = event.baseScale * mix(1.18, 1.0, decayMix)
                let releaseNorm = event.releaseStartTimestamp >= 0 ? min(max((elapsedTime - event.releaseStartTimestamp) / max(event.releaseDuration, 0.0001), 0), 1) : 0

                tunnelShapeGPUData[activeCount] = TunnelShapeGPUData(
                    positionDepthScaleEnvelope: SIMD4<Float>(event.laneOrigin.x, event.laneOrigin.y, depth, shapeScale),
                    forwardHueVariantSeed: SIMD4<Float>(event.forwardSpeed, event.hueShift, Float(event.variant), envelope),
                    axisDecaySustainRelease: SIMD4<Float>(event.axisSeed.x, event.axisSeed.y, event.decayShape, releaseNorm)
                )
                activeCount += 1
            }

            tunnelShapePool.events[index] = event
        }

        if activeCount < tunnelShapeGPUData.count {
            for index in activeCount ..< tunnelShapeGPUData.count {
                tunnelShapeGPUData[index] = .zero
            }
        }

        return UInt32(activeCount)
    }

    private func spawnFractalPulseIfNeeded(controls: RendererControlState, elapsedTime: Float) {
        guard controls.isAttack else { return }

        let sector = fractalCausticsSectorIndex(
            attackID: controls.attackID,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy,
            sectorCount: 12
        )
        let dominantEnergy = Float(max(controls.lowBandEnergy, max(controls.midBandEnergy, controls.highBandEnergy)))
        let attackStrength = Float(controls.attackStrength)
        let attackBloom = Float(controls.fractalAttackBloom)
        let fractalDetail = Float(controls.fractalDetail)
        let paletteIndex = Float(min(max(Int(controls.fractalPaletteVariant.rounded()), 0), 7))
        let center = SIMD2<Float>(Float(controls.centerOffset.x), Float(controls.centerOffset.y))

        _ = fractalPulsePool.insertIfNewAttack(attackID: controls.attackID) {
            let jitterA = (spectralHash01(controls.attackID ^ 0x23C2_9D7B_4E9A_9913) * 2) - 1
            let jitterB = spectralHash01(controls.attackID ^ 0xA83B_54D9_8FE6_C4D1)
            let jitterC = spectralHash01(controls.attackID ^ 0xD78D_2F91_B3C4_AE07)
            let sectorAngle = (Float(sector) + (jitterA * 0.38)) * ((2 * .pi) / 12)
            let offset = SIMD2<Float>(cos(sectorAngle), sin(sectorAngle)) * (0.06 + (jitterB * 0.28))
            let origin = center + offset
            let radius = mix(0.03, 0.16, min(max((fractalDetail * 0.64) + (jitterC * 0.36), 0), 1))
            let intensity = 0.34 + (attackStrength * 0.90) + (dominantEnergy * 0.42) + (attackBloom * 0.36)
            let lifetime = mix(0.42, 2.20, min(max(attackBloom, 0), 1))
            let decay = mix(0.58, 0.94, min(max(attackBloom, 0), 1))
            let hueShift = (paletteIndex / 8.0) + (Float(sector) / 12.0) * 0.25 + (jitterA * 0.08)
            let seed = jitterC

            return FractalPulseEvent(
                attackID: controls.attackID,
                birthTime: elapsedTime,
                origin: origin,
                baseRadius: radius,
                intensity: intensity,
                decay: decay,
                lifetime: lifetime,
                hueShift: hueShift,
                seed: seed,
                sector: UInt32(sector),
                isActive: true
            )
        }
    }

    private func updateFractalPulseGPUData(elapsedTime: Float, pulseLimit: Int) -> UInt32 {
        let activeLimit = max(1, min(pulseLimit, kMaxFractalPulses))
        var activeCount = 0

        for index in fractalPulsePool.events.indices {
            let event = fractalPulsePool.events[index]
            guard event.isActive else { continue }

            let age = elapsedTime - event.birthTime
            if age < 0 || age >= event.lifetime {
                fractalPulsePool.events[index].isActive = false
                continue
            }

            let lifeProgress = age / max(event.lifetime, 0.0001)
            let decayCurve = pow(max(1 - lifeProgress, 0), max(0.28, event.decay * 1.16))
            let intensity = event.intensity * decayCurve
            if intensity <= 0.0014 {
                fractalPulsePool.events[index].isActive = false
                continue
            }

            if activeCount < activeLimit {
                let radius = max(event.baseRadius * (1 + (lifeProgress * 2.1)), 0.005)
                fractalPulseGPUData[activeCount] = FractalPulseGPUData(
                    positionRadiusIntensity: SIMD4<Float>(event.origin.x, event.origin.y, radius, intensity),
                    hueDecaySeedSector: SIMD4<Float>(event.hueShift, event.decay, event.seed, Float(event.sector))
                )
                activeCount += 1
            }
        }

        if activeCount < fractalPulseGPUData.count {
            for index in activeCount ..< fractalPulseGPUData.count {
                fractalPulseGPUData[index] = .zero
            }
        }

        return UInt32(activeCount)
    }

    private func spawnRiemannAccentIfNeeded(controls: RendererControlState, elapsedTime: Float) {
        guard controls.isAttack else { return }

        let sector = riemannCorridorSectorIndex(
            attackID: controls.attackID,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy,
            sectorCount: 12
        )
        let dominantEnergy = Float(max(controls.lowBandEnergy, max(controls.midBandEnergy, controls.highBandEnergy)))
        let attackStrength = Float(controls.attackStrength)
        let zeroBloom = Float(controls.riemannZeroBloom)
        let detail = Float(controls.riemannDetail)
        let paletteIndex = Float(min(max(Int(controls.riemannPaletteVariant.rounded()), 0), 7))
        let center = SIMD2<Float>(Float(controls.centerOffset.x), Float(controls.centerOffset.y))

        _ = riemannAccentPool.insertIfNewAttack(attackID: controls.attackID) {
            let jitterA = (spectralHash01(controls.attackID ^ 0x7FB5_D329_728E_5C37) * 2) - 1
            let jitterB = spectralHash01(controls.attackID ^ 0xA6BC_6F34_2AC9_992D)
            let jitterC = spectralHash01(controls.attackID ^ 0xCB6A_48F0_3E3D_9171)
            let sectorAngle = (Float(sector) + (jitterA * 0.34)) * ((2 * .pi) / 12)
            let laneDirection = SIMD2<Float>(cos(sectorAngle), sin(sectorAngle))
            let origin = center + (laneDirection * (0.04 + (jitterB * 0.18)))
            let length = mix(0.04, 0.18, min(max((detail * 0.56) + (jitterC * 0.24), 0), 1))
            let width = mix(0.0018, 0.0060, min(max((zeroBloom * 0.52) + (jitterB * 0.22), 0), 1))
            let intensity = 0.022 + (attackStrength * 0.090) + (dominantEnergy * 0.050) + (zeroBloom * 0.046)
            let decay = mix(0.86, 0.97, min(max(zeroBloom, 0), 1))
            let lifetime = mix(0.12, 0.40, min(max(zeroBloom, 0), 1))
            let hueShift = (paletteIndex / 8.0) + (Float(sector) / 12.0) * 0.20 + (jitterA * 0.04)
            let seed = jitterC

            return RiemannAccentEvent(
                attackID: controls.attackID,
                birthTime: elapsedTime,
                origin: origin,
                direction: laneDirection,
                width: width,
                length: length,
                intensity: intensity,
                decay: decay,
                lifetime: lifetime,
                hueShift: hueShift,
                seed: seed,
                sector: UInt32(sector),
                isActive: true
            )
        }
    }

    private func updateRiemannAccentGPUData(elapsedTime: Float, accentLimit: Int) -> UInt32 {
        let activeLimit = max(1, min(accentLimit, kMaxRiemannAccents))
        var activeCount = 0

        for index in riemannAccentPool.events.indices {
            let event = riemannAccentPool.events[index]
            guard event.isActive else { continue }

            let age = elapsedTime - event.birthTime
            if age < 0 || age >= event.lifetime {
                riemannAccentPool.events[index].isActive = false
                continue
            }

            let lifeProgress = age / max(event.lifetime, 0.0001)
            let decayCurve = pow(max(1 - lifeProgress, 0), max(0.28, event.decay * 1.18))
            let intensity = event.intensity * decayCurve
            if intensity <= 0.0014 {
                riemannAccentPool.events[index].isActive = false
                continue
            }

            if activeCount < activeLimit {
                let length = max(event.length * (1 + (lifeProgress * 1.6)), 0.01)
                riemannAccentGPUData[activeCount] = RiemannAccentGPUData(
                    positionWidthIntensity: SIMD4<Float>(event.origin.x, event.origin.y, event.width, intensity),
                    directionLengthHueSeed: SIMD4<Float>(event.direction.x, event.direction.y, length, event.hueShift),
                    decaySeedSectorActive: SIMD4<Float>(event.decay, event.seed, Float(event.sector), 1)
                )
                activeCount += 1
            }
        }

        if activeCount < riemannAccentGPUData.count {
            for index in activeCount ..< riemannAccentGPUData.count {
                riemannAccentGPUData[index] = .zero
            }
        }

        return UInt32(activeCount)
    }

    private func presentFallbackFrame(
        commandQueue: MTLCommandQueue,
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable,
        drawableID: ObjectIdentifier,
        time: CFTimeInterval
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            droppedFrameCount += 1
            diagnosticsSummary.droppedFrameCount = droppedFrameCount
            return
        }

        let pulse = 0.035 + (sin(time * 0.75) * 0.015)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(
            pulse * 0.45,
            pulse * 0.60,
            pulse,
            1.0
        )

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
        prepareCommandBufferForCommit(commandBuffer, drawableID: drawableID)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func prepareCommandBufferForCommit(
        _ commandBuffer: MTLCommandBuffer,
        drawableID: ObjectIdentifier,
        retainedCameraTexture: CVMetalTexture? = nil
    ) {
        inFlightDrawableID = drawableID
        inFlightCameraTextureRef = retainedCameraTexture
        commandBuffer.addCompletedHandler { [weak self] buffer in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.inFlightDrawableID == drawableID {
                    self.inFlightDrawableID = nil
                }
                self.inFlightCameraTextureRef = nil

                guard buffer.status == .error else {
                    self.consecutiveCommandBufferErrors = 0
                    if self.pipelineStates != nil, self.diagnosticsSummary.readinessStatus != .ready {
                        self.diagnosticsSummary.readinessStatus = .ready
                        self.diagnosticsSummary.statusMessage = "Metal surface ready"
                    }
                    return
                }

                self.consecutiveCommandBufferErrors += 1
                self.droppedFrameCount += 1
                self.diagnosticsSummary.droppedFrameCount = self.droppedFrameCount
                self.diagnosticsSummary.readinessStatus = .failed
                self.diagnosticsSummary.statusMessage = "GPU command error: \(buffer.error?.localizedDescription ?? "unknown")"

                // Force a rebuild after repeated GPU failures instead of hammering the queue.
                if self.consecutiveCommandBufferErrors >= 2 {
                    self.pipelineStates = nil
                    self.spectralTargets = nil
                    self.attackParticleTargets = nil
                    self.colorFeedbackTargets = nil
                    self.prismTargets = nil
                    self.tunnelTargets = nil
                    self.fractalTargets = nil
                    self.riemannTargets = nil
                    self.lastPipelineRetryTime = nil
                    _ = self.degradeActiveModeQuality(reason: "GPU errors")
                }

                if self.consecutiveCommandBufferErrors >= 4 {
                    self.forceRadialFallbackUntil = CACurrentMediaTime() + 2.0
                    self.consecutiveCommandBufferErrors = 0
                    self.diagnosticsSummary.statusMessage = "Radial fallback active for stability"
                }
            }
        }
    }

    private func degradeSpectralQuality(reason: String) -> Bool {
        guard spectralQuality.degrade() else { return false }
        diagnosticsSummary.statusMessage = "Spectral quality reduced for stability (\(reason))"
        return true
    }

    private func degradeAttackParticleQuality(reason: String) -> Bool {
        guard attackParticleQuality.degrade() else { return false }
        diagnosticsSummary.statusMessage = "Attack particle quality reduced for stability (\(reason))"
        return true
    }

    private func degradePrismQuality(reason: String) -> Bool {
        guard prismQuality.degrade() else { return false }
        diagnosticsSummary.statusMessage = "Prism quality reduced for stability (\(reason))"
        return true
    }

    private func degradeTunnelQuality(reason: String) -> Bool {
        guard tunnelQuality.degrade() else { return false }
        diagnosticsSummary.statusMessage = "Tunnel quality reduced for stability (\(reason))"
        return true
    }

    private func degradeFractalQuality(reason: String) -> Bool {
        guard fractalQuality.degrade() else { return false }
        diagnosticsSummary.statusMessage = "Fractal quality reduced for stability (\(reason))"
        return true
    }

    private func degradeRiemannQuality(reason: String) -> Bool {
        guard riemannQuality.degrade() else { return false }
        diagnosticsSummary.statusMessage = "Riemann quality reduced for stability (\(reason))"
        return true
    }

    private func degradeActiveModeQuality(reason: String) -> Bool {
        switch currentSurfaceState.activeModeID {
        case .colorShift:
            return false
        case .prismField:
            return degradePrismQuality(reason: reason)
        case .tunnelCels:
            return degradeTunnelQuality(reason: reason)
        case .fractalCaustics:
            return degradeFractalQuality(reason: reason)
        case .riemannCorridor:
            return degradeRiemannQuality(reason: reason)
        }
    }

    private func makeUniforms(
        time: Float,
        drawableSize: CGSize,
        state: RendererSurfaceState,
        ringCount: UInt32,
        shimmerSampleCount: UInt32,
        particleCount: UInt32,
        attackTrailSampleCount: UInt32,
        prismFacetSampleCount: UInt32,
        prismDispersionSampleCount: UInt32,
        prismImpulseCount: UInt32,
        tunnelShapeCount: UInt32,
        tunnelTrailSampleCount: UInt32,
        tunnelDispersionSampleCount: UInt32,
        fractalOrbitSampleCount: UInt32,
        fractalTrapSampleCount: UInt32,
        fractalPulseCount: UInt32,
        fractalFlowPhase: Float,
        riemannTermCount: UInt32,
        riemannTrapSampleCount: UInt32,
        riemannAccentCount: UInt32,
        riemannFlowPhase: Float,
        riemannCameraCenter: SIMD2<Float>,
        riemannCameraZoom: Float,
        riemannCameraHeading: Float
    ) -> RendererFrameUniforms {
        let controls = state.controls.clamped()
        let attackIDLow = UInt32(truncatingIfNeeded: controls.attackID)
        let attackIDHigh = UInt32(truncatingIfNeeded: controls.attackID >> 32)
        let colorShiftBlackout = controls.colorFeedbackBlackout
        let prismBlackout = shouldBlackoutPrism(
            noImageInSilence: controls.noImageInSilence,
            featureAmplitude: controls.featureAmplitude,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy
        )
        let tunnelBlackout = shouldBlackoutTunnel(
            noImageInSilence: controls.noImageInSilence,
            featureAmplitude: controls.featureAmplitude,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy
        )
        let fractalBlackout = shouldBlackoutFractal(
            noImageInSilence: controls.noImageInSilence,
            featureAmplitude: controls.featureAmplitude,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy
        )
        let riemannBlackout = shouldBlackoutRiemann(
            noImageInSilence: controls.noImageInSilence,
            featureAmplitude: controls.featureAmplitude,
            lowBandEnergy: controls.lowBandEnergy,
            midBandEnergy: controls.midBandEnergy,
            highBandEnergy: controls.highBandEnergy
        )

        return RendererFrameUniforms(
            time: time,
            intensity: Float(controls.intensity),
            scale: Float(controls.scale),
            motion: Float(controls.motion),
            diffusion: Float(controls.diffusion),
            blackFloor: Float(controls.blackFloor),
            modeIndex: modeIndex(for: state.activeModeID),
            resolution: SIMD2<Float>(Float(max(drawableSize.width, 1)), Float(max(drawableSize.height, 1))),
            centerOffset: SIMD2<Float>(Float(controls.centerOffset.x), Float(controls.centerOffset.y)),
            ringDecay: Float(controls.ringDecay),
            featureAmplitude: Float(controls.featureAmplitude),
            lowBandEnergy: Float(controls.lowBandEnergy),
            midBandEnergy: Float(controls.midBandEnergy),
            highBandEnergy: Float(controls.highBandEnergy),
            attackStrength: Float(controls.attackStrength),
            ringCount: ringCount,
            shimmerSampleCount: shimmerSampleCount,
            burstDensity: Float(controls.burstDensity),
            trailDecay: Float(controls.trailDecay),
            lensSheen: Float(controls.lensSheen),
            particleCount: particleCount,
            attackTrailSampleCount: attackTrailSampleCount,
            prismFacetDensity: Float(controls.prismFacetDensity),
            prismDispersion: Float(controls.prismDispersion),
            prismFacetSampleCount: prismFacetSampleCount,
            prismDispersionSampleCount: prismDispersionSampleCount,
            prismImpulseCount: prismImpulseCount,
            prismBlackout: prismBlackout ? 1 : 0,
            tunnelShapeScale: Float(controls.tunnelShapeScale),
            tunnelDepthSpeed: Float(controls.tunnelDepthSpeed),
            tunnelReleaseTail: Float(controls.tunnelReleaseTail),
            tunnelVariant: UInt32(min(max(Int(controls.tunnelVariant.rounded()), 0), 2)),
            tunnelShapeCount: tunnelShapeCount,
            tunnelTrailSampleCount: tunnelTrailSampleCount,
            tunnelDispersionSampleCount: tunnelDispersionSampleCount,
            tunnelBlackout: tunnelBlackout ? 1 : 0,
            fractalDetail: Float(controls.fractalDetail),
            fractalFlowRate: Float(controls.fractalFlowRate),
            fractalAttackBloom: Float(controls.fractalAttackBloom),
            fractalPaletteVariant: UInt32(min(max(Int(controls.fractalPaletteVariant.rounded()), 0), 7)),
            fractalOrbitSampleCount: fractalOrbitSampleCount,
            fractalTrapSampleCount: fractalTrapSampleCount,
            fractalPulseCount: fractalPulseCount,
            fractalBlackout: fractalBlackout ? 1 : 0,
            fractalFlowPhase: fractalFlowPhase,
            riemannDetail: Float(controls.riemannDetail),
            riemannFlowRate: Float(controls.riemannFlowRate),
            riemannZeroBloom: Float(controls.riemannZeroBloom),
            riemannPaletteVariant: UInt32(min(max(Int(controls.riemannPaletteVariant.rounded()), 0), 7)),
            riemannTermCount: riemannTermCount,
            riemannTrapSampleCount: riemannTrapSampleCount,
            riemannAccentCount: riemannAccentCount,
            riemannBlackout: riemannBlackout ? 1 : 0,
            riemannFlowPhase: riemannFlowPhase,
            riemannCameraCenter: riemannCameraCenter,
            riemannCameraZoom: riemannCameraZoom,
            riemannCameraHeading: riemannCameraHeading,
            noImageInSilence: controls.noImageInSilence ? 1 : 0,
            colorShiftHue: colorShiftHuePhase,
            colorShiftSaturation: colorShiftSaturation,
            colorShiftBlackout: colorShiftBlackout ? 1 : 0,
            pitchConfidence: Float(controls.pitchConfidence),
            stablePitchClass: Int32(controls.stablePitchClass ?? -1),
            stablePitchCents: Float(controls.stablePitchCents),
            attackIDLow: attackIDLow,
            attackIDHigh: attackIDHigh
        )
    }

    private func updateColorShiftHuePhase(now: CFTimeInterval, state: RendererSurfaceState) {
        defer { lastColorShiftHueUpdateTime = now }

        guard state.activeModeID == .colorShift else { return }
        colorShiftSaturation = colorShiftSaturationValue(controls: state.controls)
        guard let lastColorShiftHueUpdateTime else { return }

        let deltaTime = Float(max(0, min(now - lastColorShiftHueUpdateTime, 0.25)))
        guard deltaTime > 0 else { return }

        let nextHue = advanceColorShiftHuePhase(
            currentHue: colorShiftHuePhase,
            deltaTime: deltaTime,
            controls: state.controls
        )
        colorShiftHuePhase = nextHue
    }

    private func updateFractalFlowPhase(now: CFTimeInterval, state: RendererSurfaceState) {
        defer { lastFractalFlowUpdateTime = now }
        guard state.activeModeID == .fractalCaustics else { return }
        guard let lastFractalFlowUpdateTime else { return }

        let deltaTime = Float(max(0, min(now - lastFractalFlowUpdateTime, 0.25)))
        guard deltaTime > 0 else { return }

        fractalFlowPhase = fractalFlowPhaseAdvance(
            currentPhase: fractalFlowPhase,
            deltaTime: deltaTime,
            controls: state.controls
        )
    }

    private func updateRiemannFlowPhase(now: CFTimeInterval, state: RendererSurfaceState) {
        defer { lastRiemannFlowUpdateTime = now }
        guard state.activeModeID == .riemannCorridor else { return }
        guard let lastRiemannFlowUpdateTime else { return }

        let deltaTime = Float(max(0, min(now - lastRiemannFlowUpdateTime, 0.25)))
        guard deltaTime > 0 else { return }
        let controls = state.controls.clamped()
        let flowRate = Float(controls.riemannFlowRate)
        let rawIntensity = riemannWeightedTraversalIntensity(controls: controls)
        let intensityAlpha = 1 - exp(-(deltaTime * mix(2.0, 6.0, flowRate)))
        riemannSmoothedIntensity += (rawIntensity - riemannSmoothedIntensity) * intensityAlpha
        riemannSmoothedIntensity = riemannSmoothedIntensity.clamped(to: 0 ... 1)
        let smoothedIntensity = riemannSmoothedIntensity

        let rawSteering = riemannSteeringVector(controls: controls)
        let rawSteeringMagnitude = simd_length(rawSteering)
        let steeringDeadzone = mix(0.24, 0.06, smoothedIntensity) * mix(1.0, 0.80, flowRate)
        let steeringTarget: SIMD2<Float>
        if rawSteeringMagnitude <= steeringDeadzone {
            steeringTarget = .zero
        } else {
            let scaledMagnitude = (rawSteeringMagnitude - steeringDeadzone) / max(1 - steeringDeadzone, 0.0001)
            steeringTarget = (rawSteering / max(rawSteeringMagnitude, 0.0001)) * scaledMagnitude
        }
        let steeringAlpha = 1 - exp(-(deltaTime * mix(1.8, 7.2, smoothedIntensity)))
        riemannSmoothedSteering += (steeringTarget - riemannSmoothedSteering) * steeringAlpha

        riemannFlowPhase = riemannFlowPhaseAdvance(
            currentPhase: riemannFlowPhase,
            deltaTime: deltaTime,
            controls: controls
        )

        let centerStructure = mandelbrotLocalStructureScore(
            center: riemannCameraCenter,
            zoom: riemannCameraZoom,
            detail: Float(controls.riemannDetail)
        )
        let routeDetail = Float(controls.riemannDetail)
        let routeZoomScale = max(Double(riemannCameraZoom), 0.000_002)
        let routeZoomBoost = min(max(-Foundation.log2(routeZoomScale), 0), 28)
        let routeIterBudget = Int(mix(72, 220, routeDetail) + Float(routeZoomBoost) * (18 + routeDetail * 18))
        let routeSampleOffset = Double(max(riemannCameraZoom, 0.000_006) * 0.020)
        let routeCenterSample = mandelbrotEscapeSample(
            real: Double(riemannCameraCenter.x),
            imag: Double(riemannCameraCenter.y),
            maxIterations: routeIterBudget
        )
        let routeCenterXNeighbor = mandelbrotEscapeSample(
            real: Double(riemannCameraCenter.x) + routeSampleOffset,
            imag: Double(riemannCameraCenter.y),
            maxIterations: routeIterBudget
        )
        let routeCenterYNeighbor = mandelbrotEscapeSample(
            real: Double(riemannCameraCenter.x),
            imag: Double(riemannCameraCenter.y) + routeSampleOffset,
            maxIterations: routeIterBudget
        )
        let routeCenterMetrics = mandelbrotStructureMetrics(
            primary: routeCenterSample,
            xNeighbor: routeCenterXNeighbor,
            yNeighbor: routeCenterYNeighbor,
            iterBudget: routeIterBudget
        )
        let deepZoomStabilityThreshold: Float = 0.006
        let offStructureThreshold: Float = riemannCameraZoom < deepZoomStabilityThreshold ? 0.10 : 0.26
        let crossingThreshold: Double = riemannCameraZoom < deepZoomStabilityThreshold ? 0.22 : 0.55
        let offStructure = centerStructure < offStructureThreshold || routeCenterMetrics.crossing < crossingThreshold

        let offStructureRetargetCooldown: CFTimeInterval = riemannCameraZoom < deepZoomStabilityThreshold ? 0.42 : 0.20
        if offStructure, (now - riemannLastRouteUpdateTime) >= offStructureRetargetCooldown {
            let route = riemannSelectMandelbrotPOITarget(
                center: riemannCameraCenter,
                zoom: riemannCameraZoom,
                heading: riemannCameraHeading,
                controls: controls,
                gridSize: 11,
                steeringOverride: riemannSmoothedSteering,
                intensityOverride: smoothedIntensity
            )
            riemannRouteTargetCenter = route.center
            if riemannCameraZoom < deepZoomStabilityThreshold {
                // At deep zoom, never hard-reset/zoom-out; keep traversing inward.
                riemannRouteTargetZoom = min(route.zoom, max(1e-9, riemannCameraZoom * 0.988))
            } else {
                riemannRouteTargetZoom = max(route.zoom, min(4.2, riemannCameraZoom * 1.30))
            }
            riemannLastRouteUpdateTime = now
        } else if smoothedIntensity >= 0.14, shouldTriggerRiemannRouteHandoff(
            lastAttackID: riemannLastRouteAttackID,
            newAttackID: controls.attackID,
            isAttackFrame: controls.isAttack,
            lastHandoffTime: riemannLastRouteUpdateTime,
            now: now,
            cooldown: riemannCameraZoom < deepZoomStabilityThreshold ? 0.72 : 0.42
        ) {
            let route = riemannSelectMandelbrotPOITarget(
                center: riemannCameraCenter,
                zoom: riemannCameraZoom,
                heading: riemannCameraHeading,
                controls: controls,
                gridSize: 9,
                steeringOverride: riemannSmoothedSteering,
                intensityOverride: smoothedIntensity
            )
            riemannRouteTargetCenter = route.center
            riemannRouteTargetZoom = route.zoom
            riemannLastRouteAttackID = controls.attackID
            riemannLastRouteUpdateTime = now
        } else if riemannLastRouteAttackID == 0 {
            // Prime deterministic initial target once at mode entry.
            riemannRouteTargetCenter = riemannCameraCenter
            riemannRouteTargetZoom = riemannCameraZoom
        } else {
            let clampedFlow = min(max(Double(controls.riemannFlowRate), 0), 1)
            let basePeriodic = (riemannCameraZoom < deepZoomStabilityThreshold ? 1.40 : 0.90) - (clampedFlow * (riemannCameraZoom < deepZoomStabilityThreshold ? 0.32 : 0.48))
            let lowIntensityPenalty = max(0, Double((0.18 - smoothedIntensity).clamped(to: 0 ... 0.18)) * 6.0)
            let periodicInterval = basePeriodic + lowIntensityPenalty
            if smoothedIntensity >= 0.08, (now - riemannLastRouteUpdateTime) >= periodicInterval {
                let route = riemannSelectMandelbrotPOITarget(
                    center: riemannCameraCenter,
                    zoom: riemannCameraZoom,
                    heading: riemannCameraHeading,
                    controls: controls,
                    gridSize: 7,
                    steeringOverride: riemannSmoothedSteering,
                    intensityOverride: smoothedIntensity
                )
                riemannRouteTargetCenter = route.center
                riemannRouteTargetZoom = route.zoom
                riemannLastRouteUpdateTime = now
            }
        }

        var traversal = riemannTraversalAdvance(
            center: riemannCameraCenter,
            zoom: riemannCameraZoom,
            heading: riemannCameraHeading,
            deltaTime: deltaTime,
            controls: controls,
            steeringOverride: riemannSmoothedSteering,
            intensityOverride: smoothedIntensity
        )

        let targetDelta = riemannRouteTargetCenter - traversal.center
        let targetDistance = simd_length(targetDelta)
        var routeBlend = min(max(deltaTime * (0.18 + (Float(controls.attackStrength) * 0.90) + (Float(controls.riemannFlowRate) * 0.60)), 0), 1)
        let routeDrive = ((smoothedIntensity - 0.06) / 0.34).clamped(to: 0 ... 1)
        routeBlend *= (0.16 + (routeDrive * 0.84))
        if offStructure {
            if traversal.zoom < deepZoomStabilityThreshold {
                routeBlend = max(routeBlend, min(0.20, deltaTime * 7.0))
            } else {
                routeBlend = max(routeBlend, min(0.62, deltaTime * 20.0))
            }
        }
        if targetDistance > 0.0001, routeBlend > 0 {
            if offStructure {
                if traversal.zoom < deepZoomStabilityThreshold {
                    let deepStep = max((0.06 + (Float(controls.riemannFlowRate) * 0.15)) * max(traversal.zoom, 1e-6), 0.000_000_4)
                    if targetDistance > deepStep {
                        traversal.center += (targetDelta / targetDistance) * deepStep
                    } else {
                        traversal.center = riemannRouteTargetCenter
                    }
                } else {
                    let snapDistance = max(traversal.zoom * 18.0, 0.0012)
                    if targetDistance > snapDistance {
                        traversal.center = riemannRouteTargetCenter
                    } else {
                        let baseStep = (0.12 + (Float(controls.riemannFlowRate) * 0.34) + (Float(controls.attackStrength) * 0.22)) * max(traversal.zoom, 0.000_9)
                        let maxStep = max(baseStep * 16.0, 0.000_04)
                        if targetDistance > maxStep {
                            traversal.center += (targetDelta / targetDistance) * maxStep
                        } else {
                            traversal.center = riemannRouteTargetCenter
                        }
                    }
                }
            } else {
                let baseStep = (0.12 + (Float(controls.riemannFlowRate) * 0.34) + (Float(controls.attackStrength) * 0.22)) * max(traversal.zoom, 0.000_9)
                if targetDistance > baseStep {
                    traversal.center += (targetDelta / targetDistance) * baseStep
                } else {
                    traversal.center = riemannRouteTargetCenter
                }
            }
        }

        let zoomBlend: Float
        if offStructure {
            if traversal.zoom < deepZoomStabilityThreshold {
                zoomBlend = max(routeBlend * 0.42, 0.06)
            } else {
                zoomBlend = max(routeBlend * 0.88, 0.28)
            }
        } else {
            zoomBlend = routeBlend * 0.32
        }
        traversal.zoom = mix(traversal.zoom, riemannRouteTargetZoom, zoomBlend)

        let routeHeading = atan2(targetDelta.y, targetDelta.x)
        if targetDistance > 0.0001 {
            let headingDelta = atan2(sin(routeHeading - traversal.heading), cos(routeHeading - traversal.heading))
            let headingGain: Float
            if offStructure {
                headingGain = traversal.zoom < deepZoomStabilityThreshold ? max(routeBlend * 0.22, 0.03) : max(routeBlend * 0.58, 0.16)
            } else {
                headingGain = routeBlend * 0.16
            }
            let headingDrive = ((smoothedIntensity - 0.08) / 0.40).clamped(to: 0 ... 1)
            let maxTurnRate = mix(0.30, 2.20, headingDrive) * mix(0.42, 1.0, Float(controls.riemannFlowRate))
            let maxStep = maxTurnRate * deltaTime
            let boundedDelta = headingDelta.clamped(to: -maxStep ... maxStep)
            traversal.heading = (traversal.heading + (boundedDelta * headingGain)).remainder(dividingBy: 2 * .pi)
        }

        riemannCameraCenter = traversal.center
        riemannCameraZoom = traversal.zoom
        riemannCameraHeading = traversal.heading
    }

    private func updateFrameTiming(now: CFTimeInterval) {
        defer { lastFrameTimestamp = now }
        guard let lastFrameTimestamp else { return }

        let deltaMS = (now - lastFrameTimestamp) * 1_000
        if smoothedFrameTimeMS == 0 {
            smoothedFrameTimeMS = deltaMS
        } else {
            smoothedFrameTimeMS = (smoothedFrameTimeMS * 0.9) + (deltaMS * 0.1)
        }

        if deltaMS > 28 {
            slowFrameStreak += 1
        } else {
            slowFrameStreak = max(0, slowFrameStreak - 1)
        }

        if slowFrameStreak >= 12 {
            if degradeActiveModeQuality(reason: "frame-time spike") {
                slowFrameStreak = 0
            }
        }

        diagnosticsSummary.averageFrameTimeMS = smoothedFrameTimeMS
        diagnosticsSummary.approximateFPS = smoothedFrameTimeMS > 0 ? 1_000 / smoothedFrameTimeMS : 0
        diagnosticsSummary.droppedFrameCount = droppedFrameCount

        if let forceRadialFallbackUntil, now >= forceRadialFallbackUntil {
            self.forceRadialFallbackUntil = nil
            if diagnosticsSummary.readinessStatus == .ready {
                diagnosticsSummary.statusMessage = "Metal surface ready"
            }
        }
    }

    private func tuneQualityForDrawableSize(_ size: CGSize, modeID: VisualModeID) {
        let megapixels = (max(size.width, 1) * max(size.height, 1)) / 1_000_000
        switch modeID {
        case .colorShift, .prismField, .tunnelCels, .fractalCaustics, .riemannCorridor:
            _ = megapixels
            return
        }
    }

    private func modeIndex(for modeID: VisualModeID) -> UInt32 {
        switch modeID {
        case .colorShift:
            return 0
        case .prismField:
            return 1
        case .tunnelCels:
            return 2
        case .fractalCaustics:
            return 3
        case .riemannCorridor:
            return 4
        }
    }
}

private extension MetalRendererService {
    func handleModeTransition(from oldMode: VisualModeID, to newMode: VisualModeID) {
        guard oldMode != newMode else { return }
        if oldMode == .riemannCorridor || newMode == .riemannCorridor {
            riemannSmoothedSteering = .zero
            riemannSmoothedIntensity = 0
            riemannLastRouteAttackID = 0
            riemannLastRouteUpdateTime = CACurrentMediaTime()
            riemannRouteTargetCenter = riemannCameraCenter
            riemannRouteTargetZoom = riemannCameraZoom
            if newMode == .riemannCorridor {
                lastRiemannFlowUpdateTime = nil
            }
        }
    }
}

private let kMaxSpectralRings = 48
private let kSpectralIntermediatePixelFormat: MTLPixelFormat = .rgba16Float
private let kMaxAttackParticles = 128
private let kAttackIntermediatePixelFormat: MTLPixelFormat = .rgba16Float
private let kMaxPrismImpulses = 32
private let kPrismIntermediatePixelFormat: MTLPixelFormat = .rgba16Float
private let kColorFeedbackIntermediatePixelFormat: MTLPixelFormat = .rgba16Float
private let kMaxTunnelShapes = 64
private let kTunnelIntermediatePixelFormat: MTLPixelFormat = .rgba16Float
private let kMaxFractalPulses = 32
private let kFractalIntermediatePixelFormat: MTLPixelFormat = .rgba16Float
private let kMaxRiemannAccents = 24
private let kRiemannIntermediatePixelFormat: MTLPixelFormat = .rgba16Float

private struct SpectralPipelineStates {
    var ringField: MTLRenderPipelineState
    var lens: MTLRenderPipelineState
    var shimmer: MTLRenderPipelineState
    var composite: MTLRenderPipelineState
}

private struct AttackParticlePipelineStates {
    var particleField: MTLRenderPipelineState
    var trail: MTLRenderPipelineState
    var composite: MTLRenderPipelineState
}

private struct ColorFeedbackPipelineStates {
    var contour: MTLRenderPipelineState
    var evolve: MTLRenderPipelineState
    var present: MTLRenderPipelineState
}

private struct PrismPipelineStates {
    var facetField: MTLRenderPipelineState
    var dispersion: MTLRenderPipelineState
    var accents: MTLRenderPipelineState
    var composite: MTLRenderPipelineState
}

private struct TunnelPipelineStates {
    var field: MTLRenderPipelineState
    var shapes: MTLRenderPipelineState
    var composite: MTLRenderPipelineState
}

private struct FractalPipelineStates {
    var field: MTLRenderPipelineState
    var accents: MTLRenderPipelineState
    var composite: MTLRenderPipelineState
}

private struct RiemannPipelineStates {
    var field: MTLRenderPipelineState
    var accents: MTLRenderPipelineState
    var composite: MTLRenderPipelineState
}

private struct RendererPipelineStates {
    var radial: MTLRenderPipelineState
    var spectral: SpectralPipelineStates?
    var attackParticle: AttackParticlePipelineStates?
    var colorFeedback: ColorFeedbackPipelineStates?
    var prism: PrismPipelineStates?
    var tunnel: TunnelPipelineStates?
    var fractal: FractalPipelineStates?
    var riemann: RiemannPipelineStates?
}

private struct SpectralRenderTargets {
    var width: Int
    var height: Int
    var ringField: MTLTexture
    var lensField: MTLTexture
    var shimmerField: MTLTexture
}

private struct AttackParticleRenderTargets {
    var width: Int
    var height: Int
    var particleField: MTLTexture
    var trailField: MTLTexture
}

private struct ColorFeedbackRenderTargets {
    var width: Int
    var height: Int
    var contourField: MTLTexture
    var feedbackA: MTLTexture
    var feedbackB: MTLTexture
    var useAAsHistory: Bool
}

private struct PrismRenderTargets {
    var width: Int
    var height: Int
    var facetField: MTLTexture
    var dispersionField: MTLTexture
    var accentField: MTLTexture
}

private struct TunnelRenderTargets {
    var width: Int
    var height: Int
    var field: MTLTexture
    var shapes: MTLTexture
}

private struct FractalRenderTargets {
    var width: Int
    var height: Int
    var field: MTLTexture
    var accents: MTLTexture
}

private struct RiemannRenderTargets {
    var width: Int
    var height: Int
    var field: MTLTexture
    var accents: MTLTexture
}

private struct SpectralQualityProfile {
    var activeRingLimit: Int
    var shimmerSampleCount: UInt32

    static let cinematicHeavy = SpectralQualityProfile(activeRingLimit: 48, shimmerSampleCount: 12)

    mutating func degrade() -> Bool {
        if activeRingLimit > 32 {
            activeRingLimit = 32
            shimmerSampleCount = 8
            return true
        }
        if activeRingLimit > 24 {
            activeRingLimit = 24
            shimmerSampleCount = 6
            return true
        }
        return false
    }
}

private struct AttackParticleQualityProfile {
    var activeParticleLimit: Int
    var trailSampleCount: UInt32

    static let cinematicHeavy = AttackParticleQualityProfile(activeParticleLimit: 128, trailSampleCount: 11)

    mutating func degrade() -> Bool {
        if activeParticleLimit > 96 {
            activeParticleLimit = 96
            trailSampleCount = 8
            return true
        }
        if activeParticleLimit > 72 {
            activeParticleLimit = 72
            trailSampleCount = 6
            return true
        }
        return false
    }
}

private struct PrismQualityProfile {
    var activeImpulseLimit: Int
    var facetSampleCount: UInt32
    var dispersionSampleCount: UInt32

    static let cinematicHeavy = PrismQualityProfile(
        activeImpulseLimit: 32,
        facetSampleCount: 12,
        dispersionSampleCount: 10
    )

    mutating func degrade() -> Bool {
        if activeImpulseLimit > 24 {
            activeImpulseLimit = 24
            facetSampleCount = 9
            dispersionSampleCount = 7
            return true
        }
        if activeImpulseLimit > 16 {
            activeImpulseLimit = 16
            facetSampleCount = 7
            dispersionSampleCount = 5
            return true
        }
        return false
    }
}

private struct TunnelQualityProfile {
    var activeShapeLimit: Int
    var trailSampleCount: UInt32
    var dispersionSampleCount: UInt32

    static let cinematicHeavy = TunnelQualityProfile(
        activeShapeLimit: 64,
        trailSampleCount: 9,
        dispersionSampleCount: 8
    )

    mutating func degrade() -> Bool {
        if activeShapeLimit > 48 {
            activeShapeLimit = 48
            trailSampleCount = 7
            dispersionSampleCount = 6
            return true
        }
        if activeShapeLimit > 32 {
            activeShapeLimit = 32
            trailSampleCount = 5
            dispersionSampleCount = 4
            return true
        }
        return false
    }
}

private struct FractalQualityProfile {
    var activePulseLimit: Int
    var orbitSampleCount: UInt32
    var trapSampleCount: UInt32

    static let cinematicHeavy = FractalQualityProfile(
        activePulseLimit: 32,
        orbitSampleCount: 42,
        trapSampleCount: 12
    )

    mutating func degrade() -> Bool {
        if activePulseLimit > 24 {
            activePulseLimit = 24
            orbitSampleCount = 34
            trapSampleCount = 9
            return true
        }
        if activePulseLimit > 16 {
            activePulseLimit = 16
            orbitSampleCount = 28
            trapSampleCount = 7
            return true
        }
        return false
    }
}

private struct RiemannQualityProfile {
    var activeAccentLimit: Int
    var termCount: UInt32
    var trapSampleCount: UInt32

    static let cinematicHeavy = RiemannQualityProfile(
        activeAccentLimit: 24,
        termCount: 36,
        trapSampleCount: 12
    )

    mutating func degrade() -> Bool {
        if termCount > 24 {
            termCount = 24
            return true
        }
        if termCount > 14 {
            termCount = 14
            return true
        }
        if trapSampleCount > 8 {
            trapSampleCount = 8
            return true
        }
        if trapSampleCount > 6 {
            trapSampleCount = 6
            return true
        }
        if activeAccentLimit > 16 {
            activeAccentLimit = 16
            return true
        }
        if activeAccentLimit > 10 {
            activeAccentLimit = 10
            return true
        }
        return false
    }
}

private struct SpectralRingGPUData {
    var positionRadiusWidthIntensity: SIMD4<Float>
    var hueDecaySectorActive: SIMD4<Float>

    static let zero = SpectralRingGPUData(
        positionRadiusWidthIntensity: .zero,
        hueDecaySectorActive: .zero
    )
}

private struct AttackParticleGPUData {
    var positionSizeIntensity: SIMD4<Float>
    var velocityHueTrail: SIMD4<Float>

    static let zero = AttackParticleGPUData(
        positionSizeIntensity: .zero,
        velocityHueTrail: .zero
    )
}

private struct PrismImpulseGPUData {
    var positionRadiusIntensity: SIMD4<Float>
    var directionHueDecay: SIMD4<Float>

    static let zero = PrismImpulseGPUData(
        positionRadiusIntensity: .zero,
        directionHueDecay: .zero
    )
}

private struct TunnelShapeGPUData {
    var positionDepthScaleEnvelope: SIMD4<Float>
    var forwardHueVariantSeed: SIMD4<Float>
    var axisDecaySustainRelease: SIMD4<Float>

    static let zero = TunnelShapeGPUData(
        positionDepthScaleEnvelope: .zero,
        forwardHueVariantSeed: .zero,
        axisDecaySustainRelease: .zero
    )
}

private struct FractalPulseGPUData {
    var positionRadiusIntensity: SIMD4<Float>
    var hueDecaySeedSector: SIMD4<Float>

    static let zero = FractalPulseGPUData(
        positionRadiusIntensity: .zero,
        hueDecaySeedSector: .zero
    )
}

private struct RiemannAccentGPUData {
    var positionWidthIntensity: SIMD4<Float>
    var directionLengthHueSeed: SIMD4<Float>
    var decaySeedSectorActive: SIMD4<Float>

    static let zero = RiemannAccentGPUData(
        positionWidthIntensity: .zero,
        directionLengthHueSeed: .zero,
        decaySeedSectorActive: .zero
    )
}

private struct RendererFrameUniforms {
    // Keep this prefix stable for compatibility with fallback radial shader source.
    var time: Float
    var intensity: Float
    var scale: Float
    var motion: Float
    var diffusion: Float
    var blackFloor: Float
    var modeIndex: UInt32
    var padding: UInt32 = 0
    var resolution: SIMD2<Float>
    var centerOffset: SIMD2<Float>

    // Multi-pass effect fields.
    var ringDecay: Float
    var featureAmplitude: Float
    var lowBandEnergy: Float
    var midBandEnergy: Float
    var highBandEnergy: Float
    var attackStrength: Float
    var ringCount: UInt32
    var shimmerSampleCount: UInt32
    var burstDensity: Float
    var trailDecay: Float
    var lensSheen: Float
    var particleCount: UInt32
    var attackTrailSampleCount: UInt32
    var prismFacetDensity: Float
    var prismDispersion: Float
    var prismFacetSampleCount: UInt32
    var prismDispersionSampleCount: UInt32
    var prismImpulseCount: UInt32
    var prismBlackout: UInt32
    var tunnelShapeScale: Float
    var tunnelDepthSpeed: Float
    var tunnelReleaseTail: Float
    var tunnelVariant: UInt32
    var tunnelShapeCount: UInt32
    var tunnelTrailSampleCount: UInt32
    var tunnelDispersionSampleCount: UInt32
    var tunnelBlackout: UInt32
    var fractalDetail: Float
    var fractalFlowRate: Float
    var fractalAttackBloom: Float
    var fractalPaletteVariant: UInt32
    var fractalOrbitSampleCount: UInt32
    var fractalTrapSampleCount: UInt32
    var fractalPulseCount: UInt32
    var fractalBlackout: UInt32
    var fractalFlowPhase: Float
    var riemannDetail: Float
    var riemannFlowRate: Float
    var riemannZeroBloom: Float
    var riemannPaletteVariant: UInt32
    var riemannTermCount: UInt32
    var riemannTrapSampleCount: UInt32
    var riemannAccentCount: UInt32
    var riemannBlackout: UInt32
    var riemannFlowPhase: Float
    var riemannCameraCenter: SIMD2<Float>
    var riemannCameraZoom: Float
    var riemannCameraHeading: Float
    var fractalPadding0: UInt32 = 0
    var fractalPadding1: UInt32 = 0
    var fractalPadding2: UInt32 = 0
    var noImageInSilence: UInt32
    var colorShiftHue: Float
    var colorShiftSaturation: Float
    var colorShiftBlackout: UInt32
    var pitchConfidence: Float
    var stablePitchClass: Int32
    var stablePitchCents: Float
    var padding1: UInt32 = 0
    var attackIDLow: UInt32
    var attackIDHigh: UInt32
    var padding2: UInt32 = 0
    var padding3: UInt32 = 0
}

private enum RendererBuildError: LocalizedError {
    case missingShaderLibrary
    case missingVertexFunction
    case missingFragmentFunction(String)

    var errorDescription: String? {
        switch self {
        case .missingShaderLibrary:
            return "Default Metal shader library is missing."
        case .missingVertexFunction:
            return "Vertex function renderer_fullscreen_vertex was not found."
        case .missingFragmentFunction(let functionName):
            return "Fragment function \(functionName) was not found."
        }
    }
}

public struct SpectralRingEvent: Equatable {
    public var attackID: UInt64
    public var birthTime: Float
    public var center: SIMD2<Float>
    public var baseRadius: Float
    public var width: Float
    public var intensity: Float
    public var hueShift: Float
    public var decay: Float
    public var lifetime: Float
    public var sector: UInt32
    public var sectorWeight: Float
    public var isActive: Bool

    public init(
        attackID: UInt64,
        birthTime: Float,
        center: SIMD2<Float>,
        baseRadius: Float,
        width: Float,
        intensity: Float,
        hueShift: Float,
        decay: Float,
        lifetime: Float,
        sector: UInt32,
        sectorWeight: Float,
        isActive: Bool
    ) {
        self.attackID = attackID
        self.birthTime = birthTime
        self.center = center
        self.baseRadius = baseRadius
        self.width = width
        self.intensity = intensity
        self.hueShift = hueShift
        self.decay = decay
        self.lifetime = lifetime
        self.sector = sector
        self.sectorWeight = sectorWeight
        self.isActive = isActive
    }

    public static let inactive = SpectralRingEvent(
        attackID: 0,
        birthTime: 0,
        center: .zero,
        baseRadius: 0,
        width: 0,
        intensity: 0,
        hueShift: 0,
        decay: 0,
        lifetime: 0,
        sector: 0,
        sectorWeight: 0,
        isActive: false
    )
}

public struct SpectralRingPool {
    public private(set) var capacity: Int
    public internal(set) var events: [SpectralRingEvent]
    public private(set) var insertionCursor: Int
    public private(set) var lastAttackID: UInt64

    public init(capacity: Int = 48) {
        let resolvedCapacity = max(1, capacity)
        self.capacity = resolvedCapacity
        self.events = [SpectralRingEvent](repeating: .inactive, count: resolvedCapacity)
        self.insertionCursor = 0
        self.lastAttackID = 0
    }

    @discardableResult
    public mutating func insertIfNewAttack(attackID: UInt64, makeEvent: () -> SpectralRingEvent) -> Bool {
        guard attackID > 0, attackID != lastAttackID else {
            return false
        }

        lastAttackID = attackID
        var event = makeEvent()
        event.isActive = true
        events[insertionCursor] = event
        insertionCursor = (insertionCursor + 1) % capacity
        return true
    }
}

public struct AttackParticleEvent: Equatable {
    public var attackID: UInt64
    public var birthTime: Float
    public var origin: SIMD2<Float>
    public var velocity: SIMD2<Float>
    public var size: Float
    public var intensity: Float
    public var hueShift: Float
    public var trailDecay: Float
    public var lifetime: Float
    public var sector: UInt32
    public var isActive: Bool

    public init(
        attackID: UInt64,
        birthTime: Float,
        origin: SIMD2<Float>,
        velocity: SIMD2<Float>,
        size: Float,
        intensity: Float,
        hueShift: Float,
        trailDecay: Float,
        lifetime: Float,
        sector: UInt32,
        isActive: Bool
    ) {
        self.attackID = attackID
        self.birthTime = birthTime
        self.origin = origin
        self.velocity = velocity
        self.size = size
        self.intensity = intensity
        self.hueShift = hueShift
        self.trailDecay = trailDecay
        self.lifetime = lifetime
        self.sector = sector
        self.isActive = isActive
    }

    public static let inactive = AttackParticleEvent(
        attackID: 0,
        birthTime: 0,
        origin: .zero,
        velocity: .zero,
        size: 0,
        intensity: 0,
        hueShift: 0,
        trailDecay: 0,
        lifetime: 0,
        sector: 0,
        isActive: false
    )
}

public struct AttackParticlePool {
    public private(set) var capacity: Int
    public internal(set) var events: [AttackParticleEvent]
    public private(set) var insertionCursor: Int
    public private(set) var lastAttackID: UInt64

    public init(capacity: Int = 128) {
        let resolvedCapacity = max(1, capacity)
        self.capacity = resolvedCapacity
        self.events = [AttackParticleEvent](repeating: .inactive, count: resolvedCapacity)
        self.insertionCursor = 0
        self.lastAttackID = 0
    }

    @discardableResult
    public mutating func insertBurstIfNewAttack(
        attackID: UInt64,
        count: Int,
        makeParticle: (_ burstIndex: Int) -> AttackParticleEvent
    ) -> Bool {
        guard attackID > 0, attackID != lastAttackID else {
            return false
        }

        lastAttackID = attackID
        let resolvedCount = max(1, count)
        for burstIndex in 0 ..< resolvedCount {
            var particle = makeParticle(burstIndex)
            particle.isActive = true
            events[insertionCursor] = particle
            insertionCursor = (insertionCursor + 1) % capacity
        }
        return true
    }
}

public struct PrismImpulseEvent: Equatable {
    public var attackID: UInt64
    public var birthTime: Float
    public var origin: SIMD2<Float>
    public var direction: SIMD2<Float>
    public var width: Float
    public var intensity: Float
    public var decay: Float
    public var lifetime: Float
    public var hueShift: Float
    public var sector: UInt32
    public var isActive: Bool

    public init(
        attackID: UInt64,
        birthTime: Float,
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        width: Float,
        intensity: Float,
        decay: Float,
        lifetime: Float,
        hueShift: Float,
        sector: UInt32,
        isActive: Bool
    ) {
        self.attackID = attackID
        self.birthTime = birthTime
        self.origin = origin
        self.direction = direction
        self.width = width
        self.intensity = intensity
        self.decay = decay
        self.lifetime = lifetime
        self.hueShift = hueShift
        self.sector = sector
        self.isActive = isActive
    }

    public static let inactive = PrismImpulseEvent(
        attackID: 0,
        birthTime: 0,
        origin: .zero,
        direction: SIMD2<Float>(0, 1),
        width: 0,
        intensity: 0,
        decay: 0,
        lifetime: 0,
        hueShift: 0,
        sector: 0,
        isActive: false
    )
}

public struct PrismImpulsePool {
    public private(set) var capacity: Int
    public internal(set) var events: [PrismImpulseEvent]
    public private(set) var insertionCursor: Int
    public private(set) var lastAttackID: UInt64

    public init(capacity: Int = 32) {
        let resolvedCapacity = max(1, capacity)
        self.capacity = resolvedCapacity
        self.events = [PrismImpulseEvent](repeating: .inactive, count: resolvedCapacity)
        self.insertionCursor = 0
        self.lastAttackID = 0
    }

    @discardableResult
    public mutating func insertIfNewAttack(attackID: UInt64, makeEvent: () -> PrismImpulseEvent) -> Bool {
        guard attackID > 0, attackID != lastAttackID else {
            return false
        }

        lastAttackID = attackID
        var event = makeEvent()
        event.isActive = true
        events[insertionCursor] = event
        insertionCursor = (insertionCursor + 1) % capacity
        return true
    }
}

public struct TunnelShapeEvent: Equatable {
    public var attackID: UInt64
    public var birthTime: Float
    public var laneOrigin: SIMD2<Float>
    public var forwardSpeed: Float
    public var depthOffset: Float
    public var baseScale: Float
    public var hueShift: Float
    public var sustainLevel: Float
    public var decayShape: Float
    public var releaseDuration: Float
    public var axisSeed: SIMD2<Float>
    public var variant: UInt32
    public var lastAboveTimestamp: Float
    public var releaseStartTimestamp: Float
    public var isActive: Bool

    public init(
        attackID: UInt64,
        birthTime: Float,
        laneOrigin: SIMD2<Float>,
        forwardSpeed: Float,
        depthOffset: Float,
        baseScale: Float,
        hueShift: Float,
        sustainLevel: Float,
        decayShape: Float,
        releaseDuration: Float,
        axisSeed: SIMD2<Float>,
        variant: UInt32,
        lastAboveTimestamp: Float,
        releaseStartTimestamp: Float,
        isActive: Bool
    ) {
        self.attackID = attackID
        self.birthTime = birthTime
        self.laneOrigin = laneOrigin
        self.forwardSpeed = forwardSpeed
        self.depthOffset = depthOffset
        self.baseScale = baseScale
        self.hueShift = hueShift
        self.sustainLevel = sustainLevel
        self.decayShape = decayShape
        self.releaseDuration = releaseDuration
        self.axisSeed = axisSeed
        self.variant = variant
        self.lastAboveTimestamp = lastAboveTimestamp
        self.releaseStartTimestamp = releaseStartTimestamp
        self.isActive = isActive
    }

    public static let inactive = TunnelShapeEvent(
        attackID: 0,
        birthTime: 0,
        laneOrigin: .zero,
        forwardSpeed: 0,
        depthOffset: 0,
        baseScale: 0,
        hueShift: 0,
        sustainLevel: 0,
        decayShape: 0,
        releaseDuration: 0,
        axisSeed: .zero,
        variant: 0,
        lastAboveTimestamp: 0,
        releaseStartTimestamp: -1,
        isActive: false
    )
}

public struct TunnelShapePool {
    public private(set) var capacity: Int
    public internal(set) var events: [TunnelShapeEvent]
    public private(set) var insertionCursor: Int
    public private(set) var lastAttackID: UInt64

    public init(capacity: Int = 64) {
        let resolvedCapacity = max(1, capacity)
        self.capacity = resolvedCapacity
        self.events = [TunnelShapeEvent](repeating: .inactive, count: resolvedCapacity)
        self.insertionCursor = 0
        self.lastAttackID = 0
    }

    @discardableResult
    public mutating func insertIfNewAttack(attackID: UInt64, makeEvent: () -> TunnelShapeEvent) -> Bool {
        guard attackID > 0, attackID != lastAttackID else {
            return false
        }

        lastAttackID = attackID
        var event = makeEvent()
        event.isActive = true
        events[insertionCursor] = event
        insertionCursor = (insertionCursor + 1) % capacity
        return true
    }
}

public struct FractalPulseEvent: Equatable {
    public var attackID: UInt64
    public var birthTime: Float
    public var origin: SIMD2<Float>
    public var baseRadius: Float
    public var intensity: Float
    public var decay: Float
    public var lifetime: Float
    public var hueShift: Float
    public var seed: Float
    public var sector: UInt32
    public var isActive: Bool

    public init(
        attackID: UInt64,
        birthTime: Float,
        origin: SIMD2<Float>,
        baseRadius: Float,
        intensity: Float,
        decay: Float,
        lifetime: Float,
        hueShift: Float,
        seed: Float,
        sector: UInt32,
        isActive: Bool
    ) {
        self.attackID = attackID
        self.birthTime = birthTime
        self.origin = origin
        self.baseRadius = baseRadius
        self.intensity = intensity
        self.decay = decay
        self.lifetime = lifetime
        self.hueShift = hueShift
        self.seed = seed
        self.sector = sector
        self.isActive = isActive
    }

    public static let inactive = FractalPulseEvent(
        attackID: 0,
        birthTime: 0,
        origin: .zero,
        baseRadius: 0,
        intensity: 0,
        decay: 0,
        lifetime: 0,
        hueShift: 0,
        seed: 0,
        sector: 0,
        isActive: false
    )
}

public struct FractalPulsePool {
    public private(set) var capacity: Int
    public internal(set) var events: [FractalPulseEvent]
    public private(set) var insertionCursor: Int
    public private(set) var lastAttackID: UInt64

    public init(capacity: Int = 32) {
        let resolvedCapacity = max(1, capacity)
        self.capacity = resolvedCapacity
        self.events = [FractalPulseEvent](repeating: .inactive, count: resolvedCapacity)
        self.insertionCursor = 0
        self.lastAttackID = 0
    }

    @discardableResult
    public mutating func insertIfNewAttack(attackID: UInt64, makeEvent: () -> FractalPulseEvent) -> Bool {
        guard attackID > 0, attackID != lastAttackID else {
            return false
        }

        lastAttackID = attackID
        var event = makeEvent()
        event.isActive = true
        events[insertionCursor] = event
        insertionCursor = (insertionCursor + 1) % capacity
        return true
    }
}

public struct RiemannAccentEvent: Equatable {
    public var attackID: UInt64
    public var birthTime: Float
    public var origin: SIMD2<Float>
    public var direction: SIMD2<Float>
    public var width: Float
    public var length: Float
    public var intensity: Float
    public var decay: Float
    public var lifetime: Float
    public var hueShift: Float
    public var seed: Float
    public var sector: UInt32
    public var isActive: Bool

    public init(
        attackID: UInt64,
        birthTime: Float,
        origin: SIMD2<Float>,
        direction: SIMD2<Float>,
        width: Float,
        length: Float,
        intensity: Float,
        decay: Float,
        lifetime: Float,
        hueShift: Float,
        seed: Float,
        sector: UInt32,
        isActive: Bool
    ) {
        self.attackID = attackID
        self.birthTime = birthTime
        self.origin = origin
        self.direction = direction
        self.width = width
        self.length = length
        self.intensity = intensity
        self.decay = decay
        self.lifetime = lifetime
        self.hueShift = hueShift
        self.seed = seed
        self.sector = sector
        self.isActive = isActive
    }

    public static let inactive = RiemannAccentEvent(
        attackID: 0,
        birthTime: 0,
        origin: .zero,
        direction: .zero,
        width: 0,
        length: 0,
        intensity: 0,
        decay: 0,
        lifetime: 0,
        hueShift: 0,
        seed: 0,
        sector: 0,
        isActive: false
    )
}

public struct RiemannAccentPool {
    public private(set) var capacity: Int
    public internal(set) var events: [RiemannAccentEvent]
    public private(set) var insertionCursor: Int
    public private(set) var lastAttackID: UInt64

    public init(capacity: Int = 24) {
        let resolvedCapacity = max(1, capacity)
        self.capacity = resolvedCapacity
        self.events = [RiemannAccentEvent](repeating: .inactive, count: resolvedCapacity)
        self.insertionCursor = 0
        self.lastAttackID = 0
    }

    @discardableResult
    public mutating func insertIfNewAttack(attackID: UInt64, makeEvent: () -> RiemannAccentEvent) -> Bool {
        guard attackID > 0, attackID != lastAttackID else {
            return false
        }

        lastAttackID = attackID
        var event = makeEvent()
        event.isActive = true
        events[insertionCursor] = event
        insertionCursor = (insertionCursor + 1) % capacity
        return true
    }
}

public func spectralBloomSectorIndex(
    attackID: UInt64,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    sectorCount: Int = 12
) -> Int {
    let sectorCount = max(1, sectorCount)
    let dominantBand: Int
    if lowBandEnergy >= midBandEnergy && lowBandEnergy >= highBandEnergy {
        dominantBand = 0
    } else if midBandEnergy >= highBandEnergy {
        dominantBand = 1
    } else {
        dominantBand = 2
    }

    let sectorsPerBand = max(1, sectorCount / 3)
    let base = dominantBand * sectorsPerBand
    let jitter = Int(spectralHash(attackID) % UInt64(sectorsPerBand))
    return (base + jitter) % sectorCount
}

public func prismFieldSectorIndex(
    attackID: UInt64,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    sectorCount: Int = 12
) -> Int {
    spectralBloomSectorIndex(
        attackID: attackID ^ 0xC2B2_AE3D_27D4_EB4F,
        lowBandEnergy: lowBandEnergy,
        midBandEnergy: midBandEnergy,
        highBandEnergy: highBandEnergy,
        sectorCount: sectorCount
    )
}

public func attackParticleSectorIndex(
    attackID: UInt64,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    sectorCount: Int = 12
) -> Int {
    spectralBloomSectorIndex(
        attackID: attackID ^ 0xA076_1D64_78BD_642F,
        lowBandEnergy: lowBandEnergy,
        midBandEnergy: midBandEnergy,
        highBandEnergy: highBandEnergy,
        sectorCount: sectorCount
    )
}

public func tunnelCelsSectorIndex(
    attackID: UInt64,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    sectorCount: Int = 12
) -> Int {
    spectralBloomSectorIndex(
        attackID: attackID ^ 0x8D58_AC26_A7F4_09D3,
        lowBandEnergy: lowBandEnergy,
        midBandEnergy: midBandEnergy,
        highBandEnergy: highBandEnergy,
        sectorCount: sectorCount
    )
}

public func fractalCausticsSectorIndex(
    attackID: UInt64,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    sectorCount: Int = 12
) -> Int {
    spectralBloomSectorIndex(
        attackID: attackID ^ 0x9DDC_4EEB_8A28_5C31,
        lowBandEnergy: lowBandEnergy,
        midBandEnergy: midBandEnergy,
        highBandEnergy: highBandEnergy,
        sectorCount: sectorCount
    )
}

public func riemannCorridorSectorIndex(
    attackID: UInt64,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    sectorCount: Int = 12
) -> Int {
    spectralBloomSectorIndex(
        attackID: attackID ^ 0x1F17_8DF1_2287_40E5,
        lowBandEnergy: lowBandEnergy,
        midBandEnergy: midBandEnergy,
        highBandEnergy: highBandEnergy,
        sectorCount: sectorCount
    )
}

private func spectralHash(_ value: UInt64) -> UInt64 {
    var x = value &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    return x ^ (x >> 31)
}

private func spectralHash01(_ value: UInt64) -> Float {
    let hash = spectralHash(value)
    let masked = UInt32(truncatingIfNeeded: hash & 0xFFFF_FFFF)
    return Float(masked) / Float(UInt32.max)
}

public enum RendererPassSelection: Equatable {
    case colorFeedback
    case prism
    case tunnel
    case fractal
    case riemann
    case radial
}

public func rendererPassSelection(
    modeID: VisualModeID,
    colorFeedbackEnabled: Bool,
    hasColorFeedbackPipeline: Bool,
    hasPrismPipeline: Bool,
    hasTunnelPipeline: Bool,
    hasFractalPipeline: Bool,
    hasRiemannPipeline: Bool,
    hasCameraFeedbackFrame: Bool,
    radialFallbackActive: Bool
) -> RendererPassSelection {
    if radialFallbackActive {
        return .radial
    }

    if modeID == .colorShift,
       colorFeedbackEnabled,
       hasColorFeedbackPipeline,
       hasCameraFeedbackFrame {
        return .colorFeedback
    }

    if modeID == .prismField, hasPrismPipeline {
        return .prism
    }

    if modeID == .tunnelCels, hasTunnelPipeline {
        return .tunnel
    }

    if modeID == .fractalCaustics, hasFractalPipeline {
        return .fractal
    }

    if modeID == .riemannCorridor, hasRiemannPipeline {
        return .riemann
    }

    return .radial
}

private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + ((b - a) * min(max(t, 0), 1))
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

func colorShiftDrive(controls: RendererControlState) -> Float {
    let controls = controls.clamped()
    let weightedBands = Float(
        (controls.lowBandEnergy * 0.24) +
        (controls.midBandEnergy * 0.44) +
        (controls.highBandEnergy * 0.32)
    )
    let weightedSignal =
        Float(controls.featureAmplitude) * 0.42 +
        weightedBands * 0.38 +
        Float(controls.attackStrength) * 0.20
    let controlShape =
        mix(0.50, 1.34, Float(controls.motion)) *
        mix(0.42, 1.16, Float(controls.scale)) *
        mix(0.55, 1.05, Float(min(max(controls.intensity / 1.5, 0), 1))) *
        mix(0.75, 1.05, 1 - Float(controls.diffusion))
    return min(max(weightedSignal * controlShape, 0), 1)
}

private func wrappedHue(_ value: Float) -> Float {
    value - floor(value)
}

private func shortestHueDelta(from: Float, to: Float) -> Float {
    var delta = to - from
    if delta > 0.5 {
        delta -= 1
    } else if delta < -0.5 {
        delta += 1
    }
    return delta
}

private func hueLerp(from: Float, to: Float, t: Float) -> Float {
    let clampedT = min(max(t, 0), 1)
    return wrappedHue(from + (shortestHueDelta(from: from, to: to) * clampedT))
}

private func colorShiftSpectralFallbackHue(controls: RendererControlState, currentHue: Float) -> Float {
    let low = Float(controls.lowBandEnergy)
    let mid = Float(controls.midBandEnergy)
    let high = Float(controls.highBandEnergy)
    let sum = max(low + mid + high, 0.0001)
    let lowMix = low / sum
    let midMix = mid / sum
    let highMix = high / sum

    let spectralHue = wrappedHue(
        (lowMix * 0.04) +
        (midMix * 0.37) +
        (highMix * 0.72) +
        (Float(controls.attackStrength) * 0.06)
    )
    let liveEnergy = colorShiftDrive(controls: controls)
    let steer = mix(0.02, 0.20, Float(controls.motion)) * min(max(liveEnergy * 1.35, 0), 1)
    return hueLerp(from: currentHue, to: spectralHue, t: steer)
}

func colorShiftHueTarget(
    currentHue: Float,
    controls: RendererControlState,
    activityThreshold: Float = 0.08
) -> Float {
    if let stablePitchClass = controls.stablePitchClass {
        let baseHue = wrappedHue(Float(stablePitchClass) / 12.0)
        let cents = Float(controls.stablePitchCents).clamped(to: -50 ... 50) / 50.0
        let glideWidth = mix(0.02, 0.18, Float(controls.scale))
        return wrappedHue(baseHue + (cents * glideWidth))
    }

    let drive = colorShiftDrive(controls: controls)
    if drive > activityThreshold {
        return colorShiftSpectralFallbackHue(controls: controls, currentHue: currentHue)
    }

    return currentHue
}

func advanceColorShiftHuePhase(
    currentHue: Float,
    deltaTime: Float,
    controls: RendererControlState,
    activityThreshold: Float = 0.08
) -> Float {
    guard deltaTime > 0 else { return currentHue }
    let targetHue = colorShiftHueTarget(currentHue: currentHue, controls: controls, activityThreshold: activityThreshold)

    let followRate =
        mix(1.6, 10.4, Float(controls.motion)) *
        mix(0.52, 1.42, Float(controls.scale)) *
        mix(0.62, 1.10, Float(min(max(controls.intensity / 1.5, 0), 1)))
    let smoothing = 1 - exp(-(followRate * deltaTime))
    return hueLerp(from: currentHue, to: targetHue, t: smoothing)
}

func colorShiftSaturationValue(controls: RendererControlState) -> Float {
    let drive = colorShiftDrive(controls: controls)
    let confidence = Float(controls.pitchConfidence).clamped(to: 0 ... 1)
    let responseShape = mix(0.50, 1.15, Float(controls.motion))
    let rangeShape = mix(0.55, 1.10, Float(controls.scale))
    let saturation = 0.30 + ((drive * 0.40 * responseShape) + (confidence * 0.34 * rangeShape))
    return saturation.clamped(to: 0.22 ... 0.98)
}

func shouldBlackoutColorShift(
    noImageInSilence: Bool,
    featureAmplitude: Double,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    silenceThreshold: Double = 0.03
) -> Bool {
    guard noImageInSilence else { return false }

    let maxBand = max(lowBandEnergy, max(midBandEnergy, highBandEnergy))
    let weightedLiveEnergy = (featureAmplitude * 0.6) + (maxBand * 0.4)
    return weightedLiveEnergy < silenceThreshold
}

func shouldBlackoutPrism(
    noImageInSilence: Bool,
    featureAmplitude: Double,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    silenceThreshold: Double = 0.03
) -> Bool {
    guard noImageInSilence else { return false }

    let maxBand = max(lowBandEnergy, max(midBandEnergy, highBandEnergy))
    let weightedLiveEnergy = (featureAmplitude * 0.6) + (maxBand * 0.4)
    return weightedLiveEnergy < silenceThreshold
}

func shouldBlackoutTunnel(
    noImageInSilence: Bool,
    featureAmplitude: Double,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    silenceThreshold: Double = 0.03
) -> Bool {
    guard noImageInSilence else { return false }

    let maxBand = max(lowBandEnergy, max(midBandEnergy, highBandEnergy))
    let weightedLiveEnergy = (featureAmplitude * 0.6) + (maxBand * 0.4)
    return weightedLiveEnergy < silenceThreshold
}

func shouldBlackoutFractal(
    noImageInSilence: Bool,
    featureAmplitude: Double,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    silenceThreshold: Double = 0.03
) -> Bool {
    guard noImageInSilence else { return false }

    let maxBand = max(lowBandEnergy, max(midBandEnergy, highBandEnergy))
    let weightedLiveEnergy = (featureAmplitude * 0.6) + (maxBand * 0.4)
    return weightedLiveEnergy < silenceThreshold
}

func shouldBlackoutRiemann(
    noImageInSilence: Bool,
    featureAmplitude: Double,
    lowBandEnergy: Double,
    midBandEnergy: Double,
    highBandEnergy: Double,
    silenceThreshold: Double = 0.03
) -> Bool {
    guard noImageInSilence else { return false }

    let maxBand = max(lowBandEnergy, max(midBandEnergy, highBandEnergy))
    let weightedLiveEnergy = (featureAmplitude * 0.6) + (maxBand * 0.4)
    return weightedLiveEnergy < silenceThreshold
}

func fractalFlowPhaseAdvance(
    currentPhase: Float,
    deltaTime: Float,
    controls: RendererControlState
) -> Float {
    guard deltaTime > 0 else { return currentPhase }
    let controls = controls.clamped()
    let weightedBands = Float(
        (controls.lowBandEnergy * 0.28) +
        (controls.midBandEnergy * 0.40) +
        (controls.highBandEnergy * 0.32)
    )
    let weightedSignal =
        Float(controls.featureAmplitude) * 0.52 +
        weightedBands * 0.36 +
        Float(controls.attackStrength) * 0.12
    let flowRate = Float(controls.fractalFlowRate)
    let attackBloom = Float(controls.fractalAttackBloom)
    let pitchConfidence = Float(controls.pitchConfidence).clamped(to: 0 ... 1)
    let pitchPhase: Float
    if let pitchClass = controls.stablePitchClass, pitchConfidence >= 0.6 {
        let classPhase = Float(min(max(pitchClass, 0), 11)) / 12.0
        let cents = (Float(controls.stablePitchCents).clamped(to: -50 ... 50)) / 50.0
        pitchPhase = classPhase + (cents * 0.08)
    } else {
        pitchPhase = 0
    }

    let flowStep = deltaTime * (0.04 + (flowRate * 1.62)) * (0.32 + (min(max(weightedSignal, 0), 1) * 1.20))
    let attackStep = deltaTime * Float(controls.attackStrength) * (0.12 + (attackBloom * 0.48))
    let pitchStep = deltaTime * pitchConfidence * pitchPhase * 0.16
    let next = currentPhase + flowStep + attackStep + pitchStep
    return next - floor(next)
}

func riemannFlowPhaseAdvance(
    currentPhase: Float,
    deltaTime: Float,
    controls: RendererControlState
) -> Float {
    guard deltaTime > 0 else { return currentPhase }
    let controls = controls.clamped()
    let weightedBands = Float(
        (controls.lowBandEnergy * 0.32) +
        (controls.midBandEnergy * 0.40) +
        (controls.highBandEnergy * 0.28)
    )
    let weightedSignal =
        Float(controls.featureAmplitude) * 0.50 +
        weightedBands * 0.40 +
        Float(controls.attackStrength) * 0.10
    let flowRate = Float(controls.riemannFlowRate)
    let detail = Float(controls.riemannDetail)
    let zeroBloom = Float(controls.riemannZeroBloom)

    let pitchPhase: Float
    if let pitchClass = controls.stablePitchClass, Float(controls.pitchConfidence) >= 0.6 {
        let classPhase = Float(min(max(pitchClass, 0), 11)) / 12.0
        let cents = (Float(controls.stablePitchCents).clamped(to: -50 ... 50)) / 50.0
        pitchPhase = classPhase + (cents * 0.08)
    } else {
        pitchPhase = 0
    }

    let flowStep = deltaTime * (0.03 + (flowRate * 1.52)) * (0.30 + (min(max(weightedSignal, 0), 1) * 1.24))
    let detailStep = deltaTime * detail * 0.22
    let bloomStep = deltaTime * Float(controls.attackStrength) * (0.10 + (zeroBloom * 0.44))
    let pitchStep = deltaTime * Float(controls.pitchConfidence).clamped(to: 0 ... 1) * pitchPhase * 0.14
    let next = currentPhase + flowStep + detailStep + bloomStep + pitchStep
    return next - floor(next)
}

private func riemannWeightedTraversalIntensity(controls: RendererControlState) -> Float {
    let controls = controls.clamped()
    let low = Float(controls.lowBandEnergy)
    let mid = Float(controls.midBandEnergy)
    let high = Float(controls.highBandEnergy)
    let amplitude = Float(controls.featureAmplitude)
    let attack = Float(controls.attackStrength)
    let maxBand = max(low, max(mid, high))
    return min(max((amplitude * 0.58) + (maxBand * 0.30) + (attack * 0.12), 0), 1)
}

private func riemannSteeringVector(controls: RendererControlState) -> SIMD2<Float> {
    let controls = controls.clamped()
    let low = Float(controls.lowBandEnergy)
    let mid = Float(controls.midBandEnergy)
    let high = Float(controls.highBandEnergy)
    let amplitude = Float(controls.featureAmplitude)
    let attack = Float(controls.attackStrength)
    let pitchConfidence = Float(controls.pitchConfidence).clamped(to: 0 ... 1)

    let pitchPhase: Float
    if let pitchClass = controls.stablePitchClass, pitchConfidence >= 0.6 {
        let classPhase = Float(min(max(pitchClass, 0), 11)) / 12.0
        let cents = Float(controls.stablePitchCents).clamped(to: -50 ... 50) / 50.0
        pitchPhase = classPhase + (cents * 0.10)
    } else {
        pitchPhase = 0
    }

    let cueX = ((mid - ((low + high) * 0.5)) * 1.55) + (pitchPhase * pitchConfidence * 0.62)
    let cueY = ((high - low) * 1.45) + (attack * 0.72) + (amplitude * 0.22)
    return SIMD2<Float>(cueX, cueY)
}

public func shouldTriggerRiemannRouteHandoff(
    lastAttackID: UInt64,
    newAttackID: UInt64,
    isAttackFrame: Bool,
    lastHandoffTime: CFTimeInterval,
    now: CFTimeInterval,
    cooldown: CFTimeInterval
) -> Bool {
    guard isAttackFrame else { return false }
    guard newAttackID > 0, newAttackID != lastAttackID else { return false }
    return (now - lastHandoffTime) >= max(0, cooldown)
}

public struct MandelbrotEscapeSample: Equatable {
    public let escaped: Bool
    public let smoothIteration: Double
    public let distanceEstimate: Double
    public let boundaryEnergy: Double

    public init(
        escaped: Bool,
        smoothIteration: Double,
        distanceEstimate: Double,
        boundaryEnergy: Double
    ) {
        self.escaped = escaped
        self.smoothIteration = smoothIteration
        self.distanceEstimate = distanceEstimate
        self.boundaryEnergy = boundaryEnergy
    }
}

public func mandelbrotEscapeSample(
    real: Double,
    imag: Double,
    maxIterations: Int
) -> MandelbrotEscapeSample {
    let iterationLimit = min(max(maxIterations, 8), 1_024)
    let c = SIMD2<Double>(real, imag)
    var z = SIMD2<Double>(0, 0)
    var dz = SIMD2<Double>(0, 0)
    var escaped = false
    var escapeIter = iterationLimit
    var escapeMag2 = 0.0

    for index in 0 ..< iterationLimit {
        let zPrime = SIMD2<Double>(
            (2 * z.x * dz.x) - (2 * z.y * dz.y) + 1,
            (2 * z.x * dz.y) + (2 * z.y * dz.x)
        )
        dz = zPrime
        let x = (z.x * z.x) - (z.y * z.y) + c.x
        let y = (2 * z.x * z.y) + c.y
        z = SIMD2<Double>(x, y)
        let mag2 = (z.x * z.x) + (z.y * z.y)
        if mag2 > 256 {
            escaped = true
            escapeIter = index
            escapeMag2 = mag2
            break
        }
    }

    let smoothIteration: Double
    var distanceEstimate = 0.0
    if escaped {
        let logEscape = Foundation.log(max(escapeMag2, 1.000_001))
        let nu = Foundation.log(max(logEscape / Foundation.log(2), 1e-9)) / Foundation.log(2)
        smoothIteration = Double(escapeIter) + 1 - min(max(nu, 0), 8)
        let mag = Foundation.sqrt(max(escapeMag2, 1e-9))
        let deriv = max(Foundation.hypot(dz.x, dz.y), 1e-9)
        distanceEstimate = (0.5 * Foundation.log(max(mag, 1.000_001)) * mag) / deriv
        if !distanceEstimate.isFinite {
            distanceEstimate = 0
        }
    } else {
        smoothIteration = Double(iterationLimit)
    }

    let boundaryEnergy: Double
    if escaped {
        boundaryEnergy = min(max(Foundation.exp(-distanceEstimate * 26.0), 0), 1)
    } else {
        boundaryEnergy = 0
    }

    return MandelbrotEscapeSample(
        escaped: escaped,
        smoothIteration: smoothIteration,
        distanceEstimate: max(distanceEstimate, 0),
        boundaryEnergy: boundaryEnergy
    )
}

public func mandelbrotVariantFeatureVector(
    real: Double,
    imag: Double,
    maxIterations: Int,
    flowPhase: Double,
    detail: Double
) -> SIMD4<Double> {
    let sample = mandelbrotEscapeSample(real: real, imag: imag, maxIterations: maxIterations)
    let detail = min(max(detail, 0), 1)
    let phase = Foundation.atan2(imag, real)
    let contour = 1 - abs(Foundation.sin((sample.smoothIteration * (0.06 + detail * 0.05)) + (flowPhase * 9.0)))
    let stream = max(0, Foundation.sin((phase * (3.8 + detail * 2.1)) + (flowPhase * 7.0)) * 0.5 + 0.5)
    let boundary = min(max(Foundation.pow(sample.boundaryEnergy, 0.78), 0), 1)
    let particleHash = Double(
        spectralHash01(
            UInt64(
                bitPattern: Int64((real * 10_000).rounded())
                    ^ Int64((imag * 7_000).rounded())
            ) ^ 0x9D16_3FA2_46B7_3C59
        )
    )
    let particle = (particleHash > 0.992 ? 1.0 : 0.0) * (0.20 + boundary * 0.80) * (0.30 + contour * 0.70)
    let topology = min(max((contour * 0.66) + (boundary * 0.34), 0), 1)
    return SIMD4<Double>(topology, stream, boundary, particle)
}

public func mandelbrotLocalStructureScore(
    center: SIMD2<Float>,
    zoom: Float,
    detail: Float
) -> Float {
    let clampedDetail = min(max(detail, 0), 1)
    let zoomScale = max(Double(zoom), 0.000_002)
    let zoomBoost = min(max(-Foundation.log2(zoomScale), 0), 28)
    let iterBudget = Int(mix(72, 220, clampedDetail) + Float(zoomBoost) * (18 + clampedDetail * 18))
    let sampleOffset = Double(max(zoom, 0.000_006) * 0.020)

    let centerSample = mandelbrotEscapeSample(
        real: Double(center.x),
        imag: Double(center.y),
        maxIterations: iterBudget
    )
    let xNeighbor = mandelbrotEscapeSample(
        real: Double(center.x) + sampleOffset,
        imag: Double(center.y),
        maxIterations: iterBudget
    )
    let yNeighbor = mandelbrotEscapeSample(
        real: Double(center.x),
        imag: Double(center.y) + sampleOffset,
        maxIterations: iterBudget
    )
    let metrics = mandelbrotStructureMetrics(
        primary: centerSample,
        xNeighbor: xNeighbor,
        yNeighbor: yNeighbor,
        iterBudget: iterBudget
    )
    return Float(metrics.structure)
}

private func mandelbrotStructureMetrics(
    primary: MandelbrotEscapeSample,
    xNeighbor: MandelbrotEscapeSample,
    yNeighbor: MandelbrotEscapeSample,
    iterBudget: Int
) -> (
    boundary: Double,
    gradient: Double,
    variance: Double,
    escapeRatio: Double,
    crossing: Double,
    structure: Double
) {
    let safeBudget = max(iterBudget, 1)
    let normalizedCenter = min(max(primary.smoothIteration / Double(safeBudget), 0), 1)
    let normalizedX = min(max(xNeighbor.smoothIteration / Double(safeBudget), 0), 1)
    let normalizedY = min(max(yNeighbor.smoothIteration / Double(safeBudget), 0), 1)

    let gradientRaw = abs(primary.smoothIteration - xNeighbor.smoothIteration) + abs(primary.smoothIteration - yNeighbor.smoothIteration)
    let gradient = min(max(gradientRaw / Double(safeBudget), 0), 1)

    let mean = (normalizedCenter + normalizedX + normalizedY) / 3
    let varianceRaw =
        ((normalizedCenter - mean) * (normalizedCenter - mean)) +
        ((normalizedX - mean) * (normalizedX - mean)) +
        ((normalizedY - mean) * (normalizedY - mean))
    let variance = min(max((varianceRaw / 3) * 22.0, 0), 1)

    let boundary = min(max(primary.boundaryEnergy, 0), 1)
    let escapeBand = max(0, 1 - min(abs(normalizedCenter - 0.56) / 0.56, 1))
    let escapedCount =
        (primary.escaped ? 1 : 0) +
        (xNeighbor.escaped ? 1 : 0) +
        (yNeighbor.escaped ? 1 : 0)
    let hasCrossing = escapedCount > 0 && escapedCount < 3
    let neighborSplit = (xNeighbor.escaped != yNeighbor.escaped) ? 1.0 : 0.0
    let centerSplit = ((primary.escaped != xNeighbor.escaped) || (primary.escaped != yNeighbor.escaped)) ? 1.0 : 0.0
    let crossing = hasCrossing ? (0.65 + (neighborSplit * 0.20) + (centerSplit * 0.15)) : 0.0

    var structure =
        (boundary * 0.42) +
        (gradient * 0.18) +
        (variance * 0.16) +
        (escapeBand * 0.04) +
        (crossing * 0.20)

    // Penalize smooth interior and far-exterior plateaus so routing prefers self-similar edge zones.
    if !primary.escaped, gradient < 0.02, variance < 0.06 {
        structure *= 0.32
    } else if primary.escaped, normalizedCenter < 0.05, boundary < 0.08, variance < 0.07 {
        structure *= 0.42
    }
    if !hasCrossing {
        structure *= 0.28
    }

    return (
        boundary: boundary,
        gradient: gradient,
        variance: variance,
        escapeRatio: normalizedCenter,
        crossing: crossing,
        structure: min(max(structure, 0), 1)
    )
}

public func riemannSelectMandelbrotPOITarget(
    center: SIMD2<Float>,
    zoom: Float,
    heading: Float,
    controls: RendererControlState,
    gridSize: Int = 9,
    steeringOverride: SIMD2<Float>? = nil,
    intensityOverride: Float? = nil
) -> (center: SIMD2<Float>, zoom: Float) {
    let controls = controls.clamped()
    let samplesPerAxis = max(5, gridSize | 1)
    let detail = Float(controls.riemannDetail)
    let flow = Float(controls.riemannFlowRate)
    let deepZoomStabilityThreshold: Float = 0.006
    let deepZoomMode = zoom < deepZoomStabilityThreshold
    let zoomScale = max(Double(zoom), 0.000_002)
    let zoomBoost = min(max(-Foundation.log2(zoomScale), 0), 28)
    let iterBudget = Int(mix(72, 220, detail) + Float(zoomBoost) * (18 + detail * 18))
    let steering = steeringOverride ?? riemannSteeringVector(controls: controls)
    let steeringMagnitude = simd_length(steering)
    let steeringUnit = steeringMagnitude > 0.000_1 ? (steering / steeringMagnitude) : SIMD2<Float>(cos(heading), sin(heading))
    let traversalDrive = (intensityOverride ?? riemannWeightedTraversalIntensity(controls: controls)).clamped(to: 0 ... 1)

    var bestScore = -Double.greatestFiniteMagnitude
    var bestCenter = center
    var bestMetrics = (
        boundary: 0.0,
        gradient: 0.0,
        variance: 0.0,
        escapeRatio: 1.0,
        crossing: 0.0,
        structure: 0.0
    )
    let halfWidth = max(zoom, 0.000_006) * 2.95
    let halfHeight = max(zoom, 0.000_006) * 2.10
    let sampleOffset = Double(max(zoom, 0.000_006) * 0.020)

    for row in 0 ..< samplesPerAxis {
        let rowT = (Float(row) / Float(samplesPerAxis - 1)) * 2 - 1
        for column in 0 ..< samplesPerAxis {
            let columnT = (Float(column) / Float(samplesPerAxis - 1)) * 2 - 1
            let local = SIMD2<Float>(columnT, rowT)
            let radial = simd_length(local)
            if radial < 0.08 || radial > 1.35 {
                continue
            }

            let rotated = SIMD2<Float>(
                (local.x * cos(heading)) - (local.y * sin(heading)),
                (local.x * sin(heading)) + (local.y * cos(heading))
            )

            let candidate = SIMD2<Float>(
                center.x + (rotated.x * halfWidth),
                center.y + (rotated.y * halfHeight)
            )

            let primary = mandelbrotEscapeSample(
                real: Double(candidate.x),
                imag: Double(candidate.y),
                maxIterations: iterBudget
            )
            let xNeighbor = mandelbrotEscapeSample(
                real: Double(candidate.x) + sampleOffset,
                imag: Double(candidate.y),
                maxIterations: iterBudget
            )
            let yNeighbor = mandelbrotEscapeSample(
                real: Double(candidate.x),
                imag: Double(candidate.y) + sampleOffset,
                maxIterations: iterBudget
            )
            let metrics = mandelbrotStructureMetrics(
                primary: primary,
                xNeighbor: xNeighbor,
                yNeighbor: yNeighbor,
                iterBudget: iterBudget
            )
            let radialUnit = local / max(radial, 0.000_1)
            let steeringBias = max(0, simd_dot(radialUnit, steeringUnit))
            let attackBias = Double(min(max(controls.attackStrength, 0), 1))
            let escapedBias = primary.escaped ? 0.02 : -0.38
            let fastEscapePenalty = max(0, (0.07 - metrics.escapeRatio) / 0.07) * 0.34
            let minStructure = deepZoomMode ? 0.10 : 0.22
            let minCrossing = deepZoomMode ? 0.22 : 0.55
            let lowStructurePenalty = metrics.structure < minStructure ? (minStructure - metrics.structure) * 1.7 : 0
            let nonCrossPenalty = metrics.crossing < minCrossing ? (minCrossing - metrics.crossing) * 1.8 : 0
            let tieBreaker = Double(
                spectralHash01(
                    controls.attackID
                        ^ (UInt64(row) << 32)
                        ^ (UInt64(column) << 24)
                        ^ 0x5A31_1CF5_0E7A_94B3
                )
            ) * 0.000_1

            let score =
                (metrics.structure * 0.56) +
                (metrics.crossing * 0.98) +
                (Double(steeringBias) * Double(0.06 + (traversalDrive * 0.12))) +
                escapedBias +
                (attackBias * 0.05) +
                (metrics.variance * 0.06) -
                fastEscapePenalty -
                lowStructurePenalty +
                nonCrossPenalty +
                tieBreaker

            if score > bestScore {
                bestScore = score
                bestCenter = candidate
                bestMetrics = metrics
            }
        }
    }

    let attack = Float(controls.attackStrength)
    let zoomFloor: Float = 0.000_000_001 + ((1 - detail) * 0.000_000_004)
    let zoomStep = mix(0.96, 0.82, min(max((detail * 0.52) + (flow * 0.34) + (attack * 0.14), 0), 1))
    var targetZoom = max(zoomFloor, zoom * zoomStep)

    // Recovery: if we drift into deep interior (black region), zoom out and reacquire edge structure.
    let centerSample = mandelbrotEscapeSample(
        real: Double(center.x),
        imag: Double(center.y),
        maxIterations: iterBudget
    )
    let centerXNeighbor = mandelbrotEscapeSample(
        real: Double(center.x) + sampleOffset,
        imag: Double(center.y),
        maxIterations: iterBudget
    )
    let centerYNeighbor = mandelbrotEscapeSample(
        real: Double(center.x),
        imag: Double(center.y) + sampleOffset,
        maxIterations: iterBudget
    )
    let centerMetrics = mandelbrotStructureMetrics(
        primary: centerSample,
        xNeighbor: centerXNeighbor,
        yNeighbor: centerYNeighbor,
        iterBudget: iterBudget
    )
    let centerStructure = Float(centerMetrics.structure)
    let bestStructure = Float(bestMetrics.structure)
    let lowStructure = deepZoomMode
        ? (bestMetrics.structure < 0.10 || bestMetrics.crossing < 0.22)
        : (bestMetrics.structure < 0.24 || bestMetrics.crossing < 0.55)
    let deepInterior =
        !deepZoomMode &&
        zoom < 0.045 &&
        centerMetrics.structure < 0.08 &&
        centerMetrics.gradient < 0.016 &&
        centerMetrics.variance < 0.06 &&
        centerMetrics.crossing < 0.20 &&
        centerMetrics.escapeRatio > 0.985
    if bestStructure > (centerStructure + 0.04) {
        let reacquireZoomOut = 1.02 + min(max(bestStructure - centerStructure, 0), 0.30) * 0.50
        targetZoom = max(targetZoom, min(4.2, zoom * reacquireZoomOut))
    }
    if deepInterior || lowStructure {
        let rescueScale: Float = deepZoomMode ? 1.45 : (deepInterior ? 7.2 : 4.0)
        let rescueHalfWidth = halfWidth * rescueScale
        let rescueHalfHeight = halfHeight * rescueScale
        var rescueBestCenter = bestCenter
        var rescueBestScore = -Double.greatestFiniteMagnitude
        let rescueGrid = 7

        for row in 0 ..< rescueGrid {
            let rowT = (Float(row) / Float(rescueGrid - 1)) * 2 - 1
            for column in 0 ..< rescueGrid {
                let columnT = (Float(column) / Float(rescueGrid - 1)) * 2 - 1
                let local = SIMD2<Float>(columnT, rowT)
                let rotated = SIMD2<Float>(
                    (local.x * cos(heading)) - (local.y * sin(heading)),
                    (local.x * sin(heading)) + (local.y * cos(heading))
                )
                let candidate = SIMD2<Float>(
                    center.x + (rotated.x * rescueHalfWidth),
                    center.y + (rotated.y * rescueHalfHeight)
                )

                let primary = mandelbrotEscapeSample(
                    real: Double(candidate.x),
                    imag: Double(candidate.y),
                    maxIterations: iterBudget
                )
                let xNeighbor = mandelbrotEscapeSample(
                    real: Double(candidate.x) + sampleOffset,
                    imag: Double(candidate.y),
                    maxIterations: iterBudget
                )
                let yNeighbor = mandelbrotEscapeSample(
                    real: Double(candidate.x),
                    imag: Double(candidate.y) + sampleOffset,
                    maxIterations: iterBudget
                )
                let metrics = mandelbrotStructureMetrics(
                    primary: primary,
                    xNeighbor: xNeighbor,
                    yNeighbor: yNeighbor,
                    iterBudget: iterBudget
                )
                let escapedBias = primary.escaped ? 0.04 : -0.42
                let fastEscapePenalty = max(0, (0.07 - metrics.escapeRatio) / 0.07) * 0.36
                let nonCrossPenalty = metrics.crossing < 0.60 ? (0.60 - metrics.crossing) * 2.0 : 0
                let score =
                    (metrics.structure * 0.60) +
                    (metrics.crossing * 1.06) +
                    (metrics.variance * 0.04) +
                    escapedBias -
                    fastEscapePenalty -
                    nonCrossPenalty
                if score > rescueBestScore {
                    rescueBestScore = score
                    rescueBestCenter = candidate
                }
            }
        }

        bestCenter = rescueBestCenter
        if !deepZoomMode {
            let zoomOutFactor: Float = deepInterior ? 1.7 : 1.28
            targetZoom = min(4.2, max(targetZoom, zoom * zoomOutFactor))
        } else {
            targetZoom = min(targetZoom, max(1e-9, zoom * 0.992))
        }

        if !deepZoomMode, rescueBestScore < 0.20 {
            let anchors: [SIMD2<Float>] = [
                SIMD2<Float>(-0.7436439, 0.1318259),
                SIMD2<Float>(-0.7453, 0.1127),
                SIMD2<Float>(-0.12256, 0.74486),
                SIMD2<Float>(-1.25066, 0.02012),
            ]
            var anchorCenter = anchors[0]
            var anchorScore = -Double.greatestFiniteMagnitude
            for (index, anchor) in anchors.enumerated() {
                let toAnchor = anchor - center
                let distance = simd_length(toAnchor)
                let directionToAnchor = distance > 0.000_1 ? (toAnchor / distance) : SIMD2<Float>(0, 0)
                let steerBias = max(0, simd_dot(directionToAnchor, steeringUnit))
                let hash = Double(
                    spectralHash01(
                        controls.attackID
                            ^ (UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
                            ^ 0xC2B2_AE3D_27D4_EB4F
                    )
                ) * 0.01
                let score = (Double(steerBias) * 0.42) - (Double(distance) * 0.28) + hash
                if score > anchorScore {
                    anchorScore = score
                    anchorCenter = anchor
                }
            }
            bestCenter = anchorCenter
            targetZoom = max(targetZoom, 0.44)
        }
    }

    return (bestCenter, targetZoom)
}

func riemannTraversalAdvance(
    center: SIMD2<Float>,
    zoom: Float,
    heading: Float,
    deltaTime: Float,
    controls: RendererControlState,
    steeringOverride: SIMD2<Float>? = nil,
    intensityOverride: Float? = nil
) -> (center: SIMD2<Float>, zoom: Float, heading: Float) {
    guard deltaTime > 0 else { return (center, zoom, heading) }
    let controls = controls.clamped()

    let low = Float(controls.lowBandEnergy)
    let mid = Float(controls.midBandEnergy)
    let high = Float(controls.highBandEnergy)
    let attack = Float(controls.attackStrength)
    let flowRate = Float(controls.riemannFlowRate)
    let detail = Float(controls.riemannDetail)
    let zeroBloom = Float(controls.riemannZeroBloom)
    let rawIntensity = (intensityOverride ?? riemannWeightedTraversalIntensity(controls: controls)).clamped(to: 0 ... 1)
    let activationOn: Float = 0.072
    let activationOff: Float = 0.046
    let drive: Float
    if rawIntensity >= activationOn {
        drive = min(max((rawIntensity - activationOn) / max(1 - activationOn, 0.0001), 0), 1)
    } else if rawIntensity <= activationOff {
        drive = 0
    } else {
        let transition = (rawIntensity - activationOff) / max(activationOn - activationOff, 0.0001)
        drive = min(max(transition * 0.15, 0), 0.15)
    }

    let speedDrive = drive * drive * (3 - (2 * drive))
    let steering = steeringOverride ?? riemannSteeringVector(controls: controls)
    let cueMagnitude = simd_length(steering)
    let cueDeadzone = mix(0.22, 0.05, speedDrive) * mix(1.0, 0.82, flowRate)
    let cueStrength = ((cueMagnitude - cueDeadzone) / max(1 - cueDeadzone, 0.0001)).clamped(to: 0 ... 1)
    let targetHeading = cueStrength > 0.001 ? atan2(steering.y, steering.x) : heading
    let headingDelta = atan2(sin(targetHeading - heading), cos(targetHeading - heading))
    let turnGain = min(max(deltaTime * (1.2 + flowRate * 2.6 + speedDrive * 3.2), 0), 1) * (0.10 + cueStrength * 0.90)
    let maxTurnRate = mix(0.45, 2.90, cueStrength) * mix(0.42, 1.0, flowRate)
    let maxTurnStep = maxTurnRate * deltaTime
    let boundedHeadingDelta = headingDelta.clamped(to: -maxTurnStep ... maxTurnStep)
    let nextHeading = (heading + boundedHeadingDelta * turnGain).remainder(dividingBy: 2 * .pi)

    // Intensity is the dominant speed driver.
    let speedIntensity = pow(speedDrive, 1.05)
    let speed =
        (0.002 + speedIntensity * 2.80) *
        (0.24 + flowRate * 1.18) *
        (0.30 + detail * 0.70)
    let strafe = (((low + high) * 0.5) - mid) * (0.010 + flowRate * 0.06) * (0.30 + cueStrength * 0.70)

    // Continuous zoom with asymptotic floor (no hard wrap/pop).
    let zoomRate =
        (0.04 + speedIntensity * 1.85 + (attack * (0.10 + (zeroBloom * 0.16)))) *
        (0.30 + detail * 0.70) *
        (0.30 + flowRate * 0.88)
    let zoomFloor: Float = 0.000_000_001 + ((1 - detail) * 0.000_000_004)
    let deepZoomStabilityThreshold: Float = 0.006

    let direction = SIMD2<Float>(cos(nextHeading), sin(nextHeading))
    let tangent = SIMD2<Float>(-direction.y, direction.x)
    let clampedZoom = max(zoom, zoomFloor)

    let recoveryIterBudget = Int(mix(72, 200, detail))
    let centerSample = mandelbrotEscapeSample(
        real: Double(center.x),
        imag: Double(center.y),
        maxIterations: recoveryIterBudget
    )
    let recoveryProbeOffset = Double(max(clampedZoom, 0.000_006) * 0.020)
    let centerXNeighbor = mandelbrotEscapeSample(
        real: Double(center.x) + recoveryProbeOffset,
        imag: Double(center.y),
        maxIterations: recoveryIterBudget
    )
    let centerYNeighbor = mandelbrotEscapeSample(
        real: Double(center.x),
        imag: Double(center.y) + recoveryProbeOffset,
        maxIterations: recoveryIterBudget
    )
    let centerMetrics = mandelbrotStructureMetrics(
        primary: centerSample,
        xNeighbor: centerXNeighbor,
        yNeighbor: centerYNeighbor,
        iterBudget: recoveryIterBudget
    )

    var scoutMaxStructure = centerMetrics.structure
    var scoutMaxCrossing = centerMetrics.crossing
    let scoutRadius = Double(max(clampedZoom * 1.6, 0.000_015))
    for index in 0 ..< 8 {
        let angle = (Double(index) / 8.0) * (2.0 * Double.pi)
        let scoutPoint = SIMD2<Double>(
            Double(center.x) + (cos(angle) * scoutRadius),
            Double(center.y) + (sin(angle) * scoutRadius)
        )
        let scoutSample = mandelbrotEscapeSample(
            real: scoutPoint.x,
            imag: scoutPoint.y,
            maxIterations: recoveryIterBudget
        )
        let scoutXNeighbor = mandelbrotEscapeSample(
            real: scoutPoint.x + recoveryProbeOffset,
            imag: scoutPoint.y,
            maxIterations: recoveryIterBudget
        )
        let scoutYNeighbor = mandelbrotEscapeSample(
            real: scoutPoint.x,
            imag: scoutPoint.y + recoveryProbeOffset,
            maxIterations: recoveryIterBudget
        )
        let scoutMetrics = mandelbrotStructureMetrics(
            primary: scoutSample,
            xNeighbor: scoutXNeighbor,
            yNeighbor: scoutYNeighbor,
            iterBudget: recoveryIterBudget
        )
        scoutMaxStructure = max(scoutMaxStructure, scoutMetrics.structure)
        scoutMaxCrossing = max(scoutMaxCrossing, scoutMetrics.crossing)
    }

    let deepZoomMode = clampedZoom < deepZoomStabilityThreshold

    let deepInteriorRecovery =
        !deepZoomMode &&
        clampedZoom < 0.05 &&
        centerMetrics.structure < 0.08 &&
        centerMetrics.gradient < 0.016 &&
        centerMetrics.variance < 0.06 &&
        centerMetrics.crossing < 0.20 &&
        centerMetrics.escapeRatio > 0.985 &&
        scoutMaxStructure < 0.11 &&
        scoutMaxCrossing < 0.28

    let offStructureRecovery =
        !deepInteriorRecovery &&
        !deepZoomMode &&
        (centerMetrics.structure < 0.26 || centerMetrics.crossing < 0.55) &&
        (scoutMaxStructure < 0.34 || scoutMaxCrossing < 0.62)

    let nextZoom: Float
    if deepZoomMode {
        nextZoom = zoomFloor + ((clampedZoom - zoomFloor) * exp(-((zoomRate * 0.55) * deltaTime)))
    } else if deepInteriorRecovery {
        let recoverRate = 1.05 + (flowRate * 0.85)
        nextZoom = min(4.2, clampedZoom * exp(recoverRate * deltaTime))
    } else if offStructureRecovery {
        let recoverRate = 0.26 + (flowRate * 0.34)
        nextZoom = min(4.2, clampedZoom * exp(recoverRate * deltaTime))
    } else {
        nextZoom = zoomFloor + ((clampedZoom - zoomFloor) * exp(-(zoomRate * deltaTime)))
    }

    // Keep movement in fractal-space scale so deep zoom remains stable and self-similar.
    let zoomMovementGain = max(nextZoom * (0.85 + detail * 0.55), 0.000_12)
    let recoveryMotionScale: Float
    if deepZoomMode {
        recoveryMotionScale = 1.0
    } else if deepInteriorRecovery {
        recoveryMotionScale = 0.0
    } else if offStructureRecovery {
        recoveryMotionScale = 0.005
    } else {
        recoveryMotionScale = 1.0
    }
    let movementScale = deltaTime * speed * zoomMovementGain * recoveryMotionScale
    var nextCenter = center + (direction * movementScale) + (tangent * strafe * movementScale)

    nextCenter.x = nextCenter.x.clamped(to: -120 ... 120)
    nextCenter.y = nextCenter.y.clamped(to: -320 ... 320)

    return (nextCenter, nextZoom, nextHeading)
}

private func complexMultiply(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> SIMD2<Double> {
    SIMD2<Double>((a.x * b.x) - (a.y * b.y), (a.x * b.y) + (a.y * b.x))
}

private func complexDivide(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> SIMD2<Double>? {
    let denominator = (b.x * b.x) + (b.y * b.y)
    guard denominator.isFinite, denominator > 1e-12 else { return nil }
    let real = ((a.x * b.x) + (a.y * b.y)) / denominator
    let imag = ((a.y * b.x) - (a.x * b.y)) / denominator
    guard real.isFinite, imag.isFinite else { return nil }
    return SIMD2<Double>(real, imag)
}

private func complexPowInt(_ base: SIMD2<Double>, exponent: Int) -> SIMD2<Double> {
    guard exponent > 0 else { return SIMD2<Double>(1, 0) }
    var result = SIMD2<Double>(1, 0)
    if exponent == 1 { return base }
    for _ in 0 ..< exponent {
        result = complexMultiply(result, base)
    }
    return result
}

private func complexExp(_ z: SIMD2<Double>) -> SIMD2<Double> {
    let expReal = Foundation.exp(z.x)
    return SIMD2<Double>(expReal * Foundation.cos(z.y), expReal * Foundation.sin(z.y))
}

private func complexLog(_ z: SIMD2<Double>) -> SIMD2<Double>? {
    let magnitudeSquared = (z.x * z.x) + (z.y * z.y)
    guard magnitudeSquared.isFinite, magnitudeSquared > 1e-18 else { return nil }
    return SIMD2<Double>(0.5 * Foundation.log(magnitudeSquared), Foundation.atan2(z.y, z.x))
}

private func complexPow(_ base: SIMD2<Double>, exponent: SIMD2<Double>) -> SIMD2<Double>? {
    guard let logBase = complexLog(base) else { return nil }
    return complexExp(complexMultiply(exponent, logBase))
}

private func complexSin(_ z: SIMD2<Double>) -> SIMD2<Double> {
    let real = Foundation.sin(z.x) * Foundation.cosh(z.y)
    let imag = Foundation.cos(z.x) * Foundation.sinh(z.y)
    return SIMD2<Double>(real, imag)
}

private func complexPowReal(base: Double, exponent: SIMD2<Double>) -> SIMD2<Double> {
    let clampedBase = max(base, 1e-9)
    let logBase = Foundation.log(clampedBase)
    let scaled = SIMD2<Double>(exponent.x * logBase, exponent.y * logBase)
    return complexExp(scaled)
}

private func complexIsFinite(_ z: SIMD2<Double>) -> Bool {
    z.x.isFinite && z.y.isFinite
}

private let lanczosCoefficients: [Double] = [
    0.999_999_999_999_809_9,
    676.520_368_121_885_1,
    -1_259.139_216_722_402_8,
    771.323_428_777_653_1,
    -176.615_029_162_140_6,
    12.507_343_278_686_905,
    -0.138_571_095_265_720_12,
    0.000_009_984_369_578_019_572,
    0.000_000_150_563_273_514_931_16,
]

private func complexGammaLanczosPositive(_ z: SIMD2<Double>) -> SIMD2<Double>? {
    let g = 7.0
    let sqrtTwoPi = 2.506_628_274_631_000_7
    let zMinusOne = z - SIMD2<Double>(1, 0)
    var series = SIMD2<Double>(lanczosCoefficients[0], 0)

    for index in 1 ..< lanczosCoefficients.count {
        let denominator = zMinusOne + SIMD2<Double>(Double(index), 0)
        guard let term = complexDivide(SIMD2<Double>(lanczosCoefficients[index], 0), denominator) else {
            return nil
        }
        series += term
    }

    let t = zMinusOne + SIMD2<Double>(g + 0.5, 0)
    guard let power = complexPow(t, exponent: zMinusOne + SIMD2<Double>(0.5, 0)) else {
        return nil
    }
    let decay = complexExp(-t)
    let result = complexMultiply(
        SIMD2<Double>(sqrtTwoPi, 0),
        complexMultiply(series, complexMultiply(power, decay))
    )
    return complexIsFinite(result) ? result : nil
}

private func complexGammaLanczos(_ z: SIMD2<Double>) -> SIMD2<Double>? {
    if z.x < 0.5 {
        let oneMinusZ = SIMD2<Double>(1 - z.x, -z.y)
        let sinPiZ = complexSin(z * Double.pi)
        guard let gammaReflected = complexGammaLanczosPositive(oneMinusZ) else { return nil }
        guard let denominator = complexDivide(SIMD2<Double>(1, 0), complexMultiply(sinPiZ, gammaReflected)) else {
            return nil
        }
        let reflected = complexMultiply(SIMD2<Double>(Double.pi, 0), denominator)
        return complexIsFinite(reflected) ? reflected : nil
    }
    return complexGammaLanczosPositive(z)
}

private func riemannZetaEtaBranch(_ s: SIMD2<Double>, termCount: Int) -> SIMD2<Double>? {
    let eta = riemannEtaApproximation(real: s.x, imag: s.y, termCount: termCount)
    let oneMinusS = SIMD2<Double>(1 - s.x, -s.y)
    let twoPow = complexPowReal(base: 2, exponent: oneMinusS)
    let denominator = SIMD2<Double>(1 - twoPow.x, -twoPow.y)
    guard let zeta = complexDivide(eta, denominator), complexIsFinite(zeta) else { return nil }
    return zeta
}

public func riemannEtaApproximation(real: Double, imag: Double, termCount: Int) -> SIMD2<Double> {
    let terms = max(2, termCount)
    var sum = SIMD2<Double>(0, 0)
    let s = SIMD2<Double>(real, imag)

    for term in 1 ... terms {
        let n = Double(term)
        let nPow = complexPowReal(base: n, exponent: s)
        let inverse = complexDivide(SIMD2<Double>(1, 0), nPow) ?? .zero
        let sign = term.isMultiple(of: 2) ? -1.0 : 1.0
        sum += inverse * sign
    }
    return sum
}

public func riemannZetaApproximation(real: Double, imag: Double, termCount: Int) -> SIMD2<Double>? {
    let s = SIMD2<Double>(real, imag)
    let terms = max(2, termCount)
    guard let etaBranch = riemannZetaEtaBranch(s, termCount: terms) else {
        return nil
    }

    let reflected = SIMD2<Double>(1 - real, -imag)
    guard let reflectedZeta = riemannZetaEtaBranch(reflected, termCount: terms) else {
        return etaBranch
    }

    let twoPow = complexPowReal(base: 2, exponent: s)
    let piPow = complexPowReal(base: Double.pi, exponent: SIMD2<Double>(real - 1, imag))
    let sinTerm = complexSin(SIMD2<Double>(0.5 * Double.pi * real, 0.5 * Double.pi * imag))
    guard let gamma = complexGammaLanczos(SIMD2<Double>(1 - real, -imag)) else {
        return etaBranch
    }

    let chi = complexMultiply(complexMultiply(twoPow, piPow), complexMultiply(sinTerm, gamma))
    let functionalBranch = complexMultiply(chi, reflectedZeta)
    guard complexIsFinite(functionalBranch) else {
        return etaBranch
    }

    // Blend in log-magnitude + wrapped-phase space to suppress branch seams.
    let etaWeight = min(max((real - (-0.40)) / (0.70 - (-0.40)), 0), 1)
    let functionalMag = max(hypot(functionalBranch.x, functionalBranch.y), 1e-12)
    let etaMag = max(hypot(etaBranch.x, etaBranch.y), 1e-12)
    let blendedMag = Foundation.exp((Foundation.log(functionalMag) * (1 - etaWeight)) + (Foundation.log(etaMag) * etaWeight))
    let functionalPhase = Foundation.atan2(functionalBranch.y, functionalBranch.x)
    let etaPhase = Foundation.atan2(etaBranch.y, etaBranch.x)
    let phaseDelta = Foundation.atan2(Foundation.sin(etaPhase - functionalPhase), Foundation.cos(etaPhase - functionalPhase))
    let blendedPhase = functionalPhase + (phaseDelta * etaWeight)
    let blended = SIMD2<Double>(Foundation.cos(blendedPhase) * blendedMag, Foundation.sin(blendedPhase) * blendedMag)
    if complexIsFinite(blended) {
        return blended
    }
    return etaWeight >= 0.5 ? etaBranch : functionalBranch
}

public struct RiemannDomainColorSample: Equatable {
    public let hue: Double
    public let saturation: Double
    public let value: Double
    public let contourEnergy: Double

    public init(hue: Double, saturation: Double, value: Double, contourEnergy: Double) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.contourEnergy = contourEnergy
    }
}

private func riemannContourLineEnergy(_ coordinate: Double, lineCount: Double) -> Double {
    let fractional = abs((coordinate * lineCount).truncatingRemainder(dividingBy: 1) - 0.5)
    let shaped = (fractional - 0.44) / 0.06
    let smooth = min(max(shaped, 0), 1)
    return 1 - (smooth * smooth * (3 - (2 * smooth)))
}

public func riemannDomainColorSample(
    real: Double,
    imag: Double,
    termCount: Int,
    contourTaps: Int = 24
) -> RiemannDomainColorSample? {
    guard let zeta = riemannZetaApproximation(real: real, imag: imag, termCount: termCount) else {
        return nil
    }

    let magnitude = Foundation.hypot(zeta.x, zeta.y)
    let phase = Foundation.atan2(zeta.y, zeta.x)
    let hueRaw = (phase / (2 * Double.pi)).truncatingRemainder(dividingBy: 1)
    let hue = hueRaw >= 0 ? hueRaw : hueRaw + 1
    let contourFrequency = max(4.0, Double(contourTaps) * 0.58 + 4.0)

    let phaseLines = riemannContourLineEnergy(hue, lineCount: contourFrequency)
    let magLog = Foundation.log(1 + max(magnitude, 1e-12))
    let magLines = riemannContourLineEnergy(magLog * 2.6, lineCount: 1.0)
    let contourEnergy = max(phaseLines, magLines)

    let satBase = 0.34 + contourEnergy * 0.50 + (1 - Foundation.exp(-magLog * 0.35)) * 0.20
    let saturation = min(max(satBase, 0.14), 1)

    let valueBase = 0.12 + (1 - Foundation.exp(-magnitude * 0.52)) * 0.68
    let plateau = min(max((real - 1.3) / (4.7 - 1.3), 0), 1)
    let valueWithContour = valueBase + contourEnergy * 0.08 + plateau * 0.22
    let zeroDip = Foundation.exp(-magnitude * 13.0)
    let value = min(max(valueWithContour * (1 - zeroDip * 0.72), 0), 1)

    return RiemannDomainColorSample(
        hue: hue,
        saturation: saturation,
        value: value,
        contourEnergy: contourEnergy
    )
}

func shouldStartTunnelRelease(
    sidechainEnergy: Float,
    lastAboveTimestamp: Float,
    elapsedTime: Float,
    offThreshold: Float = 0.07,
    dropoutHold: Float = 0.09
) -> Bool {
    sidechainEnergy <= offThreshold && (elapsedTime - lastAboveTimestamp) >= dropoutHold
}

func tunnelShapeEnvelopeValue(
    age: Float,
    sustainLevel: Float,
    releaseStartTimestamp: Float,
    elapsedTime: Float,
    releaseDuration: Float,
    attackDuration: Float = 0.035,
    decayDuration: Float = 0.140
) -> (value: Float, isExpired: Bool) {
    guard age >= 0 else { return (0, false) }
    if age < attackDuration {
        return (min(max(age / attackDuration, 0), 1), false)
    }
    if age < (attackDuration + decayDuration) {
        let t = (age - attackDuration) / max(decayDuration, 0.0001)
        return (mix(1.0, sustainLevel, min(max(t, 0), 1)), false)
    }
    if releaseStartTimestamp < 0 {
        return (sustainLevel, false)
    }

    let releaseAge = elapsedTime - releaseStartTimestamp
    let releaseT = releaseAge / max(releaseDuration, 0.0001)
    let value = sustainLevel * max(1 - releaseT, 0)
    return (value, releaseT >= 1)
}

func contourFlowEvolveValue(
    history: Float,
    contour: Float,
    attackStrength: Float,
    decay: Float = 0.93
) -> Float {
    let boundedHistory = min(max(history, 0), 1)
    let boundedContour = min(max(contour, 0), 1)
    let boundedAttack = min(max(attackStrength, 0), 1)
    let injection = boundedContour * (0.42 + (boundedAttack * 0.20))
    return min(max(max(boundedHistory * decay, injection), 0), 1)
}

private let fallbackShaderSource = """
#include <metal_stdlib>
using namespace metal;
constant uint kMaxPrismImpulses = 32;
constant uint kMaxTunnelShapes = 64;
constant uint kMaxFractalPulses = 32;
constant uint kMaxRiemannAccents = 24;
constant float kPi = 3.14159265358979323846;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct RendererFrameUniforms {
    float time;
    float intensity;
    float scale;
    float motion;
    float diffusion;
    float blackFloor;
    uint modeIndex;
    uint padding;
    float2 resolution;
    float2 centerOffset;

    float ringDecay;
    float featureAmplitude;
    float lowBandEnergy;
    float midBandEnergy;
    float highBandEnergy;
    float attackStrength;
    uint ringCount;
    uint shimmerSampleCount;
    float burstDensity;
    float trailDecay;
    float lensSheen;
    uint particleCount;
    uint attackTrailSampleCount;
    float prismFacetDensity;
    float prismDispersion;
    uint prismFacetSampleCount;
    uint prismDispersionSampleCount;
    uint prismImpulseCount;
    uint prismBlackout;
    float tunnelShapeScale;
    float tunnelDepthSpeed;
    float tunnelReleaseTail;
    uint tunnelVariant;
    uint tunnelShapeCount;
    uint tunnelTrailSampleCount;
    uint tunnelDispersionSampleCount;
    uint tunnelBlackout;
    float fractalDetail;
    float fractalFlowRate;
    float fractalAttackBloom;
    uint fractalPaletteVariant;
    uint fractalOrbitSampleCount;
    uint fractalTrapSampleCount;
    uint fractalPulseCount;
    uint fractalBlackout;
    float fractalFlowPhase;
    float riemannDetail;
    float riemannFlowRate;
    float riemannZeroBloom;
    uint riemannPaletteVariant;
    uint riemannTermCount;
    uint riemannTrapSampleCount;
    uint riemannAccentCount;
    uint riemannBlackout;
    float riemannFlowPhase;
    float2 riemannCameraCenter;
    float riemannCameraZoom;
    float riemannCameraHeading;
    uint fractalPadding0;
    uint fractalPadding1;
    uint fractalPadding2;
    uint noImageInSilence;
    float colorShiftHue;
    float colorShiftSaturation;
    uint colorShiftBlackout;
    float pitchConfidence;
    int stablePitchClass;
    float stablePitchCents;
    uint padding1;
    uint attackIDLow;
    uint attackIDHigh;
    uint padding2;
    uint padding3;
};

vertex VertexOut renderer_fullscreen_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

float3 hsvToRgb(float3 c) {
    float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

float2 complexMul(float2 a, float2 b) {
    return float2((a.x * b.x) - (a.y * b.y), (a.x * b.y) + (a.y * b.x));
}

float2 complexDiv(float2 a, float2 b) {
    float denom = max(dot(b, b), 1e-8);
    return float2(((a.x * b.x) + (a.y * b.y)) / denom, ((a.y * b.x) - (a.x * b.y)) / denom);
}

float2 complexExp(float2 z) {
    float e = exp(z.x);
    return float2(e * cos(z.y), e * sin(z.y));
}

float2 complexLog(float2 z) {
    float magnitudeSq = max(dot(z, z), 1e-12);
    return float2(0.5 * log(magnitudeSq), atan2(z.y, z.x));
}

float2 complexPow(float2 base, float2 exponent) {
    float2 logBase = complexLog(base);
    return complexExp(complexMul(exponent, logBase));
}

float2 complexSin(float2 z) {
    float sinReal = sin(z.x);
    float cosReal = cos(z.x);
    float sinhImag = sinh(z.y);
    float coshImag = cosh(z.y);
    return float2(sinReal * coshImag, cosReal * sinhImag);
}

float2 complexPowReal(float base, float2 exponent) {
    float clampedBase = max(base, 1e-6);
    float logBase = log(clampedBase);
    return complexExp(exponent * logBase);
}

float2 complexGammaLanczosPositive(float2 z) {
    constexpr float g = 7.0;
    constexpr float sqrtTwoPi = 2.5066282746310002;
    constexpr float coeffs[9] = {
        0.9999999999998099,
        676.5203681218851,
        -1259.1392167224028,
        771.3234287776531,
        -176.6150291621406,
        12.507343278686905,
        -0.13857109526572012,
        0.000009984369578019572,
        0.00000015056327351493116
    };

    float2 zMinusOne = z - float2(1.0, 0.0);
    float2 series = float2(coeffs[0], 0.0);
    for (uint index = 1u; index < 9u; index += 1u) {
        float2 denom = zMinusOne + float2(float(index), 0.0);
        series += complexDiv(float2(coeffs[index], 0.0), denom);
    }

    float2 t = zMinusOne + float2(g + 0.5, 0.0);
    float2 power = complexPow(t, zMinusOne + float2(0.5, 0.0));
    float2 decay = complexExp(-t);
    return complexMul(float2(sqrtTwoPi, 0.0), complexMul(series, complexMul(power, decay)));
}

float2 complexGammaLanczos(float2 z) {
    if (z.x < 0.5) {
        float2 oneMinusZ = float2(1.0 - z.x, -z.y);
        float2 sinPiZ = complexSin(z * kPi);
        float2 gammaReflected = complexGammaLanczosPositive(oneMinusZ);
        return complexDiv(float2(kPi, 0.0), complexMul(sinPiZ, gammaReflected));
    }
    return complexGammaLanczosPositive(z);
}

float2 riemannEtaApprox(float2 s, uint termCount);

float2 riemannZetaEtaBranch(float2 s, uint termCount) {
    float2 eta = riemannEtaApprox(s, termCount);
    float2 oneMinusS = float2(1.0 - s.x, -s.y);
    float2 twoPow = complexPowReal(2.0, oneMinusS);
    float2 denom = float2(1.0 - twoPow.x, -twoPow.y);
    return complexDiv(eta, denom);
}

float2 riemannEtaApprox(float2 s, uint termCount) {
    uint terms = clamp(termCount, 2u, 64u);
    float2 sum = float2(0.0);
    for (uint n = 1u; n <= 64u; n += 1u) {
        if (n > terms) { break; }
        float2 nPow = complexPowReal(float(n), s);
        float2 inv = complexDiv(float2(1.0, 0.0), nPow);
        float sign = (n % 2u == 0u) ? -1.0 : 1.0;
        sum += inv * sign;
    }
    return sum;
}

float2 riemannZetaApprox(float2 s, uint termCount) {
    float2 etaBranch = riemannZetaEtaBranch(s, termCount);

    float2 reflected = float2(1.0 - s.x, -s.y);
    float2 reflectedZeta = riemannZetaEtaBranch(reflected, termCount);

    float2 twoPow = complexPowReal(2.0, s);
    float2 piPow = complexPowReal(kPi, float2(s.x - 1.0, s.y));
    float2 sinTerm = complexSin(float2(0.5 * kPi * s.x, 0.5 * kPi * s.y));
    float2 gammaTerm = complexGammaLanczos(float2(1.0 - s.x, -s.y));
    float2 chi = complexMul(complexMul(twoPow, piPow), complexMul(sinTerm, gammaTerm));

    float2 functionalBranch = complexMul(chi, reflectedZeta);
    if (!isfinite(functionalBranch.x) || !isfinite(functionalBranch.y)) {
        return etaBranch;
    }

    // Blend in log-magnitude + wrapped-phase space to suppress branch seams.
    float etaWeight = smoothstep(-0.40, 0.70, s.x);
    float functionalMag = max(length(functionalBranch), 1e-9);
    float etaMag = max(length(etaBranch), 1e-9);
    float blendedMag = exp(mix(log(functionalMag), log(etaMag), etaWeight));
    float functionalPhase = atan2(functionalBranch.y, functionalBranch.x);
    float etaPhase = atan2(etaBranch.y, etaBranch.x);
    float phaseDelta = atan2(sin(etaPhase - functionalPhase), cos(etaPhase - functionalPhase));
    float blendedPhase = functionalPhase + phaseDelta * etaWeight;
    float2 blended = float2(cos(blendedPhase), sin(blendedPhase)) * blendedMag;
    if (!isfinite(blended.x) || !isfinite(blended.y)) {
        return etaWeight >= 0.5 ? etaBranch : functionalBranch;
    }
    return blended;
}

float2 centeredPoint(float2 uv, float2 resolution, float2 centerOffset) {
    float2 safeResolution = max(resolution, float2(1.0, 1.0));
    float aspect = safeResolution.x / safeResolution.y;
    return float2((uv.x - 0.5) * aspect, uv.y - 0.5) - centerOffset;
}

float3 spectralPalette(float phase) {
    float3 c0 = float3(0.08, 0.32, 0.98);
    float3 c1 = float3(0.12, 0.90, 0.80);
    float3 c2 = float3(0.96, 0.42, 0.98);

    float t0 = smoothstep(0.0, 0.45, phase);
    float t1 = smoothstep(0.45, 1.0, phase);
    float3 blend01 = mix(c0, c1, t0);
    return mix(blend01, c2, t1 * 0.65);
}

float3 fractalPaletteColor(float phase, uint variant) {
    float3 c0;
    float3 c1;
    float3 c2;

    switch (variant % 8u) {
    case 0u:
        c0 = float3(0.02, 0.08, 0.30);
        c1 = float3(0.12, 0.76, 0.88);
        c2 = float3(0.68, 0.94, 1.00);
        break;
    case 1u:
        c0 = float3(0.08, 0.02, 0.18);
        c1 = float3(0.94, 0.22, 0.18);
        c2 = float3(1.00, 0.78, 0.22);
        break;
    case 2u:
        c0 = float3(0.01, 0.05, 0.08);
        c1 = float3(0.05, 0.44, 0.62);
        c2 = float3(0.60, 0.90, 0.94);
        break;
    case 3u:
        c0 = float3(0.10, 0.03, 0.16);
        c1 = float3(0.62, 0.08, 0.94);
        c2 = float3(0.95, 0.42, 1.00);
        break;
    case 4u:
        c0 = float3(0.10, 0.01, 0.06);
        c1 = float3(0.88, 0.08, 0.30);
        c2 = float3(1.00, 0.42, 0.10);
        break;
    case 5u:
        c0 = float3(0.03, 0.04, 0.10);
        c1 = float3(0.16, 0.66, 0.90);
        c2 = float3(0.90, 0.96, 1.00);
        break;
    case 6u:
        c0 = float3(0.02, 0.02, 0.02);
        c1 = float3(0.36, 0.36, 0.36);
        c2 = float3(0.88, 0.88, 0.88);
        break;
    default:
        c0 = float3(0.05, 0.04, 0.14);
        c1 = float3(0.20, 0.58, 0.96);
        c2 = float3(0.92, 0.36, 0.96);
        break;
    }

    float t0 = smoothstep(0.0, 0.48, phase);
    float t1 = smoothstep(0.48, 1.0, phase);
    float3 blend01 = mix(c0, c1, t0);
    return mix(blend01, c2, t1 * 0.68);
}

float hash12(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

float sdBox2D(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sdDiamond2D(float2 p, float2 b) {
    p = abs(p);
    return (p.x + p.y) - b.x;
}

float sdSlab2D(float2 p, float width, float height) {
    float outer = sdBox2D(p, float2(width, height));
    float inner = sdBox2D(p, float2(width * 0.55, height * 0.55));
    return max(outer, -inner);
}

struct PrismImpulseData {
    float4 positionRadiusIntensity;
    float4 directionHueDecay;
};

struct TunnelShapeData {
    float4 positionDepthScaleEnvelope;
    float4 forwardHueVariantSeed;
    float4 axisDecaySustainRelease;
};

struct FractalPulseData {
    float4 positionRadiusIntensity;
    float4 hueDecaySeedSector;
};

struct RiemannAccentData {
    float4 positionWidthIntensity;
    float4 directionLengthHueSeed;
    float4 decaySeedSectorActive;
};

fragment float4 renderer_radial_fragment(VertexOut in [[stage_in]], constant RendererFrameUniforms& uniforms [[buffer(0)]]) {
    if (uniforms.modeIndex == 0u) {
        if (uniforms.colorShiftBlackout > 0u) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        float hue = fract(uniforms.colorShiftHue);
        float saturation = clamp(uniforms.colorShiftSaturation, 0.0, 1.0);
        float value = 0.86;
        float3 color = hsvToRgb(float3(hue, saturation, value));
        return float4(color, 1.0);
    }

    float2 resolution = max(uniforms.resolution, float2(1.0, 1.0));
    float aspect = resolution.x / resolution.y;
    float2 point = float2((in.uv.x - 0.5) * aspect, in.uv.y - 0.5) - uniforms.centerOffset;
    float radius = length(point);
    float angle = atan2(point.y, point.x);
    float t = uniforms.time * (0.18 + uniforms.motion * 1.8);

    float halo = exp(-radius * mix(6.8, 2.0, uniforms.scale));
    float spokes = 0.5 + 0.5 * sin((angle * mix(4.0, 10.0, uniforms.motion)) + (t * 1.7));
    float orbit = 0.5 + 0.5 * sin((radius * mix(9.0, 26.0, uniforms.diffusion)) - (t * 2.0));
    float shell = smoothstep(0.72, 0.04, radius + (orbit * 0.09));
    float flare = pow(max(0.0, 1.0 - radius * mix(2.8, 1.2, uniforms.scale)), mix(2.2, 0.9, uniforms.intensity / 1.5));

    float energy = halo * mix(0.48, 1.08, uniforms.intensity / 1.5);
    energy += shell * spokes * 0.42;
    energy += flare * 0.36;
    energy = max(0.0, energy - (uniforms.blackFloor * 0.12));

    float3 colorA = float3(0.04, 0.36, 0.82);
    float3 colorB = float3(0.10, 0.78, 0.88);
    float3 colorC = float3(0.62, 0.14, 0.92);
    float phase = 0.5 + 0.5 * sin((angle * 1.8) + t + (radius * 8.0));
    float3 color = mix(colorA, colorB, phase);
    color = mix(color, colorC, orbit * uniforms.motion * 0.7);
    color *= energy;

    float vignette = smoothstep(1.28, 0.16, radius);
    color *= vignette;
    color += float3(0.012, 0.012, 0.016);
    return float4(color, 1.0);
}

fragment float4 renderer_feedback_contour_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> cameraTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float2 texel = 1.0 / max(uniforms.resolution, float2(1.0, 1.0));

    float3 center = cameraTexture.sample(linearSampler, uv).rgb;
    float3 left = cameraTexture.sample(linearSampler, uv + float2(-texel.x, 0)).rgb;
    float3 right = cameraTexture.sample(linearSampler, uv + float2(texel.x, 0)).rgb;
    float3 up = cameraTexture.sample(linearSampler, uv + float2(0, -texel.y)).rgb;
    float3 down = cameraTexture.sample(linearSampler, uv + float2(0, texel.y)).rgb;

    float lumaCenter = dot(center, float3(0.299, 0.587, 0.114));
    float lumaLeft = dot(left, float3(0.299, 0.587, 0.114));
    float lumaRight = dot(right, float3(0.299, 0.587, 0.114));
    float lumaUp = dot(up, float3(0.299, 0.587, 0.114));
    float lumaDown = dot(down, float3(0.299, 0.587, 0.114));

    float gx = lumaRight - lumaLeft;
    float gy = lumaDown - lumaUp;
    float mag = sqrt((gx * gx) + (gy * gy));
    float contour = smoothstep(0.11, 0.33, mag + (lumaCenter * 0.04));
    return float4(contour, contour, contour, 1.0);
}

fragment float4 renderer_feedback_evolve_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> historyTexture [[texture(0)]],
    texture2d<float> contourTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 centered = in.uv - 0.5;
    float c = cos(0.0018);
    float s = sin(0.0018);
    float2 rotated = float2((centered.x * c) - (centered.y * s), (centered.x * s) + (centered.y * c));
    float2 warpedUV = (rotated / 1.012) + 0.5;

    float history = historyTexture.sample(linearSampler, warpedUV).r;
    float contour = contourTexture.sample(linearSampler, in.uv).r;

    float decay = 0.93;
    float injection = contour * (0.42 + (uniforms.attackStrength * 0.20));
    float evolved = max(history * decay, injection);
    return float4(evolved, evolved, evolved, 1.0);
}

fragment float4 renderer_feedback_present_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> feedbackTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.colorShiftBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float field = feedbackTexture.sample(linearSampler, in.uv).r;
    float hue = fract(uniforms.colorShiftHue);
    float saturation = clamp(uniforms.colorShiftSaturation, 0.0, 1.0);
    float3 tint = hsvToRgb(float3(hue, saturation, 0.90));
    float value = smoothstep(0.03, 0.95, field);
    return float4(tint * value, 1.0);
}

fragment float4 renderer_prism_facet_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.prismBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float density = mix(2.4, 13.5, clamp(uniforms.prismFacetDensity, 0.0, 1.0));
    float flowTime = uniforms.time * (0.16 + (uniforms.motion * 1.7));
    uint sampleCount = clamp(uniforms.prismFacetSampleCount, 4u, 20u);

    float3 color = float3(0.0);
    float energy = 0.0;
    for (uint index = 0; index < 20; index += 1) {
        if (index >= sampleCount) {
            break;
        }

        float t = (float(index) + 0.5) / float(sampleCount);
        float2 warp = float2(
            sin((uv.y + (t * 1.7)) * density + flowTime * (0.8 + t)),
            cos((uv.x - (t * 1.5)) * density + flowTime * (1.1 + (t * 0.9)))
        ) * (0.045 + uniforms.diffusion * 0.13);

        float2 cell = (point + warp) * density;
        float2 edgeDist = abs(fract(cell) - 0.5);
        float ridge = exp(-pow(min(edgeDist.x, edgeDist.y) * (11.0 + (uniforms.prismFacetDensity * 20.0)), 2.0));
        float causticPhase = 0.5 + 0.5 * sin(dot(cell, float2(0.8, 1.3)) + flowTime * (0.9 + t));
        float localEnergy = ridge * mix(0.36, 1.0, causticPhase);
        float weight = (1.0 - (t * 0.5)) / float(sampleCount);
        localEnergy *= weight;

        float hue = fract((t * 0.42) + (uniforms.prismDispersion * 0.18) + dot(cell, float2(0.018, 0.027)));
        color += spectralPalette(hue) * localEnergy;
        energy += localEnergy;
    }

    color += float3(0.003, 0.006, 0.010) * (0.35 + uniforms.featureAmplitude * 0.65);
    return float4(color, energy);
}

fragment float4 renderer_prism_dispersion_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> facetField [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float facetEnergy = facetField.sample(linearSampler, uv).a;
    float split = (0.0008 + (uniforms.prismDispersion * 0.0075)) * (0.55 + (uniforms.attackStrength * 0.45));
    float2 texel = 1.0 / max(uniforms.resolution, float2(1.0, 1.0));

    float gx0 = facetField.sample(linearSampler, uv - float2(texel.x, 0.0)).a;
    float gx1 = facetField.sample(linearSampler, uv + float2(texel.x, 0.0)).a;
    float gy0 = facetField.sample(linearSampler, uv - float2(0.0, texel.y)).a;
    float gy1 = facetField.sample(linearSampler, uv + float2(0.0, texel.y)).a;
    float2 gradient = float2(gx1 - gx0, gy1 - gy0);
    float2 bend = gradient * (0.010 + (facetEnergy * 0.034));
    float2 splitVec = float2(split, split * 0.45);

    float r = facetField.sample(linearSampler, uv + bend + splitVec).r;
    float g = facetField.sample(linearSampler, uv + bend).g;
    float b = facetField.sample(linearSampler, uv + bend - splitVec).b;
    float3 color = float3(r, g, b);
    color += spectralPalette(fract((uv.x * 0.23) + (uv.y * 0.17) + uniforms.time * 0.02)) * facetEnergy * 0.08;
    return float4(color, max(facetEnergy, 0.001));
}

fragment float4 renderer_prism_attack_accents_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device PrismImpulseData* impulses [[buffer(1)]],
    texture2d<float> facetField [[texture(0)]],
    texture2d<float> dispersionField [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    uint impulseCount = min(uniforms.prismImpulseCount, kMaxPrismImpulses);

    float3 color = float3(0.0);
    float energy = 0.0;
    for (uint index = 0; index < impulseCount; index += 1) {
        PrismImpulseData impulse = impulses[index];
        float2 position = impulse.positionRadiusIntensity.xy;
        float radius = max(impulse.positionRadiusIntensity.z, 0.004);
        float intensity = max(impulse.positionRadiusIntensity.w, 0.0);
        if (intensity <= 0.0001) {
            continue;
        }

        float2 direction = impulse.directionHueDecay.xy;
        float directionLength = max(length(direction), 0.0001);
        float2 dir = direction / directionLength;
        float2 tangent = float2(-dir.y, dir.x);
        float hue = impulse.directionHueDecay.z;
        float decay = impulse.directionHueDecay.w;
        float2 delta = point - position;
        float along = dot(delta, dir);
        float across = dot(delta, tangent);

        float shard = exp(-((across * across) / max(radius * radius * 0.45, 1e-5))) *
            exp(-(max(along, 0.0) * max(along, 0.0)) / max(radius * radius * 7.8, 1e-5));
        float halo = exp(-(dot(delta, delta) / max(radius * radius * 1.6, 1e-5)));
        float localEnergy = (shard * 0.90 + halo * 0.32) * intensity * (0.55 + (decay * 0.45));

        float3 impulseColor = spectralPalette(fract(hue + (along * 0.20) + (uniforms.time * 0.05)));
        color += impulseColor * localEnergy;
        energy += localEnergy;
    }

    float3 facet = facetField.sample(linearSampler, uv).rgb;
    float3 dispersion = dispersionField.sample(linearSampler, uv).rgb;
    color += (facet * 0.06) + (dispersion * (0.14 + uniforms.prismDispersion * 0.16));
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_prism_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> facetField [[texture(0)]],
    texture2d<float> dispersionField [[texture(1)]],
    texture2d<float> accentField [[texture(2)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.prismBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);
    float4 facet = facetField.sample(linearSampler, uv);
    float4 dispersion = dispersionField.sample(linearSampler, uv);
    float4 accents = accentField.sample(linearSampler, uv);

    float3 composed = (facet.rgb * 0.52) + (dispersion.rgb * 1.08) + (accents.rgb * 1.10);
    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * 0.24) + (point.x * 2.7) + (point.y * 3.2));
    float3 ambient = mix(float3(0.0015, 0.0024, 0.0040), float3(0.008, 0.012, 0.016), ambientPhase);
    composed += ambient;
    composed = max(composed - (uniforms.blackFloor * 0.12), float3(0.0));

    float vignette = smoothstep(1.55, 0.14, radius);
    composed *= vignette;
    return float4(composed, 1.0);
}

fragment float4 renderer_tunnel_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.tunnelBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float squareRadius = max(abs(point.x), abs(point.y));
    float centerRadius = length(point);
    float invDepth = 1.0 / max(squareRadius + 0.10, 0.10);
    float depthTime = uniforms.time * (0.45 + (uniforms.tunnelDepthSpeed * 2.40));
    float depthPhase = invDepth + depthTime;

    float ringDensity = mix(0.30, 0.72, clamp(uniforms.tunnelShapeScale, 0.0, 1.0));
    float ringSlice = abs(fract(depthPhase * ringDensity) - 0.5);
    float ringShell = exp(-pow(ringSlice * mix(22.0, 54.0, uniforms.tunnelShapeScale), 2.0));

    float2 latticeUV = point * invDepth;
    float latticeScale = mix(2.8, 9.5, clamp(uniforms.tunnelShapeScale, 0.0, 1.0));
    float2 latticeCell = abs(fract((latticeUV * latticeScale) + float2(depthPhase * 0.14, depthPhase * 0.11)) - 0.5);
    float latticeLines = exp(-pow(min(latticeCell.x, latticeCell.y) * mix(18.0, 42.0, uniforms.tunnelShapeScale), 2.0));

    float3 laneNoise = float3(
        sin((latticeUV.x * 2.6) + depthPhase * 0.18),
        sin((latticeUV.y * 2.1) - depthPhase * 0.14),
        sin(((latticeUV.x + latticeUV.y) * 1.7) + depthPhase * 0.11)
    );
    float flow = 0.5 + (0.5 * dot(laneNoise, float3(0.37, 0.33, 0.30)));
    float fog = exp(-squareRadius * mix(3.6, 1.5, uniforms.tunnelShapeScale));
    float wallMask = smoothstep(1.34, 0.10, squareRadius);
    float centerWell = exp(-pow(centerRadius * 9.0, 2.0));

    float energy = ((ringShell * 0.46) + (latticeLines * 0.66) + (fog * 0.20)) * wallMask;
    energy *= mix(0.74, 1.20, flow);
    energy = max(0.0, energy - (centerWell * 0.18));

    float hue = fract((latticeUV.x * 0.07) + (latticeUV.y * 0.05) + (depthPhase * 0.03));
    float3 prism = spectralPalette(hue);
    float3 baseA = float3(0.004, 0.008, 0.016);
    float3 baseB = float3(0.016, 0.028, 0.050);
    float3 base = mix(baseA, baseB, fog);
    float3 color = (base * (0.40 + (0.60 * fog))) + (prism * energy * 0.62);
    color += float3(0.0015, 0.0026, 0.0042) * (0.20 + (uniforms.featureAmplitude * 0.80));
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_tunnel_shapes_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device TunnelShapeData* shapes [[buffer(1)]],
    texture2d<float> tunnelField [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.tunnelBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float3 color = float3(0.0);
    float energy = 0.0;
    uint shapeCount = min(uniforms.tunnelShapeCount, kMaxTunnelShapes);

    for (uint index = 0; index < shapeCount; index += 1) {
        TunnelShapeData shape = shapes[index];
        float2 lane = shape.positionDepthScaleEnvelope.xy;
        float depth = max(shape.positionDepthScaleEnvelope.z, 0.08);
        float scale = max(shape.positionDepthScaleEnvelope.w, 0.001);
        float envelope = max(shape.forwardHueVariantSeed.w, 0.0);
        if (envelope <= 0.0001) {
            continue;
        }

        float perspective = 1.0 / (0.35 + depth);
        float2 projected = lane * perspective;
        float size = scale * perspective * mix(0.12, 0.34, uniforms.tunnelShapeScale);
        float2 local = (point - projected) / max(size, 0.0001);

        float axisAngle = atan2(shape.axisDecaySustainRelease.y, shape.axisDecaySustainRelease.x);
        float axisRotation = axisAngle + (shape.axisDecaySustainRelease.z * 0.35) + (uniforms.time * 0.08);
        float c = cos(axisRotation);
        float s = sin(axisRotation);
        float2 rotated = float2((local.x * c) - (local.y * s), (local.x * s) + (local.y * c));

        float variant = shape.forwardHueVariantSeed.z;
        float distance;
        if (variant < 0.5) {
            distance = sdBox2D(rotated, float2(0.48, 0.30));
        } else if (variant < 1.5) {
            distance = sdDiamond2D(rotated, float2(0.74, 0.74));
        } else {
            distance = sdSlab2D(rotated, 0.52, 0.22);
        }

        float edgeGlow = exp(-pow(max(distance, 0.0) * 5.2, 2.0));
        float core = smoothstep(0.16, -0.26, distance) * 0.56;
        float outline = smoothstep(0.085, 0.0, abs(distance)) * 0.72;
        float releaseMix = shape.axisDecaySustainRelease.w;
        float releaseDamp = mix(1.0, 0.20, releaseMix);
        float depthFade = smoothstep(7.2, 0.25, depth);
        float localEnergy = (edgeGlow + core + outline) * envelope * releaseDamp * depthFade;
        localEnergy *= (0.58 + (uniforms.attackStrength * 0.42));

        float hue = fract(shape.forwardHueVariantSeed.y + (shape.forwardHueVariantSeed.x * 0.03) + (local.x * 0.06));
        float3 shapeColor = spectralPalette(hue);
        color += shapeColor * localEnergy;
        energy += localEnergy;
    }

    float3 field = tunnelField.sample(linearSampler, in.uv).rgb;
    color += field * 0.20;
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_tunnel_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> tunnelField [[texture(0)]],
    texture2d<float> shapeField [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.tunnelBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float squareRadius = max(abs(point.x), abs(point.y));

    float3 field = tunnelField.sample(linearSampler, uv).rgb;
    float3 shapes = shapeField.sample(linearSampler, uv).rgb;
    float2 toVanishing = normalize((-point) + float2(1e-4, 1e-4));
    float2 tangent = float2(-toVanishing.y, toVanishing.x);

    uint sampleCount = clamp(uniforms.tunnelTrailSampleCount, 3u, 12u);
    uint dispersionSamples = clamp(uniforms.tunnelDispersionSampleCount, 3u, 12u);
    float3 trails = float3(0.0);
    for (uint index = 0; index < 12; index += 1) {
        if (index >= sampleCount) { break; }
        float t = (float(index) + 1.0) / float(sampleCount);
        float2 offset = toVanishing * t * (0.012 + uniforms.tunnelDepthSpeed * 0.060);
        trails += shapeField.sample(linearSampler, uv - offset).rgb * (1.0 - t);
    }

    float3 split = float3(0.0);
    for (uint index = 0; index < 12; index += 1) {
        if (index >= dispersionSamples) { break; }
        float t = (float(index) + 1.0) / float(dispersionSamples);
        float spread = t * (0.0008 + uniforms.tunnelReleaseTail * 0.0065);
        float3 rgb;
        rgb.r = shapeField.sample(linearSampler, uv + (tangent * spread)).r;
        rgb.g = shapeField.sample(linearSampler, uv).g;
        rgb.b = shapeField.sample(linearSampler, uv - (tangent * spread)).b;
        split += rgb * (1.0 - t);
    }

    float3 composed = (field * 0.58) + (shapes * 1.15) + (trails * 0.78) + (split * 0.52);
    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * 0.30) + (point.x * 2.6) + (point.y * 2.1));
    float3 ambient = mix(float3(0.0012, 0.0018, 0.0030), float3(0.0065, 0.0105, 0.0140), ambientPhase);
    composed += ambient;
    composed = max(composed - (uniforms.blackFloor * 0.14), float3(0.0));

    float vignette = smoothstep(1.62, 0.12, squareRadius);
    composed *= vignette;
    return float4(composed, 1.0);
}

fragment float4 renderer_fractal_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.fractalBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float detail = clamp(uniforms.fractalDetail, 0.0, 1.0);
    float flowRate = clamp(uniforms.fractalFlowRate, 0.0, 1.0);
    float flow = fract(uniforms.fractalFlowPhase + (uniforms.time * (0.03 + (flowRate * 0.24))));
    float pitchPhase = 0.0;
    if (uniforms.pitchConfidence > 0.6 && uniforms.stablePitchClass >= 0) {
        pitchPhase = (float(uniforms.stablePitchClass) / 12.0) + (clamp(uniforms.stablePitchCents, -50.0, 50.0) / 50.0) * 0.08;
    }

    float cAngle = (flow * (2.0 * 3.14159265358979323846)) + (pitchPhase * 0.45);
    float cMagnitude = mix(0.48, 0.82, detail) + (uniforms.featureAmplitude * 0.08);
    float2 c = float2(cos(cAngle), sin(cAngle)) * cMagnitude;
    c += float2(sin(flow * 3.2), cos(flow * 2.6)) * (0.04 + uniforms.motion * 0.07);

    float zoom = mix(0.92, 2.45, detail);
    float2 z = point * zoom;
    z += float2(
        sin((point.y * 2.0) + flow * 4.2),
        cos((point.x * 1.8) - flow * 3.7)
    ) * (0.02 + (uniforms.diffusion * 0.08));

    uint orbitSamples = clamp(uniforms.fractalOrbitSampleCount, 12u, 64u);
    uint trapSamples = clamp(uniforms.fractalTrapSampleCount, 4u, 16u);

    float trapLine = 1e6;
    float trapRing = 1e6;
    float trapCross = 1e6;
    float escape = 0.0;

    for (uint index = 0; index < 64; index += 1) {
        if (index >= orbitSamples) {
            break;
        }

        float2 z2 = float2((z.x * z.x) - (z.y * z.y), (2.0 * z.x * z.y)) + c;
        z = z2;

        float ringTarget = 0.75 + (0.35 * sin(flow * 6.0 + float(index) * 0.09));
        float line = abs((z.x * 0.68) + (z.y * 0.32));
        float ring = abs(length(z) - ringTarget);
        float cross = min(abs(z.x), abs(z.y));

        trapLine = min(trapLine, line);
        trapRing = min(trapRing, ring);
        trapCross = min(trapCross, cross);

        if (dot(z, z) > 24.0) {
            escape = float(index) / float(max(orbitSamples, 1u));
            break;
        }
    }

    float trapLineEnergy = exp(-trapLine * mix(16.0, 34.0, detail));
    float trapRingEnergy = exp(-trapRing * mix(18.0, 40.0, detail));
    float trapCrossEnergy = exp(-trapCross * mix(22.0, 52.0, detail));

    float trapBlend = 0.0;
    for (uint index = 0; index < 16; index += 1) {
        if (index >= trapSamples) {
            break;
        }
        float t = (float(index) + 1.0) / float(trapSamples);
        trapBlend += (trapLineEnergy * (1.0 - t)) + (trapRingEnergy * t * 0.8) + (trapCrossEnergy * 0.6);
    }
    trapBlend /= float(max(trapSamples, 1u));

    float3 color = fractalPaletteColor(fract(flow + (trapRing * 0.28) + (escape * 0.36)), uniforms.fractalPaletteVariant);
    float3 accentColor = fractalPaletteColor(fract(flow + 0.35 + trapLine * 0.24), uniforms.fractalPaletteVariant);

    float energy = trapBlend * (0.55 + (uniforms.featureAmplitude * 0.45));
    energy += trapRingEnergy * (0.18 + uniforms.attackStrength * 0.28);
    energy = max(energy - (uniforms.blackFloor * 0.07), 0.0);

    float3 fieldColor = (color * energy * 0.92) + (accentColor * trapCrossEnergy * 0.28);
    fieldColor += float3(0.0018, 0.0026, 0.0042) * (0.25 + (uniforms.featureAmplitude * 0.75));
    return float4(fieldColor, max(energy, 0.0001));
}

fragment float4 renderer_fractal_accents_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device FractalPulseData* pulses [[buffer(1)]],
    texture2d<float> fieldTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.fractalBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    uint pulseCount = min(uniforms.fractalPulseCount, kMaxFractalPulses);
    float3 color = float3(0.0);
    float energy = 0.0;

    for (uint index = 0; index < pulseCount; index += 1) {
        FractalPulseData pulse = pulses[index];
        float2 position = pulse.positionRadiusIntensity.xy;
        float radius = max(pulse.positionRadiusIntensity.z, 0.003);
        float intensity = max(pulse.positionRadiusIntensity.w, 0.0);
        if (intensity <= 0.0001) {
            continue;
        }

        float hue = pulse.hueDecaySeedSector.x;
        float decay = pulse.hueDecaySeedSector.y;
        float seed = pulse.hueDecaySeedSector.z;
        float2 delta = point - position;
        float dist = length(delta);
        float ring = exp(-pow(abs(dist - radius) / max(radius * 0.24, 0.006), 2.0) * 2.6);
        float halo = exp(-(dist * dist) / max(radius * radius * 1.9, 1e-5));
        float shard = exp(-pow(abs(delta.x * 0.72 - delta.y * 0.35) / max(radius * 0.55, 0.01), 2.0));
        float localEnergy = (ring * 0.90 + halo * 0.30 + shard * 0.34) * intensity * (0.54 + decay * 0.46);
        localEnergy *= 0.52 + (uniforms.fractalAttackBloom * 0.48);

        float3 pulseColor = fractalPaletteColor(fract(hue + (seed * 0.18) + dist * 0.22), uniforms.fractalPaletteVariant);
        color += pulseColor * localEnergy;
        energy += localEnergy;
    }

    float3 field = fieldTexture.sample(linearSampler, in.uv).rgb;
    color += field * 0.14;
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_fractal_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> fieldTexture [[texture(0)]],
    texture2d<float> accentTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.fractalBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);

    float3 field = fieldTexture.sample(linearSampler, uv).rgb;
    float3 accents = accentTexture.sample(linearSampler, uv).rgb;
    float3 composed = (field * 0.86) + (accents * (0.94 + uniforms.fractalAttackBloom * 0.52));

    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * (0.20 + uniforms.fractalFlowRate * 0.24)) + (point.x * 2.3) + (point.y * 2.7));
    float3 ambientA = fractalPaletteColor(fract(uniforms.fractalFlowPhase + 0.12), uniforms.fractalPaletteVariant) * 0.005;
    float3 ambientB = fractalPaletteColor(fract(uniforms.fractalFlowPhase + 0.48), uniforms.fractalPaletteVariant) * 0.010;
    composed += mix(ambientA, ambientB, ambientPhase);

    composed = max(composed - (uniforms.blackFloor * 0.13), float3(0.0));
    float vignette = smoothstep(1.58, 0.10, radius);
    composed *= vignette;
    return float4(composed, 1.0);
}

float riemannContourLine(float coordinate, float lineCount, float width) {
    float wrapped = abs(fract(coordinate * lineCount) - 0.5);
    float threshold = 0.5 - clamp(width, 0.001, 0.49);
    return 1.0 - smoothstep(threshold, 0.5, wrapped);
}

float3 riemannPaletteBankColor(float phase, uint bank) {
    float3 low;
    float3 mid;
    float3 high;
    if (bank == 0u) {
        low = float3(0.05, 0.12, 0.30);
        mid = float3(0.08, 0.78, 0.88);
        high = float3(0.96, 0.32, 0.80);
    } else {
        low = float3(0.06, 0.08, 0.12);
        mid = float3(0.96, 0.58, 0.16);
        high = float3(0.42, 0.90, 0.34);
    }

    float3 tri = 0.5 + 0.5 * cos((phase + float3(0.0, 0.33, 0.67)) * (2.0 * kPi));
    float3 blend = mix(low, mid, tri);
    return mix(blend, high, tri.z * 0.55);
}

fragment float4 renderer_riemann_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.riemannBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float detail = clamp(uniforms.riemannDetail, 0.0, 1.0);
    float flowRate = clamp(uniforms.riemannFlowRate, 0.0, 1.0);
    float flow = fract(uniforms.riemannFlowPhase);

    float heading = uniforms.riemannCameraHeading;
    if (uniforms.pitchConfidence > 0.6 && uniforms.stablePitchClass >= 0) {
        float pitchPhase = (float(uniforms.stablePitchClass) / 12.0) + (clamp(uniforms.stablePitchCents, -50.0, 50.0) / 50.0) * 0.10;
        heading += pitchPhase * uniforms.pitchConfidence * 0.20;
    }

    float sinR = sin(heading);
    float cosR = cos(heading);
    float2 rotated = float2(
        (point.x * cosR) - (point.y * sinR),
        (point.x * sinR) + (point.y * cosR)
    );

    // Keep the field mapping faithful: camera motion drives navigation; pixel warp does not distort the set.
    float2 p = rotated * 2.0;
    float zoom = clamp(uniforms.riemannCameraZoom, 1e-9, 4.2);
    float2 c = float2(
        uniforms.riemannCameraCenter.x + (p.x * (3.05 * zoom)),
        uniforms.riemannCameraCenter.y + (p.y * (2.05 * zoom))
    );

    float zoomBoost = max(-log2(max(zoom, 1e-9)), 0.0);
    uint maxIter = clamp(
        (uniforms.riemannTermCount * 2u) +
            uint(34.0 + detail * 120.0 + zoomBoost * (18.0 + detail * 18.0)),
        72u,
        960u
    );
    float2 z = float2(0.0, 0.0);
    float2 dz = float2(0.0, 0.0);
    uint escapeIter = maxIter;
    float escapeMag2 = 0.0;

    for (uint index = 0u; index < 1024u; index += 1u) {
        if (index >= maxIter) {
            break;
        }

        float2 dzNext = float2(
            (2.0 * z.x * dz.x) - (2.0 * z.y * dz.y) + 1.0,
            (2.0 * z.x * dz.y) + (2.0 * z.y * dz.x)
        );
        dz = dzNext;

        float x = (z.x * z.x) - (z.y * z.y) + c.x;
        float y = (2.0 * z.x * z.y) + c.y;
        z = float2(x, y);

        float m2 = dot(z, z);
        if (m2 > 256.0) {
            escapeIter = index;
            escapeMag2 = m2;
            break;
        }
    }

    bool escaped = escapeIter < maxIter;
    float smoothIter = float(maxIter);
    if (escaped) {
        float logEscape = log(max(escapeMag2, 1.000001));
        float nu = log(max(logEscape / log(2.0), 1e-9)) / log(2.0);
        smoothIter = float(escapeIter) + 1.0 - clamp(nu, 0.0, 8.0);
    }

    float iterNorm = clamp(smoothIter / float(maxIter), 0.0, 1.0);
    float phase = escaped ? atan2(z.y, z.x) : atan2(c.y, c.x);
    float phaseNormalized = fract((phase / (2.0 * kPi)) + 1.0);
    float magnitude = max(length(z), 1e-7);
    float logMagnitude = log(max(magnitude, 1.000001));
    float derivative = max(length(dz), 1e-6);
    float distanceEstimate = escaped ? (0.5 * log(max(magnitude, 1.000001)) * magnitude / derivative) : 0.0;
    float boundaryEnergy = escaped ? clamp(exp(-distanceEstimate * (22.0 + detail * 30.0)), 0.0, 1.0) : 0.0;

    float argumentLines = riemannContourLine(
        phaseNormalized + (flow * 0.04),
        8.0 + (float(uniforms.riemannTrapSampleCount) * 0.55) + (detail * 6.0),
        0.10
    );
    float equipotentialLines = riemannContourLine(
        (logMagnitude * (0.86 + detail * 0.44)) + (flow * 0.22),
        6.0 + (float(uniforms.riemannTrapSampleCount) * 0.30),
        0.09
    );
    float contourEnergy = max(argumentLines, equipotentialLines);
    float topologyMask = clamp((argumentLines * 0.62) + (equipotentialLines * 0.72) + (contourEnergy * 0.22), 0.0, 1.0);
    float boundaryMask = clamp(pow(boundaryEnergy, 0.78) * (0.68 + contourEnergy * 0.32), 0.0, 1.0);

    float streamField = sin(
        (phase * (4.6 + detail * 2.8)) +
        (logMagnitude * (6.4 + flowRate * 4.0)) +
        (flow * 10.0) +
        (p.x * 3.2)
    );
    float streamMask = pow(max(0.0, streamField * 0.5 + 0.5), 4.0) * (0.45 + boundaryEnergy * 0.55);

    float2 particleGrid = floor((c + float2(160.0, 160.0)) * (0.55 + detail * 1.10));
    float particleSeed = hash12(particleGrid + float2(float(uniforms.riemannPaletteVariant) * 2.7, floor(flow * 53.0)));
    float trap = exp(-pow(length(z - float2(-0.7436439, 0.1318259)) * (4.4 + detail * 2.4), 2.0));
    float particleMask = smoothstep(0.9925, 1.0, particleSeed) * (0.18 + trap * 0.82) * (0.25 + contourEnergy * 0.75);

    uint style = uniforms.riemannPaletteVariant % 8u;
    uint family = style / 2u;
    uint bank = style % 2u;
    float palettePhase = fract(phaseNormalized + (flow * 0.018) + ((1.0 - iterNorm) * 0.08));
    float3 baseDomain = riemannPaletteBankColor(palettePhase, bank);
    float3 boundaryColor = riemannPaletteBankColor(fract(palettePhase + 0.5), bank);
    float3 streamColor = riemannPaletteBankColor(fract(palettePhase + 0.16), bank);
    float3 particleColor = riemannPaletteBankColor(fract(palettePhase + 0.34), bank);

    float value = escaped ? (0.06 + pow(1.0 - iterNorm, 0.46) * 0.88) : 0.002;
    value = clamp(value + boundaryMask * 0.10, 0.0, 1.0);
    float saturation = clamp(0.30 + contourEnergy * 0.42 + boundaryMask * 0.18, 0.10, 1.0);

    float3 color = baseDomain;
    switch (family) {
    case 0u: // topology
        color = baseDomain * (0.30 + topologyMask * 0.96);
        color += boundaryColor * boundaryMask * 0.18;
        color += float3(1.0) * (argumentLines * 0.08 + equipotentialLines * 0.06);
        break;
    case 1u: // streams
        color = baseDomain * 0.22;
        color += streamColor * (0.22 + streamMask * 1.05);
        color += boundaryColor * boundaryMask * 0.24;
        break;
    case 2u: // boundaries
        color = baseDomain * 0.15;
        color += boundaryColor * pow(boundaryMask, 0.78) * 1.15;
        color += streamColor * streamMask * 0.16;
        break;
    default: // particles
        color = baseDomain * 0.10;
        color += particleColor * particleMask * (1.35 + uniforms.attackStrength * 0.25);
        color += boundaryColor * boundaryMask * 0.20;
        break;
    }

    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(luma), color, saturation);
    color *= value + 0.08;
    color = max(color - (uniforms.blackFloor * 0.050), float3(0.0));
    return float4(color, max(value, 0.0001));
}

fragment float4 renderer_riemann_accents_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device RiemannAccentData* accents [[buffer(1)]],
    texture2d<float> fieldTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.riemannBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    uint accentCount = min(uniforms.riemannAccentCount, kMaxRiemannAccents);
    float3 color = float3(0.0);
    float energy = 0.0;

    for (uint index = 0; index < accentCount; index += 1) {
        RiemannAccentData accent = accents[index];
        float2 position = accent.positionWidthIntensity.xy;
        float width = max(accent.positionWidthIntensity.z, 0.003);
        float intensity = max(accent.positionWidthIntensity.w, 0.0);
        if (intensity <= 0.0001) {
            continue;
        }

        float2 direction = accent.directionLengthHueSeed.xy;
        float dirLength = max(length(direction), 0.0001);
        float2 dir = direction / dirLength;
        float lengthSpan = max(accent.directionLengthHueSeed.z, 0.01);
        float hue = accent.directionLengthHueSeed.w;
        float decay = accent.decaySeedSectorActive.x;
        float seed = accent.decaySeedSectorActive.y;
        float2 tangent = float2(-dir.y, dir.x);
        float2 delta = point - position;
        float along = dot(delta, dir);
        float across = dot(delta, tangent);

        float contourStreak = exp(-pow(across / max(width, 0.0012), 2.0)) * exp(-pow(along / max(lengthSpan, 0.01), 2.0));
        float contourRing = exp(-pow(abs(length(delta) - lengthSpan) / max(width * 0.72, 0.0012), 2.0));
        float localEnergy = (contourStreak * 0.76 + contourRing * 0.24) * intensity * (0.16 + decay * 0.14);
        localEnergy *= 0.14 + uniforms.riemannZeroBloom * 0.18;

        uint bank = uniforms.riemannPaletteVariant % 2u;
        float3 accentColor = riemannPaletteBankColor(fract(hue + seed * 0.04 + along * 0.02), bank);
        color += accentColor * localEnergy;
        energy += localEnergy;
    }

    float3 field = fieldTexture.sample(linearSampler, in.uv).rgb;
    color += field * 0.015;
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_riemann_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> fieldTexture [[texture(0)]],
    texture2d<float> accentTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.riemannBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);

    float3 field = fieldTexture.sample(linearSampler, uv).rgb;
    float3 accents = accentTexture.sample(linearSampler, uv).rgb;
    float3 composed = field + (accents * (0.12 + uniforms.riemannZeroBloom * 0.20));

    composed = max(composed - (uniforms.blackFloor * 0.055), float3(0.0));
    float vignette = smoothstep(1.95, 0.00, radius);
    composed *= mix(1.0, vignette, 0.12);
    return float4(composed, 1.0);
}
"""

private func resolutionLabel(for size: CGSize) -> String {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0 else {
        return "Pending surface"
    }
    return "\(width) × \(height)"
}
