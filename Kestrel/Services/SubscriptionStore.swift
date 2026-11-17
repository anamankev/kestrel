import Foundation
import StoreKit
import KestrelCore

/// Kestrel Pro via StoreKit 2. Only transactions StoreKit has verified (signed by the App Store
/// and checked on device) count; unverified ones are logged and ignored. StoreKit caches
/// entitlements, so Pro keeps working offline until the period ends.
@MainActor @Observable final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var entitlement: Entitlement = .free
    private(set) var purchasing: ProPlan?
    private(set) var loadError: String?
    var message: String?

    #if DEBUG
    /// The screenshot tour shows Pro screens without a purchase. Never compiled into release.
    var tourOverride = false
    #endif

    var isPro: Bool {
        #if DEBUG
        if tourOverride { return true }
        #endif
        return entitlement.isPro
    }

    @ObservationIgnored private var updates: Task<Void, Never>?

    func start() {
        guard updates == nil else { return }
        // Renewals, refunds, Ask to Buy approvals and purchases made on another device.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await loadProducts(); await refresh() }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProPlan.allCases.map(\.productID))
            products = loaded.sorted { (ProPlan(productID: $0.id)?.months ?? 0) < (ProPlan(productID: $1.id)?.months ?? 0) }
            loadError = loaded.isEmpty ? "Subscriptions are unavailable right now." : nil
        } catch {
            loadError = "Couldn't reach the App Store."
        }
    }

    func product(_ plan: ProPlan) -> Product? { products.first { $0.id == plan.productID } }

    /// Recomputes Pro from StoreKit's current verified entitlements.
    func refresh() async {
        var rows: [(productID: String, expires: Date?, revoked: Bool)] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { securityLog.warning("unverified entitlement ignored"); continue }
            rows.append((t.productID, t.expirationDate, t.revocationDate != nil))
        }
        var willRenew = true
        if let status = try? await products.first?.subscription?.status.first,
           case .verified(let info) = status.renewalInfo {
            willRenew = info.willAutoRenew
        }
        entitlement = Entitlement.from(rows, willRenew: willRenew)
    }

    /// - Parameter account: tags the purchase with the Kestrel account (for a future server).
    func purchase(_ plan: ProPlan, account: UUID?) async {
        guard let product = product(plan), purchasing == nil else { return }
        purchasing = plan
        defer { purchasing = nil }
        do {
            var options: Set<Product.PurchaseOption> = []
            if let account { options.insert(.appAccountToken(account)) }
            switch try await product.purchase(options: options) {
            case .success(let result):
                await handle(result)
                message = isPro ? "Welcome to Kestrel Pro." : nil
            case .pending:
                message = "Purchase pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through: \(error.localizedDescription)"
        }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { message = "Restore failed: \(error.localizedDescription)" }
        await refresh()
        message = isPro ? "Kestrel Pro restored." : "No active subscription found for this Apple ID."
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let t):
            await t.finish()
        case .unverified(_, let error):
            securityLog.error("unverified transaction rejected: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }
}
