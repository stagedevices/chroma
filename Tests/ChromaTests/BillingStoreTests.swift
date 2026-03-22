//
//  BillingStoreTests.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 3/21/26.
//


import XCTest
@testable import Chroma

@MainActor
final class BillingStoreTests: XCTestCase {
    func testProEntitlementModeMatrix() {
        XCTAssertFalse(ProEntitlement.requiresPro(.mode(.colorShift)))
        XCTAssertFalse(ProEntitlement.requiresPro(.mode(.prismField)))
        XCTAssertTrue(ProEntitlement.requiresPro(.mode(.tunnelCels)))
        XCTAssertTrue(ProEntitlement.requiresPro(.mode(.fractalCaustics)))
        XCTAssertTrue(ProEntitlement.requiresPro(.mode(.riemannCorridor)))
        XCTAssertTrue(ProEntitlement.requiresPro(.mode(.custom)))

        XCTAssertTrue(ProEntitlement.requiresPro(.recording))
        XCTAssertTrue(ProEntitlement.requiresPro(.externalDisplay))
        XCTAssertTrue(ProEntitlement.requiresPro(.customBuilder))
        XCTAssertTrue(ProEntitlement.requiresPro(.unlimitedPresets))
        XCTAssertTrue(ProEntitlement.requiresPro(.modeMorphing))
    }

    func testProAccessVisualStateFlags() {
        XCTAssertFalse(ProAccessVisualState.inactive.hasFeatureAccess)
        XCTAssertTrue(ProAccessVisualState.trial.hasFeatureAccess)
        XCTAssertTrue(ProAccessVisualState.active.hasFeatureAccess)
        XCTAssertTrue(ProAccessVisualState.renewal.hasFeatureAccess)

        XCTAssertEqual(ProAccessVisualState.inactive.badgeText, "INACTIVE")
        XCTAssertEqual(ProAccessVisualState.trial.badgeText, "TRIAL")
        XCTAssertEqual(ProAccessVisualState.active.badgeText, "ACTIVE")
        XCTAssertEqual(ProAccessVisualState.renewal.badgeText, "RENEWAL")
    }

    func testBillingStoreInitReadsCache() {
        let suiteName = "BillingStoreTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let validatedAt = Date(timeIntervalSince1970: 1_726_000_000)
        defaults.set(true, forKey: "ChromaProCache.Active")
        defaults.set(validatedAt, forKey: "ChromaProCache.LastValidatedAt")

        let store = BillingStore(
            storeKitEnabled: false,
            userDefaults: defaults,
            now: { validatedAt }
        )

        XCTAssertTrue(store.isProActive)
        XCTAssertEqual(store.proAccessVisualState, .active)
        XCTAssertEqual(store.lastValidatedAt, validatedAt)
    }

    func testRequireProBlocksInactiveState() {
        let suiteName = "BillingStoreTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = BillingStore(storeKitEnabled: false, userDefaults: defaults)
        let router = AppRouter()
        let appViewModel = AppViewModel(router: router, billingStore: store)

        let blocked = appViewModel.requirePro(for: .recording, entryPoint: .recording)

        XCTAssertTrue(blocked)
        XCTAssertTrue(appViewModel.isShowingPaywall)
        XCTAssertEqual(appViewModel.paywallEntryPoint, .recording)
    }

    func testRequireProAllowsCachedActiveState() {
        let suiteName = "BillingStoreTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "ChromaProCache.Active")

        let store = BillingStore(storeKitEnabled: false, userDefaults: defaults)
        let router = AppRouter()
        let appViewModel = AppViewModel(router: router, billingStore: store)

        let blocked = appViewModel.requirePro(for: .recording, entryPoint: .recording)

        XCTAssertFalse(blocked)
        XCTAssertFalse(appViewModel.isShowingPaywall)
        XCTAssertNil(appViewModel.paywallEntryPoint)
    }

    func testFreePresetSaveLimitIgnoresFactorySeedPreset() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.colorShift)
        XCTAssertFalse(sessionViewModel.freePresetSaveLimitReached)

        _ = sessionViewModel.quickSaveActiveModePreset()
        XCTAssertTrue(sessionViewModel.freePresetSaveLimitReached)
    }

    func testRecoveredLockedModeFallsBackToColorShiftWhenInactive() {
        let bootstrap = ChromaAppBootstrap.makeTesting()
        let sessionViewModel = bootstrap.sessionViewModel

        sessionViewModel.selectMode(.fractalCaustics)
        XCTAssertEqual(sessionViewModel.session.activeModeID, .fractalCaustics)

        sessionViewModel.reconcileRecoveredProAccess(hasProAccess: false)

        XCTAssertEqual(sessionViewModel.session.activeModeID, .colorShift)
        XCTAssertNil(sessionViewModel.session.activePresetID)
        XCTAssertEqual(sessionViewModel.session.activePresetName, "Unsaved Session")
    }
}