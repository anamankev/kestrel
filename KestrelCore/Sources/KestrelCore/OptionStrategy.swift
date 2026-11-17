import Foundation

/// Multi-leg option positions on one expiry: payoff at expiry, model value today (Black-76 at each
/// leg's implied vol), package greeks, breakevens and max profit/loss.
public struct StrategyLeg: Sendable, Equatable, Identifiable {
    public var contract: OptionContract
    /// Contracts: positive = long, negative = short.
    public var quantity: Double
    public var id: String { contract.name }
    /// Premium paid (+) or received (−) per contract, at the mark.
    public var premium: Double { contract.mark ?? 0 }

    public init(_ contract: OptionContract, _ quantity: Double) {
        self.contract = contract
        self.quantity = quantity
    }

    func intrinsic(_ s: Double) -> Double { max(contract.isCall ? s - contract.strike : contract.strike - s, 0) }
}

public enum StrategyTemplate: String, CaseIterable, Sendable {
    case longCall = "LONG CALL", longPut = "LONG PUT", straddle = "STRADDLE", strangle = "STRANGLE"
    case bullCall = "BULL CALL SPREAD", bearPut = "BEAR PUT SPREAD", condor = "IRON CONDOR", butterfly = "CALL BUTTERFLY"

    /// Builds the legs from the chain for one expiry, picking listed strikes nearest to fixed
    /// distances from the forward.
    public func legs(chain: OptionChain, expiry: Date) -> [StrategyLeg]? {
        let rows = chain.rows(expiry: expiry).filter { $0.call?.mark != nil && $0.put?.mark != nil }
        guard let f = chain.forward(expiry: expiry), rows.count >= 3 else { return nil }
        func row(_ m: Double) -> StrikeRow { rows.min { abs($0.strike - f * m) < abs($1.strike - f * m) }! }
        func call(_ m: Double, _ q: Double) -> StrategyLeg { StrategyLeg(row(m).call!, q) }
        func put(_ m: Double, _ q: Double) -> StrategyLeg { StrategyLeg(row(m).put!, q) }
        let legs: [StrategyLeg] = switch self {
        case .longCall: [call(1, 1)]
        case .longPut: [put(1, 1)]
        case .straddle: [call(1, 1), put(1, 1)]
        case .strangle: [put(0.93, 1), call(1.07, 1)]
        case .bullCall: [call(1, 1), call(1.08, -1)]
        case .bearPut: [put(1, 1), put(0.92, -1)]
        case .condor: [put(0.88, 1), put(0.94, -1), call(1.06, -1), call(1.12, 1)]
        case .butterfly: [call(0.94, 1), call(1, -2), call(1.06, 1)]
        }
        // Templates whose strikes collapse onto the same listing (a sparse chain) aren't meaningful.
        return Set(legs.map(\.id)).count == legs.count ? legs : nil
    }
}

public struct StrategyAnalysis: Sendable {
    public let legs: [StrategyLeg]
    public init(legs: [StrategyLeg]) { self.legs = legs }

    /// Positive = debit paid, negative = credit received.
    public var netPremium: Double { legs.reduce(0) { $0 + $1.quantity * $1.premium } }

    public func payoffAtExpiry(_ s: Double) -> Double {
        legs.reduce(0) { $0 + $1.quantity * $1.intrinsic(s) } - netPremium
    }

    /// Model P&L if the forward moved to `s` now, holding each leg's implied vol.
    public func valueToday(_ s: Double, now: Date = .now) -> Double {
        legs.reduce(0) { acc, l in
            let g = Black76.greeks(f: s, k: l.contract.strike, t: l.contract.years(from: now), sigma: l.contract.iv ?? 0, call: l.contract.isCall)
            return acc + l.quantity * g.price
        } - netPremium
    }

    public func greeks(now: Date = .now) -> Black76.Greeks {
        legs.reduce(Black76.Greeks(price: 0, delta: 0, gamma: 0, vega: 0, theta: 0)) { acc, l in
            guard let g = l.contract.greeks(now: now) else { return acc }
            return Black76.Greeks(price: acc.price + l.quantity * g.price, delta: acc.delta + l.quantity * g.delta,
                                  gamma: acc.gamma + l.quantity * g.gamma, vega: acc.vega + l.quantity * g.vega,
                                  theta: acc.theta + l.quantity * g.theta)
        }
    }

    private var strikes: [Double] { Array(Set(legs.map(\.contract.strike))).sorted() }
    /// Slope of the expiry payoff above every strike: the net call position.
    private var upperSlope: Double { legs.filter(\.contract.isCall).reduce(0) { $0 + $1.quantity } }

    /// Kinks of the piecewise-linear expiry payoff, plus the zero bound and a point past the top strike.
    private var knots: [Double] {
        guard let top = strikes.last else { return [] }
        return [0] + strikes + [top * 2]
    }

    /// nil = unlimited.
    public var maxProfit: Double? { upperSlope > 1e-9 ? nil : knots.map(payoffAtExpiry).max() }
    public var maxLoss: Double? { upperSlope < -1e-9 ? nil : knots.map(payoffAtExpiry).min().map { min($0, 0) } }

    /// Underlying prices at expiry where the payoff crosses zero.
    public var breakevens: [Double] {
        let k = knots
        var out: [Double] = []
        for (a, b) in zip(k, k.dropFirst()) {
            let pa = payoffAtExpiry(a), pb = payoffAtExpiry(b)
            if pa == 0 { out.append(a) }
            if (pa < 0) != (pb < 0), pa != 0, pb != 0 { out.append(a + (b - a) * pa / (pa - pb)) }
        }
        // Past the last knot the payoff keeps the upper slope; extend once if it still has to cross.
        if let last = k.last, abs(upperSlope) > 1e-9 {
            let p = payoffAtExpiry(last)
            if (p < 0) == (upperSlope > 0) { out.append(last - p / upperSlope) }
        }
        return Array(Set(out.map { ($0 * 100).rounded() / 100 })).sorted()
    }
}
