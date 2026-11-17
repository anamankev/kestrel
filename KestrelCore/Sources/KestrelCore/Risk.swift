import Foundation

/// Portfolio risk from daily history: beta, historical-simulation VaR, exposures.
public enum Risk {
    /// Simple returns between consecutive closes.
    public static func returns(_ closes: [Double]) -> [Double] {
        zip(closes.dropFirst(), closes).compactMap { $1 > 0 ? $0 / $1 - 1 : nil }
    }

    /// OLS beta of asset returns on market returns (cov / var). Inputs must be date-aligned.
    public static func beta(asset: [Double], market: [Double]) -> Double? {
        let n = min(asset.count, market.count)
        guard n >= 20 else { return nil }
        let a = asset.suffix(n), m = market.suffix(n)
        let ma = a.reduce(0, +) / Double(n), mm = m.reduce(0, +) / Double(n)
        var cov = 0.0, varM = 0.0
        for (x, y) in zip(a, m) { cov += (x - ma) * (y - mm); varM += (y - mm) * (y - mm) }
        return varM > 0 ? cov / varM : nil
    }

    /// One-day historical-simulation VaR: the loss not exceeded on `confidence` of days,
    /// returned as a positive number (0 if the tail shows no loss).
    public static func historicalVaR(pnl: [Double], confidence: Double = 0.95) -> Double? {
        guard pnl.count >= 20, (0.5..<1).contains(confidence) else { return nil }
        let sorted = pnl.sorted()
        let idx = Int((Double(sorted.count) * (1 - confidence)).rounded(.down))
        return max(-sorted[min(idx, sorted.count - 1)], 0)
    }

    /// Expected shortfall (CVaR): mean loss on the days beyond VaR.
    public static func expectedShortfall(pnl: [Double], confidence: Double = 0.95) -> Double? {
        guard pnl.count >= 20 else { return nil }
        let sorted = pnl.sorted()
        let k = max(Int((Double(sorted.count) * (1 - confidence)).rounded(.down)), 1)
        return max(-sorted.prefix(k).reduce(0, +) / Double(k), 0)
    }

    /// Aligns several daily series on the UTC calendar dates they all share, then returns
    /// per-symbol simple returns over those dates (crypto trades weekends; equities don't).
    public static func alignedReturns(_ series: [String: [Candle]]) -> [String: [Double]] {
        alignedCloses(series).closes.mapValues(returns)
    }

    /// Closes on the UTC calendar dates every series shares, oldest first.
    public static func alignedCloses(_ series: [String: [Candle]]) -> (dates: [Date], closes: [String: [Double]]) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func day(_ d: Date) -> Date { cal.startOfDay(for: d) }
        let maps = series.mapValues { cs in Dictionary(cs.map { (day($0.time), $0.close) }, uniquingKeysWith: { _, b in b }) }
        guard var common = maps.values.first.map({ Set($0.keys) }) else { return ([], [:]) }
        for m in maps.values { common.formIntersection(m.keys) }
        let dates = common.sorted()
        return (dates, maps.mapValues { m in dates.map { m[$0]! } })
    }

    /// Daily P&L history of a portfolio holding `exposure` (signed market value per symbol).
    public static func pnlSeries(exposure: [String: Double], returns: [String: [Double]]) -> [Double] {
        let n = exposure.keys.compactMap { returns[$0]?.count }.min() ?? 0
        guard n > 0 else { return [] }
        return (0..<n).map { t in exposure.reduce(0) { acc, e in acc + e.value * (returns[e.key].map { $0[$0.count - n + t] } ?? 0) } }
    }

    /// Pearson correlation of two date-aligned return series (nil under 20 observations or zero variance).
    public static func correlation(_ x: [Double], _ y: [Double]) -> Double? {
        let n = min(x.count, y.count)
        guard n >= 20 else { return nil }
        let a = x.suffix(n), b = y.suffix(n)
        let ma = a.reduce(0, +) / Double(n), mb = b.reduce(0, +) / Double(n)
        var cov = 0.0, va = 0.0, vb = 0.0
        for (p, q) in zip(a, b) { cov += (p - ma) * (q - mb); va += (p - ma) * (p - ma); vb += (q - mb) * (q - mb) }
        guard va > 1e-20, vb > 1e-20 else { return nil }   // flat series: variance is only rounding noise
        return min(max(cov / (va * vb).squareRoot(), -1), 1)
    }

    /// Symmetric correlation matrix in `symbols` order; the diagonal is 1 when the series exists.
    public static func correlationMatrix(_ returns: [String: [Double]], symbols: [String]) -> [[Double?]] {
        symbols.map { a in symbols.map { b in
            guard let x = returns[a], let y = returns[b] else { return nil }
            return a == b ? (x.count >= 20 ? 1 : nil) : correlation(x, y)
        } }
    }
}
