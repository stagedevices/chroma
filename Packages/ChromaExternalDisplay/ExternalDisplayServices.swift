import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public protocol ExternalDisplayCoordinator: AnyObject {
    var targets: [DisplayTarget] { get }
    var targetsPublisher: AnyPublisher<[DisplayTarget], Never> { get }
    var selectedTargetID: String { get }
    var selectedTargetIDPublisher: AnyPublisher<String, Never> { get }
    func availableTargets() -> [DisplayTarget]
    func selectDisplayTarget(id: String)
}

public final class PlaceholderExternalDisplayCoordinator: ExternalDisplayCoordinator {
    public private(set) var targets: [DisplayTarget]
    public var targetsPublisher: AnyPublisher<[DisplayTarget], Never> {
        targetsSubject.eraseToAnyPublisher()
    }
    public private(set) var selectedTargetID: String
    public var selectedTargetIDPublisher: AnyPublisher<String, Never> {
        selectedTargetIDSubject.eraseToAnyPublisher()
    }

    private let targetsSubject: CurrentValueSubject<[DisplayTarget], Never>
    private let selectedTargetIDSubject: CurrentValueSubject<String, Never>

    public init(targets: [DisplayTarget] = ParameterCatalog.defaultDisplayTargets, selectedTargetID: String = "device") {
        self.targets = targets
        self.selectedTargetID = selectedTargetID
        targetsSubject = CurrentValueSubject(targets)
        selectedTargetIDSubject = CurrentValueSubject(selectedTargetID)
    }

    public func availableTargets() -> [DisplayTarget] {
        targets
    }

    public func selectDisplayTarget(id: String) {
        guard targets.contains(where: { $0.id == id }) else {
            selectedTargetID = "device"
            selectedTargetIDSubject.send(selectedTargetID)
            return
        }
        selectedTargetID = id
        selectedTargetIDSubject.send(selectedTargetID)
    }
}

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
@MainActor
public final class LiveExternalDisplayCoordinator: ExternalDisplayCoordinator {
    public private(set) var targets: [DisplayTarget]
    public var targetsPublisher: AnyPublisher<[DisplayTarget], Never> {
        targetsSubject.eraseToAnyPublisher()
    }
    public private(set) var selectedTargetID: String
    public var selectedTargetIDPublisher: AnyPublisher<String, Never> {
        selectedTargetIDSubject.eraseToAnyPublisher()
    }

    private let notificationCenter: NotificationCenter
    private let externalScreenProvider: () -> Bool
    private let targetsSubject: CurrentValueSubject<[DisplayTarget], Never>
    private let selectedTargetIDSubject: CurrentValueSubject<String, Never>

    public init(
        notificationCenter: NotificationCenter = .default,
        externalScreenProvider: @escaping () -> Bool = { UIScreen.screens.contains { $0 !== UIScreen.main } },
        selectedTargetID: String = "device"
    ) {
        self.notificationCenter = notificationCenter
        self.externalScreenProvider = externalScreenProvider
        self.selectedTargetID = selectedTargetID
        let initialTargets = Self.makeTargets(externalAvailable: externalScreenProvider())
        self.targets = initialTargets
        self.targetsSubject = CurrentValueSubject(initialTargets)
        self.selectedTargetIDSubject = CurrentValueSubject(selectedTargetID)
        reconcileSelectionIfNeeded()

        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenConfigurationDidChange),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenConfigurationDidChange),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    public func availableTargets() -> [DisplayTarget] {
        targets
    }

    public func selectDisplayTarget(id: String) {
        let isKnown = targets.contains(where: { $0.id == id })
        guard isKnown else {
            selectedTargetID = "device"
            selectedTargetIDSubject.send(selectedTargetID)
            return
        }

        if id == "external",
           let external = targets.first(where: { $0.id == "external" }),
           !external.isAvailable {
            return
        }

        selectedTargetID = id
        selectedTargetIDSubject.send(selectedTargetID)
    }

    @objc
    private func handleScreenConfigurationDidChange() {
        targets = Self.makeTargets(externalAvailable: externalScreenProvider())
        targetsSubject.send(targets)
        reconcileSelectionIfNeeded()
    }

    func refreshTargetAvailabilityForTesting() {
        handleScreenConfigurationDidChange()
    }

    private func reconcileSelectionIfNeeded() {
        if selectedTargetID == "external",
           let external = targets.first(where: { $0.id == "external" }),
           !external.isAvailable {
            selectedTargetID = "device"
            selectedTargetIDSubject.send(selectedTargetID)
            return
        }

        if !targets.contains(where: { $0.id == selectedTargetID }) {
            selectedTargetID = "device"
            selectedTargetIDSubject.send(selectedTargetID)
        }
    }

    private static func makeTargets(externalAvailable: Bool) -> [DisplayTarget] {
        [
            DisplayTarget(id: "device", name: "Device Screen", kind: .deviceScreen, isAvailable: true, supportsFullscreen: true),
            DisplayTarget(id: "external", name: "External Display", kind: .externalDisplay, isAvailable: externalAvailable, supportsFullscreen: true),
        ]
    }
}
#endif
