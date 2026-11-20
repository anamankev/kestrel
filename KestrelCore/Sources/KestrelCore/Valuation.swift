import Foundation

// MARK: - RV: relative valuation against same-industry peers

/// Peers are other 10-K filers under the company's SEC SIC industry code (widened to the 3-digit group when
/// the exact code is sparse), closest in revenue. Valuation uses delayed prices × shares outstanding from SEC
/// filings. Mirrors web/src/core/valuation.ts.
public enum RelativeValuation {
    public struct Member: Sendable, Equatable { public var cik: Int; public var name: String }

    /// EDGAR's company list for one SIC code, 100 filers per page.
    public static func industryURL(sic: String, start: Int) -> URL {
        URL(string: "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&SIC=\(sic)&type=10-K&dateb=&owner=include&start=\(start)&count=100&output=atom")!
    }

    /// Shares outstanding for every filer at one quarter end (e.g. "CY2026Q2I").
    public static func sharesURL(quarter: String) -> URL {
        URL(string: "https://data.sec.gov/api/xbrl/frames/dei/EntityCommonStockSharesOutstanding/shares/\(quarter).json")!
    }

    /// The last three complete calendar quarters, newest first.
    public static func recentQuarters(now: Date = .now) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let y = cal.component(.year, from: now), q = (cal.component(.month, from: now) - 1) / 3
        return (0..<3).map { k in
            let n = y * 4 + q - 1 - k
            return "CY\(n / 4)Q\(n % 4 + 1)I"
        }
    }

    /// Companies in an EDGAR company-list Atom feed, one per `<entry>`. A company with former names has an
    /// escaped `<formerly-names>` block between its CIK and its name.
    public static func decodeIndustry(_ data: Data) -> [Member] {
        let text = String(decoding: data, as: UTF8.self)
        var out: [Member] = []
        for entry in text.components(separatedBy: "<entry>").dropFirst() {
            guard let c = entry.firstMatch(of: /<cik>(\d{1,10})<\/cik>/), let cik = Int(c.1),
                  let n = entry.firstMatch(of: /<name>([^<]{1,200})<\/name>/) else { continue }
            out.append(Member(cik: cik, name: String(n.1).replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespaces)))
        }
        return out
    }

    /// The SIC code and description from a company's SEC submissions JSON.
    public static func industry(fromSubmissions data: Data) -> (sic: String, name: String)? {
        struct S: Decodable { let sic: String?; let sicDescription: String? }
        // Only a 4-digit code ever reaches a request URL.
        guard let s = try? JSONDecoder().decode(S.self, from: data), let sic = s.sic, sic.wholeMatch(of: /[0-9]{4}/) != nil else { return nil }
        return (sic, String((s.sicDescription ?? "").prefix(120)))
    }

    /// Up to `n` peers with annual data, closest in revenue to the target (log scale).
    public static func pickPeers(target: ScreenRow, rows: [ScreenRow], members: Set<Int>, n: Int = 12) -> [ScreenRow] {
        let t = target.revenue.flatMap { $0 > 0 ? log($0) : nil }
        func dist(_ r: ScreenRow) -> Double {
            guard let t, let v = r.revenue, v > 0 else { return .infinity }
            return abs(log(v) - t)
        }
        return rows.filter { $0.cik != target.cik && members.contains($0.cik) }
            .sorted { (dist($0), $0.sizeRank) < (dist($1), $1.sizeRank) }
            .prefix(n).map { $0 }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public var cik: Int, ticker: String, name: String, isTarget: Bool
        public var price: Double?, marketCap: Double?, pe: Double?, ps: Double?, pb: Double?
        public var revenue: Double?, growth: Double?, margin: Double?, roe: Double?, leverage: Double?
        public var id: Int { cik }
    }

    private static func ratio(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b, a.isFinite, b.isFinite, b > 0 else { return nil }
        return a / b
    }

    /// Valuation and quality ratios for one company. P/E is left blank when earnings are negative.
    public static func row(_ r: ScreenRow, isTarget: Bool, price: Double?, shares: Double?, priorRevenue: Double?) -> Row {
        let cap: Double? = { guard let price, let shares, price.isFinite, shares > 0 else { return nil }; return price * shares }()
        return Row(cik: r.cik, ticker: r.ticker, name: r.name, isTarget: isTarget, price: price, marketCap: cap,
                   pe: (r.netIncome ?? 0) > 0 ? ratio(cap, r.netIncome) : nil,
                   ps: ratio(cap, r.revenue), pb: ratio(cap, r.equity), revenue: r.revenue,
                   growth: ratio(r.revenue, priorRevenue).map { $0 - 1 },
                   margin: r.netIncome != nil ? ratio(r.netIncome, r.revenue) : nil,
                   roe: r.netIncome != nil ? ratio(r.netIncome, r.equity) : nil,
                   leverage: ratio(r.liabilities, r.assets))
    }

    /// Median of the defined values (the peer benchmark).
    public static func median(_ values: [Double?]) -> Double? {
        let v = values.compactMap { $0 }.filter(\.isFinite).sorted()
        guard !v.isEmpty else { return nil }
        let m = v.count / 2
        return v.count % 2 == 1 ? v[m] : (v[m - 1] + v[m]) / 2
    }

    /// The target's value over the peer median, minus one.
    public static func premium(_ value: Double?, _ median: Double?) -> Double? { ratio(value, median).map { $0 - 1 } }
}

// MARK: - SEAS: seasonality by calendar month

/// Mirrors web/src/core/quant.ts (monthlyReturns, seasonality).
public enum Seasonality {
    public struct MonthReturn: Sendable, Equatable { public var year: Int; public var month: Int; public var ret: Double }
    public struct MonthStat: Sendable, Equatable, Identifiable {
        public var month: Int, n: Int
        public var mean: Double?, median: Double?, positive: Double?, best: Double?, worst: Double?
        public var id: Int { month }
    }

    /// Calendar-month returns from monthly (or finer) bars: each month's last close over the previous month's.
    /// The current, unfinished month is left out. Months are 0 (January) to 11.
    public static func monthlyReturns(_ bars: [Candle], now: Date = .now) -> [MonthReturn] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func key(_ d: Date) -> Int { cal.component(.year, from: d) * 12 + cal.component(.month, from: d) - 1 }
        var ends: [Int: Double] = [:]
        for b in bars.sorted(by: { $0.time < $1.time }) where b.close > 0 { ends[key(b.time)] = b.close }
        let current = key(now)
        return ends.compactMap { k, close -> MonthReturn? in
            guard k < current, let prev = ends[k - 1] else { return nil }
            return MonthReturn(year: k / 12, month: k % 12, ret: close / prev - 1)
        }
        .sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }

    public static func stats(_ rets: [MonthReturn]) -> [MonthStat] {
        (0..<12).map { m in
            let v = rets.filter { $0.month == m }.map(\.ret).sorted()
            guard !v.isEmpty else { return MonthStat(month: m, n: 0) }
            let mid = v.count / 2
            return MonthStat(month: m, n: v.count, mean: v.reduce(0, +) / Double(v.count),
                             median: v.count % 2 == 1 ? v[mid] : (v[mid - 1] + v[mid]) / 2,
                             positive: Double(v.filter { $0 > 0 }.count) / Double(v.count), best: v.last, worst: v.first)
        }
    }
}
