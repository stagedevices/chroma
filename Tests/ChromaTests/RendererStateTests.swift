import XCTest
@testable import Chroma

@MainActor
final class RendererStateTests: XCTestCase {
    func testRendererControlStateClampsExpectedRanges() {
        let clamped = RendererControlState(
            intensity: 3,
            scale: -1,
            motion: 2,
            diffusion: -0.4,
            blackFloor: 1.4,
            ringDecay: 2.1,
            burstDensity: 1.8,
            trailDecay: -0.6,
            lensSheen: 1.7,
            prismFacetDensity: -0.5,
            prismDispersion: 1.8,
            tunnelShapeScale: -0.4,
            tunnelDepthSpeed: 1.6,
            tunnelReleaseTail: 1.4,
            tunnelVariant: 3.7,
            fractalDetail: -0.6,
            fractalFlowRate: 1.8,
            fractalAttackBloom: 1.5,
            fractalPaletteVariant: 8.2,
            riemannDetail: -0.3,
            riemannFlowRate: 1.8,
            riemannZeroBloom: 1.4,
            riemannPaletteVariant: 9.1,
            featureAmplitude: -0.3,
            lowBandEnergy: 1.2,
            midBandEnergy: -1.0,
            highBandEnergy: 1.6,
            pitchConfidence: 1.6,
            stablePitchClass: 17,
            stablePitchCents: -84,
            colorShiftSaturation: 2.0,
            isAttack: true,
            attackStrength: 4.0,
            attackID: 99,
            noImageInSilence: true,
            centerOffset: RendererCenterOffset(x: 2, y: -2)
        ).clamped()

        XCTAssertEqual(clamped.intensity, 1.5)
        XCTAssertEqual(clamped.scale, 0)
        XCTAssertEqual(clamped.motion, 1)
        XCTAssertEqual(clamped.diffusion, 0)
        XCTAssertEqual(clamped.blackFloor, 1)
        XCTAssertEqual(clamped.ringDecay, 1)
        XCTAssertEqual(clamped.burstDensity, 1)
        XCTAssertEqual(clamped.trailDecay, 0)
        XCTAssertEqual(clamped.lensSheen, 1)
        XCTAssertEqual(clamped.prismFacetDensity, 0)
        XCTAssertEqual(clamped.prismDispersion, 1)
        XCTAssertEqual(clamped.tunnelShapeScale, 0)
        XCTAssertEqual(clamped.tunnelDepthSpeed, 1)
        XCTAssertEqual(clamped.tunnelReleaseTail, 1)
        XCTAssertEqual(clamped.tunnelVariant, 2)
        XCTAssertEqual(clamped.fractalDetail, 0)
        XCTAssertEqual(clamped.fractalFlowRate, 1)
        XCTAssertEqual(clamped.fractalAttackBloom, 1)
        XCTAssertEqual(clamped.fractalPaletteVariant, 7)
        XCTAssertEqual(clamped.riemannDetail, 0)
        XCTAssertEqual(clamped.riemannFlowRate, 1)
        XCTAssertEqual(clamped.riemannZeroBloom, 1)
        XCTAssertEqual(clamped.riemannPaletteVariant, 7)
        XCTAssertEqual(clamped.featureAmplitude, 0)
        XCTAssertEqual(clamped.lowBandEnergy, 1)
        XCTAssertEqual(clamped.midBandEnergy, 0)
        XCTAssertEqual(clamped.highBandEnergy, 1)
        XCTAssertEqual(clamped.pitchConfidence, 1)
        XCTAssertEqual(clamped.stablePitchClass, 11)
        XCTAssertEqual(clamped.stablePitchCents, -50)
        XCTAssertEqual(clamped.colorShiftSaturation, 1)
        XCTAssertEqual(clamped.attackStrength, 1)
        XCTAssertEqual(clamped.attackID, 99)
        XCTAssertTrue(clamped.noImageInSilence)
        XCTAssertEqual(clamped.centerOffset, RendererCenterOffset(x: 1, y: -1))
    }

    func testColorShiftHuePhaseTracksStablePitchClassTarget() {
        let controls = RendererControlState(
            intensity: 1.0,
            scale: 0.80,
            motion: 0.78,
            diffusion: 0.35,
            featureAmplitude: 0.78,
            lowBandEnergy: 0.52,
            midBandEnergy: 0.63,
            highBandEnergy: 0.58,
            pitchConfidence: 0.92,
            stablePitchClass: 9,
            stablePitchCents: 10,
            attackStrength: 0.62
        )
        let advanced = advanceColorShiftHuePhase(
            currentHue: 0.02,
            deltaTime: 0.1,
            controls: controls
        )
        XCTAssertGreaterThan(advanced, 0.02)
        XCTAssertLessThanOrEqual(advanced, 1.0)
    }

    func testColorShiftHuePhaseHoldsInSilence() {
        let controls = RendererControlState(
            intensity: 1.0,
            scale: 0.74,
            motion: 0.72,
            diffusion: 0.35,
            featureAmplitude: 0,
            lowBandEnergy: 0,
            midBandEnergy: 0,
            highBandEnergy: 0,
            pitchConfidence: 0,
            stablePitchClass: nil,
            stablePitchCents: 0,
            attackStrength: 0
        )
        let held = advanceColorShiftHuePhase(
            currentHue: 0.61,
            deltaTime: 0.1,
            controls: controls
        )

        XCTAssertEqual(held, 0.61, accuracy: 0.0001)
    }

    func testColorShiftHuePhaseDeterministicForSameInputs() {
        let controls = RendererControlState(
            intensity: 0.92,
            scale: 0.66,
            motion: 0.64,
            diffusion: 0.40,
            featureAmplitude: 0.71,
            lowBandEnergy: 0.62,
            midBandEnergy: 0.55,
            highBandEnergy: 0.49,
            pitchConfidence: 0.88,
            stablePitchClass: 4,
            stablePitchCents: -8,
            attackStrength: 0.58
        )
        let first = advanceColorShiftHuePhase(
            currentHue: 0.22,
            deltaTime: 0.016,
            controls: controls
        )
        let second = advanceColorShiftHuePhase(
            currentHue: 0.22,
            deltaTime: 0.016,
            controls: controls
        )

        XCTAssertEqual(first, second, accuracy: 0.000001)
    }

    func testColorShiftSaturationIncreasesWithDriveAndConfidence() {
        let low = colorShiftSaturationValue(
            controls: RendererControlState(
                intensity: 0.6,
                scale: 0.4,
                motion: 0.4,
                featureAmplitude: 0.12,
                lowBandEnergy: 0.10,
                midBandEnergy: 0.10,
                highBandEnergy: 0.08,
                pitchConfidence: 0.15
            )
        )
        let high = colorShiftSaturationValue(
            controls: RendererControlState(
                intensity: 1.0,
                scale: 0.8,
                motion: 0.8,
                featureAmplitude: 0.80,
                lowBandEnergy: 0.72,
                midBandEnergy: 0.74,
                highBandEnergy: 0.70,
                pitchConfidence: 0.92
            )
        )

        XCTAssertGreaterThan(high, low)
    }

    func testColorShiftBlackoutDependsOnNoImageInSilenceToggle() {
        let liveEnergyBlackout = shouldBlackoutColorShift(
            noImageInSilence: true,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )
        let liveEnergyVisible = shouldBlackoutColorShift(
            noImageInSilence: false,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )

        XCTAssertTrue(liveEnergyBlackout)
        XCTAssertFalse(liveEnergyVisible)
    }

    func testContourFlowEvolveValueIsDeterministic() {
        let first = contourFlowEvolveValue(
            history: 0.35,
            contour: 0.48,
            attackStrength: 0.62
        )
        let second = contourFlowEvolveValue(
            history: 0.35,
            contour: 0.48,
            attackStrength: 0.62
        )

        XCTAssertEqual(first, second, accuracy: 0.000001)
    }

    func testContourFlowEvolveValueIncreasesWithAttackStrength() {
        let low = contourFlowEvolveValue(
            history: 0.20,
            contour: 0.40,
            attackStrength: 0.10
        )
        let high = contourFlowEvolveValue(
            history: 0.20,
            contour: 0.40,
            attackStrength: 0.90
        )

        XCTAssertGreaterThan(high, low)
    }

    func testSessionMapsParametersIntoRendererSurfaceState() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "response.inputGain")!,
            value: .scalar(1.1)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "response.smoothing")!,
            value: .scalar(0.44)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.colorShift.hueRange")!,
            value: .scalar(0.65)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.colorShift.hueResponse")!,
            value: .scalar(0.31)
        )

        let surfaceState = sessionViewModel.rendererSurfaceState
        XCTAssertEqual(surfaceState.activeModeID, .colorShift)
        XCTAssertEqual(surfaceState.controls.intensity, 1.1, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.diffusion, 0.44, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.scale, 0.65, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.motion, 0.31, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.ringDecay, 0.82, accuracy: 0.0001)
    }

    func testSessionMapsPrismModeIntoRendererSurfaceState() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.prismField)
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "response.smoothing")!,
            value: .scalar(0.64)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.prismField.facetDensity")!,
            value: .scalar(0.73)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.prismField.dispersion")!,
            value: .scalar(0.41)
        )

        let surfaceState = sessionViewModel.rendererSurfaceState
        XCTAssertEqual(surfaceState.activeModeID, .prismField)
        XCTAssertEqual(surfaceState.controls.scale, 0.64, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.motion, 0.4896, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.prismFacetDensity, 0.73, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.prismDispersion, 0.41, accuracy: 0.0001)
    }

    func testSessionMapsTunnelModeIntoRendererSurfaceState() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.tunnelCels)
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.tunnelCels.shapeScale")!,
            value: .scalar(0.69)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.tunnelCels.depthSpeed")!,
            value: .scalar(0.43)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.tunnelCels.releaseTail")!,
            value: .scalar(0.72)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.tunnelCels.variant")!,
            value: .scalar(1.1)
        )

        let surfaceState = sessionViewModel.rendererSurfaceState
        XCTAssertEqual(surfaceState.activeModeID, .tunnelCels)
        XCTAssertEqual(surfaceState.controls.tunnelShapeScale, 0.69, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.tunnelDepthSpeed, 0.43, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.tunnelReleaseTail, 0.72, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.tunnelVariant, 1.0, accuracy: 0.0001)
    }

    func testSessionMapsFractalModeIntoRendererSurfaceState() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.fractalCaustics)
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.fractalCaustics.detail")!,
            value: .scalar(0.71)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.fractalCaustics.flowRate")!,
            value: .scalar(0.47)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.fractalCaustics.attackBloom")!,
            value: .scalar(0.79)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.fractalCaustics.paletteVariant")!,
            value: .scalar(2.9)
        )

        let surfaceState = sessionViewModel.rendererSurfaceState
        XCTAssertEqual(surfaceState.activeModeID, .fractalCaustics)
        XCTAssertEqual(surfaceState.controls.fractalDetail, 0.71, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.fractalFlowRate, 0.47, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.fractalAttackBloom, 0.79, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.fractalPaletteVariant, 3.0, accuracy: 0.0001)
    }

    func testSessionMapsRiemannModeIntoRendererSurfaceState() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.riemannCorridor)
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.riemannCorridor.detail")!,
            value: .scalar(0.67)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.riemannCorridor.flowRate")!,
            value: .scalar(0.48)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.riemannCorridor.zeroBloom")!,
            value: .scalar(0.74)
        )
        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "mode.riemannCorridor.paletteVariant")!,
            value: .scalar(6.8)
        )

        let surfaceState = sessionViewModel.rendererSurfaceState
        XCTAssertEqual(surfaceState.activeModeID, .riemannCorridor)
        XCTAssertEqual(surfaceState.controls.riemannDetail, 0.67, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.riemannFlowRate, 0.48, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.riemannZeroBloom, 0.74, accuracy: 0.0001)
        XCTAssertEqual(surfaceState.controls.riemannPaletteVariant, 7.0, accuracy: 0.0001)
    }

    func testSessionUsesDefaultAttackThresholdInAnalysisTuning() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel
        guard let analysis = sessionViewModel.audioAnalysisService as? PlaceholderAudioAnalysisService else {
            return XCTFail("Expected PlaceholderAudioAnalysisService")
        }

        XCTAssertEqual(analysis.currentTuning.attackThresholdDB, 8, accuracy: 0.0001)
        XCTAssertEqual(analysis.currentTuning.attackHysteresisDB, 2, accuracy: 0.0001)
        XCTAssertEqual(analysis.currentTuning.attackCooldownMS, 70, accuracy: 0.0001)
        XCTAssertEqual(analysis.currentTuning.inputGainDB, 0, accuracy: 0.0001)
    }

    func testSessionPushesResponseGainIntoAnalysisTuning() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel
        guard let analysis = sessionViewModel.audioAnalysisService as? PlaceholderAudioAnalysisService else {
            return XCTFail("Expected PlaceholderAudioAnalysisService")
        }

        sessionViewModel.updateParameter(
            sessionViewModel.parameterStore.descriptor(for: "response.inputGain")!,
            value: .scalar(1.22)
        )

        XCTAssertEqual(analysis.currentTuning.inputGainDB, 8.0, accuracy: 0.0001)
    }

    func testDiagnosticsSnapshotReflectsRendererSummary() {
        let summary = RendererDiagnosticsSummary(
            readinessStatus: .ready,
            statusMessage: "Metal surface ready",
            resolutionLabel: "1179 × 2556",
            approximateFPS: 59.7,
            averageFrameTimeMS: 16.74,
            droppedFrameCount: 2,
            activeModeSummary: "Color Shift"
        )

        let snapshot = PlaceholderDiagnosticsService().currentSnapshot(
            rendererSummary: summary,
            audioStatus: "Live input"
        )
        XCTAssertEqual(snapshot.rendererStatus, "Ready")
        XCTAssertEqual(snapshot.averageFrameTimeMS, 16.74, accuracy: 0.001)
        XCTAssertEqual(snapshot.droppedFrameCount, 2)
        XCTAssertEqual(snapshot.renderer.activeModeSummary, "Color Shift")
    }

    func testSpectralRingPoolRejectsDuplicateAttackIDs() {
        var pool = SpectralRingPool(capacity: 4)

        let insertedFirst = pool.insertIfNewAttack(attackID: 1) {
            SpectralRingEvent(
                attackID: 1,
                birthTime: 0,
                center: SIMD2<Float>(0, 0),
                baseRadius: 0.1,
                width: 0.01,
                intensity: 0.8,
                hueShift: 0.2,
                decay: 0.8,
                lifetime: 1.2,
                sector: 0,
                sectorWeight: 1.0,
                isActive: true
            )
        }
        let insertedDuplicate = pool.insertIfNewAttack(attackID: 1) {
            SpectralRingEvent.inactive
        }

        XCTAssertTrue(insertedFirst)
        XCTAssertFalse(insertedDuplicate)
        XCTAssertEqual(pool.events.filter(\.isActive).count, 1)
    }

    func testSpectralRingPoolEvictionIsDeterministic() {
        var pool = SpectralRingPool(capacity: 3)
        for attackID: UInt64 in [1, 2, 3, 4] {
            _ = pool.insertIfNewAttack(attackID: attackID) {
                SpectralRingEvent(
                    attackID: attackID,
                    birthTime: Float(attackID),
                    center: SIMD2<Float>(Float(attackID), 0),
                    baseRadius: 0.05,
                    width: 0.01,
                    intensity: 0.7,
                    hueShift: 0.1,
                    decay: 0.8,
                    lifetime: 1.0,
                    sector: UInt32(attackID % 12),
                    sectorWeight: 1.0,
                    isActive: true
                )
            }
        }

        XCTAssertEqual(pool.insertionCursor, 1)
        XCTAssertEqual(pool.events.map(\.attackID), [4, 2, 3])
    }

    func testSpectralBloomSectorSelectionIsDeterministicPerBandBias() {
        let lowA = spectralBloomSectorIndex(
            attackID: 42,
            lowBandEnergy: 0.9,
            midBandEnergy: 0.3,
            highBandEnergy: 0.1
        )
        let lowB = spectralBloomSectorIndex(
            attackID: 42,
            lowBandEnergy: 0.9,
            midBandEnergy: 0.3,
            highBandEnergy: 0.1
        )
        let high = spectralBloomSectorIndex(
            attackID: 42,
            lowBandEnergy: 0.1,
            midBandEnergy: 0.2,
            highBandEnergy: 0.95
        )

        XCTAssertEqual(lowA, lowB)
        XCTAssertTrue((0 ... 3).contains(lowA))
        XCTAssertTrue((8 ... 11).contains(high))
    }

    func testAttackParticlePoolRejectsDuplicateAttackIDs() {
        var pool = AttackParticlePool(capacity: 12)
        let inserted = pool.insertBurstIfNewAttack(attackID: 5, count: 4) { index in
            AttackParticleEvent(
                attackID: 5,
                birthTime: 0,
                origin: SIMD2<Float>(Float(index), 0),
                velocity: SIMD2<Float>(0.1, 0.2),
                size: 0.02,
                intensity: 0.9,
                hueShift: 0.2,
                trailDecay: 0.8,
                lifetime: 1.3,
                sector: 2,
                isActive: true
            )
        }
        let duplicate = pool.insertBurstIfNewAttack(attackID: 5, count: 4) { _ in
            AttackParticleEvent.inactive
        }

        XCTAssertTrue(inserted)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(pool.events.filter(\.isActive).count, 4)
    }

    func testAttackParticlePoolEvictionIsDeterministic() {
        var pool = AttackParticlePool(capacity: 5)
        _ = pool.insertBurstIfNewAttack(attackID: 1, count: 3) { index in
            AttackParticleEvent(
                attackID: 1,
                birthTime: 0,
                origin: SIMD2<Float>(Float(index), 0),
                velocity: SIMD2<Float>(0.1, 0.1),
                size: 0.02,
                intensity: 0.8,
                hueShift: 0.1,
                trailDecay: 0.6,
                lifetime: 1.0,
                sector: 0,
                isActive: true
            )
        }
        _ = pool.insertBurstIfNewAttack(attackID: 2, count: 4) { index in
            AttackParticleEvent(
                attackID: 2,
                birthTime: 0.1,
                origin: SIMD2<Float>(Float(index), 1),
                velocity: SIMD2<Float>(0.2, 0.1),
                size: 0.03,
                intensity: 0.7,
                hueShift: 0.2,
                trailDecay: 0.7,
                lifetime: 1.2,
                sector: 5,
                isActive: true
            )
        }

        XCTAssertEqual(pool.events.map(\.attackID), [2, 2, 1, 2, 2])
        XCTAssertEqual(pool.insertionCursor, 2)
    }

    func testAttackParticleSectorSelectionIsDeterministicPerBandBias() {
        let lowA = attackParticleSectorIndex(
            attackID: 77,
            lowBandEnergy: 0.92,
            midBandEnergy: 0.3,
            highBandEnergy: 0.1
        )
        let lowB = attackParticleSectorIndex(
            attackID: 77,
            lowBandEnergy: 0.92,
            midBandEnergy: 0.3,
            highBandEnergy: 0.1
        )
        let high = attackParticleSectorIndex(
            attackID: 77,
            lowBandEnergy: 0.1,
            midBandEnergy: 0.2,
            highBandEnergy: 0.95
        )

        XCTAssertEqual(lowA, lowB)
        XCTAssertTrue((0 ... 3).contains(lowA))
        XCTAssertTrue((8 ... 11).contains(high))
    }

    func testPrismImpulsePoolRejectsDuplicateAttackIDs() {
        var pool = PrismImpulsePool(capacity: 4)
        let inserted = pool.insertIfNewAttack(attackID: 13) {
            PrismImpulseEvent(
                attackID: 13,
                birthTime: 0,
                origin: SIMD2<Float>(0.1, -0.2),
                direction: SIMD2<Float>(0.7, 0.3),
                width: 0.08,
                intensity: 0.92,
                decay: 0.8,
                lifetime: 1.2,
                hueShift: 0.2,
                sector: 3,
                isActive: true
            )
        }
        let duplicate = pool.insertIfNewAttack(attackID: 13) {
            PrismImpulseEvent.inactive
        }

        XCTAssertTrue(inserted)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(pool.events.filter(\.isActive).count, 1)
    }

    func testPrismImpulsePoolEvictionIsDeterministic() {
        var pool = PrismImpulsePool(capacity: 3)
        for attackID: UInt64 in [1, 2, 3, 4] {
            _ = pool.insertIfNewAttack(attackID: attackID) {
                PrismImpulseEvent(
                    attackID: attackID,
                    birthTime: 0,
                    origin: SIMD2<Float>(Float(attackID), 0),
                    direction: SIMD2<Float>(1, 0),
                    width: 0.07,
                    intensity: 0.7,
                    decay: 0.8,
                    lifetime: 1.0,
                    hueShift: 0.1,
                    sector: UInt32(attackID % 12),
                    isActive: true
                )
            }
        }

        XCTAssertEqual(pool.insertionCursor, 1)
        XCTAssertEqual(pool.events.map(\.attackID), [4, 2, 3])
    }

    func testPrismFieldSectorSelectionIsDeterministicPerBandBias() {
        let lowA = prismFieldSectorIndex(
            attackID: 29,
            lowBandEnergy: 0.91,
            midBandEnergy: 0.2,
            highBandEnergy: 0.1
        )
        let lowB = prismFieldSectorIndex(
            attackID: 29,
            lowBandEnergy: 0.91,
            midBandEnergy: 0.2,
            highBandEnergy: 0.1
        )
        let high = prismFieldSectorIndex(
            attackID: 29,
            lowBandEnergy: 0.1,
            midBandEnergy: 0.2,
            highBandEnergy: 0.93
        )

        XCTAssertEqual(lowA, lowB)
        XCTAssertTrue((0 ... 3).contains(lowA))
        XCTAssertTrue((8 ... 11).contains(high))
    }

    func testPrismBlackoutDependsOnNoImageInSilenceToggle() {
        let blackout = shouldBlackoutPrism(
            noImageInSilence: true,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )
        let visible = shouldBlackoutPrism(
            noImageInSilence: false,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )

        XCTAssertTrue(blackout)
        XCTAssertFalse(visible)
    }

    func testTunnelShapePoolRejectsDuplicateAttackIDs() {
        var pool = TunnelShapePool(capacity: 4)
        let inserted = pool.insertIfNewAttack(attackID: 21) {
            TunnelShapeEvent(
                attackID: 21,
                birthTime: 0,
                laneOrigin: SIMD2<Float>(0.2, -0.1),
                forwardSpeed: 0.9,
                depthOffset: 0.4,
                baseScale: 0.7,
                hueShift: 0.18,
                sustainLevel: 0.62,
                decayShape: 1.0,
                releaseDuration: 0.8,
                axisSeed: SIMD2<Float>(0.8, 0.2),
                variant: 1,
                lastAboveTimestamp: 0,
                releaseStartTimestamp: -1,
                isActive: true
            )
        }
        let duplicate = pool.insertIfNewAttack(attackID: 21) { TunnelShapeEvent.inactive }

        XCTAssertTrue(inserted)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(pool.events.filter(\.isActive).count, 1)
    }

    func testTunnelShapePoolEvictionIsDeterministic() {
        var pool = TunnelShapePool(capacity: 3)
        for attackID: UInt64 in [1, 2, 3, 4] {
            _ = pool.insertIfNewAttack(attackID: attackID) {
                TunnelShapeEvent(
                    attackID: attackID,
                    birthTime: Float(attackID),
                    laneOrigin: SIMD2<Float>(Float(attackID), 0),
                    forwardSpeed: 1,
                    depthOffset: 0.1,
                    baseScale: 0.7,
                    hueShift: 0.2,
                    sustainLevel: 0.6,
                    decayShape: 1.0,
                    releaseDuration: 0.8,
                    axisSeed: SIMD2<Float>(1, 0),
                    variant: 0,
                    lastAboveTimestamp: 0,
                    releaseStartTimestamp: -1,
                    isActive: true
                )
            }
        }

        XCTAssertEqual(pool.insertionCursor, 1)
        XCTAssertEqual(pool.events.map(\.attackID), [4, 2, 3])
    }

    func testTunnelSectorSelectionIsDeterministicPerBandBias() {
        let lowA = tunnelCelsSectorIndex(
            attackID: 81,
            lowBandEnergy: 0.93,
            midBandEnergy: 0.2,
            highBandEnergy: 0.1
        )
        let lowB = tunnelCelsSectorIndex(
            attackID: 81,
            lowBandEnergy: 0.93,
            midBandEnergy: 0.2,
            highBandEnergy: 0.1
        )
        let high = tunnelCelsSectorIndex(
            attackID: 81,
            lowBandEnergy: 0.1,
            midBandEnergy: 0.2,
            highBandEnergy: 0.94
        )

        XCTAssertEqual(lowA, lowB)
        XCTAssertTrue((0 ... 3).contains(lowA))
        XCTAssertTrue((8 ... 11).contains(high))
    }

    func testTunnelBlackoutDependsOnNoImageInSilenceToggle() {
        let blackout = shouldBlackoutTunnel(
            noImageInSilence: true,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )
        let visible = shouldBlackoutTunnel(
            noImageInSilence: false,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )

        XCTAssertTrue(blackout)
        XCTAssertFalse(visible)
    }

    func testFractalPulsePoolRejectsDuplicateAttackIDs() {
        var pool = FractalPulsePool(capacity: 4)
        let inserted = pool.insertIfNewAttack(attackID: 88) {
            FractalPulseEvent(
                attackID: 88,
                birthTime: 0,
                origin: SIMD2<Float>(0.1, -0.1),
                baseRadius: 0.08,
                intensity: 0.9,
                decay: 0.8,
                lifetime: 1.4,
                hueShift: 0.3,
                seed: 0.5,
                sector: 7,
                isActive: true
            )
        }
        let duplicate = pool.insertIfNewAttack(attackID: 88) { FractalPulseEvent.inactive }

        XCTAssertTrue(inserted)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(pool.events.filter(\.isActive).count, 1)
    }

    func testFractalPulsePoolEvictionIsDeterministic() {
        var pool = FractalPulsePool(capacity: 3)
        for attackID: UInt64 in [1, 2, 3, 4] {
            _ = pool.insertIfNewAttack(attackID: attackID) {
                FractalPulseEvent(
                    attackID: attackID,
                    birthTime: 0,
                    origin: SIMD2<Float>(Float(attackID), 0),
                    baseRadius: 0.05,
                    intensity: 0.7,
                    decay: 0.8,
                    lifetime: 1.0,
                    hueShift: 0.2,
                    seed: 0.4,
                    sector: UInt32(attackID % 12),
                    isActive: true
                )
            }
        }

        XCTAssertEqual(pool.insertionCursor, 1)
        XCTAssertEqual(pool.events.map(\.attackID), [4, 2, 3])
    }

    func testFractalSectorSelectionIsDeterministicPerBandBias() {
        let lowA = fractalCausticsSectorIndex(
            attackID: 145,
            lowBandEnergy: 0.92,
            midBandEnergy: 0.3,
            highBandEnergy: 0.1
        )
        let lowB = fractalCausticsSectorIndex(
            attackID: 145,
            lowBandEnergy: 0.92,
            midBandEnergy: 0.3,
            highBandEnergy: 0.1
        )
        let high = fractalCausticsSectorIndex(
            attackID: 145,
            lowBandEnergy: 0.1,
            midBandEnergy: 0.2,
            highBandEnergy: 0.95
        )

        XCTAssertEqual(lowA, lowB)
        XCTAssertTrue((0 ... 3).contains(lowA))
        XCTAssertTrue((8 ... 11).contains(high))
    }

    func testFractalFlowAdvanceDeterministicForFixedInputs() {
        let controls = RendererControlState(
            fractalDetail: 0.68,
            fractalFlowRate: 0.57,
            fractalAttackBloom: 0.63,
            featureAmplitude: 0.74,
            lowBandEnergy: 0.52,
            midBandEnergy: 0.67,
            highBandEnergy: 0.61,
            pitchConfidence: 0.84,
            stablePitchClass: 4,
            stablePitchCents: 6,
            attackStrength: 0.72
        )

        let first = fractalFlowPhaseAdvance(currentPhase: 0.21, deltaTime: 0.016, controls: controls)
        let second = fractalFlowPhaseAdvance(currentPhase: 0.21, deltaTime: 0.016, controls: controls)

        XCTAssertEqual(first, second, accuracy: 0.000001)
    }

    func testFractalBlackoutDependsOnNoImageInSilenceToggle() {
        let blackout = shouldBlackoutFractal(
            noImageInSilence: true,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )
        let visible = shouldBlackoutFractal(
            noImageInSilence: false,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )

        XCTAssertTrue(blackout)
        XCTAssertFalse(visible)
    }

    func testRiemannAccentPoolRejectsDuplicateAttackIDs() {
        var pool = RiemannAccentPool(capacity: 4)
        let inserted = pool.insertIfNewAttack(attackID: 55) {
            RiemannAccentEvent(
                attackID: 55,
                birthTime: 0,
                origin: SIMD2<Float>(0.2, -0.1),
                direction: SIMD2<Float>(0.8, 0.2),
                width: 0.04,
                length: 0.26,
                intensity: 0.9,
                decay: 0.78,
                lifetime: 1.2,
                hueShift: 0.22,
                seed: 0.45,
                sector: 8,
                isActive: true
            )
        }
        let duplicate = pool.insertIfNewAttack(attackID: 55) {
            RiemannAccentEvent.inactive
        }

        XCTAssertTrue(inserted)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(pool.events.filter(\.isActive).count, 1)
    }

    func testRiemannAccentPoolEvictionIsDeterministic() {
        var pool = RiemannAccentPool(capacity: 3)
        for attackID: UInt64 in [1, 2, 3, 4] {
            _ = pool.insertIfNewAttack(attackID: attackID) {
                RiemannAccentEvent(
                    attackID: attackID,
                    birthTime: Float(attackID),
                    origin: SIMD2<Float>(Float(attackID), 0),
                    direction: SIMD2<Float>(1, 0),
                    width: 0.03,
                    length: 0.22,
                    intensity: 0.7,
                    decay: 0.8,
                    lifetime: 1.0,
                    hueShift: 0.2,
                    seed: 0.4,
                    sector: UInt32(attackID % 12),
                    isActive: true
                )
            }
        }

        XCTAssertEqual(pool.insertionCursor, 1)
        XCTAssertEqual(pool.events.map(\.attackID), [4, 2, 3])
    }

    func testRiemannSectorSelectionIsDeterministicPerBandBias() {
        let lowA = riemannCorridorSectorIndex(
            attackID: 221,
            lowBandEnergy: 0.92,
            midBandEnergy: 0.2,
            highBandEnergy: 0.1
        )
        let lowB = riemannCorridorSectorIndex(
            attackID: 221,
            lowBandEnergy: 0.92,
            midBandEnergy: 0.2,
            highBandEnergy: 0.1
        )
        let high = riemannCorridorSectorIndex(
            attackID: 221,
            lowBandEnergy: 0.1,
            midBandEnergy: 0.2,
            highBandEnergy: 0.94
        )

        XCTAssertEqual(lowA, lowB)
        XCTAssertTrue((0 ... 3).contains(lowA))
        XCTAssertTrue((8 ... 11).contains(high))
    }

    func testRiemannFlowAdvanceDeterministicForFixedInputs() {
        let controls = RendererControlState(
            riemannDetail: 0.72,
            riemannFlowRate: 0.61,
            riemannZeroBloom: 0.66,
            featureAmplitude: 0.76,
            lowBandEnergy: 0.51,
            midBandEnergy: 0.69,
            highBandEnergy: 0.58,
            pitchConfidence: 0.87,
            stablePitchClass: 7,
            stablePitchCents: -4,
            attackStrength: 0.71
        )

        let first = riemannFlowPhaseAdvance(currentPhase: 0.31, deltaTime: 0.016, controls: controls)
        let second = riemannFlowPhaseAdvance(currentPhase: 0.31, deltaTime: 0.016, controls: controls)

        XCTAssertEqual(first, second, accuracy: 0.000001)
    }

    func testRiemannTraversalAdvanceDeterministicForFixedInputs() {
        let controls = RendererControlState(
            riemannDetail: 0.69,
            riemannFlowRate: 0.63,
            riemannZeroBloom: 0.58,
            featureAmplitude: 0.74,
            lowBandEnergy: 0.56,
            midBandEnergy: 0.47,
            highBandEnergy: 0.39,
            pitchConfidence: 0.90,
            stablePitchClass: 9,
            stablePitchCents: -12,
            attackStrength: 0.66
        )

        let first = riemannTraversalAdvance(
            center: SIMD2<Float>(-0.8, 0.0),
            zoom: 1.0,
            heading: 0.0,
            deltaTime: 0.016,
            controls: controls
        )
        let second = riemannTraversalAdvance(
            center: SIMD2<Float>(-0.8, 0.0),
            zoom: 1.0,
            heading: 0.0,
            deltaTime: 0.016,
            controls: controls
        )

        XCTAssertEqual(first.center.x, second.center.x, accuracy: 0.000001)
        XCTAssertEqual(first.center.y, second.center.y, accuracy: 0.000001)
        XCTAssertEqual(first.zoom, second.zoom, accuracy: 0.000001)
        XCTAssertEqual(first.heading, second.heading, accuracy: 0.000001)
    }

    func testRiemannRouteHandoffTriggersOnlyForNewAttackAndCooldown() {
        XCTAssertTrue(
            shouldTriggerRiemannRouteHandoff(
                lastAttackID: 10,
                newAttackID: 11,
                isAttackFrame: true,
                lastHandoffTime: 1.00,
                now: 1.25,
                cooldown: 0.16
            )
        )
        XCTAssertFalse(
            shouldTriggerRiemannRouteHandoff(
                lastAttackID: 11,
                newAttackID: 11,
                isAttackFrame: true,
                lastHandoffTime: 1.00,
                now: 1.30,
                cooldown: 0.16
            )
        )
        XCTAssertFalse(
            shouldTriggerRiemannRouteHandoff(
                lastAttackID: 11,
                newAttackID: 12,
                isAttackFrame: true,
                lastHandoffTime: 1.20,
                now: 1.30,
                cooldown: 0.16
            )
        )
        XCTAssertFalse(
            shouldTriggerRiemannRouteHandoff(
                lastAttackID: 11,
                newAttackID: 12,
                isAttackFrame: false,
                lastHandoffTime: 1.00,
                now: 1.40,
                cooldown: 0.16
            )
        )
    }

    func testRiemannPOITargetSelectionDeterministicAndZooming() {
        let controls = RendererControlState(
            riemannDetail: 0.74,
            riemannFlowRate: 0.69,
            riemannZeroBloom: 0.62,
            featureAmplitude: 0.80,
            lowBandEnergy: 0.44,
            midBandEnergy: 0.78,
            highBandEnergy: 0.36,
            isAttack: true,
            attackStrength: 0.81,
            attackID: 881
        )

        let first = riemannSelectMandelbrotPOITarget(
            center: SIMD2<Float>(-0.8, 0.0),
            zoom: 1.0,
            heading: 0.0,
            controls: controls,
            gridSize: 9
        )
        let second = riemannSelectMandelbrotPOITarget(
            center: SIMD2<Float>(-0.8, 0.0),
            zoom: 1.0,
            heading: 0.0,
            controls: controls,
            gridSize: 9
        )

        XCTAssertEqual(first.center.x, second.center.x, accuracy: 0.000_001)
        XCTAssertEqual(first.center.y, second.center.y, accuracy: 0.000_001)
        XCTAssertEqual(first.zoom, second.zoom, accuracy: 0.000_001)
        XCTAssertTrue(first.zoom.isFinite)
        XCTAssertGreaterThan(first.zoom, 0)
        XCTAssertLessThanOrEqual(first.zoom, 4.2)
    }

    func testRiemannTraversalAdvanceRespondsToAudioFlightCues() {
        let calm = RendererControlState(
            riemannDetail: 0.60,
            riemannFlowRate: 0.55,
            riemannZeroBloom: 0.58,
            featureAmplitude: 0.08,
            lowBandEnergy: 0.07,
            midBandEnergy: 0.08,
            highBandEnergy: 0.09,
            pitchConfidence: 0.12,
            stablePitchClass: nil,
            stablePitchCents: 0,
            attackStrength: 0.03
        )
        let active = RendererControlState(
            riemannDetail: 0.78,
            riemannFlowRate: 0.84,
            riemannZeroBloom: 0.71,
            featureAmplitude: 0.81,
            lowBandEnergy: 0.34,
            midBandEnergy: 0.76,
            highBandEnergy: 0.68,
            pitchConfidence: 0.86,
            stablePitchClass: 7,
            stablePitchCents: 18,
            attackStrength: 0.77
        )

        let calmStep = riemannTraversalAdvance(
            center: SIMD2<Float>(-0.8, 0.0),
            zoom: 1.0,
            heading: 0.0,
            deltaTime: 0.016,
            controls: calm
        )
        let activeStep = riemannTraversalAdvance(
            center: SIMD2<Float>(-0.8, 0.0),
            zoom: 1.0,
            heading: 0.0,
            deltaTime: 0.016,
            controls: active
        )

        let calmMove = hypot(calmStep.center.x + 0.8, calmStep.center.y)
        let activeMove = hypot(activeStep.center.x + 0.8, activeStep.center.y)
        XCTAssertGreaterThan(activeMove, calmMove)
        XCTAssertNotEqual(activeStep.zoom, 1.0, accuracy: 0.000001)
        XCTAssertNotEqual(activeStep.heading, 0.0, accuracy: 0.000001)
    }

    func testRiemannTraversalAdvanceContinuouslyZoomsAndIntensitySetsSpeed() {
        let base = RendererControlState(
            riemannDetail: 0.64,
            riemannFlowRate: 0.62,
            riemannZeroBloom: 0.58,
            featureAmplitude: 0.08,
            lowBandEnergy: 0.22,
            midBandEnergy: 0.48,
            highBandEnergy: 0.31,
            pitchConfidence: 0.72,
            stablePitchClass: 4,
            stablePitchCents: 6,
            attackStrength: 0.06
        )
        let intense = RendererControlState(
            riemannDetail: 0.64,
            riemannFlowRate: 0.62,
            riemannZeroBloom: 0.58,
            featureAmplitude: 0.86,
            lowBandEnergy: 0.44,
            midBandEnergy: 0.77,
            highBandEnergy: 0.61,
            pitchConfidence: 0.90,
            stablePitchClass: 4,
            stablePitchCents: 6,
            attackStrength: 0.78
        )

        let startCenter = SIMD2<Float>(-0.7436439, 0.1318259)
        let startZoom: Float = 0.22

        let baseStep = riemannTraversalAdvance(
            center: startCenter,
            zoom: startZoom,
            heading: 0.0,
            deltaTime: 0.016,
            controls: base
        )
        let intenseStep = riemannTraversalAdvance(
            center: startCenter,
            zoom: startZoom,
            heading: 0.0,
            deltaTime: 0.016,
            controls: intense
        )

        let baseZoomDelta = abs(baseStep.zoom - startZoom)
        let intenseZoomDelta = abs(intenseStep.zoom - startZoom)
        XCTAssertGreaterThan(intenseZoomDelta, baseZoomDelta, "Higher intensity should drive stronger zoom response")

        let baseMove = hypot(baseStep.center.x - startCenter.x, baseStep.center.y - startCenter.y)
        let intenseMove = hypot(intenseStep.center.x - startCenter.x, intenseStep.center.y - startCenter.y)
        XCTAssertGreaterThan(intenseMove, baseMove, "Higher intensity should increase travel speed")
    }

    func testRiemannTraversalAdvanceRecoversFromDeepInteriorByZoomingOut() {
        let controls = RendererControlState(
            riemannDetail: 0.72,
            riemannFlowRate: 0.66,
            riemannZeroBloom: 0.58,
            featureAmplitude: 0.62,
            lowBandEnergy: 0.40,
            midBandEnergy: 0.44,
            highBandEnergy: 0.38,
            attackStrength: 0.51
        )

        let startCenter = SIMD2<Float>(0.0, 0.0)
        let startZoom: Float = 0.01

        let step = riemannTraversalAdvance(
            center: startCenter,
            zoom: startZoom,
            heading: 0.0,
            deltaTime: 0.016,
            controls: controls
        )

        XCTAssertGreaterThan(step.zoom, startZoom, "Deep-interior recovery should zoom back out to reacquire boundaries")
    }

    func testRiemannPOITargetSelectionRecoversFromInteriorWithZoomOut() {
        let controls = RendererControlState(
            riemannDetail: 0.78,
            riemannFlowRate: 0.69,
            riemannZeroBloom: 0.60,
            featureAmplitude: 0.74,
            lowBandEnergy: 0.36,
            midBandEnergy: 0.41,
            highBandEnergy: 0.35,
            attackStrength: 0.70,
            attackID: 712
        )

        let zoom: Float = 0.01
        let target = riemannSelectMandelbrotPOITarget(
            center: SIMD2<Float>(0.0, 0.0),
            zoom: zoom,
            heading: 0.0,
            controls: controls,
            gridSize: 9
        )

        XCTAssertGreaterThan(target.zoom, zoom, "Interior recovery should request a zoom-out target")
    }

    func testMandelbrotLocalStructureScoreHigherOnBoundaryThanInterior() {
        let detail: Float = 0.72
        let zoom: Float = 0.01
        let boundary = mandelbrotLocalStructureScore(
            center: SIMD2<Float>(-0.75, 0.1),
            zoom: zoom,
            detail: detail
        )
        let interior = mandelbrotLocalStructureScore(
            center: SIMD2<Float>(0.0, 0.0),
            zoom: zoom,
            detail: detail
        )

        XCTAssertGreaterThan(boundary, interior)
    }

    func testRiemannBlackoutDependsOnNoImageInSilenceToggle() {
        let blackout = shouldBlackoutRiemann(
            noImageInSilence: true,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )
        let visible = shouldBlackoutRiemann(
            noImageInSilence: false,
            featureAmplitude: 0.01,
            lowBandEnergy: 0.01,
            midBandEnergy: 0.01,
            highBandEnergy: 0.01
        )

        XCTAssertTrue(blackout)
        XCTAssertFalse(visible)
    }

    func testRiemannEtaApproximationIsFiniteForStripSamples() {
        let samples: [(Double, Double)] = [
            (0.45, 8.0),
            (0.50, 14.0),
            (0.65, 22.0),
            (1.20, -6.0),
        ]
        for sample in samples {
            let eta = riemannEtaApproximation(real: sample.0, imag: sample.1, termCount: 36)
            XCTAssertTrue(eta.x.isFinite)
            XCTAssertTrue(eta.y.isFinite)
        }
    }

    func testRiemannZetaApproximationMatchesKnownValueAtSTwo() {
        guard let zeta = riemannZetaApproximation(real: 2.0, imag: 0.0, termCount: 80) else {
            return XCTFail("Expected finite zeta approximation at s=2")
        }
        let expected = Double.pi * Double.pi / 6.0
        XCTAssertEqual(zeta.x, expected, accuracy: 0.02)
        XCTAssertEqual(zeta.y, 0, accuracy: 0.02)
    }

    func testRiemannZetaApproximationMatchesKnownValueAtSNegativeOne() {
        guard let zeta = riemannZetaApproximation(real: -1.0, imag: 0.0, termCount: 96) else {
            return XCTFail("Expected finite zeta approximation at s=-1")
        }
        let expected = -1.0 / 12.0
        XCTAssertEqual(zeta.x, expected, accuracy: 0.03)
        XCTAssertEqual(zeta.y, 0, accuracy: 0.03)
    }

    func testRiemannZetaApproximationIsFiniteAcrossRepresentativeStripSweep() {
        let samples: [(Double, Double)] = [
            (-4.8, -18.0),
            (-3.2, 0.0),
            (-1.0, 14.0),
            (0.5, -9.0),
            (2.0, 11.0),
            (4.6, 19.0),
        ]

        for sample in samples {
            guard let zeta = riemannZetaApproximation(real: sample.0, imag: sample.1, termCount: 56) else {
                return XCTFail("Expected finite zeta approximation at (\(sample.0), \(sample.1))")
            }
            XCTAssertTrue(zeta.x.isFinite)
            XCTAssertTrue(zeta.y.isFinite)
        }
    }

    func testRiemannZetaApproximationIsContinuousAcrossBranchTransitionBand() {
        let imagSamples: [Double] = [-22.0, -13.0, -7.0, -2.0, 2.0, 7.0, 13.0, 22.0]
        for imag in imagSamples {
            guard
                let left = riemannZetaApproximation(real: 0.12, imag: imag, termCount: 64),
                let right = riemannZetaApproximation(real: 0.24, imag: imag, termCount: 64)
            else {
                return XCTFail("Expected finite zeta approximation near branch transition at imag=\(imag)")
            }

            let leftMag = hypot(left.x, left.y)
            let rightMag = hypot(right.x, right.y)
            let magRatio = max(leftMag, rightMag) / max(min(leftMag, rightMag), 1e-9)
            XCTAssertLessThan(magRatio, 20.0, "Unexpected branch-magnitude seam at imag=\(imag)")

            let leftPhase = atan2(left.y, left.x)
            let rightPhase = atan2(right.y, right.x)
            let phaseDelta = abs(atan2(sin(leftPhase - rightPhase), cos(leftPhase - rightPhase)))
            XCTAssertLessThan(phaseDelta, 2.9, "Unexpected branch-phase seam at imag=\(imag)")
        }
    }

    func testRiemannZetaApproximationGuardsNearSingularDenominator() {
        let singular = riemannZetaApproximation(real: 1.0, imag: 0.0, termCount: 36)
        XCTAssertNil(singular)
    }

    func testRiemannDomainColorFieldHasTwoDimensionalStructure() {
        let realSamples = stride(from: -5.0, through: 5.0, by: 1.25).map { $0 }
        let imagSamples = stride(from: -18.0, through: 18.0, by: 4.5).map { $0 }

        func variance(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let mean = values.reduce(0, +) / Double(values.count)
            let sq = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
            return sq / Double(values.count)
        }

        var rowVariances: [Double] = []
        var columnVariances: [Double] = []
        var allValues: [Double] = []

        for imag in imagSamples {
            var row: [Double] = []
            for real in realSamples {
                guard let sample = riemannDomainColorSample(real: real, imag: imag, termCount: 48, contourTaps: 24) else {
                    return XCTFail("Expected finite domain-color sample at (\(real), \(imag))")
                }
                let structureValue = sample.value + (sample.contourEnergy * 0.22)
                row.append(structureValue)
                allValues.append(structureValue)
            }
            rowVariances.append(variance(row))
        }

        for real in realSamples {
            var column: [Double] = []
            for imag in imagSamples {
                guard let sample = riemannDomainColorSample(real: real, imag: imag, termCount: 48, contourTaps: 24) else {
                    return XCTFail("Expected finite domain-color sample at (\(real), \(imag))")
                }
                column.append(sample.value + (sample.contourEnergy * 0.22))
            }
            columnVariances.append(variance(column))
        }

        let meanRowVariance = rowVariances.reduce(0, +) / Double(rowVariances.count)
        let meanColumnVariance = columnVariances.reduce(0, +) / Double(columnVariances.count)
        XCTAssertGreaterThan(meanRowVariance, 0.003)
        XCTAssertGreaterThan(meanColumnVariance, 0.003)
        XCTAssertGreaterThan(variance(allValues), 0.006)
    }

    func testMandelbrotCenterlineContinuityNearVerticalAxis() {
        let center = SIMD2<Float>(-0.8, 0.0)
        let zoom: Float = 0.75
        let epsilon = Double(zoom) * 0.0008
        let ySamples = stride(from: -1.2, through: 1.2, by: 0.2).map { $0 }
        var totalDelta = 0.0
        var sampleCount = 0.0

        for y in ySamples {
            let imag = Double(center.y) + (y * Double(zoom) * 2.05)
            let left = mandelbrotEscapeSample(
                real: Double(center.x) - epsilon,
                imag: imag,
                maxIterations: 128
            )
            let right = mandelbrotEscapeSample(
                real: Double(center.x) + epsilon,
                imag: imag,
                maxIterations: 128
            )

            let smoothDelta = abs(left.smoothIteration - right.smoothIteration) / 128.0
            let boundaryDelta = abs(left.boundaryEnergy - right.boundaryEnergy)
            totalDelta += smoothDelta + boundaryDelta
            sampleCount += 1
        }

        let meanDelta = totalDelta / max(sampleCount, 1)
        XCTAssertLessThan(meanDelta, 0.55, "Center-line continuity regressed")
    }

    func testMandelbrotVariantFeatureFamiliesAreNonDegenerate() {
        let samples: [(Double, Double)] = [
            (-1.85, 0.02),
            (-1.22, 0.28),
            (-0.74, 0.12),
            (-0.32, 0.62),
            (0.21, -0.58),
            (0.38, 0.36),
        ]
        var totals = SIMD4<Double>(repeating: 0)
        for sample in samples {
            totals += mandelbrotVariantFeatureVector(
                real: sample.0,
                imag: sample.1,
                maxIterations: 112,
                flowPhase: 0.37,
                detail: 0.68
            )
        }

        let count = Double(samples.count)
        let means = totals / count
        XCTAssertGreaterThan(abs(means.x - means.y), 0.03)
        XCTAssertGreaterThan(abs(means.y - means.z), 0.03)
        XCTAssertGreaterThan(abs(means.z - means.w), 0.03)
    }

    func testTunnelReleaseGateUsesHysteresisHold() {
        let notYet = shouldStartTunnelRelease(
            sidechainEnergy: 0.05,
            lastAboveTimestamp: 1.00,
            elapsedTime: 1.06
        )
        let starts = shouldStartTunnelRelease(
            sidechainEnergy: 0.05,
            lastAboveTimestamp: 1.00,
            elapsedTime: 1.10
        )

        XCTAssertFalse(notYet)
        XCTAssertTrue(starts)
    }

    func testTunnelEnvelopeTransitionsAttackDecaySustainRelease() {
        let attack = tunnelShapeEnvelopeValue(
            age: 0.010,
            sustainLevel: 0.6,
            releaseStartTimestamp: -1,
            elapsedTime: 0.010,
            releaseDuration: 0.8
        )
        let sustain = tunnelShapeEnvelopeValue(
            age: 0.300,
            sustainLevel: 0.6,
            releaseStartTimestamp: -1,
            elapsedTime: 0.300,
            releaseDuration: 0.8
        )
        let release = tunnelShapeEnvelopeValue(
            age: 0.600,
            sustainLevel: 0.6,
            releaseStartTimestamp: 0.500,
            elapsedTime: 0.900,
            releaseDuration: 0.8
        )
        let expired = tunnelShapeEnvelopeValue(
            age: 0.900,
            sustainLevel: 0.6,
            releaseStartTimestamp: 0.500,
            elapsedTime: 1.500,
            releaseDuration: 0.8
        )

        XCTAssertGreaterThan(attack.value, 0)
        XCTAssertLessThan(attack.value, 1)
        XCTAssertEqual(sustain.value, 0.6, accuracy: 0.0001)
        XCTAssertLessThan(release.value, 0.6)
        XCTAssertFalse(release.isExpired)
        XCTAssertTrue(expired.isExpired)
    }

    func testRendererPassSelectionChoosesPrismWhenAvailable() {
        let selection = rendererPassSelection(
            modeID: .prismField,
            colorFeedbackEnabled: false,
            hasColorFeedbackPipeline: true,
            hasPrismPipeline: true,
            hasTunnelPipeline: true,
            hasFractalPipeline: true,
            hasRiemannPipeline: true,
            hasCameraFeedbackFrame: false,
            radialFallbackActive: false
        )

        XCTAssertEqual(selection, .prism)
    }

    func testRendererPassSelectionChoosesTunnelWhenAvailable() {
        let selection = rendererPassSelection(
            modeID: .tunnelCels,
            colorFeedbackEnabled: false,
            hasColorFeedbackPipeline: true,
            hasPrismPipeline: true,
            hasTunnelPipeline: true,
            hasFractalPipeline: true,
            hasRiemannPipeline: true,
            hasCameraFeedbackFrame: false,
            radialFallbackActive: false
        )

        XCTAssertEqual(selection, .tunnel)
    }

    func testRendererPassSelectionChoosesFractalWhenAvailable() {
        let selection = rendererPassSelection(
            modeID: .fractalCaustics,
            colorFeedbackEnabled: false,
            hasColorFeedbackPipeline: true,
            hasPrismPipeline: true,
            hasTunnelPipeline: true,
            hasFractalPipeline: true,
            hasRiemannPipeline: true,
            hasCameraFeedbackFrame: false,
            radialFallbackActive: false
        )

        XCTAssertEqual(selection, .fractal)
    }

    func testRendererPassSelectionChoosesRiemannWhenAvailable() {
        let selection = rendererPassSelection(
            modeID: .riemannCorridor,
            colorFeedbackEnabled: false,
            hasColorFeedbackPipeline: true,
            hasPrismPipeline: true,
            hasTunnelPipeline: true,
            hasFractalPipeline: true,
            hasRiemannPipeline: true,
            hasCameraFeedbackFrame: false,
            radialFallbackActive: false
        )

        XCTAssertEqual(selection, .riemann)
    }
}
