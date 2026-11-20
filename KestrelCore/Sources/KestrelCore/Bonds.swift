import Foundation

/// GC and YAS: U.S. Treasury par yield curves and fixed-coupon bond math. Mirrors web/src/core/bonds.ts.
public enum Treasury {
    public struct Tenor: Sendable, Hashable { public let label: String; public let header: String; public let years: Double }

    /// Tenors shown in GC, as Treasury labels them in the CSV header.
    public static let tenors: [Tenor] = [
        .init(label: "1M", header: "1 Mo", years: 1.0 / 12), .init(label: "2M", header: "2 Mo", years: 2.0 / 12), .init(label: "3M", header: "3 Mo", years: 0.25),
        .init(label: "4M", header: "4 Mo", years: 4.0 / 12), .init(label: "6M", header: "6 Mo", years: 0.5), .init(label: "1Y", header: "1 Yr", years: 1),
        .init(label: "2Y", header: "2 Yr", years: 2), .init(label: "3Y", header: "3 Yr", years: 3), .init(label: "5Y", header: "5 Yr", years: 5),
        .init(label: "7Y", header: "7 Yr", years: 7), .init(label: "10Y", header: "10 Yr", years: 10), .init(label: "20Y", header: "20 Yr", years: 20),
        .init(label: "30Y", header: "30 Yr", years: 30),
    ]

    /// One day's par yields in percent by tenor label; a tenor not published that day is missing.
    public struct CurveDay: Sendable, Equatable { public var date: Date; public var yields: [String: Double] }

    /// Treasury's daily par yield curve CSV for one calendar year.
    public static func url(year: Int) -> URL {
        URL(string: "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/\(year)/all?type=daily_treasury_yield_curve&field_tdr_date_value=\(year)&page&_format=csv")!
    }

    /// Rows of one yearly CSV, oldest day first.
    public static func parse(_ text: String) -> [CurveDay] {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let head = lines[0].split(separator: ",", omittingEmptySubsequences: false).map { $0.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces) }
        let cols = tenors.compactMap { t in head.firstIndex(of: t.header).flatMap { $0 > 0 ? (t.label, $0) : nil } }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        var out: [CurveDay] = []
        for line in lines.dropFirst() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let m = f.first?.wholeMatch(of: /(\d{2})\/(\d{2})\/(\d{4})/), let mo = Int(m.1), let d = Int(m.2), let y = Int(m.3),
                  let date = utc.date(from: DateComponents(year: y, month: mo, day: d)) else { continue }
            var yields: [String: Double] = [:]
            for (label, at) in cols where at < f.count { if let v = Double(f[at]), v.isFinite { yields[label] = v } }
            if !yields.isEmpty { out.append(CurveDay(date: date, yields: yields)) }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// The last curve published on or before `date` (days sorted oldest first).
    public static func curve(on date: Date, in days: [CurveDay]) -> CurveDay? {
        var lo = 0, hi = days.count - 1
        var best: CurveDay?
        while lo <= hi {
            let m = (lo + hi) / 2
            if days[m].date <= date { best = days[m]; lo = m + 1 } else { hi = m - 1 }
        }
        return best
    }

    /// Par yield at any maturity, straight-line between published tenors and flat beyond the ends.
    public static func interpolate(_ day: CurveDay, years: Double) -> Double? {
        let pts = tenors.compactMap { t in day.yields[t.label].map { (t.years, $0) } }
        guard let first = pts.first, let last = pts.last else { return nil }
        if years <= first.0 { return first.1 }
        for k in 1..<pts.count where years <= pts[k].0 {
            let (x0, y0) = pts[k - 1], (x1, y1) = pts[k]
            return y0 + (y1 - y0) * (years - x0) / (x1 - x0)
        }
        return last.1
    }
}

public enum Bond {
    /// Where settlement sits in the coupon schedule: `n` coupons left, the next one `w` of a period away
    /// (actual/actual: days to the next coupon over days in the period).
    public struct Schedule: Sendable, Equatable { public var n: Int; public var w: Double; public var years: Double
        public init(n: Int, w: Double, years: Double = 0) { self.n = n; self.w = w; self.years = years }
    }

    public struct Risk: Sendable, Equatable { public var clean, dirty, accrued, macaulay, modified, convexity, dv01: Double }

    private static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    /// Coupon dates step back from maturity (clamped to shorter months), as on a real bond. Dates are UTC midnights.
    public static func schedule(settle: Date, maturity: Date, freq: Int = 2) -> Schedule? {
        guard maturity > settle else { return nil }
        let cal = utc, step = 12 / freq
        var next = maturity, n = 1
        while n <= 1200 {
            guard let prev = cal.date(byAdding: .month, value: -step * n, to: maturity) else { return nil }
            if prev <= settle {
                return Schedule(n: n, w: next.timeIntervalSince(settle) / next.timeIntervalSince(prev), years: maturity.timeIntervalSince(settle) / (365.25 * 86_400))
            }
            next = prev; n += 1
        }
        return nil
    }

    /// Price and risk per 100 face at a yield (decimal), compounding at the coupon frequency.
    public static func risk(coupon: Double, _ s: Schedule, yield y: Double, freq: Int = 2) -> Risk {
        let f = Double(freq), cpn = 100 * coupon / f, d = 1 + y / f
        var dirty = 0.0, dur = 0.0, cvx = 0.0
        for k in 0..<s.n {
            let p = Double(k) + s.w, t = p / f, cf = cpn + (k == s.n - 1 ? 100 : 0), pv = cf / pow(d, p)
            dirty += pv; dur += t * pv; cvx += t * (t + 1 / f) * pv
        }
        let accrued = cpn * (1 - s.w), mac = dur / dirty, mod = mac / d
        return Risk(clean: dirty - accrued, dirty: dirty, accrued: accrued, macaulay: mac, modified: mod, convexity: cvx / (dirty * d * d), dv01: mod * dirty / 10_000)
    }

    /// Yield to maturity for a clean price, by bisection (prices fall as yields rise).
    public static func yield(coupon: Double, _ s: Schedule, clean: Double, freq: Int = 2) -> Double? {
        guard clean > 0, s.n > 0 else { return nil }
        var lo = -0.05, hi = 1.0
        guard risk(coupon: coupon, s, yield: lo, freq: freq).clean >= clean, risk(coupon: coupon, s, yield: hi, freq: freq).clean <= clean else { return nil }
        for _ in 0..<200 where hi - lo > 1e-12 {
            let mid = (lo + hi) / 2
            if risk(coupon: coupon, s, yield: mid, freq: freq).clean > clean { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}
