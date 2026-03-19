import Foundation

public struct AudioInputSourceDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var transportSummary: String

    public init(id: String, name: String, transportSummary: String) {
        self.id = id
        self.name = name
        self.transportSummary = transportSummary
    }
}
