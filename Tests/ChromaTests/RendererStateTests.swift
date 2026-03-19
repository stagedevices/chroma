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

    func testRendererPassSelectionChoosesPrismWhenAvailable() {
        let selection = rendererPassSelection(
            modeID: .prismField,
            colorFeedbackEnabled: false,
            hasColorFeedbackPipeline: true,
            hasPrismPipeline: true,
            hasCameraFeedbackFrame: false,
            radialFallbackActive: false
        )

        XCTAssertEqual(selection, .prism)
    }
}
