import Foundation
import Combine
import Accelerate

public protocol AudioAnalysisService: AnyObject {
    var latestFrame: AudioFeatureFrame { get }
    var framePublisher: AnyPublisher<AudioFeatureFrame, Never> { get }
    func startAnalysis() async throws
    func stopAnalysis()
    func updateTuning(_ tuning: AudioAnalysisTuning)
}

public final class PlaceholderAudioAnalysisService: AudioAnalysisService {
    public private(set) var latestFrame: AudioFeatureFrame
    public var framePublisher: AnyPublisher<AudioFeatureFrame, Never> {
        subject.eraseToAnyPublisher()
    }
    public private(set) var currentTuning: AudioAnalysisTuning

    private let subject: CurrentValueSubject<AudioFeatureFrame, Never>

    public init(
        latestFrame: AudioFeatureFrame = .silent,
        currentTuning: AudioAnalysisTuning = .default
    ) {
        self.latestFrame = latestFrame
        self.currentTuning = currentTuning
        subject = CurrentValueSubject(latestFrame)
    }

    public func startAnalysis() async throws {
    }

    public func stopAnalysis() {
    }

    public func updateTuning(_ tuning: AudioAnalysisTuning) {
        currentTuning = tuning.clamped()
    }

    public func publishForTesting(_ frame: AudioFeatureFrame) {
        latestFrame = frame
        subject.send(frame)
    }
}

public final class LiveAudioAnalysisService: AudioAnalysisService {
    public private(set) var latestFrame: AudioFeatureFrame
    public var framePublisher: AnyPublisher<AudioFeatureFrame, Never> {
        subject.eraseToAnyPublisher()
    }

    private let meterPublisher: AnyPublisher<AudioMeterFrame, Never>
    private let samplePublisher: AnyPublisher<AudioSampleFrame, Never>
    private let subject: CurrentValueSubject<AudioFeatureFrame, Never>
    private var cancellables: Set<AnyCancellable> = []

    private var smoothedAmplitude: Double = 0
    private var previousAmplitude: Double = 0
    private var rollingNoiseFloorDB: Double = -72
    private var previousDbOverFloor: Double = 0
    private var gateArmed = true
    private var lastAttackTimestamp: Date = .distantPast
    private var currentAttackID: UInt64 = 0
    private var nextAttackID: UInt64 = 0
    private var currentTuning: AudioAnalysisTuning
    private var hasInitializedNoiseFloor = false
    private var processedFrameCount: UInt64 = 0

    private let pitchQueue = DispatchQueue(label: "chroma.analysis.pitch", qos: .userInitiated)
    private let pitchObservationLock = NSLock()
    private var pitchObservation = PitchObservation()
    private var pitchDetector = PitchDetectorState()
    private var pitchStability = PitchStabilityTracker()

    public init(
        meterPublisher: AnyPublisher<AudioMeterFrame, Never>,
        samplePublisher: AnyPublisher<AudioSampleFrame, Never> = Empty<AudioSampleFrame, Never>().eraseToAnyPublisher(),
        initialTuning: AudioAnalysisTuning = .default
    ) {
        self.meterPublisher = meterPublisher
        self.samplePublisher = samplePublisher
        self.latestFrame = .silent
        self.subject = CurrentValueSubject(.silent)
        self.currentTuning = initialTuning.clamped()
    }

    public func startAnalysis() async throws {
        guard cancellables.isEmpty else { return }
        resetState()

        meterPublisher
            .sink { [weak self] meterFrame in
                self?.consume(meterFrame: meterFrame)
            }
            .store(in: &cancellables)

        samplePublisher
            .sink { [weak self] sampleFrame in
                self?.enqueue(sampleFrame: sampleFrame)
            }
            .store(in: &cancellables)
    }

    public func stopAnalysis() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        resetState()
    }

    public func updateTuning(_ tuning: AudioAnalysisTuning) {
        currentTuning = tuning.clamped()
    }

    private func resetState() {
        processedFrameCount = 0
        previousDbOverFloor = 0
        gateArmed = true
        lastAttackTimestamp = .distantPast
        hasInitializedNoiseFloor = false
        smoothedAmplitude = 0
        previousAmplitude = 0
        rollingNoiseFloorDB = -72
        currentAttackID = 0
        nextAttackID = 0
        latestFrame = .silent
        subject.send(.silent)

        pitchObservationLock.lock()
        pitchObservation = PitchObservation()
        pitchObservationLock.unlock()

        pitchQueue.async { [weak self] in
            guard let self else { return }
            self.pitchDetector = PitchDetectorState()
            self.pitchStability = PitchStabilityTracker()
        }
    }

    private func enqueue(sampleFrame: AudioSampleFrame) {
        guard !sampleFrame.monoSamples.isEmpty else { return }
        pitchQueue.async { [weak self] in
            self?.consume(sampleFrame: sampleFrame)
        }
    }

    private func consume(sampleFrame: AudioSampleFrame) {
        guard sampleFrame.sampleRate > 0 else { return }

        pitchDetector.append(sampleFrame.monoSamples)
        guard let window = pitchDetector.latestWindow() else { return }

        let rms = rmsLinear(window)
        let signalGate = normalizedSignalGate(rms)
        let signalActive = signalGate >= 0.22

        let yinResult = detectPitchYIN(samples: window, sampleRate: sampleFrame.sampleRate)
        let hpsWindow = window.count >= 2048 ? Array(window.suffix(2048)) : window
        let hpsResult = detectPitchHPS(samples: hpsWindow, sampleRate: sampleFrame.sampleRate)
        let signalProfile = analyzePitchSignalProfile(
            samples: hpsWindow,
            sampleRate: sampleFrame.sampleRate
        )

        let resolved = resolvePitchDetection(
            yinResult: yinResult,
            hpsResult: hpsResult,
            signalGate: signalGate,
            signalActive: signalActive,
            signalProfile: signalProfile
        )
        let pitchHz = resolved?.hz
        let confidence = resolved?.confidence ?? 0

        let stable = pitchStability.update(
            hz: pitchHz,
            confidence: confidence,
            signalActive: signalActive,
            timestamp: sampleFrame.timestamp
        )

        setPitchObservation(
            PitchObservation(
                hz: pitchHz,
                confidence: confidence,
                stablePitchClass: stable.stablePitchClass,
                stablePitchCents: stable.stablePitchCents
            )
        )
    }

    private func consume(meterFrame: AudioMeterFrame) {
        processedFrameCount &+= 1

        let tuning = currentTuning
        let rmsDBFS = meterFrame.rmsDBFS ?? linearToDecibels(meterFrame.rms)
        let peakDBFS = meterFrame.peakDBFS ?? linearToDecibels(meterFrame.peak)
        let weightedSignalDB = (rmsDBFS * 0.78) + (peakDBFS * 0.22)
        let signalDB = (weightedSignalDB + tuning.inputGainDB).clamped(to: -120 ... 0)

        if !hasInitializedNoiseFloor {
            rollingNoiseFloorDB = min(signalDB, -54)
            previousDbOverFloor = 0
            hasInitializedNoiseFloor = true
        }
        updateNoiseFloor(signalDB: signalDB)

        let dbOverFloor = min(max(signalDB - rollingNoiseFloorDB, 0), 60)
        let normalizedInput = min(max(dbOverFloor / 30, 0), 1)
        let shapedInput = pow(normalizedInput, 0.64)

        let blend = shapedInput > smoothedAmplitude ? 0.38 : 0.16
        smoothedAmplitude = (smoothedAmplitude * (1 - blend)) + (shapedInput * blend)
        let amplitude = min(max(smoothedAmplitude * 1.12, 0), 1)

        let transientDelta = max(0, amplitude - previousAmplitude)
        let peakOverFloor = max(0, (peakDBFS + tuning.inputGainDB) - rollingNoiseFloorDB)
        let peakTransient = min(max(peakOverFloor / 24, 0), 1)
        let transient = min(max((transientDelta * 4.4) + (peakTransient * 0.32), 0), 1)
        previousAmplitude = amplitude

        let attack = detectAttack(
            dbOverFloor: dbOverFloor,
            transientStrength: transient,
            timestamp: meterFrame.timestamp,
            frameCount: processedFrameCount
        )

        let lowBand = min(max((amplitude * 0.80) + (meterFrame.rms * 0.20), 0), 1)
        let midBand = min(max((amplitude * 0.62) + (transient * 0.38), 0), 1)
        let highBand = min(max((meterFrame.peak * 0.68) + (transient * 0.32), 0), 1)
        let pitch = getPitchObservation()

        let frame = AudioFeatureFrame(
            timestamp: meterFrame.timestamp,
            amplitude: amplitude,
            lowBandEnergy: lowBand,
            midBandEnergy: midBand,
            highBandEnergy: highBand,
            transientStrength: transient,
            pitchHz: pitch.hz,
            pitchConfidence: pitch.confidence,
            stablePitchClass: pitch.stablePitchClass,
            stablePitchCents: pitch.stablePitchCents,
            isAttack: attack.isAttack,
            attackStrength: attack.strength,
            attackID: currentAttackID,
            attackDbOverFloor: dbOverFloor
        )
        latestFrame = frame
        subject.send(frame)
    }

    private func setPitchObservation(_ observation: PitchObservation) {
        pitchObservationLock.lock()
        pitchObservation = observation
        pitchObservationLock.unlock()
    }

    private func getPitchObservation() -> PitchObservation {
        pitchObservationLock.lock()
        defer { pitchObservationLock.unlock() }
        return pitchObservation
    }

    private func updateNoiseFloor(signalDB: Double) {
        let riseAlpha = 0.005 // Slow rise in louder rooms.
        let fallAlpha = 0.10  // Faster fall when ambient level drops.
        let alpha = signalDB > rollingNoiseFloorDB ? riseAlpha : fallAlpha
        rollingNoiseFloorDB = ((1 - alpha) * rollingNoiseFloorDB) + (alpha * signalDB)
        rollingNoiseFloorDB = rollingNoiseFloorDB.clamped(to: -96 ... -18)
    }

    private func detectAttack(
        dbOverFloor: Double,
        transientStrength: Double,
        timestamp: Date,
        frameCount: UInt64
    ) -> (isAttack: Bool, strength: Double) {
        let tuning = currentTuning
        let slope = dbOverFloor - previousDbOverFloor
        previousDbOverFloor = dbOverFloor

        if !gateArmed {
            let rearmThreshold = max(0, tuning.attackThresholdDB - tuning.attackHysteresisDB)
            if dbOverFloor <= rearmThreshold {
                gateArmed = true
            }
        }

        let isOffCooldown = timestamp.timeIntervalSince(lastAttackTimestamp) >= tuning.attackCooldownSeconds
        let isWarmedUp = frameCount >= 2
        let shouldTrigger = isWarmedUp && gateArmed && isOffCooldown && dbOverFloor >= tuning.attackThresholdDB && slope > 0.4

        guard shouldTrigger else {
            return (false, 0)
        }

        gateArmed = false
        lastAttackTimestamp = timestamp
        nextAttackID &+= 1
        currentAttackID = max(nextAttackID, 1)

        let overThreshold = max(0, dbOverFloor - tuning.attackThresholdDB)
        let dbStrength = min(max(overThreshold / 10, 0), 1)
        let strength = min(max((dbStrength * 0.72) + (transientStrength * 0.28), 0), 1)
        return (true, strength)
    }

    private func linearToDecibels(_ linear: Double) -> Double {
        guard linear > 0 else { return -120 }
        return (20 * log10(linear)).clamped(to: -120 ... 0)
    }

    private func rmsLinear(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            vDSP_rmsqv(baseAddress, 1, &rms, vDSP_Length(samples.count))
        }
        return Double(rms)
    }

    private func normalizedSignalGate(_ rms: Double) -> Double {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let clamped = db.clamped(to: -66 ... -18)
        return ((clamped + 66) / 48).clamped(to: 0 ... 1)
    }
}

struct PitchDetectionResult: Equatable {
    var hz: Double
    var confidence: Double
}

struct PitchSignalProfile: Equatable {
    var tonalLikelihood: Double
    var noiseLikelihood: Double
    var voiceLikelihood: Double
}

func resolvePitchDetection(
    yinResult: PitchDetectionResult?,
    hpsResult: PitchDetectionResult?,
    signalGate: Double,
    signalActive: Bool,
    signalProfile: PitchSignalProfile?
) -> PitchDetectionResult? {
    let profile = signalProfile ?? PitchSignalProfile(
        tonalLikelihood: 0.5,
        noiseLikelihood: 0.5,
        voiceLikelihood: 0.5
    )
    let selected = yinResult ?? hpsResult
    guard var selected else { return nil }

    if let yinResult, let hpsResult {
        let agreementCents = abs(centsDistance(hzA: yinResult.hz, hzB: hpsResult.hz))
        let agreementToleranceCents = 45 + (profile.tonalLikelihood * 35)
        let agreementWeight = 1.0 - min(max(agreementCents / agreementToleranceCents, 0), 1)
        let yinBlend = (0.62 + (profile.voiceLikelihood * 0.23) - (profile.noiseLikelihood * 0.17)).clamped(to: 0.50 ... 0.86)
        let agreementBlend = 1 - yinBlend
        selected.confidence = (yinResult.confidence * yinBlend) + (agreementWeight * agreementBlend)
    } else if yinResult != nil {
        // Voice-like material tends to track better with YIN.
        selected.confidence *= (1 + (profile.voiceLikelihood * 0.16))
    } else if hpsResult != nil {
        // HPS-only path should be conservative on noisy stage input.
        selected.confidence *= (1 - (profile.noiseLikelihood * 0.24))
    }

    selected.confidence = (selected.confidence * signalGate).clamped(to: 0 ... 1)
    let noisePenalty = 1 - (profile.noiseLikelihood * 0.46)
    let voiceBoost = 1 + (profile.voiceLikelihood * 0.22)
    let tonalBoost = 1 + (profile.tonalLikelihood * 0.10)
    selected.confidence = (selected.confidence * noisePenalty * voiceBoost * tonalBoost).clamped(to: 0 ... 1)

    let dynamicFloor = (0.06 + (profile.noiseLikelihood * 0.10) - (profile.voiceLikelihood * 0.03)).clamped(to: 0.04 ... 0.14)
    guard signalActive, selected.confidence >= dynamicFloor else {
        return nil
    }

    return selected
}

func analyzePitchSignalProfile(samples: [Float], sampleRate: Double) -> PitchSignalProfile {
    guard sampleRate > 0, samples.count >= 1024 else {
        return PitchSignalProfile(tonalLikelihood: 0.5, noiseLikelihood: 0.5, voiceLikelihood: 0.5)
    }

    let windowSize = 1024
    var x = Array(samples.suffix(windowSize))

    var mean: Float = 0
    vDSP_meanv(x, 1, &mean, vDSP_Length(windowSize))
    var negMean = -mean
    vDSP_vsadd(x, 1, &negMean, &x, 1, vDSP_Length(windowSize))

    var hann = [Float](repeating: 0, count: windowSize)
    vDSP_hann_window(&hann, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
    vDSP_vmul(x, 1, hann, 1, &x, 1, vDSP_Length(windowSize))

    let log2n = vDSP_Length(round(log2(Float(windowSize))))
    guard (1 << log2n) == windowSize else {
        return PitchSignalProfile(tonalLikelihood: 0.5, noiseLikelihood: 0.5, voiceLikelihood: 0.5)
    }

    guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
        return PitchSignalProfile(tonalLikelihood: 0.5, noiseLikelihood: 0.5, voiceLikelihood: 0.5)
    }
    defer { vDSP_destroy_fftsetup(setup) }

    let half = windowSize / 2
    var magnitude = [Float](repeating: 0, count: half)
    var real = x
    var imag = [Float](repeating: 0, count: windowSize)
    real.withUnsafeMutableBufferPointer { realBuffer in
        imag.withUnsafeMutableBufferPointer { imagBuffer in
            guard
                let realBase = realBuffer.baseAddress,
                let imagBase = imagBuffer.baseAddress
            else { return }

            var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
            vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            vDSP_zvabs(&split, 1, &magnitude, 1, vDSP_Length(half))
        }
    }

    let epsilon = 1e-8
    let safeMags = magnitude.map { Double(max($0, Float(epsilon))) }
    let arithmeticMean = safeMags.reduce(0, +) / Double(max(safeMags.count, 1))
    let logMean = safeMags.map(log).reduce(0, +) / Double(max(safeMags.count, 1))
    let geometricMean = exp(logMean)
    let flatness = (geometricMean / max(arithmeticMean, epsilon)).clamped(to: 0 ... 1)

    let peak = safeMags.max() ?? 0
    let peakRatio = (peak / max(arithmeticMean, epsilon)).clamped(to: 1 ... 200)
    let peakProminence = ((peakRatio - 1) / 14).clamped(to: 0 ... 1)

    var zeroCrossings = 0
    for index in 1 ..< x.count {
        if (x[index - 1] >= 0 && x[index] < 0) || (x[index - 1] < 0 && x[index] >= 0) {
            zeroCrossings += 1
        }
    }
    let zcr = Double(zeroCrossings) / Double(max(x.count - 1, 1))
    let zcrNormalized = ((zcr - 0.015) / 0.30).clamped(to: 0 ... 1)

    let binHz = sampleRate / Double(windowSize)
    let voiceStart = max(1, Int(80 / binHz))
    let voiceEnd = min(half - 1, Int(420 / binHz))
    let bodyEnd = min(half - 1, Int(4_000 / binHz))
    let voiceEnergy = safeMags[voiceStart ... voiceEnd].reduce(0, +)
    let bodyEnergy = safeMags[voiceStart ... bodyEnd].reduce(0, +)
    let voiceBandRatio = (voiceEnergy / max(bodyEnergy, epsilon)).clamped(to: 0 ... 1)

    let tonalLikelihood = ((1 - flatness) * 0.62 + peakProminence * 0.38).clamped(to: 0 ... 1)
    let noiseLikelihood = (flatness * 0.68 + zcrNormalized * 0.32).clamped(to: 0 ... 1)

    // Voice-like profile is harmonic with strong 80-420 Hz body and moderate ZCR.
    let zcrVoiceCenter = (1 - abs(zcrNormalized - 0.33) / 0.33).clamped(to: 0 ... 1)
    let voiceLikelihood = (voiceBandRatio * 0.55 + tonalLikelihood * 0.30 + zcrVoiceCenter * 0.15).clamped(to: 0 ... 1)

    return PitchSignalProfile(
        tonalLikelihood: tonalLikelihood,
        noiseLikelihood: noiseLikelihood,
        voiceLikelihood: voiceLikelihood
    )
}

func detectPitchYIN(
    samples: [Float],
    sampleRate: Double,
    minHz: Double = 55,
    maxHz: Double = 1_760
) -> PitchDetectionResult? {
    let nFull = samples.count
    guard nFull >= 2_048, sampleRate > 0 else { return nil }

    let windowSize = nFull >= 4_096 ? 4_096 : 2_048
    let start = max((nFull - windowSize) / 2, 0)
    var x = Array(samples[start ..< start + windowSize])

    var mean: Float = 0
    vDSP_meanv(x, 1, &mean, vDSP_Length(windowSize))
    var negMean = -mean
    vDSP_vsadd(x, 1, &negMean, &x, 1, vDSP_Length(windowSize))

    var hann = [Float](repeating: 0, count: windowSize)
    vDSP_hann_window(&hann, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
    vDSP_vmul(x, 1, hann, 1, &x, 1, vDSP_Length(windowSize))

    let maxTau = min(windowSize - 2, Int(floor(sampleRate / minHz)))
    let minTau = max(2, Int(floor(sampleRate / maxHz)))
    guard maxTau > minTau else { return nil }

    var d = [Float](repeating: 0, count: maxTau + 1)
    var cumulative = [Float](repeating: 0, count: maxTau + 1)
    var diff = [Float](repeating: 0, count: windowSize)

    x.withUnsafeBufferPointer { ptr in
        guard let base = ptr.baseAddress else { return }
        for tau in 1 ... maxTau {
            let len = windowSize - tau
            vDSP_vsub(base + tau, 1, base, 1, &diff, 1, vDSP_Length(len))
            var sq: Float = 0
            vDSP_svesq(diff, 1, &sq, vDSP_Length(len))
            d[tau] = sq
            cumulative[tau] = cumulative[tau - 1] + sq
        }
    }

    var cmnd = [Float](repeating: 1, count: maxTau + 1)
    for tau in minTau ... maxTau {
        let denom = cumulative[tau] / Float(tau)
        cmnd[tau] = denom > 0 ? d[tau] / denom : 1
    }

    let threshold: Float = 0.15
    var bestTau = -1
    var bestValue: Float = 1

    for t in max(minTau + 1, 2) ... (maxTau - 1) {
        let value = cmnd[t]
        if value < threshold, value <= cmnd[t - 1], value <= cmnd[t + 1] {
            bestTau = t
            bestValue = value
            break
        }
    }

    if bestTau < 0 {
        for t in minTau ... maxTau {
            let value = cmnd[t]
            if value < bestValue {
                bestValue = value
                bestTau = t
            }
        }
    }

    guard bestTau > 1 else { return nil }

    let t = bestTau
    let ym1 = cmnd[max(t - 1, minTau)]
    let y0 = cmnd[t]
    let yp1 = cmnd[min(t + 1, maxTau)]
    let denom = (2 * (ym1 - (2 * y0) + yp1))
    var shift: Float = 0
    if abs(denom) > 1e-6 {
        shift = (ym1 - yp1) / denom
        shift = max(-1, min(1, shift))
    }

    let tau = Double(t) + Double(shift)
    guard tau > 0 else { return nil }

    let hz = sampleRate / tau
    guard hz.isFinite, hz >= minHz, hz <= maxHz else { return nil }

    let quality = max(0, min(1, (0.24 - Double(bestValue)) / 0.24))
    let confidence = bestValue < threshold ? max(quality, 0.55) : quality
    return PitchDetectionResult(hz: hz, confidence: confidence.clamped(to: 0 ... 1))
}

func detectPitchHPS(
    samples: [Float],
    sampleRate: Double,
    minHz: Double = 55,
    maxHz: Double = 1_760
) -> PitchDetectionResult? {
    let n = 2_048
    guard samples.count >= n, sampleRate > 0 else { return nil }

    var x = Array(samples.prefix(n))
    var mean: Float = 0
    vDSP_meanv(x, 1, &mean, vDSP_Length(n))
    var negMean = -mean
    vDSP_vsadd(x, 1, &negMean, &x, 1, vDSP_Length(n))

    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    var weighted = [Float](repeating: 0, count: n)
    vDSP_vmul(x, 1, window, 1, &weighted, 1, vDSP_Length(n))

    let log2n = vDSP_Length(round(log2(Float(n))))
    guard (1 << log2n) == n else { return nil }

    guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
    defer { vDSP_destroy_fftsetup(setup) }

    var magnitude = [Float](repeating: 0, count: n / 2)
    var real = weighted
    var imag = [Float](repeating: 0, count: n)
    real.withUnsafeMutableBufferPointer { realBuffer in
        imag.withUnsafeMutableBufferPointer { imagBuffer in
            guard
                let realBase = realBuffer.baseAddress,
                let imagBase = imagBuffer.baseAddress
            else { return }

            var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
            vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            vDSP_zvabs(&split, 1, &magnitude, 1, vDSP_Length(n / 2))
        }
    }

    let size = n / 2
    let minBin = max(1, Int(floor(minHz * Double(n) / sampleRate)))
    let maxBin = min(size - 2, Int(ceil(maxHz * Double(n) / sampleRate)))
    guard maxBin > minBin else { return nil }

    // Stabilized harmonic score for live fallback:
    // strong fundamental response, then harmonic support without forcing
    // pure-tone inputs to collapse toward low-frequency bins.
    let epsilon: Float = 1e-7
    var score = [Float](repeating: 0, count: size)
    for i in minBin ..< maxBin {
        let m1 = magnitude[i]
        let m2 = (i * 2) < size ? magnitude[i * 2] : epsilon
        let m3 = (i * 3) < size ? magnitude[i * 3] : epsilon
        let s1 = logf(m1 + epsilon)
        let s2 = logf(m2 + epsilon)
        let s3 = logf(m3 + epsilon)
        score[i] = (0.68 * s1) + (0.22 * s2) + (0.10 * s3)
    }

    var bestIndex = -1
    var bestValue: Float = -.greatestFiniteMagnitude
    for i in minBin ..< maxBin {
        let value = score[i]
        if value > bestValue {
            bestValue = value
            bestIndex = i
        }
    }

    guard bestIndex > 1, bestValue.isFinite else { return nil }

    let ym1 = score[bestIndex - 1]
    let y0 = score[bestIndex]
    let yp1 = score[bestIndex + 1]
    let denom = (2 * (ym1 - (2 * y0) + yp1))
    var shift: Float = 0
    if abs(denom) > 1e-6 {
        shift = (ym1 - yp1) / denom
        shift = max(-1, min(1, shift))
    }

    let bin = Double(bestIndex) + Double(shift)
    let hz = bin * sampleRate / Double(n)
    guard hz.isFinite, hz > 0 else { return nil }

    let neighborhoodStart = max(minBin, bestIndex - 10)
    let neighborhoodEnd = min(maxBin, bestIndex + 10)
    var scoreNeighborhoodSum: Float = 0
    var magnitudeNeighborhoodSum: Float = 0
    var neighborhoodCount = 0
    for i in neighborhoodStart ... neighborhoodEnd {
        if i == bestIndex { continue }
        scoreNeighborhoodSum += score[i]
        magnitudeNeighborhoodSum += magnitude[i]
        neighborhoodCount += 1
    }
    let scoreNeighborhoodMean = neighborhoodCount > 0 ? scoreNeighborhoodSum / Float(neighborhoodCount) : 0
    let magnitudeNeighborhoodMean = neighborhoodCount > 0 ? magnitudeNeighborhoodSum / Float(neighborhoodCount) : 0
    let scoreProminence = Double(max(bestValue - scoreNeighborhoodMean, 0))
    let magnitudeProminence = Double(magnitude[bestIndex] / max(magnitudeNeighborhoodMean, epsilon))
    let confidence = ((scoreProminence / 2.8) * 0.55 + ((magnitudeProminence - 1.0) / 8.0) * 0.45).clamped(to: 0 ... 1)
    return PitchDetectionResult(hz: hz, confidence: confidence)
}

struct StablePitchResult: Equatable {
    var stablePitchClass: Int?
    var stablePitchCents: Double
}

struct PitchStabilityTracker {
    var stablePitchClass: Int?
    var stablePitchCents: Double = 0
    var candidatePitchClass: Int?
    var candidateCents: Double = 0
    var candidateSince: Date?
    var lowConfidenceSince: Date?

    let lockConfidence: Double = 0.60
    let releaseConfidence: Double = 0.35
    let switchHysteresisCents: Double = 14
    let switchDwellSeconds: Double = 0.09
    let releaseHoldSeconds: Double = 0.18

    mutating func update(hz: Double?, confidence: Double, signalActive: Bool, timestamp: Date) -> StablePitchResult {
        let releaseCondition = !signalActive || confidence < releaseConfidence || hz == nil
        if releaseCondition {
            if lowConfidenceSince == nil {
                lowConfidenceSince = timestamp
            }
            if let lowConfidenceSince,
               timestamp.timeIntervalSince(lowConfidenceSince) >= releaseHoldSeconds {
                stablePitchClass = nil
                stablePitchCents = 0
                candidatePitchClass = nil
                candidateSince = nil
            }
            return StablePitchResult(stablePitchClass: stablePitchClass, stablePitchCents: stablePitchCents)
        }

        lowConfidenceSince = nil
        guard let hz else {
            return StablePitchResult(stablePitchClass: stablePitchClass, stablePitchCents: stablePitchCents)
        }

        let mapping = pitchClassAndCents(hz: hz)

        guard confidence >= lockConfidence else {
            if let stablePitchClass, stablePitchClass == mapping.pitchClass {
                stablePitchCents = (stablePitchCents * 0.76) + (mapping.cents * 0.24)
            }
            return StablePitchResult(stablePitchClass: stablePitchClass, stablePitchCents: stablePitchCents)
        }

        if stablePitchClass == nil {
            startOrCommitCandidate(pitchClass: mapping.pitchClass, cents: mapping.cents, timestamp: timestamp)
            return StablePitchResult(stablePitchClass: stablePitchClass, stablePitchCents: stablePitchCents)
        }

        if stablePitchClass == mapping.pitchClass {
            candidatePitchClass = nil
            candidateSince = nil
            stablePitchCents = (stablePitchCents * 0.68) + (mapping.cents * 0.32)
            return StablePitchResult(stablePitchClass: stablePitchClass, stablePitchCents: stablePitchCents)
        }

        let insideTargetCore = abs(mapping.cents) <= (50 - switchHysteresisCents)
        guard insideTargetCore else {
            candidatePitchClass = nil
            candidateSince = nil
            return StablePitchResult(stablePitchClass: stablePitchClass, stablePitchCents: stablePitchCents)
        }

        startOrCommitCandidate(pitchClass: mapping.pitchClass, cents: mapping.cents, timestamp: timestamp)
        return StablePitchResult(stablePitchClass: stablePitchClass, stablePitchCents: stablePitchCents)
    }

    private mutating func startOrCommitCandidate(pitchClass: Int, cents: Double, timestamp: Date) {
        if candidatePitchClass != pitchClass {
            candidatePitchClass = pitchClass
            candidateCents = cents
            candidateSince = timestamp
            return
        }

        candidateCents = (candidateCents * 0.64) + (cents * 0.36)
        guard let candidateSince else { return }

        if timestamp.timeIntervalSince(candidateSince) >= switchDwellSeconds {
            stablePitchClass = pitchClass
            stablePitchCents = candidateCents.clamped(to: -50 ... 50)
            self.candidatePitchClass = nil
            self.candidateSince = nil
        }
    }
}

private struct PitchObservation {
    var hz: Double?
    var confidence: Double
    var stablePitchClass: Int?
    var stablePitchCents: Double

    init(hz: Double? = nil, confidence: Double = 0, stablePitchClass: Int? = nil, stablePitchCents: Double = 0) {
        self.hz = hz
        self.confidence = confidence.clamped(to: 0 ... 1)
        self.stablePitchClass = stablePitchClass
        self.stablePitchCents = stablePitchCents.clamped(to: -50 ... 50)
    }
}

private struct PitchDetectorState {
    private static let capacity = 4_096
    private(set) var ring = [Float](repeating: 0, count: capacity)
    private(set) var writeIndex = 0
    private(set) var sampleCount = 0

    mutating func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        for sample in samples {
            ring[writeIndex] = sample
            writeIndex = (writeIndex + 1) % Self.capacity
            sampleCount = min(sampleCount + 1, Self.capacity)
        }
    }

    func latestWindow() -> [Float]? {
        let windowSize: Int
        if sampleCount >= 4_096 {
            windowSize = 4_096
        } else if sampleCount >= 2_048 {
            windowSize = 2_048
        } else {
            return nil
        }

        let start = (writeIndex - windowSize + Self.capacity) % Self.capacity
        if start + windowSize <= Self.capacity {
            return Array(ring[start ..< start + windowSize])
        }

        let firstCount = Self.capacity - start
        let secondCount = windowSize - firstCount
        return Array(ring[start ..< Self.capacity] + ring[0 ..< secondCount])
    }
}

private func pitchClassAndCents(hz: Double) -> (pitchClass: Int, cents: Double) {
    let midi = 69.0 + (12.0 * log2(hz / 440.0))
    let nearest = Int(round(midi))
    let wrappedClass = ((nearest % 12) + 12) % 12
    let cents = (midi - Double(nearest)) * 100.0
    return (pitchClass: wrappedClass, cents: cents.clamped(to: -50 ... 50))
}

private func centsDistance(hzA: Double, hzB: Double) -> Double {
    guard hzA > 0, hzB > 0 else { return 0 }
    return 1_200 * log2(hzA / hzB)
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
