//
//  BillingStore.swift
//  Chroma
//
//  Created by Sebastian Suarez-Solis on 3/21/26.
//


import Foundation
import Combine
import StoreKit

public enum ProAccessVisualState: String, Equatable, Sendable {
    case inactive
    case trial
    case active
    case renewal

    public var badgeText: String {
        switch self {
        case .inactive: return "INACTIVE"
        case .trial: return "TRIAL"
        case .active: return "ACTIVE"
        case .renewal: return "RENEWAL"
        }
    }

    public var hasFeatureAccess: Bool {
        self != .inactive
    }

    public var caption: String? {
        switch self {
        case .inactive:
            return "Unlock additional modes, recording, presets, and external display."
        case .trial:
            return "Your annual trial is active."
        case .active:
            return "Chroma Pro is active on this device."
        case .renewal:
            return "Your subscription renewed successfully."
        }
    }
}

public struct ProAccessVisualSignals: Equatable, Sendable {
    public let state: ProAccessVisualState
    public let title: String
    public let caption: String?
}

public struct PaywallTrialInfo: Equatable, Sendable {
    public let headline: String
    public let detail: String
}

public struct PaywallPlanOption: Identifiable, Equatable, Sendable {
    public var id: String { productID }

    public let productID: String
    public let title: String
    public let subtitle: String
    public let priceText: String
    public let periodText: String
    public let badgeText: String?
    public let trialInfo: PaywallTrialInfo?
    public let isBestValue: Bool
}

public struct PaywallSavingsSummary: Equatable, Sendable {
    public let effectiveMonthlyText: String
    public let savingsText: String
}

@MainActor
public final class BillingStore: ObservableObject {
    public static let monthlyProductID = "CHRMAPROMONTHLY"
    public static let annualProductID = "CHRMAPROANNUALLY"
    public static let entitlementKey = "chroma_pro"
    
    private static let cachedActiveKey = "ChromaProCache.Active"
    private static let cachedValidatedAtKey = "ChromaProCache.LastValidatedAt"
    
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var isLoadingProducts = false
    @Published public private(set) var isPurchasing = false
    @Published public private(set) var isProActive: Bool
    @Published public private(set) var proAccessVisualState: ProAccessVisualState
    @Published public private(set) var lastValidatedAt: Date?
    @Published public private(set) var lastErrorMessage: String?
    
    private let storeKitEnabled: Bool
    private let userDefaults: UserDefaults
    private let now: () -> Date
    
    private var didStart = false
    private var updatesTask: Task<Void, Never>?
    
    public init(
        storeKitEnabled: Bool = true,
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.storeKitEnabled = storeKitEnabled
        self.userDefaults = userDefaults
        self.now = now
        
        let cachedActive = userDefaults.bool(forKey: Self.cachedActiveKey)
        let cachedValidatedAt = userDefaults.object(forKey: Self.cachedValidatedAtKey) as? Date
        
        self.isProActive = cachedActive
        self.lastValidatedAt = cachedValidatedAt
        self.proAccessVisualState = cachedActive ? .active : .inactive
        self.lastErrorMessage = nil
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    public var proAccessVisualSignals: ProAccessVisualSignals {
        ProAccessVisualSignals(
            state: proAccessVisualState,
            title: "Subscription: \(proAccessVisualState.badgeText)",
            caption: proAccessVisualState.caption
        )
    }
    
    public var paywallPlanOptions: [PaywallPlanOption] {
        [
            annualPlanOption(product: product(for: Self.annualProductID)),
            monthlyPlanOption(product: product(for: Self.monthlyProductID)),
        ]
    }
    
    public var paywallSavingsSummary: PaywallSavingsSummary {
        PaywallSavingsSummary(
            effectiveMonthlyText: "$2.92/mo effective",
            savingsText: "Save 42% vs monthly"
        )
    }
    
    public func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        
        guard storeKitEnabled else {
            applyCachedState()
            return
        }
        
        await loadProducts()
        await refreshEntitlements()
        listenForTransactions()
    }
    
    public func refreshEntitlements() async {
        guard storeKitEnabled else {
            applyCachedState()
            return
        }
        
        var activeTransactions: [Transaction] = []
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try verified(result)
                guard Self.productIDs.contains(transaction.productID) else { continue }
                guard activeEntitlement(from: transaction) else { continue }
                activeTransactions.append(transaction)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        
        let validatedAt = now()
        let nextIsActive = !activeTransactions.isEmpty
        let nextVisualState = computeVisualState(from: activeTransactions)
        
        isProActive = nextIsActive
        proAccessVisualState = nextVisualState
        lastValidatedAt = validatedAt
        updateCache(active: nextIsActive, validatedAt: validatedAt)
    }
    
    public func purchase(productID: String) async {
        guard storeKitEnabled else {
            lastErrorMessage = "StoreKit is disabled for this build."
            return
        }
        
        if products.isEmpty {
            await loadProducts()
        }
        
        guard let product = product(for: productID) else {
            lastErrorMessage = "Subscription product not loaded."
            return
        }
        
        isPurchasing = true
        lastErrorMessage = nil
        defer { isPurchasing = false }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                lastErrorMessage = "Purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
    
    public func restorePurchases() async {
        guard storeKitEnabled else {
            lastErrorMessage = "StoreKit is disabled for this build."
            return
        }
        
        lastErrorMessage = nil
        
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
    
    private func loadProducts() async {
        guard storeKitEnabled else { return }
        
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        
        do {
            let loaded = try await Product.products(for: Array(Self.productIDs))
            products = loaded.sorted { lhs, rhs in
                sortOrder(for: lhs.id) < sortOrder(for: rhs.id)
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
    
    private func listenForTransactions() {
        guard updatesTask == nil else { return }
        
        updatesTask = Task { [weak self] in
            guard let self else { return }
            
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self.handle(transactionResult: result)
            }
        }
    }
    
    private func handle(transactionResult: VerificationResult<Transaction>) async {
        do {
            let transaction = try verified(transactionResult)
            guard Self.productIDs.contains(transaction.productID) else { return }
            await transaction.finish()
            await refreshEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
    
    private func activeEntitlement(from transaction: Transaction) -> Bool {
        guard transaction.revocationDate == nil else { return false }
        if let expirationDate = transaction.expirationDate {
            return expirationDate > now()
        }
        return true
    }
    
    private func computeVisualState(from activeTransactions: [Transaction]) -> ProAccessVisualState {
        guard let newest = activeTransactions.sorted(by: { $0.purchaseDate > $1.purchaseDate }).first else {
            return .inactive
        }

        if newest.offerType == .introductory {
            return .trial
        }

        return .active
    }
    
    private func applyCachedState() {
        let cachedActive = userDefaults.bool(forKey: Self.cachedActiveKey)
        let cachedValidatedAt = userDefaults.object(forKey: Self.cachedValidatedAtKey) as? Date
        
        isProActive = cachedActive
        proAccessVisualState = cachedActive ? .active : .inactive
        lastValidatedAt = cachedValidatedAt
    }
    
    private func updateCache(active: Bool, validatedAt: Date) {
        userDefaults.set(active, forKey: Self.cachedActiveKey)
        userDefaults.set(validatedAt, forKey: Self.cachedValidatedAtKey)
    }
    
    private func product(for productID: String) -> Product? {
        products.first(where: { $0.id == productID })
    }
    
    private func monthlyPlanOption(product: Product?) -> PaywallPlanOption {
        PaywallPlanOption(
            productID: Self.monthlyProductID,
            title: "Monthly",
            subtitle: "Same features, billed monthly",
            priceText: product?.displayPrice ?? "$4.99",
            periodText: "/mo",
            badgeText: nil,
            trialInfo: nil,
            isBestValue: false
        )
    }
    
    private func annualPlanOption(product: Product?) -> PaywallPlanOption {
        PaywallPlanOption(
            productID: Self.annualProductID,
            title: "Annual",
            subtitle: "1 week free, then billed yearly",
            priceText: product?.displayPrice ?? "$34.99",
            periodText: "/yr",
            badgeText: "Best Value",
            trialInfo: PaywallTrialInfo(
                headline: "1 week free",
                detail: "$2.92/mo effective after trial"
            ),
            isBestValue: true
        )
    }
    
    private func sortOrder(for productID: String) -> Int {
        switch productID {
        case Self.annualProductID:
            return 0
        case Self.monthlyProductID:
            return 1
        default:
            return 999
        }
    }
    
    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }
    
    private static var productIDs: Set<String> {
        [
            BillingStore.monthlyProductID,
            BillingStore.annualProductID,
        ]
    }
}
