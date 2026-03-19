import Foundation

public struct PerformanceCue: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var notes: String
    public var presetID: UUID?

    public init(id: UUID = UUID(), name: String, notes: String, presetID: UUID? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
        self.presetID = presetID
    }
}

public struct PerformanceSet: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var cues: [PerformanceCue]

    public init(id: UUID = UUID(), name: String, cues: [PerformanceCue]) {
        self.id = id
        self.name = name
        self.cues = cues
    }
}
