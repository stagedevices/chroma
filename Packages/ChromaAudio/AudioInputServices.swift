import Foundation
import Combine
import AVFoundation
import Accelerate

public enum AudioInputAuthorizationStatus: String, Codable {
    case notDetermined
    case denied
    case authorized
}

public protocol AudioInputService: AnyObject {
    var authorizationStatus: AudioInputAuthorizationStatus { get }
    var latestMeterFrame: AudioMeterFrame { get }
    var meterPublisher: AnyPublisher<AudioMeterFrame, Never> { get }
    var samplePublisher: AnyPublisher<AudioSampleFrame, Never> { get }
    var availableInputSources: [AudioInputSourceDescriptor] { get }
    var selectedInputSourceID: String? { get }
    var audioEngine: AVAudioEngine? { get }
    func startCapture() async throws
    func stopCapture()
    func refreshInputSources()
    func selectInputSource(id: String) throws
}

public protocol InputCalibrationService: AnyObject {
    func beginCalibration() async throws -> InputCalibrationResult
    func cancelCalibration()
}

public struct InputCalibrationResult: Equatable, Sendable {
    public var attackThresholdDB: Double
    public var silenceGateThreshold: Double
    public var measuredNoiseFloorDBFS: Double
    public var measuredAmbientEnergy: Double

    public init(
        attackThresholdDB: Double,
        silenceGateThreshold: Double,
        measuredNoiseFloorDBFS: Double,
        measuredAmbientEnergy: Double
    ) {
        self.attackThresholdDB = attackThresholdDB
        self.silenceGateThreshold = silenceGateThreshold
        self.measuredNoiseFloorDBFS = measuredNoiseFloorDBFS
        self.measuredAmbientEnergy = measuredAmbientEnergy
    }
}

public final class PlaceholderAudioInputService: AudioInputService {
    public private(set) var authorizationStatus: AudioInputAuthorizationStatus
    public private(set) var latestMeterFrame: AudioMeterFrame
    public var meterPublisher: AnyPublisher<AudioMeterFrame, Never> {
        meterSubject.eraseToAnyPublisher()
    }
    public var samplePublisher: AnyPublisher<AudioSampleFrame, Never> {
        sampleSubject.eraseToAnyPublisher()
    }
    public private(set) var availableInputSources: [AudioInputSourceDescriptor]
    public private(set) var selectedInputSourceID: String?
    public var audioEngine: AVAudioEngine? { nil }

    private let meterSubject: CurrentValueSubject<AudioMeterFrame, Never>
    private let sampleSubject: CurrentValueSubject<AudioSampleFrame, Never>

    public init(
        authorizationStatus: AudioInputAuthorizationStatus = .authorized,
        latestMeterFrame: AudioMeterFrame = .silent
    ) {
        self.authorizationStatus = authorizationStatus
        self.latestMeterFrame = latestMeterFrame
        self.availableInputSources = [
            AudioInputSourceDescriptor(
                id: "placeholder.mic",
                name: "Built-In Mic (Placeholder)",
                transportSummary: "Internal"
            ),
        ]
        self.selectedInputSourceID = "placeholder.mic"
        meterSubject = CurrentValueSubject(latestMeterFrame)
        sampleSubject = CurrentValueSubject(
            AudioSampleFrame(timestamp: .distantPast, sampleRate: 48_000, monoSamples: [])
        )
    }

    public func startCapture() async throws {
    }

    public func stopCapture() {
    }

    public func refreshInputSources() {
    }

    public func selectInputSource(id: String) throws {
        guard availableInputSources.contains(where: { $0.id == id }) else {
            throw AudioInputError.inputNotFound
        }
        selectedInputSourceID = id
    }

    public func publishForTesting(_ frame: AudioMeterFrame) {
        latestMeterFrame = frame
        meterSubject.send(frame)
    }

    public func publishSampleForTesting(_ frame: AudioSampleFrame) {
        sampleSubject.send(frame)
    }
}

public final class PlaceholderInputCalibrationService: InputCalibrationService {
    public init() {
    }

    public func beginCalibration() async throws -> InputCalibrationResult {
        InputCalibrationResult(
            attackThresholdDB: 8,
            silenceGateThreshold: 0.03,
            measuredNoiseFloorDBFS: -56,
            measuredAmbientEnergy: 0.02
        )
    }

    public func cancelCalibration() {
    }
}

public final class LiveInputCalibrationService: InputCalibrationService {
    private let meterPublisher: AnyPublisher<AudioMeterFrame, Never>
    private let calibrationWindowSeconds: TimeInterval
    private let queue = DispatchQueue(label: "chroma.calibration.capture", qos: .userInitiated)

    private var activeCalibrationToken: UUID?
    private var meterCancellable: AnyCancellable?

    public init(
        meterPublisher: AnyPublisher<AudioMeterFrame, Never>,
        calibrationWindowSeconds: TimeInterval = 2.5
    ) {
        self.meterPublisher = meterPublisher
        self.calibrationWindowSeconds = max(0.8, calibrationWindowSeconds)
    }

    public func beginCalibration() async throws -> InputCalibrationResult {
        cancelCalibration()

        let token = UUID()
        activeCalibrationToken = token
        var capturedFrames: [AudioMeterFrame] = []

        meterCancellable = meterPublisher
            .receive(on: queue)
            .sink { frame in
                capturedFrames.append(frame)
            }

        let sleepDuration = UInt64(calibrationWindowSeconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: sleepDuration)

        guard activeCalibrationToken == token else {
            throw CancellationError()
        }

        meterCancellable?.cancel()
        meterCancellable = nil
        activeCalibrationToken = nil

        let frames = queue.sync { capturedFrames }

        return Self.result(from: frames)
    }

    public func cancelCalibration() {
        activeCalibrationToken = nil
        meterCancellable?.cancel()
        meterCancellable = nil
    }

    private static func result(from frames: [AudioMeterFrame]) -> InputCalibrationResult {
        guard !frames.isEmpty else {
            return InputCalibrationResult(
                attackThresholdDB: 8,
                silenceGateThreshold: 0.03,
                measuredNoiseFloorDBFS: -56,
                measuredAmbientEnergy: 0.02
            )
        }

        let dbfsSamples = frames.map { frame in
            frame.rmsDBFS ?? linearToDB(frame.rms)
        }.sorted()
        let energySamples = frames.map(\.rms).sorted()

        let noiseFloorDB = percentile(dbfsSamples, p: 0.72)
        let ambientDB = percentile(dbfsSamples, p: 0.86)
        let ambientEnergy = percentile(energySamples, p: 0.82)

        let ambientNoiseNorm = ((ambientDB + 62) / 32).clamped(to: 0 ... 1)
        let attackThresholdDB = (8 + (ambientNoiseNorm * 6)).clamped(to: 3 ... 18)

        let silenceGateBase = (ambientEnergy * 1.22) + 0.008
        let silenceGateThreshold = silenceGateBase.clamped(to: 0.01 ... 0.20)

        return InputCalibrationResult(
            attackThresholdDB: attackThresholdDB,
            silenceGateThreshold: silenceGateThreshold,
            measuredNoiseFloorDBFS: noiseFloorDB,
            measuredAmbientEnergy: ambientEnergy
        )
    }
}

public final class LiveAudioInputService: AudioInputService {
    public private(set) var authorizationStatus: AudioInputAuthorizationStatus
    public private(set) var latestMeterFrame: AudioMeterFrame
    public var meterPublisher: AnyPublisher<AudioMeterFrame, Never> {
        meterSubject.eraseToAnyPublisher()
    }
    public var samplePublisher: AnyPublisher<AudioSampleFrame, Never> {
        sampleSubject.eraseToAnyPublisher()
    }
    public private(set) var availableInputSources: [AudioInputSourceDescriptor]
    public private(set) var selectedInputSourceID: String?
    public var audioEngine: AVAudioEngine? { engine }

    private let engine: AVAudioEngine
    private let meterSubject: CurrentValueSubject<AudioMeterFrame, Never>
    private let sampleSubject: CurrentValueSubject<AudioSampleFrame, Never>
    private var isTapInstalled = false
    private var isCapturing = false

    public init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        self.latestMeterFrame = .silent
        self.meterSubject = CurrentValueSubject(.silent)
        self.sampleSubject = CurrentValueSubject(
            AudioSampleFrame(timestamp: .distantPast, sampleRate: 48_000, monoSamples: [])
        )
        self.authorizationStatus = Self.currentAuthorizationStatus()
        self.availableInputSources = []
        self.selectedInputSourceID = nil
        refreshInputSources()
    }

    public func startCapture() async throws {
        authorizationStatus = Self.currentAuthorizationStatus()
        if authorizationStatus == .notDetermined {
            let granted = await Self.requestRecordPermissionIfNeeded()
            authorizationStatus = granted ? .authorized : .denied
        }
        guard authorizationStatus == .authorized else {
            throw AudioInputError.notAuthorized
        }
        guard !isCapturing else { return }

        do {
            try configureTapIfNeeded()
            try configureAudioSessionIfNeeded()
            refreshInputSources()
            try engine.start()
            isCapturing = true
        } catch {
            if isTapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            engine.stop()
            isCapturing = false
            throw error
        }
    }

    public func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
        engine.stop()
        isCapturing = false
    }

    public func refreshInputSources() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        let preferredID = session.preferredInput?.uid
        let currentRouteID = session.currentRoute.inputs.first?.uid

        var descriptors = (session.availableInputs ?? []).map { input in
            AudioInputSourceDescriptor(
                id: input.uid,
                name: input.portName,
                transportSummary: input.portType.rawValue
            )
        }

        if descriptors.isEmpty, let routeInput = session.currentRoute.inputs.first {
            descriptors = [
                AudioInputSourceDescriptor(
                    id: routeInput.uid,
                    name: routeInput.portName,
                    transportSummary: routeInput.portType.rawValue
                ),
            ]
        }

        availableInputSources = descriptors
        selectedInputSourceID = preferredID ?? currentRouteID ?? descriptors.first?.id
        #else
        availableInputSources = [
            AudioInputSourceDescriptor(
                id: "system.default.input",
                name: "System Default Input",
                transportSummary: "System"
            ),
        ]
        selectedInputSourceID = "system.default.input"
        #endif
    }

    public func selectInputSource(id: String) throws {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        guard
            let selected = session.availableInputs?.first(where: { $0.uid == id })
        else {
            throw AudioInputError.inputNotFound
        }

        try session.setPreferredInput(selected)
        selectedInputSourceID = selected.uid
        #else
        guard availableInputSources.contains(where: { $0.id == id }) else {
            throw AudioInputError.inputNotFound
        }
        selectedInputSourceID = id
        #endif
    }

    private func configureTapIfNeeded() throws {
        guard !isTapInstalled else { return }
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw AudioInputError.unavailableInputFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        isTapInstalled = true
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard
            let floatChannelData = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var rmsLinear: Float = 0
        var peakLinear: Float = 0
        var monoSamples = [Float](repeating: 0, count: frameLength)

        for channelIndex in 0 ..< channelCount {
            let channelData = floatChannelData[channelIndex]
            var channelRMS: Float = 0
            var channelPeak: Float = 0
            vDSP_rmsqv(channelData, 1, &channelRMS, vDSP_Length(frameLength))
            vDSP_maxmgv(channelData, 1, &channelPeak, vDSP_Length(frameLength))
            rmsLinear = max(rmsLinear, channelRMS)
            peakLinear = max(peakLinear, channelPeak)

            for sampleIndex in 0 ..< frameLength {
                monoSamples[sampleIndex] += channelData[sampleIndex]
            }
        }

        if channelCount > 1 {
            let scale = 1.0 / Float(channelCount)
            for sampleIndex in 0 ..< frameLength {
                monoSamples[sampleIndex] *= scale
            }
        }

        // Lift practical mic levels into a useful control range while preserving dynamics.
        let normalizedRMS = normalizedLevel(fromLinear: Double(rmsLinear), floorDB: -58, boostPower: 0.62)
        let normalizedPeak = normalizedLevel(fromLinear: Double(peakLinear), floorDB: -46, boostPower: 0.70)
        let rmsDBFS = linearToDecibels(Double(rmsLinear))
        let peakDBFS = linearToDecibels(Double(peakLinear))

        let frame = AudioMeterFrame(
            timestamp: .now,
            rms: normalizedRMS,
            peak: max(normalizedPeak, normalizedRMS),
            rmsDBFS: rmsDBFS,
            peakDBFS: peakDBFS
        )
        latestMeterFrame = frame
        meterSubject.send(frame)
        sampleSubject.send(
            AudioSampleFrame(
                timestamp: frame.timestamp,
                sampleRate: buffer.format.sampleRate,
                monoSamples: monoSamples
            )
        )
    }

    private func normalizedLevel(fromLinear linear: Double, floorDB: Double, boostPower: Double) -> Double {
        guard linear > 0 else { return 0 }
        let decibels = 20 * log10(linear)
        let clampedDB = min(max(decibels, floorDB), 0)
        let normalized = (clampedDB - floorDB) / -floorDB
        return min(max(pow(normalized, boostPower), 0), 1)
    }

    private func linearToDecibels(_ linear: Double) -> Double {
        guard linear > 0 else { return -120 }
        return min(max(20 * log10(linear), -120), 0)
    }

    private func configureAudioSessionIfNeeded() throws {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP]
        if #unavailable(iOS 14.0) {
            options = [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
        }
        try session.setCategory(.playAndRecord, mode: .measurement, options: options)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true, options: [])
        #endif
    }

    private static func currentAuthorizationStatus() -> AudioInputAuthorizationStatus {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .denied:
            return .denied
        case .undetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
        #else
        return .authorized
        #endif
    }

    private static func requestRecordPermissionIfNeeded() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }
}

public enum AudioInputError: LocalizedError {
    case notAuthorized
    case unavailableInputFormat
    case inputNotFound

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone authorization denied or unavailable."
        case .unavailableInputFormat:
            return "Audio input format is unavailable."
        case .inputNotFound:
            return "Selected audio input source is unavailable."
        }
    }
}

private func percentile(_ values: [Double], p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let clamped = p.clamped(to: 0 ... 1)
    let position = clamped * Double(values.count - 1)
    let lower = Int(floor(position))
    let upper = Int(ceil(position))
    if lower == upper {
        return values[lower]
    }
    let t = position - Double(lower)
    return values[lower] + ((values[upper] - values[lower]) * t)
}

private func linearToDB(_ linear: Double) -> Double {
    guard linear > 0 else { return -120 }
    return min(max(20 * log10(linear), -120), 0)
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
