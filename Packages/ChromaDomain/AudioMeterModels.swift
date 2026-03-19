import Foundation

public struct AudioMeterFrame: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var rms: Double
    public var peak: Double
    public var rmsDBFS: Double?
    public var peakDBFS: Double?

    public init(
        timestamp: Date,
        rms: Double,
        peak: Double,
        rmsDBFS: Double? = nil,
        peakDBFS: Double? = nil
    ) {
        self.timestamp = timestamp
        self.rms = rms
        self.peak = peak
        self.rmsDBFS = rmsDBFS
        self.peakDBFS = peakDBFS
    }

    public static let silent = AudioMeterFrame(
        timestamp: .distantPast,
        rms: 0,
        peak: 0,
        rmsDBFS: -120,
        peakDBFS: -120
    )
}
