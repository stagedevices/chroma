import Foundation

public struct RendererCenterOffset: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }
}

public struct RendererControlState: Codable, Equatable, Sendable {
    public var intensity: Double
    public var scale: Double
    public var motion: Double
    public var diffusion: Double
    public var blackFloor: Double
    public var ringDecay: Double
    public var burstDensity: Double
    public var trailDecay: Double
    public var lensSheen: Double
    public var prismFacetDensity: Double
    public var prismDispersion: Double
    public var tunnelShapeScale: Double
    public var tunnelDepthSpeed: Double
    public var tunnelReleaseTail: Double
    public var tunnelVariant: Double
    public var fractalDetail: Double
    public var fractalFlowRate: Double
    public var fractalAttackBloom: Double
    public var fractalPaletteVariant: Double
    public var riemannDetail: Double
    public var riemannFlowRate: Double
    public var riemannZeroBloom: Double
    public var riemannPaletteVariant: Double
    public var featureAmplitude: Double
    public var lowBandEnergy: Double
    public var midBandEnergy: Double
    public var highBandEnergy: Double
    public var pitchConfidence: Double
    public var stablePitchClass: Int?
    public var stablePitchCents: Double
    public var colorShiftSaturation: Double
    public var isAttack: Bool
    public var attackStrength: Double
    public var attackID: UInt64
    public var noImageInSilence: Bool
    public var colorFeedbackEnabled: Bool
    public var colorFeedbackBlackout: Bool
    public var centerOffset: RendererCenterOffset

    public init(
        intensity: Double = 0.72,
        scale: Double = 0.58,
        motion: Double = 0.22,
        diffusion: Double = 0.38,
        blackFloor: Double = 0.86,
        ringDecay: Double = 0.82,
        burstDensity: Double = 0.66,
        trailDecay: Double = 0.78,
        lensSheen: Double = 0.54,
        prismFacetDensity: Double = 0.58,
        prismDispersion: Double = 0.62,
        tunnelShapeScale: Double = 0.56,
        tunnelDepthSpeed: Double = 0.62,
        tunnelReleaseTail: Double = 0.58,
        tunnelVariant: Double = 0,
        fractalDetail: Double = 0.60,
        fractalFlowRate: Double = 0.56,
        fractalAttackBloom: Double = 0.62,
        fractalPaletteVariant: Double = 0,
        riemannDetail: Double = 0.60,
        riemannFlowRate: Double = 0.56,
        riemannZeroBloom: Double = 0.62,
        riemannPaletteVariant: Double = 0,
        featureAmplitude: Double = 0,
        lowBandEnergy: Double = 0,
        midBandEnergy: Double = 0,
        highBandEnergy: Double = 0,
        pitchConfidence: Double = 0,
        stablePitchClass: Int? = nil,
        stablePitchCents: Double = 0,
        colorShiftSaturation: Double = 0.84,
        isAttack: Bool = false,
        attackStrength: Double = 0,
        attackID: UInt64 = 0,
        noImageInSilence: Bool = false,
        colorFeedbackEnabled: Bool = false,
        colorFeedbackBlackout: Bool = false,
        centerOffset: RendererCenterOffset = RendererCenterOffset()
    ) {
        self.intensity = intensity
        self.scale = scale
        self.motion = motion
        self.diffusion = diffusion
        self.blackFloor = blackFloor
        self.ringDecay = ringDecay
        self.burstDensity = burstDensity
        self.trailDecay = trailDecay
        self.lensSheen = lensSheen
        self.prismFacetDensity = prismFacetDensity
        self.prismDispersion = prismDispersion
        self.tunnelShapeScale = tunnelShapeScale
        self.tunnelDepthSpeed = tunnelDepthSpeed
        self.tunnelReleaseTail = tunnelReleaseTail
        self.tunnelVariant = tunnelVariant
        self.fractalDetail = fractalDetail
        self.fractalFlowRate = fractalFlowRate
        self.fractalAttackBloom = fractalAttackBloom
        self.fractalPaletteVariant = fractalPaletteVariant
        self.riemannDetail = riemannDetail
        self.riemannFlowRate = riemannFlowRate
        self.riemannZeroBloom = riemannZeroBloom
        self.riemannPaletteVariant = riemannPaletteVariant
        self.featureAmplitude = featureAmplitude
        self.lowBandEnergy = lowBandEnergy
        self.midBandEnergy = midBandEnergy
        self.highBandEnergy = highBandEnergy
        self.pitchConfidence = pitchConfidence
        self.stablePitchClass = stablePitchClass
        self.stablePitchCents = stablePitchCents
        self.colorShiftSaturation = colorShiftSaturation
        self.isAttack = isAttack
        self.attackStrength = attackStrength
        self.attackID = attackID
        self.noImageInSilence = noImageInSilence
        self.colorFeedbackEnabled = colorFeedbackEnabled
        self.colorFeedbackBlackout = colorFeedbackBlackout
        self.centerOffset = centerOffset
    }

    public func clamped() -> RendererControlState {
        RendererControlState(
            intensity: intensity.clamped(to: 0 ... 1.5),
            scale: scale.clamped(to: 0 ... 1),
            motion: motion.clamped(to: 0 ... 1),
            diffusion: diffusion.clamped(to: 0 ... 1),
            blackFloor: blackFloor.clamped(to: 0 ... 1),
            ringDecay: ringDecay.clamped(to: 0 ... 1),
            burstDensity: burstDensity.clamped(to: 0 ... 1),
            trailDecay: trailDecay.clamped(to: 0 ... 1),
            lensSheen: lensSheen.clamped(to: 0 ... 1),
            prismFacetDensity: prismFacetDensity.clamped(to: 0 ... 1),
            prismDispersion: prismDispersion.clamped(to: 0 ... 1),
            tunnelShapeScale: tunnelShapeScale.clamped(to: 0 ... 1),
            tunnelDepthSpeed: tunnelDepthSpeed.clamped(to: 0 ... 1),
            tunnelReleaseTail: tunnelReleaseTail.clamped(to: 0 ... 1),
            tunnelVariant: tunnelVariant.clamped(to: 0 ... 2),
            fractalDetail: fractalDetail.clamped(to: 0 ... 1),
            fractalFlowRate: fractalFlowRate.clamped(to: 0 ... 1),
            fractalAttackBloom: fractalAttackBloom.clamped(to: 0 ... 1),
            fractalPaletteVariant: fractalPaletteVariant.clamped(to: 0 ... 7),
            riemannDetail: riemannDetail.clamped(to: 0 ... 1),
            riemannFlowRate: riemannFlowRate.clamped(to: 0 ... 1),
            riemannZeroBloom: riemannZeroBloom.clamped(to: 0 ... 1),
            riemannPaletteVariant: riemannPaletteVariant.clamped(to: 0 ... 7),
            featureAmplitude: featureAmplitude.clamped(to: 0 ... 1),
            lowBandEnergy: lowBandEnergy.clamped(to: 0 ... 1),
            midBandEnergy: midBandEnergy.clamped(to: 0 ... 1),
            highBandEnergy: highBandEnergy.clamped(to: 0 ... 1),
            pitchConfidence: pitchConfidence.clamped(to: 0 ... 1),
            stablePitchClass: stablePitchClass.map { min(max($0, 0), 11) },
            stablePitchCents: stablePitchCents.clamped(to: -50 ... 50),
            colorShiftSaturation: colorShiftSaturation.clamped(to: 0 ... 1),
            isAttack: isAttack,
            attackStrength: attackStrength.clamped(to: 0 ... 1),
            attackID: attackID,
            noImageInSilence: noImageInSilence,
            colorFeedbackEnabled: colorFeedbackEnabled,
            colorFeedbackBlackout: colorFeedbackBlackout,
            centerOffset: RendererCenterOffset(
                x: centerOffset.x.clamped(to: -1 ... 1),
                y: centerOffset.y.clamped(to: -1 ... 1)
            )
        )
    }
}

public struct RendererSurfaceState: Codable, Equatable, Sendable {
    public var activeModeID: VisualModeID
    public var controls: RendererControlState

    public init(activeModeID: VisualModeID = .colorShift, controls: RendererControlState = RendererControlState()) {
        self.activeModeID = activeModeID
        self.controls = controls
    }
}

public enum RendererReadinessStatus: String, Codable, Equatable, Sendable {
    case idle
    case ready
    case unavailable
    case failed

    public var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .ready:
            return "Ready"
        case .unavailable:
            return "Unavailable"
        case .failed:
            return "Failed"
        }
    }
}

public struct RendererDiagnosticsSummary: Codable, Equatable, Sendable {
    public var readinessStatus: RendererReadinessStatus
    public var statusMessage: String
    public var resolutionLabel: String
    public var approximateFPS: Double
    public var averageFrameTimeMS: Double
    public var droppedFrameCount: Int
    public var activeModeSummary: String

    public init(
        readinessStatus: RendererReadinessStatus,
        statusMessage: String,
        resolutionLabel: String,
        approximateFPS: Double,
        averageFrameTimeMS: Double,
        droppedFrameCount: Int,
        activeModeSummary: String
    ) {
        self.readinessStatus = readinessStatus
        self.statusMessage = statusMessage
        self.resolutionLabel = resolutionLabel
        self.approximateFPS = approximateFPS
        self.averageFrameTimeMS = averageFrameTimeMS
        self.droppedFrameCount = droppedFrameCount
        self.activeModeSummary = activeModeSummary
    }

    public static func placeholder(modeID: VisualModeID = .colorShift) -> RendererDiagnosticsSummary {
        RendererDiagnosticsSummary(
            readinessStatus: .idle,
            statusMessage: "Renderer idle",
            resolutionLabel: "Pending surface",
            approximateFPS: 0,
            averageFrameTimeMS: 0,
            droppedFrameCount: 0,
            activeModeSummary: modeID.displayName
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
