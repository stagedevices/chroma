import Foundation
import Combine
import AVFoundation

// MARK: - Protocol

public protocol PlaybackService: AnyObject {
    var isPlaying: Bool { get }
    var nowPlayingTitle: String? { get }
    var nowPlayingArtist: String? { get }
    var meterPublisher: AnyPublisher<AudioMeterFrame, Never> { get }
    var samplePublisher: AnyPublisher<AudioSampleFrame, Never> { get }
    func play(url: URL) async throws
    func pause()
    func stop()
    func resume()
}

// MARK: - Placeholder

public final class PlaceholderPlaybackService: PlaybackService {
    public private(set) var isPlaying: Bool = false
    public private(set) var nowPlayingTitle: String?
    public private(set) var nowPlayingArtist: String?

    private let meterSubject = CurrentValueSubject<AudioMeterFrame, Never>(.silent)
    private let sampleSubject = CurrentValueSubject<AudioSampleFrame, Never>(
        AudioSampleFrame(timestamp: .distantPast, sampleRate: 48_000, monoSamples: [])
    )

    public var meterPublisher: AnyPublisher<AudioMeterFrame, Never> {
        meterSubject.eraseToAnyPublisher()
    }
    public var samplePublisher: AnyPublisher<AudioSampleFrame, Never> {
        sampleSubject.eraseToAnyPublisher()
    }

    public init() {}

    public func play(url: URL) async throws {
        isPlaying = true
        nowPlayingTitle = url.lastPathComponent
    }
    public func pause() { isPlaying = false }
    public func stop() {
        isPlaying = false
        nowPlayingTitle = nil
        nowPlayingArtist = nil
    }
    public func resume() { isPlaying = true }
}
