import XCTest
import Combine
@testable import Chroma

@MainActor
final class AudioPipelineCoreTests: XCTestCase {
    func testRendererSurfaceStateMapperAppliesAudioFeatureModulation() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(0.70), for: "response.inputGain", scope: .global)
        store.setValue(.scalar(0.42), for: "response.smoothing", scope: .global)
        store.setValue(.scalar(0.61), for: "mode.colorShift.hueRange", scope: .mode(.colorShift))
        store.setValue(.scalar(0.29), for: "mode.colorShift.hueResponse", scope: .mode(.colorShift))

        let mapper = RendererSurfaceStateMapper()
        let session = ChromaSession.initial()
        let baseline = mapper.map(session: session, parameterStore: store, latestFeatureFrame: nil)

        let featureFrame = AudioFeatureFrame(
            timestamp: .now,
            amplitude: 0.8,
            lowBandEnergy: 0.7,
            midBandEnergy: 0.6,
            highBandEnergy: 0.5,
            transientStrength: 0.9,
            pitchHz: 440,
            pitchConfidence: 0.81,
            stablePitchClass: 9,
            stablePitchCents: 6,
            isAttack: true,
            attackStrength: 0.8,
            attackID: 12,
            attackDbOverFloor: 11
        )
        let modulated = mapper.map(session: session, parameterStore: store, latestFeatureFrame: featureFrame)

        XCTAssertGreaterThan(modulated.controls.intensity, baseline.controls.intensity)
        XCTAssertGreaterThan(modulated.controls.motion, baseline.controls.motion)
        XCTAssertEqual(modulated.controls.attackID, 12)
        XCTAssertEqual(modulated.controls.attackStrength, 0.8, accuracy: 0.0001)
        XCTAssertEqual(modulated.controls.pitchConfidence, 0.81, accuracy: 0.0001)
        XCTAssertEqual(modulated.controls.stablePitchClass, 9)
        XCTAssertEqual(modulated.controls.stablePitchCents, 6, accuracy: 0.0001)
        XCTAssertEqual(modulated.activeModeID, .colorShift)
    }

    func testRendererSurfaceStateMapperRoutesColorShiftControlsAndAttackFields() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(0.68), for: "mode.colorShift.hueResponse", scope: .mode(.colorShift))
        store.setValue(.scalar(0.74), for: "mode.colorShift.hueRange", scope: .mode(.colorShift))
        store.setValue(.scalar(0.23), for: "mode.colorShift.hueCenterTrim", scope: .mode(.colorShift))
        store.setValue(.scalar(1.7), for: "mode.colorShift.excitementMode", scope: .mode(.colorShift))

        let mapper = RendererSurfaceStateMapper()
        var session = ChromaSession.initial()
        session.activeModeID = .colorShift

        let featureFrame = AudioFeatureFrame(
            timestamp: .now,
            amplitude: 0.6,
            lowBandEnergy: 0.3,
            midBandEnergy: 0.5,
            highBandEnergy: 0.9,
            transientStrength: 0.8,
            pitchHz: 329.63,
            pitchConfidence: 0.77,
            stablePitchClass: 4,
            stablePitchCents: -7.5,
            isAttack: true,
            attackStrength: 0.76,
            attackID: 45,
            attackDbOverFloor: 12
        )
        let mapped = mapper.map(session: session, parameterStore: store, latestFeatureFrame: featureFrame)

        XCTAssertEqual(mapped.activeModeID, .colorShift)
        XCTAssertTrue(mapped.controls.isAttack)
        XCTAssertEqual(mapped.controls.attackID, 45)
        XCTAssertEqual(mapped.controls.attackStrength, 0.76, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.pitchConfidence, 0.77, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.stablePitchClass, 4)
        XCTAssertEqual(mapped.controls.stablePitchCents, -7.5, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.scale, 0.74, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.colorHueMin, 0.13, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.colorHueMax, 0.87, accuracy: 0.0001)
        XCTAssertFalse(mapped.controls.colorHueOutside)
        XCTAssertEqual(mapped.controls.colorHueShift, 0.23, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.colorShiftExcitementMode, 2.0, accuracy: 0.0001)
        XCTAssertGreaterThan(mapped.controls.motion, 0.68)
    }

    func testRendererSurfaceStateMapperRoutesPrismFieldControls() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(0.57), for: "response.smoothing", scope: .global)
        store.setValue(.scalar(0.71), for: "mode.prismField.facetDensity", scope: .mode(.prismField))
        store.setValue(.scalar(0.39), for: "mode.prismField.dispersion", scope: .mode(.prismField))

        let mapper = RendererSurfaceStateMapper()
        var session = ChromaSession.initial()
        session.activeModeID = .prismField

        let featureFrame = AudioFeatureFrame(
            timestamp: .now,
            amplitude: 0.44,
            lowBandEnergy: 0.22,
            midBandEnergy: 0.48,
            highBandEnergy: 0.61,
            transientStrength: 0.55
        )
        let mapped = mapper.map(session: session, parameterStore: store, latestFeatureFrame: featureFrame)

        XCTAssertEqual(mapped.activeModeID, .prismField)
        XCTAssertEqual(mapped.controls.prismFacetDensity, 0.71, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.prismDispersion, 0.39, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.scale, 0.57, accuracy: 0.0001)
    }

    func testRendererSurfaceStateMapperRoutesTunnelCelsControls() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(0.67), for: "mode.tunnelCels.shapeScale", scope: .mode(.tunnelCels))
        store.setValue(.scalar(0.41), for: "mode.tunnelCels.depthSpeed", scope: .mode(.tunnelCels))
        store.setValue(.scalar(0.72), for: "mode.tunnelCels.releaseTail", scope: .mode(.tunnelCels))
        store.setValue(.scalar(1.8), for: "mode.tunnelCels.variant", scope: .mode(.tunnelCels))

        let mapper = RendererSurfaceStateMapper()
        var session = ChromaSession.initial()
        session.activeModeID = .tunnelCels

        let featureFrame = AudioFeatureFrame(
            timestamp: .now,
            amplitude: 0.52,
            lowBandEnergy: 0.68,
            midBandEnergy: 0.47,
            highBandEnergy: 0.21,
            transientStrength: 0.70,
            isAttack: true,
            attackStrength: 0.64,
            attackID: 101,
            attackDbOverFloor: 9.4
        )
        let mapped = mapper.map(session: session, parameterStore: store, latestFeatureFrame: featureFrame)

        XCTAssertEqual(mapped.activeModeID, .tunnelCels)
        XCTAssertEqual(mapped.controls.tunnelShapeScale, 0.67, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.tunnelDepthSpeed, 0.41, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.tunnelReleaseTail, 0.72, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.tunnelVariant, 2.0, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.scale, 0.67, accuracy: 0.0001)
        XCTAssertGreaterThan(mapped.controls.motion, 0.41)
        XCTAssertEqual(mapped.controls.centerOffset.x, 0, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.centerOffset.y, 0, accuracy: 0.0001)
    }

    func testRendererSurfaceStateMapperRoutesFractalCausticsControls() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(0.73), for: "mode.fractalCaustics.detail", scope: .mode(.fractalCaustics))
        store.setValue(.scalar(0.44), for: "mode.fractalCaustics.flowRate", scope: .mode(.fractalCaustics))
        store.setValue(.scalar(0.81), for: "mode.fractalCaustics.attackBloom", scope: .mode(.fractalCaustics))
        store.setValue(.scalar(6.6), for: "mode.fractalCaustics.paletteVariant", scope: .mode(.fractalCaustics))

        let mapper = RendererSurfaceStateMapper()
        var session = ChromaSession.initial()
        session.activeModeID = .fractalCaustics

        let featureFrame = AudioFeatureFrame(
            timestamp: .now,
            amplitude: 0.57,
            lowBandEnergy: 0.29,
            midBandEnergy: 0.63,
            highBandEnergy: 0.72,
            transientStrength: 0.66,
            pitchHz: 261.63,
            pitchConfidence: 0.84,
            stablePitchClass: 0,
            stablePitchCents: 4.2,
            isAttack: true,
            attackStrength: 0.79,
            attackID: 301,
            attackDbOverFloor: 10.8
        )
        let mapped = mapper.map(session: session, parameterStore: store, latestFeatureFrame: featureFrame)

        XCTAssertEqual(mapped.activeModeID, .fractalCaustics)
        XCTAssertEqual(mapped.controls.fractalDetail, 0.73, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.fractalFlowRate, 0.44, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.fractalAttackBloom, 0.81, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.fractalPaletteVariant, 7.0, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.scale, 0.73, accuracy: 0.0001)
        XCTAssertGreaterThan(mapped.controls.motion, 0.44)
        XCTAssertEqual(mapped.controls.pitchConfidence, 0.84, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.stablePitchClass, 0)
    }

    func testRendererSurfaceStateMapperRoutesRiemannCorridorControls() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        store.setValue(.scalar(0.69), for: "mode.riemannCorridor.detail", scope: .mode(.riemannCorridor))
        store.setValue(.scalar(0.42), for: "mode.riemannCorridor.flowRate", scope: .mode(.riemannCorridor))
        store.setValue(.scalar(0.77), for: "mode.riemannCorridor.zeroBloom", scope: .mode(.riemannCorridor))
        store.setValue(.scalar(1.0), for: "mode.riemannCorridor.navigationMode", scope: .mode(.riemannCorridor))
        store.setValue(.scalar(0.88), for: "mode.riemannCorridor.steeringStrength", scope: .mode(.riemannCorridor))
        store.setValue(.scalar(5.7), for: "mode.riemannCorridor.paletteVariant", scope: .mode(.riemannCorridor))

        let mapper = RendererSurfaceStateMapper()
        var session = ChromaSession.initial()
        session.activeModeID = .riemannCorridor
        session.performanceSettings.mode = .highQuality
        session.audioCalibrationSettings.silenceGateThreshold = 0.081

        let featureFrame = AudioFeatureFrame(
            timestamp: .now,
            amplitude: 0.53,
            lowBandEnergy: 0.64,
            midBandEnergy: 0.41,
            highBandEnergy: 0.33,
            transientStrength: 0.62,
            pitchHz: 293.66,
            pitchConfidence: 0.79,
            stablePitchClass: 2,
            stablePitchCents: -3.5,
            isAttack: true,
            attackStrength: 0.74,
            attackID: 411,
            attackDbOverFloor: 10.1
        )
        let mapped = mapper.map(session: session, parameterStore: store, latestFeatureFrame: featureFrame)

        XCTAssertEqual(mapped.activeModeID, .riemannCorridor)
        XCTAssertEqual(mapped.controls.riemannDetail, 0.69, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.riemannFlowRate, 0.42, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.riemannZeroBloom, 0.77, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.riemannNavigationMode, 1.0, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.riemannSteeringStrength, 0.88, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.riemannPaletteVariant, 6.0, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.performanceModeIndex, 1.0, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.silenceGateThreshold, 0.081, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.scale, 0.69, accuracy: 0.0001)
        XCTAssertGreaterThan(mapped.controls.motion, 0.42)
        XCTAssertEqual(mapped.controls.pitchConfidence, 0.79, accuracy: 0.0001)
        XCTAssertEqual(mapped.controls.stablePitchClass, 2)
    }

    func testRendererSurfaceStateMapperRespectsPerformanceOverride() {
        let store = ParameterStore(descriptors: ParameterCatalog.descriptors)
        let mapper = RendererSurfaceStateMapper()
        var session = ChromaSession.initial()
        session.performanceSettings.mode = .highQuality

        let defaultMapped = mapper.map(
            session: session,
            parameterStore: store,
            latestFeatureFrame: nil
        )
        let overriddenMapped = mapper.map(
            session: session,
            parameterStore: store,
            latestFeatureFrame: nil,
            performanceModeOverride: .safeFPS
        )

        XCTAssertEqual(defaultMapped.controls.performanceModeIndex, 1.0, accuracy: 0.0001)
        XCTAssertEqual(overriddenMapped.controls.performanceModeIndex, 2.0, accuracy: 0.0001)
    }

    func testAudioStatusFormatterProducesLiveSummary() {
        let formatter = AudioStatusFormatter()
        let status = formatter.liveStatus(
            meterFrame: AudioMeterFrame(timestamp: .now, rms: 0.5, peak: 0.8),
            featureFrame: AudioFeatureFrame(
                timestamp: .now,
                amplitude: 0.5,
                lowBandEnergy: 0.4,
                midBandEnergy: 0.3,
                highBandEnergy: 0.2,
                transientStrength: 0.7
            )
        )

        XCTAssertTrue(status.contains("Live input"))
        XCTAssertTrue(status.contains("dBFS"))
        XCTAssertTrue(status.contains("transient"))
    }

    func testLiveAudioAnalysisPublishesFeatureFramesFromMeterInput() async throws {
        let subject = PassthroughSubject<AudioMeterFrame, Never>()
        let analysisService = LiveAudioAnalysisService(meterPublisher: subject.eraseToAnyPublisher())

        try await analysisService.startAnalysis()
        subject.send(AudioMeterFrame(timestamp: .now, rms: 0.6, peak: 0.9))
        subject.send(AudioMeterFrame(timestamp: .now, rms: 0.2, peak: 0.4))

        XCTAssertGreaterThan(analysisService.latestFrame.amplitude, 0)
        XCTAssertGreaterThanOrEqual(analysisService.latestFrame.transientStrength, 0)
        XCTAssertLessThanOrEqual(analysisService.latestFrame.transientStrength, 1)

        analysisService.stopAnalysis()
    }

    func testLiveAudioAnalysisAttackGateCooldownAndHysteresis() async throws {
        let subject = PassthroughSubject<AudioMeterFrame, Never>()
        let analysisService = LiveAudioAnalysisService(meterPublisher: subject.eraseToAnyPublisher())
        analysisService.updateTuning(
            AudioAnalysisTuning(
                attackThresholdDB: 8,
                attackHysteresisDB: 2,
                attackCooldownMS: 70
            )
        )

        try await analysisService.startAnalysis()

        let t0 = Date(timeIntervalSince1970: 1_000)
        subject.send(
            AudioMeterFrame(
                timestamp: t0,
                rms: 0.02,
                peak: 0.03,
                rmsDBFS: -82,
                peakDBFS: -76
            )
        )
        XCTAssertFalse(analysisService.latestFrame.isAttack)
        XCTAssertEqual(analysisService.latestFrame.attackID, 0)

        subject.send(
            AudioMeterFrame(
                timestamp: t0.addingTimeInterval(0.10),
                rms: 0.72,
                peak: 0.94,
                rmsDBFS: -18,
                peakDBFS: -12
            )
        )
        XCTAssertTrue(analysisService.latestFrame.isAttack)
        XCTAssertGreaterThan(analysisService.latestFrame.attackStrength, 0)
        let firstAttackID = analysisService.latestFrame.attackID
        XCTAssertEqual(firstAttackID, 1)

        subject.send(
            AudioMeterFrame(
                timestamp: t0.addingTimeInterval(0.12),
                rms: 0.74,
                peak: 0.96,
                rmsDBFS: -17,
                peakDBFS: -11
            )
        )
        XCTAssertFalse(analysisService.latestFrame.isAttack)
        XCTAssertEqual(analysisService.latestFrame.attackID, firstAttackID)

        // Stay above hysteresis re-arm floor after cooldown: no retrigger.
        subject.send(
            AudioMeterFrame(
                timestamp: t0.addingTimeInterval(0.22),
                rms: 0.62,
                peak: 0.85,
                rmsDBFS: -20,
                peakDBFS: -15
            )
        )
        XCTAssertFalse(analysisService.latestFrame.isAttack)
        XCTAssertEqual(analysisService.latestFrame.attackID, firstAttackID)

        // Drop enough to re-arm, then trigger a second attack.
        subject.send(
            AudioMeterFrame(
                timestamp: t0.addingTimeInterval(0.30),
                rms: 0.01,
                peak: 0.02,
                rmsDBFS: -80,
                peakDBFS: -75
            )
        )
        XCTAssertFalse(analysisService.latestFrame.isAttack)

        subject.send(
            AudioMeterFrame(
                timestamp: t0.addingTimeInterval(0.42),
                rms: 0.78,
                peak: 0.98,
                rmsDBFS: -16,
                peakDBFS: -10
            )
        )
        XCTAssertTrue(analysisService.latestFrame.isAttack)
        XCTAssertEqual(analysisService.latestFrame.attackID, firstAttackID + 1)

        analysisService.stopAnalysis()
    }

    func testLiveInputCalibrationServiceDeterministicallyMapsAmbientFrames() async throws {
        let subject = PassthroughSubject<AudioMeterFrame, Never>()
        let calibrationService = LiveInputCalibrationService(
            meterPublisher: subject.eraseToAnyPublisher(),
            calibrationWindowSeconds: 0.8
        )

        let task = Task { try await calibrationService.beginCalibration() }
        try await Task.sleep(nanoseconds: 30_000_000)

        let baseTime = Date(timeIntervalSince1970: 20_000)
        let frames: [AudioMeterFrame] = [
            AudioMeterFrame(timestamp: baseTime, rms: 0.010, peak: 0.020, rmsDBFS: -62, peakDBFS: -56),
            AudioMeterFrame(timestamp: baseTime.addingTimeInterval(0.10), rms: 0.012, peak: 0.023, rmsDBFS: -60, peakDBFS: -54),
            AudioMeterFrame(timestamp: baseTime.addingTimeInterval(0.20), rms: 0.015, peak: 0.026, rmsDBFS: -58, peakDBFS: -52),
            AudioMeterFrame(timestamp: baseTime.addingTimeInterval(0.30), rms: 0.018, peak: 0.030, rmsDBFS: -56, peakDBFS: -50),
            AudioMeterFrame(timestamp: baseTime.addingTimeInterval(0.40), rms: 0.022, peak: 0.034, rmsDBFS: -54, peakDBFS: -48),
            AudioMeterFrame(timestamp: baseTime.addingTimeInterval(0.50), rms: 0.026, peak: 0.040, rmsDBFS: -52, peakDBFS: -46),
            AudioMeterFrame(timestamp: baseTime.addingTimeInterval(0.60), rms: 0.030, peak: 0.045, rmsDBFS: -50, peakDBFS: -44),
        ]
        for frame in frames {
            subject.send(frame)
        }

        let result = try await task.value
        XCTAssertEqual(result.measuredNoiseFloorDBFS, -53.36, accuracy: 0.2)
        XCTAssertEqual(result.measuredAmbientEnergy, 0.02568, accuracy: 0.001)
        XCTAssertEqual(result.attackThresholdDB, 9.935, accuracy: 0.2)
        XCTAssertEqual(result.silenceGateThreshold, 0.0393, accuracy: 0.003)
    }

    func testLiveAudioAnalysisUsesDBFSMeterWhenAvailable() async throws {
        let subject = PassthroughSubject<AudioMeterFrame, Never>()
        let analysisService = LiveAudioAnalysisService(meterPublisher: subject.eraseToAnyPublisher())
        analysisService.updateTuning(
            AudioAnalysisTuning(
                attackThresholdDB: 8,
                attackHysteresisDB: 2,
                attackCooldownMS: 70,
                inputGainDB: 0
            )
        )

        try await analysisService.startAnalysis()

        let start = Date(timeIntervalSince1970: 2_000)
        subject.send(
            AudioMeterFrame(
                timestamp: start,
                rms: 0.03,
                peak: 0.04,
                rmsDBFS: -82,
                peakDBFS: -76
            )
        )
        XCTAssertFalse(analysisService.latestFrame.isAttack)

        subject.send(
            AudioMeterFrame(
                timestamp: start.addingTimeInterval(0.12),
                rms: 0.03,
                peak: 0.04,
                rmsDBFS: -20,
                peakDBFS: -14
            )
        )
        XCTAssertTrue(analysisService.latestFrame.isAttack)
        XCTAssertGreaterThan(analysisService.latestFrame.attackDbOverFloor, 8)

        analysisService.stopAnalysis()
    }

    func testYINDetectsStableSine() {
        let sampleRate = 48_000.0
        let frequency = 440.0
        let samples = makeSine(frequency: frequency, sampleRate: sampleRate, count: 4_096, amplitude: 0.5)

        let detected = detectPitchYIN(samples: samples, sampleRate: sampleRate)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected?.hz ?? 0, frequency, accuracy: 4.0)
        XCTAssertGreaterThan(detected?.confidence ?? 0, 0.55)
    }

    func testHPSProducesPitchForStableSine() {
        let sampleRate = 48_000.0
        let frequency = 220.0
        let samples = makeSine(frequency: frequency, sampleRate: sampleRate, count: 2_048, amplitude: 0.5)

        let detected = detectPitchHPS(samples: samples, sampleRate: sampleRate)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected?.hz ?? 0, frequency, accuracy: 8.0)
        XCTAssertGreaterThanOrEqual(detected?.confidence ?? 0, 0)
    }

    func testPitchResolverFallsBackToHPSWhenYINMissing() {
        let hps = PitchDetectionResult(hz: 293.66, confidence: 0.71)
        let resolved = resolvePitchDetection(
            yinResult: nil,
            hpsResult: hps,
            signalGate: 1.0,
            signalActive: true,
            signalProfile: PitchSignalProfile(tonalLikelihood: 0.55, noiseLikelihood: 0.25, voiceLikelihood: 0.70)
        )

        guard let resolved else {
            return XCTFail("Expected HPS fallback result")
        }
        XCTAssertEqual(resolved.hz, hps.hz, accuracy: 0.0001)
        XCTAssertGreaterThan(resolved.confidence, 0.4)
    }

    func testPitchSignalProfileSeparatesToneAndNoise() {
        let sampleRate = 48_000.0
        let tone = makeSine(frequency: 220, sampleRate: sampleRate, count: 2_048, amplitude: 0.5)
        let noise = makeWhiteNoise(count: 2_048, amplitude: 0.5)

        let toneProfile = analyzePitchSignalProfile(samples: tone, sampleRate: sampleRate)
        let noiseProfile = analyzePitchSignalProfile(samples: noise, sampleRate: sampleRate)

        XCTAssertGreaterThan(toneProfile.tonalLikelihood, noiseProfile.tonalLikelihood)
        XCTAssertLessThan(toneProfile.noiseLikelihood, noiseProfile.noiseLikelihood)
    }

    func testPitchResolverConfidenceRespondsToSignalProfile() {
        let yin = PitchDetectionResult(hz: 261.63, confidence: 0.82)
        let hps = PitchDetectionResult(hz: 261.10, confidence: 0.74)

        let neutral = resolvePitchDetection(
            yinResult: yin,
            hpsResult: hps,
            signalGate: 1.0,
            signalActive: true,
            signalProfile: PitchSignalProfile(tonalLikelihood: 0.5, noiseLikelihood: 0.5, voiceLikelihood: 0.5)
        )
        let voiceLike = resolvePitchDetection(
            yinResult: yin,
            hpsResult: hps,
            signalGate: 1.0,
            signalActive: true,
            signalProfile: PitchSignalProfile(tonalLikelihood: 0.86, noiseLikelihood: 0.12, voiceLikelihood: 0.88)
        )
        let noisy = resolvePitchDetection(
            yinResult: yin,
            hpsResult: hps,
            signalGate: 1.0,
            signalActive: true,
            signalProfile: PitchSignalProfile(tonalLikelihood: 0.12, noiseLikelihood: 0.90, voiceLikelihood: 0.10)
        )

        guard let neutral, let voiceLike, let noisy else {
            return XCTFail("Expected resolver outputs for profile comparison")
        }
        XCTAssertGreaterThan(voiceLike.confidence, neutral.confidence)
        XCTAssertLessThan(noisy.confidence, neutral.confidence)
    }

    func testPitchStabilityHysteresisPreventsBoundaryChatter() {
        var tracker = PitchStabilityTracker()
        let t0 = Date(timeIntervalSince1970: 10_000)

        // Establish lock on A (MIDI 69, class 9)
        _ = tracker.update(hz: 440.0, confidence: 0.92, signalActive: true, timestamp: t0)
        _ = tracker.update(hz: 440.5, confidence: 0.90, signalActive: true, timestamp: t0.addingTimeInterval(0.06))
        let locked = tracker.update(hz: 441.0, confidence: 0.91, signalActive: true, timestamp: t0.addingTimeInterval(0.12))
        XCTAssertEqual(locked.stablePitchClass, 9)

        // Boundary-near movement should not switch lock.
        let nearBoundary = tracker.update(hz: 453.5, confidence: 0.90, signalActive: true, timestamp: t0.addingTimeInterval(0.16))
        XCTAssertEqual(nearBoundary.stablePitchClass, 9)
    }

    func testPitchStabilityReleasesAfterSustainedLowConfidence() {
        var tracker = PitchStabilityTracker()
        let t0 = Date(timeIntervalSince1970: 20_000)

        _ = tracker.update(hz: 329.63, confidence: 0.92, signalActive: true, timestamp: t0)
        _ = tracker.update(hz: 329.63, confidence: 0.92, signalActive: true, timestamp: t0.addingTimeInterval(0.06))
        let locked = tracker.update(hz: 329.63, confidence: 0.92, signalActive: true, timestamp: t0.addingTimeInterval(0.12))
        XCTAssertNotNil(locked.stablePitchClass)

        let held = tracker.update(hz: nil, confidence: 0.1, signalActive: false, timestamp: t0.addingTimeInterval(0.20))
        XCTAssertNotNil(held.stablePitchClass)

        let released = tracker.update(hz: nil, confidence: 0.1, signalActive: false, timestamp: t0.addingTimeInterval(0.40))
        XCTAssertNil(released.stablePitchClass)
    }

    private func makeSine(frequency: Double, sampleRate: Double, count: Int, amplitude: Double) -> [Float] {
        (0 ..< count).map { index in
            let t = Double(index) / sampleRate
            return Float(sin(2 * Double.pi * frequency * t) * amplitude)
        }
    }

    private func makeWhiteNoise(count: Int, amplitude: Double) -> [Float] {
        var state: UInt64 = 0xC0FFEE
        return (0 ..< count).map { _ in
            state = state &* 6364136223846793005 &+ 1
            let value = Double((state >> 33) & 0xFFFF) / 65535.0
            let centered = (value * 2) - 1
            return Float(centered * amplitude)
        }
    }
}
