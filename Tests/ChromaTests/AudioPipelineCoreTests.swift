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
