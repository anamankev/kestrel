import Foundation

/// Technical studies. Outputs align index-for-index with the input; warm-up slots are nil.
public enum Indicators {
    public static func sma(_ x: [Double], period n: Int) -> [Double?] {
        guard n > 0 else { return x.map { _ in nil } }
        var out = [Double?](repeating: nil, count: x.count)
        var sum = 0.0
        for i in x.indices {
            sum += x[i]
            if i >= n { sum -= x[i - n] }
            if i >= n - 1 { out[i] = sum / Double(n) }
        }
        return out
    }

    public static func ema(_ x: [Double], period n: Int) -> [Double?] {
        guard n > 0, x.count >= n else { return x.map { _ in nil } }
        var out = [Double?](repeating: nil, count: x.count)
        let k = 2.0 / Double(n + 1)
        var prev = x[0..<n].reduce(0, +) / Double(n)
        out[n - 1] = prev
        for i in n..<x.count {
            prev = x[i] * k + prev * (1 - k)
            out[i] = prev
        }
        return out
    }

    public struct Band: Sendable, Equatable { public var mid, upper, lower: Double }

    /// Bollinger bands (population standard deviation, as conventionally computed).
    public static func bollinger(_ x: [Double], period n: Int = 20, k: Double = 2) -> [Band?] {
        let mid = sma(x, period: n)
        return x.indices.map { i in
            guard let m = mid[i] else { return nil }
            let window = x[(i - n + 1)...i]
            let sd = (window.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n)).squareRoot()
            return Band(mid: m, upper: m + k * sd, lower: m - k * sd)
        }
    }

    /// Wilder's RSI.
    public static func rsi(_ x: [Double], period n: Int = 14) -> [Double?] {
        guard x.count > n else { return x.map { _ in nil } }
        var out = [Double?](repeating: nil, count: x.count)
        var gain = 0.0, loss = 0.0
        for i in 1...n {
            let d = x[i] - x[i - 1]
            if d > 0 { gain += d } else { loss -= d }
        }
        gain /= Double(n); loss /= Double(n)
        func value() -> Double { loss == 0 ? 100 : 100 - 100 / (1 + gain / loss) }
        out[n] = value()
        for i in (n + 1)..<x.count {
            let d = x[i] - x[i - 1]
            gain = (gain * Double(n - 1) + max(d, 0)) / Double(n)
            loss = (loss * Double(n - 1) + max(-d, 0)) / Double(n)
            out[i] = value()
        }
        return out
    }

    /// Session VWAP over candles using typical price.
    public static func vwap(_ c: [Candle]) -> [Double?] {
        var pv = 0.0, vol = 0.0
        return c.map { k in
            pv += (k.high + k.low + k.close) / 3 * k.volume
            vol += k.volume
            return vol > 0 ? pv / vol : nil
        }
    }

    /// Rebases a main series and a comparison to % change from the first bar, aligning the
    /// comparison by timestamp (its last close at or before each main bar). Returns the main
    /// candles in % and the comparison values (nil before the comparison has data).
    public static func rebase(_ main: [Candle], against other: [Candle]) -> (main: [Candle], other: [Double?]) {
        guard let base = main.first?.close, base > 0 else { return (main, []) }
        func pct(_ v: Double) -> Double { (v / base - 1) * 100 }
        let m = main.map { Candle(time: $0.time, open: pct($0.open), high: pct($0.high), low: pct($0.low), close: pct($0.close), volume: $0.volume) }
        let sorted = other.sorted { $0.time < $1.time }
        func closeAt(_ t: Date) -> Double? {
            var lo = 0, hi = sorted.count - 1, best: Int?
            while lo <= hi { let mid = (lo + hi) / 2; if sorted[mid].time <= t { best = mid; lo = mid + 1 } else { hi = mid - 1 } }
            return best.map { sorted[$0].close }
        }
        let raw = main.map { closeAt($0.time) }
        guard let cBase = raw.compactMap({ $0 }).first, cBase > 0 else { return (m, []) }
        return (m, raw.map { $0.map { ($0 / cBase - 1) * 100 } })
    }
}
