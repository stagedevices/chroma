import Foundation

public struct Preset: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var modeID: VisualModeID
    public var values: [ScopedParameterValue]

    public init(id: UUID = UUID(), name: String, modeID: VisualModeID, values: [ScopedParameterValue]) {
        self.id = id
        self.name = name
        self.modeID = modeID
        self.values = values
    }
}
