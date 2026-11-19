import Foundation

/// Summary statistics for a price history (HP, risk).
public struct ReturnStats: Sendable, Equatable {
    /// Total return over the window, as a fraction.
    public var totalReturn: Double
    /// Annualised volatility of log returns, as a fraction.
    public var annualizedVolatility: Double
    /// Largest peak-to-trough fall, as a negative fraction.
    public var maxDrawdown: Double
    public var bestPeriod: Double
    public var worstPeriod: Double
    public var periods: Int

    /// - Parameter periodsPerYear: 252 for equity daily bars, 365 for crypto, 52 for weekly.
    public init?(closes: [Double], periodsPerYear: Double) {
        let c = closes.filter { $0 > 0 && $0.isFinite }
        guard c.count >= 3 else { return nil }
        let simple = zip(c.dropFirst(), c).map { $0 / $1 - 1 }
        let logs = zip(c.dropFirst(), c).map { log($0 / $1) }
        let mean = logs.reduce(0, +) / Double(logs.count)
        let variance = logs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(logs.count - 1)
        var peak = c[0], mdd = 0.0
        for p in c { peak = max(peak, p); mdd = min(mdd, p / peak - 1) }
        totalReturn = c.last! / c.first! - 1
        annualizedVolatility = variance.squareRoot() * periodsPerYear.squareRoot()
        maxDrawdown = mdd
        bestPeriod = simple.max()!
        worstPeriod = simple.min()!
        periods = simple.count
    }
}

public enum CSV {
    /// Parses RFC 4180 CSV (quoted fields may hold commas, quotes and newlines) into rows of fields.
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], f = "", quoted = false
        var it = Array(text).makeIterator(), pending: Character? = nil
        func next() -> Character? { if let p = pending { pending = nil; return p }; return it.next() }
        while let c = next() {
            if quoted {
                if c == "\"" { if let n = next() { if n == "\"" { f.append("\"") } else { quoted = false; pending = n } } else { quoted = false } }
                else { f.append(c) }
                continue
            }
            switch c {
            case "\"": quoted = true
            case ",": row.append(f); f = ""
            case "\n", "\r", "\r\n": row.append(f); rows.append(row); row = []; f = ""
            default: f.append(c)
            }
        }
        if !f.isEmpty || !row.isEmpty { row.append(f); rows.append(row) }
        return rows
    }

    /// Tab-separated text for the clipboard: pastes into Excel or Numbers cells and reads with
    /// pandas.read_clipboard(). Tabs and line breaks inside fields become spaces so cells stay in place.
    public static func tsv(fromCSV text: String) -> String {
        parse(text).map { $0.map { $0.replacingOccurrences(of: "[\t\r\n]+", with: " ", options: .regularExpression) }.joined(separator: "\t") }
            .joined(separator: "\n") + "\n"
    }

    /// RFC 4180 field escaping. Text starting with = + - @ is prefixed with ' so a spreadsheet
    /// never evaluates it as a formula (numbers such as -0.5 are left alone).
    public static func field(_ s: String) -> String {
        var v = s
        if let f = v.first, "=+-@".contains(f), Double(v) == nil { v = "'" + v }
        return v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }

    /// Date,Open,High,Low,Close,Volume, oldest first, ISO dates (UTC), full precision.
    public static func candles(_ c: [Candle], intraday: Bool) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = intraday ? [.withInternetDateTime] : [.withFullDate]
        var out = "Date,Open,High,Low,Close,Volume\r\n"
        for k in c.sorted(by: { $0.time < $1.time }) {
            out += [f.string(from: k.time), "\(k.open)", "\(k.high)", "\(k.low)", "\(k.close)", "\(k.volume)"].map(field).joined(separator: ",") + "\r\n"
        }
        return out
    }
}


/// Rolling sample window with percentiles (latency and timing diagnostics).
public struct Samples: Sendable, Equatable {
    public private(set) var values: [Double] = []
    public let capacity: Int
    private var next = 0

    public init(capacity: Int = 2048) { self.capacity = capacity }

    public mutating func add(_ v: Double) {
        guard v.isFinite else { return }
        if values.count < capacity { values.append(v) } else { values[next] = v; next = (next + 1) % capacity }
    }

    /// Nearest-rank percentile, p in 0...100.
    public func percentile(_ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}
