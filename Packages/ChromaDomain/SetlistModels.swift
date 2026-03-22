import Foundation

public struct PerformanceCue: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var presetID: UUID?

    // SyncTimer scaffold fields — stored and displayed but not executed yet.
    public var delayFromPrevious: TimeInterval  // 0 = manual GO, >0 = auto-follow seconds
    public var transitionDuration: TimeInterval // crossfade length in seconds

    public init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        presetID: UUID? = nil,
        delayFromPrevious: TimeInterval = 0,
        transitionDuration: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.presetID = presetID
        self.delayFromPrevious = delayFromPrevious
        self.transitionDuration = transitionDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        notes = try container.decode(String.self, forKey: .notes)
        presetID = try container.decodeIfPresent(UUID.self, forKey: .presetID)
        delayFromPrevious = try container.decodeIfPresent(TimeInterval.self, forKey: .delayFromPrevious) ?? 0
        transitionDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .transitionDuration) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, notes, presetID, delayFromPrevious, transitionDuration
    }
}

public struct PerformanceSet: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var cues: [PerformanceCue]

    public init(id: UUID = UUID(), name: String, cues: [PerformanceCue] = []) {
        self.id = id
        self.name = name
        self.cues = cues
    }

    public static func empty(name: String = "New Set") -> PerformanceSet {
        PerformanceSet(name: name)
    }
}
