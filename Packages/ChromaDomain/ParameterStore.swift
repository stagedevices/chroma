import Foundation

public final class ParameterStore {
    private let descriptorsByID: [String: ParameterDescriptor]
    private var globalValues: [String: ParameterValue]
    private var modeValues: [VisualModeID: [String: ParameterValue]]

    public init(descriptors: [ParameterDescriptor]) {
        self.descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        self.globalValues = [:]
        self.modeValues = [:]
    }

    public func descriptor(for parameterID: String) -> ParameterDescriptor? {
        descriptorsByID[parameterID]
    }

    public func descriptors(group: ParameterGroup? = nil, tier: ParameterTier? = nil, for modeID: VisualModeID? = nil) -> [ParameterDescriptor] {
        descriptorsByID.values
            .filter { descriptor in
                let groupMatches = group.map { descriptor.group == $0 } ?? true
                let tierMatches = tier.map { descriptor.tier == $0 } ?? true
                let scopeMatches: Bool
                switch descriptor.scope.kind {
                case .global:
                    scopeMatches = true
                case .mode:
                    scopeMatches = descriptor.scope.modeID == modeID
                }
                return groupMatches && tierMatches && scopeMatches
            }
            .sorted { $0.title < $1.title }
    }

    public func value(for parameterID: String, scope: ParameterScope) -> ParameterValue? {
        guard let descriptor = descriptorsByID[parameterID] else { return nil }
        switch (descriptor.scope.kind, scope.kind) {
        case (.global, .global):
            return globalValues[parameterID] ?? descriptor.defaultValue
        case (.mode, .mode):
            guard descriptor.scope.modeID == scope.modeID, let modeID = scope.modeID else { return nil }
            return modeValues[modeID]?[parameterID] ?? descriptor.defaultValue
        default:
            return nil
        }
    }

    public func setValue(_ value: ParameterValue, for parameterID: String, scope: ParameterScope) {
        switch scope.kind {
        case .global:
            globalValues[parameterID] = value
        case .mode:
            guard let modeID = scope.modeID else { return }
            var modeDictionary = modeValues[modeID] ?? [:]
            modeDictionary[parameterID] = value
            modeValues[modeID] = modeDictionary
        }
    }

    public func resetValue(for parameterID: String, scope: ParameterScope) {
        switch scope.kind {
        case .global:
            globalValues.removeValue(forKey: parameterID)
        case .mode:
            guard let modeID = scope.modeID else { return }
            modeValues[modeID]?.removeValue(forKey: parameterID)
        }
    }

    public func snapshot() -> [ScopedParameterValue] {
        let globalSnapshot = globalValues.map { key, value in
            ScopedParameterValue(parameterID: key, scope: .global, value: value)
        }
        let modeSnapshot = modeValues.flatMap { modeID, values in
            values.map { key, value in
                ScopedParameterValue(parameterID: key, scope: .mode(modeID), value: value)
            }
        }
        return (globalSnapshot + modeSnapshot).sorted {
            if $0.parameterID == $1.parameterID {
                return ($0.scope.modeID?.rawValue ?? "") < ($1.scope.modeID?.rawValue ?? "")
            }
            return $0.parameterID < $1.parameterID
        }
    }

    public func load(_ values: [ScopedParameterValue]) {
        globalValues = [:]
        modeValues = [:]
        values.forEach { assignment in
            setValue(assignment.value, for: assignment.parameterID, scope: assignment.scope)
        }
    }
}
