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
    private var forceRadialFallbackUntil: CFTimeInterval?
    private var colorShiftHuePhase: Float = 0
    private var colorShiftSaturation: Float = 0.84
    private var lastColorShiftHueUpdateTime: CFTimeInterval?
    private var latestCameraFeedbackFrame: CameraFeedbackFrame?
    private var cameraTextureCache: CVMetalTextureCache?
    private var inFlightCameraTextureRef: CVMetalTexture?
    private var prismImpulsePool = PrismImpulsePool(capacity: kMaxPrismImpulses)
    private var prismImpulseGPUData = [PrismImpulseGPUData](repeating: .zero, count: kMaxPrismImpulses)

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
        currentSurfaceState.activeModeID = activeModeID
        diagnosticsSummary.activeModeSummary = activeModeID.displayName
    }

    public func update(surfaceState: RendererSurfaceState) {
        currentSurfaceState = RendererSurfaceState(activeModeID: surfaceState.activeModeID, controls: surfaceState.controls.clamped())
        diagnosticsSummary.activeModeSummary = currentSurfaceState.activeModeID.displayName
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
            prismImpulseCount: 0
        )

        let radialFallbackActive = forceRadialFallbackUntil.map { now < $0 } ?? false
        let selectedPath = rendererPassSelection(
            modeID: currentSurfaceState.activeModeID,
            colorFeedbackEnabled: currentSurfaceState.controls.colorFeedbackEnabled,
            hasColorFeedbackPipeline: pipelineStates.colorFeedback != nil,
            hasPrismPipeline: pipelineStates.prism != nil,
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
        return RendererPipelineStates(
            radial: radial,
            spectral: spectral,
            attackParticle: attackParticle,
            colorFeedback: colorFeedback,
            prism: prism
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
            pipelineStates.prism != nil
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

    private func degradeActiveModeQuality(reason: String) -> Bool {
        switch currentSurfaceState.activeModeID {
        case .colorShift:
            return false
        case .prismField:
            return degradePrismQuality(reason: reason)
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
        prismImpulseCount: UInt32
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
        case .colorShift, .prismField:
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

private struct RendererPipelineStates {
    var radial: MTLRenderPipelineState
    var spectral: SpectralPipelineStates?
    var attackParticle: AttackParticlePipelineStates?
    var colorFeedback: ColorFeedbackPipelineStates?
    var prism: PrismPipelineStates?
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
    case radial
}

public func rendererPassSelection(
    modeID: VisualModeID,
    colorFeedbackEnabled: Bool,
    hasColorFeedbackPipeline: Bool,
    hasPrismPipeline: Bool,
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

struct PrismImpulseData {
    float4 positionRadiusIntensity;
    float4 directionHueDecay;
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
"""

private func resolutionLabel(for size: CGSize) -> String {
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0 else {
        return "Pending surface"
    }
    return "\(width) × \(height)"
}
