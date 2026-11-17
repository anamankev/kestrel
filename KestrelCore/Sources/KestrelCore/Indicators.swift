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
}
