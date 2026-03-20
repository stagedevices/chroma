import Foundation

public enum ParameterGroup: String, CaseIterable, Codable {
    case input
    case response
    case geometry
    case color
    case output
}

public enum ParameterTier: String, CaseIterable, Codable {
    case basic
    case advanced
}

public enum ParameterControlStyle: String, Codable {
    case slider
    case toggle
    case hueRange
}

public struct ParameterScope: Codable, Hashable, Equatable {
    public enum Kind: String, Codable {
        case global
        case mode
    }

    public var kind: Kind
    public var modeID: VisualModeID?

    public static let global = ParameterScope(kind: .global, modeID: nil)

    public static func mode(_ modeID: VisualModeID) -> ParameterScope {
        ParameterScope(kind: .mode, modeID: modeID)
    }

    public init(kind: Kind, modeID: VisualModeID?) {
        self.kind = kind
        self.modeID = modeID
    }
}

public enum ParameterValue: Codable, Equatable, Hashable {
    case scalar(Double)
    case toggle(Bool)
    case hueRange(min: Double, max: Double, outside: Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case scalar
        case toggle
        case hueRangeMin
        case hueRangeMax
        case hueRangeOutside
    }

    private enum ValueType: String, Codable {
        case scalar
        case toggle
        case hueRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .scalar:
            self = .scalar(try container.decode(Double.self, forKey: .scalar))
        case .toggle:
            self = .toggle(try container.decode(Bool.self, forKey: .toggle))
        case .hueRange:
            self = .hueRange(
                min: try container.decode(Double.self, forKey: .hueRangeMin),
                max: try container.decode(Double.self, forKey: .hueRangeMax),
                outside: try container.decode(Bool.self, forKey: .hueRangeOutside)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scalar(let value):
            try container.encode(ValueType.scalar, forKey: .type)
            try container.encode(value, forKey: .scalar)
        case .toggle(let value):
            try container.encode(ValueType.toggle, forKey: .type)
            try container.encode(value, forKey: .toggle)
        case .hueRange(let min, let max, let outside):
            try container.encode(ValueType.hueRange, forKey: .type)
            try container.encode(min, forKey: .hueRangeMin)
            try container.encode(max, forKey: .hueRangeMax)
            try container.encode(outside, forKey: .hueRangeOutside)
        }
    }

    public var scalarValue: Double? {
        guard case .scalar(let value) = self else { return nil }
        return value
    }

    public var toggleValue: Bool? {
        guard case .toggle(let value) = self else { return nil }
        return value
    }

    public var hueRangeValue: (min: Double, max: Double, outside: Bool)? {
        guard case .hueRange(let min, let max, let outside) = self else { return nil }
        return (min, max, outside)
    }
}

public struct ParameterDescriptor: Identifiable, Codable, Equatable {
    public let id: String
    public var title: String
    public var summary: String
    public var group: ParameterGroup
    public var tier: ParameterTier
    public var scope: ParameterScope
    public var controlStyle: ParameterControlStyle
    public var defaultValue: ParameterValue
    public var minimumValue: Double?
    public var maximumValue: Double?

    public init(
        id: String,
        title: String,
        summary: String,
        group: ParameterGroup,
        tier: ParameterTier,
        scope: ParameterScope,
        controlStyle: ParameterControlStyle,
        defaultValue: ParameterValue,
        minimumValue: Double? = nil,
        maximumValue: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.group = group
        self.tier = tier
        self.scope = scope
        self.controlStyle = controlStyle
        self.defaultValue = defaultValue
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
    }
}

public struct ScopedParameterValue: Codable, Equatable, Hashable {
    public var parameterID: String
    public var scope: ParameterScope
    public var value: ParameterValue

    public init(parameterID: String, scope: ParameterScope, value: ParameterValue) {
        self.parameterID = parameterID
        self.scope = scope
        self.value = value
    }
}
