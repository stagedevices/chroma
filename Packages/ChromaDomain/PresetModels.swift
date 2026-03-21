import Foundation

public struct Preset: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var modeID: VisualModeID
    public var values: [ScopedParameterValue]
    public var customPatchID: UUID?

    public init(id: UUID = UUID(), name: String, modeID: VisualModeID, values: [ScopedParameterValue], customPatchID: UUID? = nil) {
        self.id = id
        self.name = name
        self.modeID = modeID
        self.values = values
        self.customPatchID = customPatchID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        modeID = try container.decode(VisualModeID.self, forKey: .modeID)
        values = try container.decode([ScopedParameterValue].self, forKey: .values)
        customPatchID = try container.decodeIfPresent(UUID.self, forKey: .customPatchID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, modeID, values, customPatchID
    }
}
