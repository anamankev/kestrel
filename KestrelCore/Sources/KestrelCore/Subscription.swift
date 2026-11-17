import Foundation

/// Kestrel Pro: one auto-renewing subscription group with three durations. StoreKit is the
/// source of truth for who is subscribed; this file is the product catalogue and the rules for
/// what Pro unlocks, kept pure so they can be tested.
public enum ProPlan: String, CaseIterable, Sendable, Codable {
    case monthly = "dev.kestrel.pro.monthly"
    case halfYear = "dev.kestrel.pro.halfyear"
    case annual = "dev.kestrel.pro.annual"

    public var productID: String { rawValue }
    public var months: Int { switch self { case .monthly: 1; case .halfYear: 6; case .annual: 12 } }
    public var title: String { switch self { case .monthly: "Monthly"; case .halfYear: "6 Months"; case .annual: "Yearly" } }
    /// "month", "6 months", "year": for "$9.99 / month" style labels and renewal terms.
    public var periodLabel: String { switch self { case .monthly: "month"; case .halfYear: "6 months"; case .annual: "year" } }

    public init?(productID: String) { self.init(rawValue: productID) }

    /// Price per month, for comparing plans.
    public func perMonth(_ price: Decimal) -> Decimal { price / Decimal(months) }

    /// Saving against paying monthly for the same span (0.17 = 17%), or nil for the monthly plan.
    public func saving(price: Decimal, monthlyPrice: Decimal) -> Double? {
        guard self != .monthly, monthlyPrice > 0 else { return nil }
        let full = monthlyPrice * Decimal(months)
        let s = ((full - price) / full).double
        return s > 0 ? s : nil
    }
}

/// What Pro unlocks. Everything else in Kestrel is free.
public enum ProFeature: String, CaseIterable, Sendable {
    case backtest, optionStrategies, correlation, earnings, multiPanel, backgroundAlerts

    public var title: String {
        switch self {
        case .backtest: "BT strategy backtester"
        case .optionStrategies: "OSA option strategy builder"
        case .correlation: "CORR correlation matrix"
        case .earnings: "ERN earnings calendar"
        case .multiPanel: "4- and 6-panel layouts"
        case .backgroundAlerts: "Alerts while Kestrel is closed"
        }
    }
}

public extension TerminalFunction {
    /// The Pro feature a function needs, or nil if it's free.
    var proFeature: ProFeature? {
        switch self {
        case .bt: .backtest
        case .osa: .optionStrategies
        case .corr: .correlation
        case .ern: .earnings
        default: nil
        }
    }
}

/// The current entitlement, derived from verified StoreKit transactions.
public enum Entitlement: Equatable, Sendable {
    case free
    case pro(plan: ProPlan, expires: Date?, willRenew: Bool)

    public var isPro: Bool { if case .pro = self { true } else { false } }

    /// From the latest verified transaction per product: active if not revoked and not expired.
    /// When several are active (e.g. mid-upgrade), the longest plan wins.
    public static func from(_ transactions: [(productID: String, expires: Date?, revoked: Bool)], willRenew: Bool = true, now: Date = .now) -> Entitlement {
        let active = transactions.compactMap { t -> (ProPlan, Date?)? in
            guard !t.revoked, let plan = ProPlan(productID: t.productID), (t.expires ?? .distantFuture) > now else { return nil }
            return (plan, t.expires)
        }
        guard let best = active.max(by: { $0.0.months < $1.0.months }) else { return .free }
        return .pro(plan: best.0, expires: best.1, willRenew: willRenew)
    }
}

public extension ProFeature {
    /// Free accounts get the 1- and 2-panel layouts; 4 and 6 are Pro.
    static let freePanels = 2
}
