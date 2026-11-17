import Foundation
import Compression

// MARK: - Minimal ZIP reader (Ken French ships each dataset as a one-file deflate ZIP)

public enum Zip {
    public enum ZipError: Error { case notZip, unsupported, corrupt }

    /// Returns the first file in the archive. Reads the central directory, so archives that
    /// use data descriptors (sizes after the data) work too. Stored and deflate only.
    public static func firstFile(_ data: Data, maxSize: Int = 32 << 20) throws -> Data {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard b.count >= 22 else { throw ZipError.notZip }
        // End of central directory: signature 0x06054b50 within the last 64 KB + 22 bytes.
        var eocd = -1
        var i = b.count - 22
        while i >= max(0, b.count - 65_557) {
            if b[i] == 0x50, b[i + 1] == 0x4b, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let cd = u32(eocd + 16)
        guard cd + 46 <= b.count, u32(cd) == 0x02014b50 else { throw ZipError.corrupt }
        let method = u16(cd + 10), packed = u32(cd + 20), size = u32(cd + 24), local = u32(cd + 42)
        guard size <= maxSize, local + 30 <= b.count, u32(local) == 0x04034b50 else { throw ZipError.corrupt }
        let start = local + 30 + u16(local + 26) + u16(local + 28)
        guard start + packed <= b.count else { throw ZipError.corrupt }
        let body = Data(b[start..<(start + packed)])
        switch method {
        case 0: return body
        case 8:
            guard size > 0 else { return Data() }
            var out = Data(count: size)
            let written = out.withUnsafeMutableBytes { dst in
                body.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                              src.bindMemory(to: UInt8.self).baseAddress!, packed, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == size else { throw ZipError.corrupt }
            return out
        default: throw ZipError.unsupported
        }
    }
}

// MARK: - Fama-French factors (Kenneth R. French Data Library)

public enum FactorSet: String, CaseIterable, Sendable {
    case threeFactor = "FF3", fiveFactor = "FF5", momentum = "MOM"

    public var url: URL {
        let file = switch self {
        case .threeFactor: "F-F_Research_Data_Factors_daily_CSV.zip"
        case .fiveFactor: "F-F_Research_Data_5_Factors_2x3_daily_CSV.zip"
        case .momentum: "F-F_Momentum_Factor_daily_CSV.zip"
        }
        return URL(string: "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/\(file)")!
    }
}

/// Daily factor returns as fractions (the files publish percent), keyed by yyyymmdd.
public struct FactorTable: Sendable, Equatable {
    public var names: [String]
    public var rows: [Int: [Double]]
    public var lastDate: Int { rows.keys.max() ?? 0 }

    public func column(_ name: String) -> Int? { names.firstIndex(of: name) }

    /// Parses the first daily block: a header line starting with "," then `yyyymmdd, v1, v2 …`.
    public static func parse(_ csv: String) -> FactorTable {
        var names: [String] = []
        var rows: [Int: [Double]] = [:]
        var inBlock = false
        for raw in csv.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if line.hasPrefix(",") {
                    names = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    inBlock = !names.isEmpty
                }
                continue
            }
            let cells = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let d = cells.first.flatMap({ Int($0) }), d > 19000000 else {
                if !rows.isEmpty { break } else { continue }
            }
            let values = cells.dropFirst().compactMap(Double.init)
            guard values.count == names.count else { continue }
            rows[d] = values.map { $0 / 100 }
        }
        return FactorTable(names: names, rows: rows)
    }

    /// Joins tables on date (e.g. FF3 + momentum); a date missing from either is dropped.
    public func merged(with other: FactorTable) -> FactorTable {
        let extra = other.names.enumerated().filter { !names.contains($0.element) }
        var out: [Int: [Double]] = [:]
        for (d, v) in rows { if let o = other.rows[d] { out[d] = v + extra.map { o[$0.offset] } } }
        return FactorTable(names: names + extra.map(\.element), rows: out)
    }
}

public enum FactorModel: String, CaseIterable, Sendable {
    case capm = "CAPM", ff3 = "FF3", carhart = "CARHART 4", ff5 = "FF5"
    public var factors: [String] {
        switch self {
        case .capm: ["Mkt-RF"]
        case .ff3: ["Mkt-RF", "SMB", "HML"]
        case .carhart: ["Mkt-RF", "SMB", "HML", "Mom"]
        case .ff5: ["Mkt-RF", "SMB", "HML", "RMW", "CMA"]
        }
    }
    public var sets: [FactorSet] {
        switch self {
        case .capm, .ff3: [.threeFactor]
        case .carhart: [.threeFactor, .momentum]
        case .ff5: [.fiveFactor]
        }
    }
    public static func describe(_ factor: String) -> String {
        switch factor {
        case "Mkt-RF": "Market excess return"
        case "SMB": "Size: small minus big"
        case "HML": "Value: high minus low book-to-market"
        case "RMW": "Profitability: robust minus weak"
        case "CMA": "Investment: conservative minus aggressive"
        case "Mom": "Momentum: winners minus losers"
        default: factor
        }
    }
}

/// UTC calendar date as yyyymmdd (the factor files' key).
public func yyyymmdd(_ d: Date) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day], from: d)
    return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
}

// MARK: - Multiple regression

public struct LinearFit: Sendable, Equatable {
    public struct Term: Sendable, Equatable {
        public var name: String
        public var coefficient: Double
        public var standardError: Double
        public var t: Double { standardError > 0 ? coefficient / standardError : .nan }
    }
    /// Intercept first, then one term per regressor.
    public var terms: [Term]
    public var r2: Double
    public var adjustedR2: Double
    public var residualSD: Double
    public var n: Int

    /// OLS with intercept: y = a + Σ bᵢ·xᵢ + e. `columns` are the regressors, each of length n.
    public static func ols(y: [Double], columns: [[Double]], names: [String]) -> LinearFit? {
        let n = y.count, k = columns.count + 1
        guard n > k + 1, columns.allSatisfy({ $0.count == n }), names.count == columns.count else { return nil }
        // X'X and X'y with an intercept column of ones.
        func x(_ row: Int, _ j: Int) -> Double { j == 0 ? 1 : columns[j - 1][row] }
        var xtx = Array(repeating: Array(repeating: 0.0, count: k), count: k)
        var xty = Array(repeating: 0.0, count: k)
        for r in 0..<n {
            for i in 0..<k {
                let xi = x(r, i)
                xty[i] += xi * y[r]
                for j in i..<k { xtx[i][j] += xi * x(r, j) }
            }
        }
        for i in 0..<k { for j in 0..<i { xtx[i][j] = xtx[j][i] } }
        guard let inv = invert(xtx) else { return nil }
        let beta = (0..<k).map { i in (0..<k).reduce(0) { $0 + inv[i][$1] * xty[$1] } }
        let mean = y.reduce(0, +) / Double(n)
        var sse = 0.0, sst = 0.0
        for r in 0..<n {
            let fit = (0..<k).reduce(0) { $0 + beta[$1] * x(r, $1) }
            sse += (y[r] - fit) * (y[r] - fit)
            sst += (y[r] - mean) * (y[r] - mean)
        }
        let s2 = sse / Double(n - k)
        let r2 = sst > 0 ? max(0, 1 - sse / sst) : 0
        let terms = (0..<k).map { i in
            Term(name: i == 0 ? "Alpha" : names[i - 1], coefficient: beta[i], standardError: (max(inv[i][i], 0) * s2).squareRoot())
        }
        return LinearFit(terms: terms, r2: r2, adjustedR2: 1 - (1 - r2) * Double(n - 1) / Double(n - k),
                         residualSD: s2.squareRoot(), n: n)
    }

    /// Gauss-Jordan inverse with partial pivoting; nil when singular (collinear regressors).
    static func invert(_ m: [[Double]]) -> [[Double]]? {
        let n = m.count
        var a = m.enumerated().map { i, row in row + (0..<n).map { $0 == i ? 1.0 : 0.0 } }
        for c in 0..<n {
            guard let p = (c..<n).max(by: { abs(a[$0][c]) < abs(a[$1][c]) }), abs(a[p][c]) > 1e-14 else { return nil }
            a.swapAt(c, p)
            let d = a[c][c]
            for j in 0..<(2 * n) { a[c][j] /= d }
            for r in 0..<n where r != c {
                let f = a[r][c]
                if f != 0 { for j in 0..<(2 * n) { a[r][j] -= f * a[c][j] } }
            }
        }
        return a.map { Array($0[n...]) }
    }
}

// MARK: - Dividends (DVD)

public struct DividendSummary: Sendable, Equatable {
    public var trailing12M: Double
    public var yield: Double?            // trailing 12 months / price
    public var paymentsPerYear: Int
    public var annual: [(year: Int, total: Double)]
    public var growth5Y: Double?         // CAGR of the last 5 complete calendar years

    public static func == (a: Self, b: Self) -> Bool {
        a.trailing12M == b.trailing12M && a.yield == b.yield && a.paymentsPerYear == b.paymentsPerYear
            && a.annual.map(\.year) == b.annual.map(\.year) && a.annual.map(\.total) == b.annual.map(\.total) && a.growth5Y == b.growth5Y
    }

    public static func of(_ divs: [Dividend], price: Double?, now: Date = .now) -> DividendSummary? {
        guard !divs.isEmpty else { return nil }
        let cutoff = now.addingTimeInterval(-365 * 86_400)
        let ttm = divs.filter { $0.date > cutoff && $0.date <= now }.map(\.amount).reduce(0, +)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let thisYear = cal.component(.year, from: now)
        let byYear = Dictionary(grouping: divs) { cal.component(.year, from: $0.date) }
        let annual = byYear.map { (year: $0.key, total: $0.value.map(\.amount).reduce(0, +)) }.sorted { $0.year < $1.year }
        let complete = annual.filter { $0.year < thisYear }
        // Payments per year: the most common count among recent complete years.
        let counts = complete.suffix(3).map { byYear[$0.year]?.count ?? 0 }
        let freq = counts.max { a, b in counts.filter { $0 == a }.count < counts.filter { $0 == b }.count } ?? 0
        var growth: Double?
        if complete.count >= 6, let last = complete.last, last.total > 0 {
            let first = complete[complete.count - 6]
            if first.total > 0 { growth = pow(last.total / first.total, 1.0 / 5) - 1 }
        }
        return DividendSummary(trailing12M: ttm, yield: price.flatMap { $0 > 0 ? ttm / $0 : nil },
                               paymentsPerYear: freq, annual: annual, growth5Y: growth)
    }
}
