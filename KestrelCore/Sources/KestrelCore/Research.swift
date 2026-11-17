import Foundation

// MARK: - BETA: ordinary least squares of asset returns on benchmark returns

public struct Regression: Sendable, Equatable {
    public var alpha: Double          // per period
    public var beta: Double
    public var alphaSE: Double
    public var betaSE: Double
    public var r2: Double
    public var correlation: Double
    public var residualSD: Double     // per period
    public var n: Int

    public var alphaT: Double { alphaSE > 0 ? alpha / alphaSE : .nan }
    public var betaT: Double { betaSE > 0 ? beta / betaSE : .nan }
    /// Blume adjustment toward 1, as quoted on most terminals: 0.67 × raw + 0.33.
    public var adjustedBeta: Double { 0.67 * beta + 0.33 }

    /// y = alpha + beta·x + e. Needs at least 3 paired observations and variance in x.
    public static func ols(y: [Double], x: [Double]) -> Regression? {
        let n = min(x.count, y.count)
        guard n >= 3 else { return nil }
        let x = Array(x.suffix(n)), y = Array(y.suffix(n))
        let mx = x.reduce(0, +) / Double(n), my = y.reduce(0, +) / Double(n)
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in 0..<n {
            let dx = x[i] - mx, dy = y[i] - my
            sxx += dx * dx; sxy += dx * dy; syy += dy * dy
        }
        guard sxx > 1e-20 else { return nil }
        let beta = sxy / sxx
        let alpha = my - beta * mx
        var sse = 0.0
        for i in 0..<n { let e = y[i] - alpha - beta * x[i]; sse += e * e }
        let s2 = sse / Double(n - 2)
        let r2 = syy > 0 ? max(0, 1 - sse / syy) : 0
        return Regression(alpha: alpha, beta: beta,
                          alphaSE: (s2 * (1 / Double(n) + mx * mx / sxx)).squareRoot(),
                          betaSE: (s2 / sxx).squareRoot(),
                          r2: r2, correlation: syy > 0 ? sxy / (sxx * syy).squareRoot() : 0,
                          residualSD: s2.squareRoot(), n: n)
    }
}

// MARK: - COMP: performance summary of one price series

public struct PerformanceSummary: Sendable, Equatable {
    public var totalReturn: Double
    public var annualizedReturn: Double
    public var annualizedVol: Double
    public var sharpe: Double?        // excess over the risk-free rate
    public var maxDrawdown: Double    // negative fraction

    /// - Parameters: closes oldest first; `periodsPerYear` 252 for stocks, 365 for crypto; `riskFree` annual.
    public static func of(_ closes: [Double], periodsPerYear: Double, riskFree: Double = 0) -> PerformanceSummary? {
        guard closes.count >= 3, let first = closes.first, first > 0, let last = closes.last else { return nil }
        let r = Risk.returns(closes)
        let years = Double(r.count) / periodsPerYear
        let total = last / first - 1
        let ann = years > 0 ? pow(1 + total, 1 / years) - 1 : 0
        let mean = r.reduce(0, +) / Double(r.count)
        let sd = (r.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(r.count - 1, 1))).squareRoot()
        let vol = sd * periodsPerYear.squareRoot()
        var peak = first, dd = 0.0
        for c in closes { peak = max(peak, c); dd = min(dd, c / peak - 1) }
        return PerformanceSummary(totalReturn: total, annualizedReturn: ann, annualizedVol: vol,
                                  sharpe: vol > 0 ? (ann - riskFree) / vol : nil, maxDrawdown: dd)
    }

    /// Rebased to 100 at the first close, for the comparison chart.
    public static func rebased(_ closes: [Double]) -> [Double] {
        guard let f = closes.first, f > 0 else { return [] }
        return closes.map { $0 / f * 100 }
    }
}

// MARK: - MVO: long-only mean-variance efficient frontier

public struct Portfolio: Sendable, Equatable {
    public var weights: [Double]
    public var expectedReturn: Double  // annual
    public var volatility: Double      // annual
    public func sharpe(riskFree: Double) -> Double { volatility > 0 ? (expectedReturn - riskFree) / volatility : 0 }
}

public enum Frontier {
    /// Annualized mean vector and sample covariance matrix of aligned per-period returns.
    public static func moments(_ returns: [[Double]], periodsPerYear: Double) -> (mu: [Double], cov: [[Double]])? {
        let k = returns.count
        guard k >= 2, let n = returns.map(\.count).min(), n >= 20 else { return nil }
        let r = returns.map { Array($0.suffix(n)) }
        let means = r.map { $0.reduce(0, +) / Double(n) }
        var cov = Array(repeating: Array(repeating: 0.0, count: k), count: k)
        for i in 0..<k {
            for j in i..<k {
                var s = 0.0
                for t in 0..<n { s += (r[i][t] - means[i]) * (r[j][t] - means[j]) }
                cov[i][j] = s / Double(n - 1) * periodsPerYear
                cov[j][i] = cov[i][j]
            }
        }
        return (means.map { $0 * periodsPerYear }, cov)
    }

    /// Euclidean projection onto the probability simplex (weights ≥ 0, sum to 1).
    public static func projectToSimplex(_ v: [Double]) -> [Double] {
        let u = v.sorted(by: >)
        var css = 0.0, theta = 0.0
        for (i, x) in u.enumerated() {
            css += x
            let t = (css - 1) / Double(i + 1)
            if x - t > 0 { theta = t }
        }
        return v.map { max($0 - theta, 0) }
    }

    static func evaluate(_ w: [Double], _ mu: [Double], _ cov: [[Double]]) -> Portfolio {
        let k = w.count
        var variance = 0.0
        for i in 0..<k { for j in 0..<k { variance += w[i] * w[j] * cov[i][j] } }
        let ret = zip(w, mu).map(*).reduce(0, +)
        return Portfolio(weights: w, expectedReturn: ret, volatility: max(variance, 0).squareRoot())
    }

    /// Minimizes wᵀΣw − λ·μᵀw over long-only, fully invested weights (projected gradient).
    public static func optimize(mu: [Double], cov: [[Double]], lambda: Double, iterations: Int = 3000) -> Portfolio {
        let k = mu.count
        // Step size from a bound on the largest eigenvalue (max row sum of |Σ|).
        let lipschitz = 2 * (cov.map { $0.map(abs).reduce(0, +) }.max() ?? 1)
        let step = 1 / max(lipschitz, 1e-12)
        var w = Array(repeating: 1 / Double(k), count: k)
        for _ in 0..<iterations {
            var g = Array(repeating: 0.0, count: k)
            for i in 0..<k {
                var s = 0.0
                for j in 0..<k { s += cov[i][j] * w[j] }
                g[i] = 2 * s - lambda * mu[i]
            }
            let next = projectToSimplex(zip(w, g).map { $0 - step * $1 })
            let moved = zip(next, w).map { abs($0 - $1) }.max() ?? 0
            w = next
            if moved < 1e-10 { break }
        }
        return evaluate(w, mu, cov)
    }

    /// Frontier from minimum variance to the highest-return asset, plus the max-Sharpe portfolio.
    public static func build(mu: [Double], cov: [[Double]], riskFree: Double, points: Int = 40)
        -> (frontier: [Portfolio], minVariance: Portfolio, maxSharpe: Portfolio)? {
        guard mu.count >= 2, cov.count == mu.count else { return nil }
        let minVar = optimize(mu: mu, cov: cov, lambda: 0)
        var curve = [minVar]
        // λ spaced geometrically so the curve is dense near the minimum-variance end.
        let scale = (cov.map { $0.map(abs).max() ?? 0 }.max() ?? 1) / max(mu.map(abs).max() ?? 1, 1e-9)
        for p in 1...points {
            let lambda = scale * 0.01 * pow(1000, Double(p) / Double(points))
            curve.append(optimize(mu: mu, cov: cov, lambda: lambda))
        }
        var frontier: [Portfolio] = []
        for p in curve.sorted(by: { $0.volatility < $1.volatility })
        where frontier.last.map({ p.expectedReturn > $0.expectedReturn + 1e-9 }) ?? true {
            frontier.append(p)
        }
        let best = frontier.max { $0.sharpe(riskFree: riskFree) < $1.sharpe(riskFree: riskFree) } ?? minVar
        return (frontier, minVar, best)
    }
}

// MARK: - EQS: fundamental screen over every SEC filer (XBRL frames)

public struct ScreenRow: Sendable, Equatable, Identifiable {
    public var cik: Int
    public var ticker: String
    public var name: String
    /// Position in SEC's ticker file, which is ordered by market value: a size rank.
    public var sizeRank: Int
    public var revenue: Double?
    public var netIncome: Double?
    public var assets: Double?
    public var liabilities: Double?
    public var equity: Double?
    public var id: Int { cik }

    public var netMargin: Double? {
        guard let r = revenue, r > 0, let n = netIncome else { return nil }
        return n / r
    }
    public var roe: Double? {
        guard let e = equity, e > 0, let n = netIncome else { return nil }
        return n / e
    }
    public var roa: Double? {
        guard let a = assets, a > 0, let n = netIncome else { return nil }
        return n / a
    }
    public var leverage: Double? {
        guard let a = assets, a > 0, let l = liabilities else { return nil }
        return l / a
    }
}

public enum SECFrames {
    public enum Period: Sendable { case year(Int), yearEnd(Int) }

    public static func url(concept: String, period: Period) -> URL {
        let p: String = switch period {
        case .year(let y): "CY\(y)"
        case .yearEnd(let y): "CY\(y)Q4I"
        }
        return URL(string: "https://data.sec.gov/api/xbrl/frames/us-gaap/\(concept)/USD/\(p).json")!
    }

    private struct Root: Decodable { let data: [Row] }
    private struct Row: Decodable { let cik: Int; let val: Double }

    /// cik → value. One frame is a single fact per company for the period.
    public static func decode(_ data: Data) throws -> [Int: Double] {
        var out: [Int: Double] = [:]
        for r in try JSONDecoder().decode(Root.self, from: data).data { out[r.cik] = r.val }
        return out
    }

    public struct Listing: Sendable, Equatable { public var ticker: String; public var name: String; public var rank: Int }

    /// SEC's company_tickers.json as cik → its primary listing (the lowest rank, i.e. largest line).
    public static func listings(_ data: Data) throws -> [Int: Listing] {
        struct R: Decodable { let cik_str: Int; let ticker: String; let title: String }
        let rows = try JSONDecoder().decode([String: R].self, from: data)
        var out: [Int: Listing] = [:]
        for (key, r) in rows {
            let rank = Int(key) ?? .max
            if let have = out[r.cik_str], have.rank <= rank { continue }
            out[r.cik_str] = Listing(ticker: r.ticker.uppercased().replacingOccurrences(of: ".", with: "-"), name: r.title, rank: rank)
        }
        return out
    }

    /// Joins the frames onto listed companies. Many filers skip the plain totals, so:
    /// revenue falls back to ASC 606 revenue, net income to ProfitLoss, equity to equity
    /// including non-controlling interests, and liabilities to (liabilities + equity) − equity.
    public static func rows(listings: [Int: Listing], revenues: [Int: Double], contractRevenues: [Int: Double],
                            netIncome: [Int: Double], assets: [Int: Double], liabilities: [Int: Double],
                            equity: [Int: Double], profitLoss: [Int: Double] = [:], equityWithNCI: [Int: Double] = [:],
                            liabilitiesAndEquity: [Int: Double] = [:]) -> [ScreenRow] {
        listings.compactMap { cik, l in
            let rev = revenues[cik] ?? contractRevenues[cik]
            let ni = netIncome[cik] ?? profitLoss[cik]
            let eq = equity[cik] ?? equityWithNCI[cik]
            var liab = liabilities[cik]
            if liab == nil, let total = liabilitiesAndEquity[cik], let e = equityWithNCI[cik] ?? equity[cik] { liab = total - e }
            guard rev != nil || ni != nil || assets[cik] != nil else { return nil }
            return ScreenRow(cik: cik, ticker: l.ticker, name: l.name, sizeRank: l.rank, revenue: rev,
                             netIncome: ni, assets: assets[cik] ?? liabilitiesAndEquity[cik], liabilities: liab, equity: eq)
        }
        .sorted { $0.sizeRank < $1.sizeRank }
    }
}

// MARK: - CSV tables

extension CSV {
    public static func make(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    public static func number(_ v: Double?, digits: Int = 6) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.\(digits)f", v)
    }
}
