import Foundation

// MARK: - MIDI Event

public struct MIDIEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case noteOn(note: UInt8, velocity: UInt8, channel: UInt8)
        case noteOff(note: UInt8, channel: UInt8)
        case controlChange(cc: UInt8, value: UInt8, channel: UInt8)
        case clock
        case start
        case stop
        case `continue`
    }

    public let kind: Kind
    public let timestamp: Date

    public init(kind: Kind, timestamp: Date = Date()) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

// MARK: - MIDI Device

public struct MIDIDeviceDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let manufacturer: String

    public init(id: String, name: String, manufacturer: String = "") {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
    }
}

// MARK: - MIDI Tempo State

public struct MIDITempoState: Equatable, Sendable {
    public var bpm: Double
    public var beat: Double
    public var isPlaying: Bool

    public init(bpm: Double = 120, beat: Double = 0, isPlaying: Bool = false) {
        self.bpm = bpm
        self.beat = beat
        self.isPlaying = isPlaying
    }

    public static let idle = MIDITempoState(bpm: 0, beat: 0, isPlaying: false)
}

// MARK: - MIDI Note Utilities

public enum MIDINoteUtility {
    /// Convert MIDI note number to frequency in Hz.
    public static func noteToHz(_ note: UInt8) -> Double {
        440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
    }

    /// Chromatic pitch class (0 = C, 1 = C#, ... 11 = B).
    public static func pitchClass(_ note: UInt8) -> Int {
        Int(note) % 12
    }

    /// Cents deviation from equal temperament (always 0 for MIDI — perfect tuning).
    public static let centsDeviation: Double = 0
}
