import Foundation

/// One fiscal year of reported figures (USD unless noted). Missing tags stay nil.
public struct FiscalYear: Sendable, Equatable, Identifiable {
    public var year: Int
    public var periodEnd: Date
    public var revenue: Double?
    public var grossProfit: Double?
    public var operatingIncome: Double?
    public var netIncome: Double?
    public var epsDiluted: Double?
    public var operatingCashFlow: Double?
    public var capex: Double?
    public var cash: Double?
    public var longTermDebt: Double?
    public var equity: Double?
    public var assets: Double?
    public var liabilities: Double?

    public var id: Int { year }

    public var freeCashFlow: Double? {
        guard let o = operatingCashFlow else { return nil }
        return o - (capex ?? 0)
    }
    public var grossMargin: Double? { ratio(grossProfit, revenue) }
    public var operatingMargin: Double? { ratio(operatingIncome, revenue) }
    public var netMargin: Double? { ratio(netIncome, revenue) }
    public var returnOnEquity: Double? { ratio(netIncome, equity) }
    public var debtToEquity: Double? { ratio(longTermDebt, equity) }

    private func ratio(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b, b != 0 else { return nil }
        return a / b
    }
}

public struct CompanyFundamentals: Sendable, Equatable {
    public var name: String
    public var cik: Int
    /// Oldest first.
    public var years: [FiscalYear]
    public var sharesOutstanding: Double?
    public var lastFiled: Date?

    public var latest: FiscalYear? { years.last }

    /// Year-over-year growth of a metric for `year`, as a fraction.
    public func growth(_ metric: KeyPath<FiscalYear, Double?>, year: Int) -> Double? {
        guard let i = years.firstIndex(where: { $0.year == year }), i > 0,
              let now = years[i][keyPath: metric], let prev = years[i - 1][keyPath: metric], prev != 0 else { return nil }
        return (now - prev) / abs(prev)
    }

    public func marketCap(price: Double) -> Double? { sharesOutstanding.map { $0 * price } }

    /// Trailing P/E on the latest fiscal year's diluted EPS (nil when EPS ≤ 0, as conventionally reported).
    public func priceToEarnings(price: Double) -> Double? {
        guard let eps = latest?.epsDiluted, eps > 0 else { return nil }
        return price / eps
    }
}

/// SEC EDGAR XBRL "company facts" (https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json).
///
/// Companies tag the same line item differently across years, so each metric tries a list of
/// US-GAAP concepts in order. Only annual 10-K figures are used; for flow items the period must
/// span roughly a year, which filters out the quarterly comparatives that 10-Ks also contain.
public enum SECFacts {
    public static func factsURL(cik: Int) -> URL {
        URL(string: String(format: "https://data.sec.gov/api/xbrl/companyfacts/CIK%010d.json", cik))!
    }
    public static let tickersURL = URL(string: "https://www.sec.gov/files/company_tickers.json")!

    public static func filingURL(cik: Int) -> URL {
        URL(string: "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=\(cik)&type=10-K")!
    }

    /// SEC asks automated clients to declare a contact in the User-Agent.
    public static func userAgent(contact: String) -> String { "Kestrel Terminal \(contact)" }

    /// Minimal contact validation: one @, a dot in the domain, no whitespace, sane length.
    public static func isValidContact(_ s: String) -> Bool {
        s.count <= 100 && s.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    private struct Root: Decodable {
        let cik: Int
        let entityName: String
        let facts: [String: [String: Concept]]
    }
    private struct Concept: Decodable { let units: [String: [Fact]] }
    private struct Fact: Decodable {
        let start: String?
        let end: String
        let val: Double
        let fy: Int?
        let fp: String?
        let form: String?
        let filed: String?
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated(unsafe) static let flows: [(WritableKeyPath<FiscalYear, Double?>, [String])] = [
        (\.revenue, ["RevenueFromContractWithCustomerExcludingAssessedTax", "Revenues", "SalesRevenueNet", "RevenueFromContractWithCustomerIncludingAssessedTax"]),
        (\.grossProfit, ["GrossProfit"]),
        (\.operatingIncome, ["OperatingIncomeLoss"]),
        (\.netIncome, ["NetIncomeLoss", "ProfitLoss"]),
        (\.epsDiluted, ["EarningsPerShareDiluted", "EarningsPerShareBasicAndDiluted"]),
        (\.operatingCashFlow, ["NetCashProvidedByUsedInOperatingActivities"]),
        (\.capex, ["PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsToAcquireProductiveAssets"]),
    ]
    nonisolated(unsafe) static let instants: [(WritableKeyPath<FiscalYear, Double?>, [String])] = [
        (\.cash, ["CashAndCashEquivalentsAtCarryingValue", "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents"]),
        (\.longTermDebt, ["LongTermDebt", "LongTermDebtNoncurrent"]),
        (\.equity, ["StockholdersEquity", "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest"]),
        (\.assets, ["Assets"]),
        (\.liabilities, ["Liabilities"]),
    ]

    /// Annual values by fiscal period end. Concepts are tried in priority order: an earlier concept
    /// owns every period it reports; later ones only fill gaps. Within a concept the latest filing
    /// (i.e. any restatement) wins.
    private static func annual(_ gaap: [String: Concept], _ names: [String], flow: Bool) -> [Date: (Double, Date)] {
        var out: [Date: (Double, Date)] = [:]
        for name in names {
            guard let units = gaap[name]?.units, let facts = units["USD"] ?? units["USD/shares"] else { continue }
            var mine: [Date: (Double, Date)] = [:]
            for f in facts where f.form == "10-K" || f.form == "10-K/A" {
                guard let end = day.date(from: f.end) else { continue }
                if flow {
                    guard let s = f.start.flatMap(day.date(from:)),
                          (330...400).contains(end.timeIntervalSince(s) / 86_400) else { continue }
                }
                let filed = f.filed.flatMap(day.date(from:)) ?? .distantPast
                if mine[end].map({ $0.1 <= filed }) ?? true { mine[end] = (f.val, filed) }
            }
            for (end, v) in mine where out[end] == nil { out[end] = v }
        }
        return out
    }

    public static func decode(_ data: Data, years limit: Int = 5) throws -> CompanyFundamentals {
        let root = try JSONDecoder().decode(Root.self, from: data)
        let gaap = root.facts["us-gaap"] ?? [:]
        // Fiscal year ends come from the revenue/net income periods; everything aligns to those dates.
        var byEnd: [Date: FiscalYear] = [:]
        var lastFiled: Date?
        for (path, names) in flows {
            for (end, (v, filed)) in annual(gaap, names, flow: true) {
                var fy = byEnd[end] ?? FiscalYear(year: Calendar(identifier: .gregorian).component(.year, from: end), periodEnd: end)
                fy[keyPath: path] = v
                byEnd[end] = fy
                if filed > (lastFiled ?? .distantPast) { lastFiled = filed }
            }
        }
        for (path, names) in instants {
            let values = annual(gaap, names, flow: false)
            for end in byEnd.keys { if let v = values[end] { byEnd[end]![keyPath: path] = v.0 } }
        }
        // Drop stray periods (e.g. transition years) that lack both revenue and net income.
        let years = byEnd.values
            .filter { $0.revenue != nil || $0.netIncome != nil }
            .sorted { $0.periodEnd < $1.periodEnd }
        let shares = (root.facts["dei"]?["EntityCommonStockSharesOutstanding"]?.units["shares"])?
            .max { ($0.end, $0.filed ?? "") < ($1.end, $1.filed ?? "") }?.val
        return CompanyFundamentals(name: root.entityName, cik: root.cik, years: Array(years.suffix(limit)),
                                   sharesOutstanding: shares, lastFiled: lastFiled)
    }

    private struct TickerRow: Decodable { let cik_str: Int; let ticker: String }

    /// `company_tickers.json` → ticker (Yahoo style, `-` for class shares) → CIK.
    public static func decodeTickers(_ data: Data) throws -> [String: Int] {
        let rows = try JSONDecoder().decode([String: TickerRow].self, from: data)
        var out: [String: Int] = [:]
        for r in rows.values { out[r.ticker.uppercased().replacingOccurrences(of: ".", with: "-")] = r.cik_str }
        return out
    }
}
