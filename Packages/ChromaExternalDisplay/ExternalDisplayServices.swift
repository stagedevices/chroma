import Foundation

public protocol ExternalDisplayCoordinator: AnyObject {
    func availableTargets() -> [DisplayTarget]
    func selectDisplayTarget(id: String)
}

public final class PlaceholderExternalDisplayCoordinator: ExternalDisplayCoordinator {
    private var targets: [DisplayTarget]
    private(set) var selectedTargetID: String

    public init(targets: [DisplayTarget] = ParameterCatalog.defaultDisplayTargets, selectedTargetID: String = "device") {
        self.targets = targets
        self.selectedTargetID = selectedTargetID
    }

    public func availableTargets() -> [DisplayTarget] {
        targets
    }

    public func selectDisplayTarget(id: String) {
        selectedTargetID = id
    }
}
