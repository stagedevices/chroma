import Foundation

public struct RendererSurfaceStateMapper {
    public init() {
    }

    public func map(
        session: ChromaSession,
        parameterStore: ParameterStore,
        latestFeatureFrame: AudioFeatureFrame?
    ) -> RendererSurfaceState {
        let intensity = scalarValue(
            parameterID: "response.inputGain",
            scope: .global,
            parameterStore: parameterStore,
            fallback: 0.72
        )
        let diffusion = scalarValue(
            parameterID: "response.smoothing",
            scope: .global,
            parameterStore: parameterStore,
            fallback: 0.38
        )
        let blackFloor = scalarValue(
            parameterID: "output.blackFloor",
            scope: .global,
            parameterStore: parameterStore,
            fallback: 0.86
        )
        let hueResponse = scalarValue(
            parameterID: "mode.colorShift.hueResponse",
            scope: .mode(.colorShift),
            parameterStore: parameterStore,
            fallback: 0.66
        )
        let hueRange = scalarValue(
            parameterID: "mode.colorShift.hueRange",
            scope: .mode(.colorShift),
            parameterStore: parameterStore,
            fallback: 0.74
        )
        let prismFacetDensity = scalarValue(
            parameterID: "mode.prismField.facetDensity",
            scope: .mode(.prismField),
            parameterStore: parameterStore,
            fallback: 0.58
        )
        let prismDispersion = scalarValue(
            parameterID: "mode.prismField.dispersion",
            scope: .mode(.prismField),
            parameterStore: parameterStore,
            fallback: 0.62
        )
        let tunnelShapeScale = scalarValue(
            parameterID: "mode.tunnelCels.shapeScale",
            scope: .mode(.tunnelCels),
            parameterStore: parameterStore,
            fallback: 0.56
        )
        let tunnelDepthSpeed = scalarValue(
            parameterID: "mode.tunnelCels.depthSpeed",
            scope: .mode(.tunnelCels),
            parameterStore: parameterStore,
            fallback: 0.62
        )
        let tunnelReleaseTail = scalarValue(
            parameterID: "mode.tunnelCels.releaseTail",
            scope: .mode(.tunnelCels),
            parameterStore: parameterStore,
            fallback: 0.58
        )
        let tunnelVariantRaw = scalarValue(
            parameterID: "mode.tunnelCels.variant",
            scope: .mode(.tunnelCels),
            parameterStore: parameterStore,
            fallback: 0
        )
        let tunnelVariant = min(max(Double(Int(tunnelVariantRaw.rounded())), 0), 2)
        let noImageInSilence = parameterStore.value(for: "output.noImageInSilence", scope: .global)?.toggleValue ?? false

        let scale: Double
        let motion: Double
        switch session.activeModeID {
        case .colorShift:
            scale = hueRange
            motion = hueResponse
        case .prismField:
            scale = max(diffusion, 0.2)
            motion = max(intensity * 0.68, 0.16)
        case .tunnelCels:
            scale = tunnelShapeScale
            motion = tunnelDepthSpeed
        }

        // Task 003 bridge: live features can gently modulate manual controls.
        let featureAmplitude = latestFeatureFrame?.amplitude ?? 0
        let featureTransient = latestFeatureFrame?.transientStrength ?? 0
        let featureLowBand = latestFeatureFrame?.lowBandEnergy ?? 0
        let featureMidBand = latestFeatureFrame?.midBandEnergy ?? 0
        let featureHighBand = latestFeatureFrame?.highBandEnergy ?? 0
        let pitchConfidence = latestFeatureFrame?.pitchConfidence ?? 0
        let stablePitchClass = latestFeatureFrame?.stablePitchClass
        let stablePitchCents = latestFeatureFrame?.stablePitchCents ?? 0
        let isAttack = latestFeatureFrame?.isAttack ?? false
        let attackStrength = latestFeatureFrame?.attackStrength ?? 0
        let attackID = latestFeatureFrame?.attackID ?? 0
        let maxBandEnergy = max(featureLowBand, max(featureMidBand, featureHighBand))
        let weightedLiveEnergy = (featureAmplitude * 0.6) + (maxBandEnergy * 0.4)
        let colorFeedbackEnabled = session.activeModeID == .colorShift && session.outputState.isColorFeedbackEnabled
        let colorFeedbackBlackout = noImageInSilence && weightedLiveEnergy < 0.03
        let modulatedIntensity = intensity + (featureAmplitude * 0.38)
        let modulatedMotion = motion + (featureTransient * 0.24) + (featureAmplitude * 0.10)

        let centerOffset = RendererCenterOffset(
            x: (modulatedMotion - 0.5) * 0.22,
            y: (0.5 - diffusion) * 0.14
        )

        return RendererSurfaceState(
            activeModeID: session.activeModeID,
            controls: RendererControlState(
                intensity: modulatedIntensity,
                scale: scale,
                motion: modulatedMotion,
                diffusion: diffusion,
                blackFloor: blackFloor,
                ringDecay: 0.82,
                burstDensity: 0.66,
                trailDecay: 0.78,
                lensSheen: 0.54,
                prismFacetDensity: prismFacetDensity,
                prismDispersion: prismDispersion,
                tunnelShapeScale: tunnelShapeScale,
                tunnelDepthSpeed: tunnelDepthSpeed,
                tunnelReleaseTail: tunnelReleaseTail,
                tunnelVariant: tunnelVariant,
                featureAmplitude: featureAmplitude,
                lowBandEnergy: featureLowBand,
                midBandEnergy: featureMidBand,
                highBandEnergy: featureHighBand,
                pitchConfidence: pitchConfidence,
                stablePitchClass: stablePitchClass,
                stablePitchCents: stablePitchCents,
                colorShiftSaturation: 0.84,
                isAttack: isAttack,
                attackStrength: attackStrength,
                attackID: attackID,
                noImageInSilence: noImageInSilence,
                colorFeedbackEnabled: colorFeedbackEnabled,
                colorFeedbackBlackout: colorFeedbackBlackout,
                centerOffset: centerOffset
            ).clamped()
        )
    }

    private func scalarValue(
        parameterID: String,
        scope: ParameterScope,
        parameterStore: ParameterStore,
        fallback: Double
    ) -> Double {
        parameterStore.value(for: parameterID, scope: scope)?.scalarValue ?? fallback
    }
}
