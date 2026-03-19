import Foundation

public struct AudioSampleFrame: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var sampleRate: Double
    public var monoSamples: [Float]

    public init(timestamp: Date, sampleRate: Double, monoSamples: [Float]) {
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.monoSamples = monoSamples
    }
}
