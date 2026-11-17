import Foundation
import Synchronization

// MARK: - Black-76 (options on futures/forwards, r = 0 as on crypto venues)

/// Black-76 pricing and greeks. Crypto options settle against a forward, so the forward `F`
/// replaces spot and discounting is dropped (r = 0), matching Deribit's own mark model.
public enum Black76 {
    public struct Greeks: Sendable, Equatable {
        public var price: Double
        /// ∂V/∂F.
        public var delta: Double
        /// ∂²V/∂F².
        public var gamma: Double
        /// Value change for a 1 vol-point (0.01) move in σ.
        public var vega: Double
        /// Value change per calendar day of decay.
        public var theta: Double
    }

    static func cdf(_ x: Double) -> Double { 0.5 * erfc(-x / 2.squareRoot()) }
    static func pdf(_ x: Double) -> Double { exp(-0.5 * x * x) / (2 * Double.pi).squareRoot() }

    /// - Parameters: forward `f`, strike `k`, years to expiry `t`, volatility `sigma` (0.5 = 50%).
    public static func greeks(f: Double, k: Double, t: Double, sigma: Double, call: Bool) -> Greeks {
        guard f > 0, k > 0 else { return Greeks(price: 0, delta: 0, gamma: 0, vega: 0, theta: 0) }
        guard t > 0, sigma > 0 else {
            // At expiry (or zero vol) the option is worth its intrinsic value.
            let itm = call ? f > k : f < k
            return Greeks(price: max(call ? f - k : k - f, 0), delta: itm ? (call ? 1 : -1) : 0, gamma: 0, vega: 0, theta: 0)
        }
        let sd = sigma * t.squareRoot()
        let d1 = (log(f / k) + 0.5 * sigma * sigma * t) / sd
        let d2 = d1 - sd
        let price = call ? f * cdf(d1) - k * cdf(d2) : k * cdf(-d2) - f * cdf(-d1)
        let n1 = pdf(d1)
        return Greeks(price: price,
                      delta: call ? cdf(d1) : cdf(d1) - 1,
                      gamma: n1 / (f * sd),
                      vega: f * n1 * t.squareRoot() / 100,
                      theta: -f * n1 * sigma / (2 * t.squareRoot()) / 365)
    }

    /// Implied volatility by safeguarded Newton–bisection. Returns nil when the price is outside
    /// no-arbitrage bounds (below intrinsic or above the forward/strike cap).
    public static func impliedVol(price: Double, f: Double, k: Double, t: Double, call: Bool) -> Double? {
        let intrinsic = max(call ? f - k : k - f, 0)
        let cap = call ? f : k
        guard t > 0, price > intrinsic, price < cap else { return nil }
        var lo = 1e-4, hi = 10.0, sigma = 0.6
        for _ in 0..<100 {
            let g = greeks(f: f, k: k, t: t, sigma: sigma, call: call)
            let diff = g.price - price
            if abs(diff) < 1e-10 * max(price, 1) { return sigma }
            if diff > 0 { hi = sigma } else { lo = sigma }
            let vegaPerUnit = g.vega * 100
            let newton = vegaPerUnit > 1e-12 ? sigma - diff / vegaPerUnit : .nan
            sigma = (newton > lo && newton < hi) ? newton : (lo + hi) / 2
        }
        return sigma
    }
}

// MARK: - Contracts and chains

public struct OptionContract: Sendable, Equatable, Identifiable {
    public let name: String
    public let underlying: String
    public let expiry: Date
    public let strike: Double
    public let isCall: Bool
    /// USD prices (Deribit quotes in coin; converted with the expiry's forward).
    public var bid: Double?
    public var ask: Double?
    public var mark: Double?
    /// Implied volatility as a fraction (0.4983 = 49.83%).
    public var iv: Double?
    public var openInterest: Double
    public var volume: Double
    /// Forward (future) price for this expiry.
    public var forward: Double

    public var id: String { name }

    public func years(from now: Date) -> Double { max(expiry.timeIntervalSince(now), 0) / (365 * 86_400) }

    public func greeks(now: Date = .now) -> Black76.Greeks? {
        guard let iv else { return nil }
        return Black76.greeks(f: forward, k: strike, t: years(from: now), sigma: iv, call: isCall)
    }

    public var isITM: Bool { isCall ? forward > strike : forward < strike }
}

public struct StrikeRow: Sendable, Equatable, Identifiable {
    public var strike: Double
    public var call: OptionContract?
    public var put: OptionContract?
    public var id: Double { strike }
}

public struct OptionChain: Sendable, Equatable {
    public let contracts: [OptionContract]
    public let expiries: [Date]

    public init(_ contracts: [OptionContract]) {
        self.contracts = contracts
        expiries = Array(Set(contracts.map(\.expiry))).sorted()
    }

    public func contracts(expiry: Date) -> [OptionContract] { contracts.filter { $0.expiry == expiry } }

    public func rows(expiry: Date) -> [StrikeRow] {
        var byStrike: [Double: StrikeRow] = [:]
        for c in contracts(expiry: expiry) {
            var row = byStrike[c.strike] ?? StrikeRow(strike: c.strike)
            if c.isCall { row.call = c } else { row.put = c }
            byStrike[c.strike] = row
        }
        return byStrike.values.sorted { $0.strike < $1.strike }
    }

    public func forward(expiry: Date) -> Double? { contracts(expiry: expiry).first?.forward }

    /// Strike closest to the forward.
    public func atmStrike(expiry: Date) -> Double? {
        guard let f = forward(expiry: expiry) else { return nil }
        return rows(expiry: expiry).min { abs($0.strike - f) < abs($1.strike - f) }?.strike
    }

    /// ATM implied vol: average of the call and put marks at the ATM strike.
    public func atmIV(expiry: Date) -> Double? {
        guard let k = atmStrike(expiry: expiry), let row = rows(expiry: expiry).first(where: { $0.strike == k }) else { return nil }
        let ivs = [row.call?.iv, row.put?.iv].compactMap { $0 }
        return ivs.isEmpty ? nil : ivs.reduce(0, +) / Double(ivs.count)
    }

    /// Settlement price that minimises the total payout to option holders (open-interest weighted).
    public func maxPain(expiry: Date) -> Double? {
        let cs = contracts(expiry: expiry)
        let strikes = Set(cs.map(\.strike)).sorted()
        return strikes.min { payout(cs, at: $0) < payout(cs, at: $1) }
    }

    private func payout(_ cs: [OptionContract], at s: Double) -> Double {
        cs.reduce(0) { $0 + $1.openInterest * max($1.isCall ? s - $1.strike : $1.strike - s, 0) }
    }

    public func putCallOIRatio(expiry: Date? = nil) -> Double? {
        let cs = expiry.map(contracts(expiry:)) ?? contracts
        let calls = cs.filter(\.isCall).reduce(0) { $0 + $1.openInterest }
        let puts = cs.filter { !$0.isCall }.reduce(0) { $0 + $1.openInterest }
        return calls > 0 ? puts / calls : nil
    }
}

// MARK: - Deribit public REST (no key)

public enum Deribit {
    public static func summaryURL(currency: String) -> URL {
        var c = URLComponents(string: "https://www.deribit.com/api/v2/public/get_book_summary_by_currency")!
        c.queryItems = [.init(name: "currency", value: currency), .init(name: "kind", value: "option")]
        return c.url!
    }

    /// Currencies with listed options on Deribit's public API.
    public static let currencies: Set<String> = ["BTC", "ETH"]

    /// Parses `BTC-20NOV26-64000-P`. Deribit options expire at 08:00 UTC.
    public static func parse(_ name: String) -> (underlying: String, expiry: Date, strike: Double, call: Bool)? {
        var cache: [Substring: Date] = [:]
        return parse(name, cache: &cache)
    }

    /// One shared formatter (creating a DateFormatter per contract made a 1,000-contract chain
    /// take 44 ms to decode); callers decoding many names pass a cache keyed by the date token.
    private static func parse(_ name: String, cache: inout [Substring: Date]) -> (underlying: String, expiry: Date, strike: Double, call: Bool)? {
        let p = name.split(separator: "-")
        guard p.count == 4, let strike = Double(p[2]), p[3] == "C" || p[3] == "P" else { return nil }
        let day: Date
        if let d = cache[p[1]] { day = d } else {
            guard let d = expiryFormatter.withLock({ $0.date(from: String(p[1])) }) else { return nil }
            cache[p[1]] = d
            day = d
        }
        return (String(p[0]), day.addingTimeInterval(8 * 3600), strike, p[3] == "C")
    }

    private static let expiryFormatter: Mutex<DateFormatter> = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dMMMyy"
        return Mutex(f)
    }()

    private struct Envelope: Decodable { let result: [Row] }
    private struct Row: Decodable {
        let instrument_name: String
        let bid_price: Double?
        let ask_price: Double?
        let mark_price: Double?
        let mark_iv: Double?
        let open_interest: Double?
        let volume: Double?
        let underlying_price: Double?
    }

    public static func decode(_ data: Data) throws -> OptionChain {
        let rows = try JSONDecoder().decode(Envelope.self, from: data).result
        var cache: [Substring: Date] = [:]
        let contracts = rows.compactMap { r -> OptionContract? in
            guard let p = parse(r.instrument_name, cache: &cache), let fwd = r.underlying_price, fwd > 0 else { return nil }
            func usd(_ v: Double?) -> Double? { v.flatMap { $0 > 0 ? $0 * fwd : nil } }
            return OptionContract(name: r.instrument_name, underlying: p.underlying, expiry: p.expiry, strike: p.strike,
                                  isCall: p.call, bid: usd(r.bid_price), ask: usd(r.ask_price), mark: usd(r.mark_price),
                                  iv: r.mark_iv.flatMap { $0 > 0 ? $0 / 100 : nil },
                                  openInterest: r.open_interest ?? 0, volume: r.volume ?? 0, forward: fwd)
        }
        return OptionChain(contracts)
    }
}
