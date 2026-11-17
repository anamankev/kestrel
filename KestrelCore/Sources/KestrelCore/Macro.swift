import Foundation

public struct DataPoint: Sendable, Equatable {
    public var date: Date
    public var value: Double
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}

// MARK: - Macro indicators

/// How a raw series is turned into the number desks quote.
public enum MacroTransform: Sendable, Equatable {
    /// The value as published (e.g. unemployment rate).
    case level
    /// Percent change versus 12 observations earlier (monthly series → YoY inflation).
    case yearOverYear
    /// Difference versus the prior observation (payrolls: thousands of jobs added).
    case change
}

public struct MacroIndicator: Sendable, Equatable, Identifiable {
    public let id: String          // source series id
    public let name: String
    public let group: String
    public let transform: MacroTransform
    public let unit: String        // "%", "K", "bp"…
    public let source: String

    public init(id: String, name: String, group: String, transform: MacroTransform, unit: String, source: String) {
        self.id = id; self.name = name; self.group = group; self.transform = transform; self.unit = unit; self.source = source
    }

    /// The transformed series (oldest first), aligned to the dates it can be computed for.
    public func series(_ raw: [DataPoint]) -> [DataPoint] {
        switch transform {
        case .level: return raw
        case .change:
            return zip(raw.dropFirst(), raw).map { DataPoint(date: $0.date, value: $0.value - $1.value) }
        case .yearOverYear:
            guard raw.count > 12 else { return [] }
            return (12..<raw.count).compactMap { i in
                raw[i - 12].value == 0 ? nil : DataPoint(date: raw[i].date, value: (raw[i].value / raw[i - 12].value - 1) * 100)
            }
        }
    }

    public static let all: [MacroIndicator] = [
        MacroIndicator(id: "CUSR0000SA0", name: "CPI inflation (YoY)", group: "INFLATION", transform: .yearOverYear, unit: "%", source: "BLS"),
        MacroIndicator(id: "CUSR0000SA0L1E", name: "Core CPI ex food & energy (YoY)", group: "INFLATION", transform: .yearOverYear, unit: "%", source: "BLS"),
        MacroIndicator(id: "WPSFD4", name: "PPI final demand (YoY)", group: "INFLATION", transform: .yearOverYear, unit: "%", source: "BLS"),
        MacroIndicator(id: "LNS14000000", name: "Unemployment rate", group: "LABOR", transform: .level, unit: "%", source: "BLS"),
        MacroIndicator(id: "CES0000000001", name: "Nonfarm payrolls (monthly change)", group: "LABOR", transform: .change, unit: "K", source: "BLS"),
        MacroIndicator(id: "CES0500000003", name: "Average hourly earnings (YoY)", group: "LABOR", transform: .yearOverYear, unit: "%", source: "BLS"),
        MacroIndicator(id: "LNS11300000", name: "Labor force participation", group: "LABOR", transform: .level, unit: "%", source: "BLS"),
    ]
}

/// Bureau of Labor Statistics public API v1: no key, up to 25 series per request.
public enum BLS {
    public static let url = URL(string: "https://api.bls.gov/publicAPI/v1/timeseries/data/")!

    public static func request(series: [String]) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["seriesid": Array(series.prefix(25))])
        return r
    }

    private struct Root: Decodable {
        let status: String
        let Results: Results?
    }
    private struct Results: Decodable { let series: [Series] }
    private struct Series: Decodable { let seriesID: String; let data: [Point] }
    private struct Point: Decodable { let year: String; let period: String; let value: String }

    public enum DecodeError: Error { case notSucceeded(String) }

    /// Monthly observations per series, oldest first. Annual averages (M13) are dropped.
    public static func decode(_ data: Data) throws -> [String: [DataPoint]] {
        let root = try JSONDecoder().decode(Root.self, from: data)
        guard root.status == "REQUEST_SUCCEEDED", let results = root.Results else { throw DecodeError.notSucceeded(root.status) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var out: [String: [DataPoint]] = [:]
        for s in results.series {
            out[s.seriesID] = s.data.compactMap { p in
                guard p.period.hasPrefix("M"), let m = Int(p.period.dropFirst()), (1...12).contains(m),
                      let y = Int(p.year), let v = Double(p.value),
                      let d = cal.date(from: DateComponents(year: y, month: m, day: 1)) else { return nil }
                return DataPoint(date: d, value: v)
            }
            .sorted { $0.date < $1.date }
        }
        return out
    }
}

/// New York Fed reference rates (EFFR, SOFR): https://markets.newyorkfed.org/api/rates/…
public enum NYFed {
    public static func url(_ rate: String, last n: Int = 60) -> URL {
        let path = rate == "sofr" ? "secured/sofr" : "unsecured/effr"
        return URL(string: "https://markets.newyorkfed.org/api/rates/\(path)/last/\(n).json")!
    }

    public struct Rates: Sendable, Equatable {
        public var series: [DataPoint]   // oldest first
        public var targetLow: Double?
        public var targetHigh: Double?
    }

    private struct Root: Decodable { let refRates: [Row] }
    private struct Row: Decodable {
        let effectiveDate: String
        let percentRate: Double
        let targetRateFrom: Double?
        let targetRateTo: Double?
    }

    public static func decode(_ data: Data) throws -> Rates {
        let rows = try JSONDecoder().decode(Root.self, from: data).refRates
        let series = rows.compactMap { r in SECFacts.day.date(from: r.effectiveDate).map { DataPoint(date: $0, value: r.percentRate) } }
            .sorted { $0.date < $1.date }
        return Rates(series: series, targetLow: rows.first?.targetRateFrom, targetHigh: rows.first?.targetRateTo)
    }
}

// MARK: - Company events (SEC submissions)

public struct Filing: Sendable, Equatable, Identifiable {
    public var form: String
    public var date: Date
    public var title: String
    public var url: URL
    public var isEarnings: Bool
    public var id: String { url.absoluteString }
}

public enum SECFilings {
    public static func url(cik: Int) -> URL {
        URL(string: String(format: "https://data.sec.gov/submissions/CIK%010d.json", cik))!
    }

    /// 8-K item codes that matter to a trader.
    static let items: [String: String] = [
        "1.01": "Material agreement", "1.03": "Bankruptcy", "2.01": "Acquisition / disposition",
        "2.02": "Earnings release", "2.05": "Restructuring costs", "2.06": "Impairment",
        "3.01": "Listing notice", "4.02": "Non-reliance on prior financials", "5.02": "Officer / director change",
        "5.03": "Bylaw amendment", "5.07": "Shareholder vote", "7.01": "Reg FD disclosure", "8.01": "Other material event",
    ]
    static let forms: [String: String] = [
        "10-K": "Annual report", "10-Q": "Quarterly report", "DEF 14A": "Proxy statement", "S-1": "Registration",
        "SC 13D": "Activist stake (>5%)", "SC 13G": "Passive stake (>5%)", "4": "Insider transaction",
    ]

    private struct Root: Decodable { let cik: String; let filings: F }
    private struct F: Decodable { let recent: Recent }
    private struct Recent: Decodable {
        let accessionNumber: [String]
        let filingDate: [String]
        let form: [String]
        let items: [String]
        let primaryDocument: [String]
    }

    /// Material filings, newest first. Form 4s are kept but collapsed into the insider count by the UI.
    public static func decode(_ data: Data, limit: Int = 80) throws -> [Filing] {
        let root = try JSONDecoder().decode(Root.self, from: data)
        let r = root.filings.recent
        let cik = Int(root.cik) ?? 0
        let n = [r.accessionNumber.count, r.filingDate.count, r.form.count, r.items.count, r.primaryDocument.count].min() ?? 0
        var out: [Filing] = []
        for i in 0..<n {
            let form = r.form[i]
            guard let date = SECFacts.day.date(from: r.filingDate[i]) else { continue }
            let title: String
            var earnings = false
            if form == "8-K" {
                let codes = r.items[i].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let named = codes.compactMap { items[$0] }
                guard !named.isEmpty else { continue }
                earnings = codes.contains("2.02")
                title = named.joined(separator: " · ")
            } else if let t = forms[form] {
                title = t
            } else { continue }
            let acc = r.accessionNumber[i].replacingOccurrences(of: "-", with: "")
            guard let url = URL(string: "https://www.sec.gov/Archives/edgar/data/\(cik)/\(acc)/\(r.primaryDocument[i])") else { continue }
            out.append(Filing(form: form, date: date, title: title, url: url, isEarnings: earnings))
            if out.count >= limit { break }
        }
        return out
    }

    /// Next earnings estimate: the last earnings 8-K rolled forward by a quarter (91 days) until it is
    /// in the future. A heuristic, labelled as such in the UI; real dates need a paid calendar feed.
    public static func estimatedNextEarnings(_ filings: [Filing], now: Date = .now) -> Date? {
        guard var d = filings.filter(\.isEarnings).map(\.date).max() else { return nil }
        while d <= now { d = d.addingTimeInterval(91 * 86_400) }
        return d
    }
}
