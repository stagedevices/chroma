//
//  CoreAudio.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 10/17/25.
//

import Foundation
//
//  CoreAudio.swift
//  Chroma
//
//  Sprint 1: AVAudioEngine input + FFT + spectral-flux onsets + tempo/phase.
//  Publishes AudioFeatures via Combine.
//

import Foundation
import AVFoundation
import Accelerate
import Combine
import QuartzCore // for CACurrentMediaTime()

// MARK: - Public Types
public struct AudioFeatures {
    public var rms: Float
    public var onset: Bool
    public var tempo: Double        // BPM estimate
    public var beatPhase: Double    // 0..1 within current beat
    public var beatCount: Int       // increments on detected beats
    public var fftMagnitudes: [Float]

    public static let empty = AudioFeatures(
        rms: 0, onset: false, tempo: 120, beatPhase: 0, beatCount: 0, fftMagnitudes: []
    )
}

public protocol AudioEngineProtocol {
    var featuresPublisher: AnyPublisher<AudioFeatures, Never> { get }
    func start()
    func stop()
    func tapTempo()
}

// MARK: - SystemAudioEngine
final class SystemAudioEngine: NSObject, AudioEngineProtocol {
    // Public
    var featuresPublisher: AnyPublisher<AudioFeatures, Never> { subject.eraseToAnyPublisher() }

    // Private
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private var subject = PassthroughSubject<AudioFeatures, Never>()
    private var cancellables = Set<AnyCancellable>()

    // FFT config
    private let fftSize: Int = 1024
    private var fftSetup: vDSP_DFT_Setup?
    private var window: [Float] = []
    private var previousSpectrum: [Float] = []

    // Onset / tempo tracking
    private var fluxEMA: Float = 0
    private var fluxVarEMA: Float = 0
    private let fluxAlpha: Float = 0.2
    private var lastOnsetTime: CFTimeInterval = CACurrentMediaTime()
    private var iois: [Double] = [] // inter-onset intervals (s)
    private var beatCounter: Int = 0
    private var tempoBPM: Double = 120
    private var phaseClockStart: CFTimeInterval = CACurrentMediaTime()

    override init() {
        super.init()
        prepareFFT()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTapTempo),
                                               name: .tapTempo,
                                               object: nil)
    }

    @objc private func handleTapTempo() { tapTempo() }


    deinit {
        stop()
        if let setup = fftSetup { vDSP_DFT_DestroySetup(setup) }
    }

    // MARK: Lifecycle
    func start() {
        requestMicIfNeeded()
        configureSession()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let frameCount = AVAudioFrameCount(fftSize)

        input.installTap(onBus: 0, bufferSize: frameCount, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func tapTempo() {
        let now = CACurrentMediaTime()
        let ioi = now - lastOnsetTime
        lastOnsetTime = now
        guard ioi > 0.2 && ioi < 2.5 else { return } // basic guard
        iois.append(ioi)
        if iois.count > 8 { iois.removeFirst(iois.count - 8) }
        tempoBPM = 60.0 / median(iois)
        // reset phase to align
        phaseClockStart = now
    }

    // MARK: Processing
    private func process(buffer: AVAudioPCMBuffer) {
        guard let src = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        if n == 0 { return }

        // Window (rebuild if size changed)
        if window.count != n {
            window = vDSP.window(ofType: Float.self,
                                 usingSequence: .hanningDenormalized,
                                 count: n,
                                 isHalfWindow: false)
        }

        // Copy & apply window (avoid vDSP.multiply on raw pointers)
        var frame = [Float](repeating: 0, count: n)
        for i in 0..<n { frame[i] = src[i] * window[i] }

        // RMS (manual, avoids deprecated C APIs)
        var sumSq: Float = 0
        for x in frame { sumSq += x * x }
        let rms = sqrtf(sumSq / Float(max(n, 1)))

        // FFT -> magnitude spectrum (0..N/2-1), log-compressed + normalized 0..1
        let spectrum = computeSpectrum(frame: frame)

        // Spectral flux (half-wave rectified difference)
        let flux = spectralFlux(current: spectrum, previous: previousSpectrum)
        previousSpectrum = spectrum

        // Adaptive threshold via EMA
        fluxEMA = fluxEMA * (1 - fluxAlpha) + flux * fluxAlpha
        let diff = flux - fluxEMA
        fluxVarEMA = fluxVarEMA * (1 - fluxAlpha) + diff * diff * fluxAlpha
        let threshold = fluxEMA + 1.5 * sqrtf(max(fluxVarEMA, 1e-6))
        let isOnset = flux > threshold && rms > 1e-4

        // Tempo update on onset
        let now = CACurrentMediaTime()
        if isOnset {
            let ioi = now - lastOnsetTime
            lastOnsetTime = now
            if ioi > 0.2 && ioi < 2.5 { // ~24–300 BPM window
                iois.append(ioi)
                if iois.count > 16 { iois.removeFirst(iois.count - 16) }
                tempoBPM = 60.0 / median(iois)
                beatCounter &+= 1
                // Reset phase clock so phase = 0 at onset
                phaseClockStart = now
            }
        }

        // Beat phase from running clock
        let elapsed = now - phaseClockStart
        let secondsPerBeat = 60.0 / max(tempoBPM, 1)
        let phase = elapsed / secondsPerBeat
        let beatPhase = phase - floor(phase) // 0..1

        // Publish
        let features = AudioFeatures(
            rms: rms,
            onset: isOnset,
            tempo: tempoBPM,
            beatPhase: beatPhase,
            beatCount: beatCounter,
            fftMagnitudes: spectrum
        )
        subject.send(features)
        // Broadcast to any UI listener:
        NotificationCenter.default.post(name: .audioFeaturesUpdate, object: features)
        if isOnset {
            NotificationCenter.default.post(name: .audioOnsetFlash, object: nil)
        }
    }

    // MARK: FFT / Spectrum
    private func prepareFFT() {
        if fftSetup == nil {
            fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        }
    }

    /// Returns log-compressed, per-frame normalized magnitudes [0..1] for bins 0..N/2-1.
    private func computeSpectrum(frame: [Float]) -> [Float] {
        // Zero-pad/trim to fftSize
        let n = frame.count
        var real = [Float](repeating: 0, count: fftSize)
        let copyCount = min(n, fftSize)
        if copyCount > 0 {
            real.replaceSubrange(0..<copyCount, with: frame[0..<copyCount])
        }
        var imag = [Float](repeating: 0, count: fftSize)

        // Allocate output
        var outReal = [Float](repeating: 0, count: fftSize)
        var outImag = [Float](repeating: 0, count: fftSize)

        if fftSetup == nil {
            fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        }
        if let setup = fftSetup {
            vDSP_DFT_Execute(setup, real, imag, &outReal, &outImag)
        }

        let half = fftSize / 2
        var mags = [Float](repeating: 0, count: half)
        for i in 0..<half {
            let r = outReal[i]
            let im = outImag[i]
            mags[i] = sqrtf(r*r + im*im)
        }

        // Log compress
        for i in 0..<half {
            mags[i] = logf(mags[i] + 1e-6) // natural log
        }

        // Normalize to 0..1 per frame
        var minVal = mags[0]
        var maxVal = mags[0]
        for v in mags {
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
        }
        let denom = max(maxVal - minVal, 1e-6)
        for i in 0..<half {
            mags[i] = (mags[i] - minVal) / denom
        }
        return mags
    }

    // MARK: Helpers
    /// Half-wave rectified spectral flux between current & previous spectra
    private func spectralFlux(current: [Float], previous: [Float]) -> Float {
        let c = min(current.count, previous.count)
        if c == 0 { return 0 }
        var sum: Float = 0
        for i in 0..<c {
            let d = current[i] - previous[i]
            if d > 0 { sum += d }
        }
        return sum / Float(c) // normalize by bin count
    }

    private func requestMicIfNeeded() {
        session.requestRecordPermission { _ in }
    }

    private func configureSession() {
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.defaultToSpeaker, .mixWithOthers])
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("AVAudioSession config error: \(error)")
        }
    }

    private func median(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0.5 }
        let sorted = arr.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
}

// MARK: - Transport State (simple 4/4 derived)
struct TransportState {
    var tempo: Double = 120
    var bar: Int = 1
    var beat: Int = 1
    var phase: Double = 0
    var beatsPerBar: Int = 4
    private var lastBeatCount: Int = 0

    mutating func update(with f: AudioFeatures) {
        tempo = f.tempo
        phase = f.beatPhase
        if f.beatCount != lastBeatCount {
            let delta = f.beatCount &- lastBeatCount
            for _ in 0..<max(delta, 1) {
                beat += 1
                if beat > beatsPerBar { beat = 1; bar += 1 }
            }
            lastBeatCount = f.beatCount
        }
    }
}
