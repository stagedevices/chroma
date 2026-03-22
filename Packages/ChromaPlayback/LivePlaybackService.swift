import Foundation
import Combine
import AVFoundation
import Accelerate

public final class LivePlaybackService: PlaybackService {
    public private(set) var isPlaying: Bool = false
    public private(set) var nowPlayingTitle: String?
    public private(set) var nowPlayingArtist: String?

    private let meterSubject = PassthroughSubject<AudioMeterFrame, Never>()
    private let sampleSubject = PassthroughSubject<AudioSampleFrame, Never>()

    public var meterPublisher: AnyPublisher<AudioMeterFrame, Never> {
        meterSubject.eraseToAnyPublisher()
    }
    public var samplePublisher: AnyPublisher<AudioSampleFrame, Never> {
        sampleSubject.eraseToAnyPublisher()
    }

    private weak var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isTapInstalled = false
    private let tapBufferSize: AVAudioFrameCount = 1024

    /// Initialize with a shared AVAudioEngine from the audio input service.
    public init(engine: AVAudioEngine?) {
        self.engine = engine
    }

    public func play(url: URL) async throws {
        guard let engine else { return }

        stop()

        let file = try AVAudioFile(forReading: url)
        let player = AVAudioPlayerNode()
        playerNode = player

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

        installTap(on: player, format: file.processingFormat)

        if !engine.isRunning {
            try engine.start()
        }

        player.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackFinished()
            }
        }
        player.play()

        nowPlayingTitle = url.deletingPathExtension().lastPathComponent
        nowPlayingArtist = nil
        isPlaying = true
    }

    public func pause() {
        playerNode?.pause()
        isPlaying = false
    }

    public func resume() {
        playerNode?.play()
        isPlaying = true
    }

    public func stop() {
        removeTap()
        if let player = playerNode, let engine {
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        playerNode = nil
        isPlaying = false
        nowPlayingTitle = nil
        nowPlayingArtist = nil
    }

    // MARK: - Tap

    private func installTap(on player: AVAudioPlayerNode, format: AVAudioFormat) {
        removeTap()

        let outputFormat = player.outputFormat(forBus: 0)
        guard outputFormat.sampleRate > 0 else { return }

        player.installTap(onBus: 0, bufferSize: tapBufferSize, format: outputFormat) { [weak self] buffer, time in
            self?.processBuffer(buffer, sampleRate: outputFormat.sampleRate)
        }
        isTapInstalled = true
    }

    private func removeTap() {
        guard isTapInstalled, let player = playerNode else { return }
        player.removeTap(onBus: 0)
        isTapInstalled = false
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Mix down to mono
        let channelCount = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: frameCount)
        for ch in 0..<channelCount {
            let src = channelData[ch]
            for i in 0..<frameCount {
                mono[i] += src[i]
            }
        }
        if channelCount > 1 {
            let scale = 1.0 / Float(channelCount)
            vDSP_vsmul(mono, 1, [scale], &mono, 1, vDSP_Length(frameCount))
        }

        // RMS + peak
        var rms: Float = 0
        vDSP_rmsqv(mono, 1, &rms, vDSP_Length(frameCount))
        var peak: Float = 0
        vDSP_maxmgv(mono, 1, &peak, vDSP_Length(frameCount))

        let now = Date()
        let meterFrame = AudioMeterFrame(
            timestamp: now,
            rms: Double(rms),
            peak: Double(peak)
        )
        meterSubject.send(meterFrame)

        let sampleFrame = AudioSampleFrame(
            timestamp: now,
            sampleRate: sampleRate,
            monoSamples: mono
        )
        sampleSubject.send(sampleFrame)
    }

    // MARK: - Completion

    private func handlePlaybackFinished() {
        isPlaying = false
    }
}
