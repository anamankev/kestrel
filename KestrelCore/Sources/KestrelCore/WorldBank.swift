import Foundation

/// World Bank World Development Indicators (api.worldbank.org, no key; data CC BY 4.0).
public enum WorldBank {
    public enum Unit: Sendable { case percent, usd, count, ratio }

    public struct Indicator: Sendable, Hashable, Identifiable {
        public var id: String
        public var name: String
        public var short: String
        public var unit: Unit
    }

    /// The headline set shown on a country profile.
    public static let indicators: [Indicator] = [
        .init(id: "NY.GDP.MKTP.KD.ZG", name: "Real GDP growth", short: "GDP GROWTH", unit: .percent),
        .init(id: "NY.GDP.MKTP.CD", name: "GDP (current US$)", short: "GDP", unit: .usd),
        .init(id: "NY.GDP.PCAP.CD", name: "GDP per capita (current US$)", short: "GDP / CAPITA", unit: .usd),
        .init(id: "FP.CPI.TOTL.ZG", name: "Inflation, consumer prices", short: "CPI INFLATION", unit: .percent),
        .init(id: "SL.UEM.TOTL.ZS", name: "Unemployment (% of labour force, ILO)", short: "UNEMPLOYMENT", unit: .percent),
        .init(id: "BN.CAB.XOKA.GD.ZS", name: "Current account balance (% of GDP)", short: "CURRENT ACCOUNT", unit: .percent),
        .init(id: "GC.DOD.TOTL.GD.ZS", name: "Central government debt (% of GDP)", short: "GOVT DEBT", unit: .percent),
        .init(id: "NE.EXP.GNFS.ZS", name: "Exports of goods and services (% of GDP)", short: "EXPORTS", unit: .percent),
        .init(id: "BX.KLT.DINV.WD.GD.ZS", name: "Foreign direct investment, net inflows (% of GDP)", short: "FDI INFLOWS", unit: .percent),
        .init(id: "FR.INR.RINR", name: "Real interest rate", short: "REAL RATE", unit: .percent),
        .init(id: "SP.POP.TOTL", name: "Population", short: "POPULATION", unit: .count),
    ]

    public struct Country: Sendable, Hashable, Identifiable {
        public var id: String        // ISO3
        public var name: String
        public var region: String
        public var income: String
    }

    public struct Point: Sendable, Hashable { public var year: Int; public var value: Double }

    static let base = "https://api.worldbank.org/v2/"

    public static var countriesURL: URL { URL(string: base + "country?format=json&per_page=400")! }

    /// One indicator for every country and aggregate over a span of years (~4,000 rows, ~1 MB).
    /// Popular bulk queries are usually served from the World Bank's cache, unlike per-country ones.
    public static func panelURL(indicator: String, from: Int, to: Int) -> URL {
        URL(string: base + "country/all/indicator/\(indicator)?format=json&per_page=20000&date=\(from):\(to)")!
    }

    private struct Named: Decodable { let id: String?; let value: String? }
    private struct CountryRow: Decodable { let id: String; let name: String; let region: Named; let incomeLevel: Named }
    private struct ValueRow: Decodable { let countryiso3code: String?; let date: String; let value: Double? }

    /// The API answers `[meta, rows]`, or `[{message: …}]` on error (→ no rows).
    private static func rows<T: Decodable>(_ data: Data, as: T.Type) throws -> [T] {
        guard let top = try JSONSerialization.jsonObject(with: data) as? [Any], top.count > 1, let list = top[1] as? [Any] else { return [] }
        return try JSONDecoder().decode([T].self, from: JSONSerialization.data(withJSONObject: list))
    }

    /// Real countries only: aggregates (regions, income groups) are dropped.
    public static func decodeCountries(_ data: Data) throws -> [Country] {
        try rows(data, as: CountryRow.self)
            .filter { ($0.region.value ?? "").trimmingCharacters(in: .whitespaces) != "Aggregates" && $0.id.count == 3 }
            .map { Country(id: $0.id, name: $0.name, region: ($0.region.value ?? "").trimmingCharacters(in: .whitespaces),
                           income: ($0.incomeLevel.value ?? "").trimmingCharacters(in: .whitespaces)) }
            .sorted { $0.name < $1.name }
    }

    /// The official bulk download: a ZIP with the full history (1960 on) for every country. A static
    /// file, so it is fast and reliable when the query API's origin is slow.
    public static func bulkURL(indicator: String) -> URL {
        URL(string: base + "en/indicator/\(indicator)?downloadformat=csv")!
    }

    /// Parses the bulk ZIP's `API_…csv`: "Country Name","Country Code","Indicator Name","Indicator Code","1960",…
    public static func decodeBulk(_ zip: Data) throws -> [String: [Point]] {
        let raw = try Zip.file(zip) { $0.hasPrefix("API_") && $0.hasSuffix(".csv") }
        guard let text = String(data: raw, encoding: .utf8) else { throw Zip.ZipError.corrupt }
        var years: [Int?] = []
        var out: [String: [Point]] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let cells = csvFields(String(line))
            if cells.first == "Country Name" { years = cells.map { Int($0) }; continue }
            guard !years.isEmpty, cells.count > 4, cells[1].count == 3 else { continue }
            var points: [Point] = []
            for (k, cell) in cells.enumerated() where k >= 4 && k < years.count {
                if let y = years[k], let v = Double(cell) { points.append(Point(year: y, value: v)) }
            }
            if !points.isEmpty { out[cells[1]] = points }
        }
        return out
    }

    /// One RFC 4180 line: quoted fields may contain commas ("Korea, Rep.") and doubled quotes.
    static func csvFields(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        var it = line.makeIterator()
        while let ch = it.next() {
            if quoted {
                if ch == "\"" {
                    if let n = it.next() {
                        if n == "\"" { cur.append("\"") } else { quoted = false; if n == "," { out.append(cur); cur = "" } else { cur.append(n) } }
                    } else { quoted = false }
                } else { cur.append(ch) }
            } else if ch == "\"" { quoted = true }
            else if ch == "," { out.append(cur); cur = "" }
            else if ch != "\u{FEFF}" { cur.append(ch) }
        }
        out.append(cur)
        return out
    }

    /// ISO3 → yearly points (oldest first), empty values dropped.
    public static func decodePanel(_ data: Data) throws -> [String: [Point]] {
        var out: [String: [Point]] = [:]
        for r in try rows(data, as: ValueRow.self) {
            guard let iso = r.countryiso3code, iso.count == 3, let v = r.value, let y = Int(r.date) else { continue }
            out[iso, default: []].append(Point(year: y, value: v))
        }
        return out.mapValues { $0.sorted { $0.year < $1.year } }
    }

    /// Each country's most recent value in a panel.
    public static func latest(_ panel: [String: [Point]]) -> [String: Point] {
        panel.compactMapValues(\.last)
    }

    /// Finds a country by ISO3 code or name (`JPN`, `japan`, `united king`).
    public static func match(_ query: String, in countries: [Country]) -> Country? {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return nil }
        return countries.first { $0.id == q }
            ?? countries.first { $0.name.uppercased() == q }
            ?? countries.first { $0.name.uppercased().hasPrefix(q) }
            ?? countries.first { $0.name.uppercased().contains(q) }
    }
}

