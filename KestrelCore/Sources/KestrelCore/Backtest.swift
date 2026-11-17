import Foundation

/// Long/flat strategy backtests on daily bars. Signals are read at the close and traded at the
/// next bar's open, so a rule never trades on a price it could not have seen.
public enum Strategy: Hashable, Sendable {
    case smaCross(fast: Int, slow: Int)
    case rsi(period: Int, buyBelow: Double, sellAbove: Double)
    case bollinger(period: Int, k: Double)
    case buyAndHold

    public var label: String {
        switch self {
        case .smaCross(let f, let s): "SMA \(f)/\(s) cross"
        case .rsi(let p, let lo, let hi): "RSI(\(p)) buy < \(Int(lo)), sell > \(Int(hi))"
        case .bollinger(let p, let k): "Bollinger(\(p), \(k.formatted())) mean reversion"
        case .buyAndHold: "Buy and hold"
        }
    }

    /// Desired position (true = long) after each close; nil until the indicators warm up.
    func targets(_ closes: [Double]) -> [Bool?] {
        switch self {
        case .buyAndHold:
            return closes.map { _ in true }
        case .smaCross(let f, let s):
            let a = Indicators.sma(closes, period: f), b = Indicators.sma(closes, period: s)
            return closes.indices.map { i in a[i].flatMap { x in b[i].map { x > $0 } } }
        case .rsi(let p, let lo, let hi):
            // Enter when oversold, exit when overbought, otherwise keep the current state.
            let r = Indicators.rsi(closes, period: p)
            var state = false
            return r.map { v in
                guard let v else { return nil }
                if v < lo { state = true } else if v > hi { state = false }
                return state
            }
        case .bollinger(let p, let k):
            // Buy a close below the lower band, sell once price recovers to the middle.
            let bands = Indicators.bollinger(closes, period: p, k: k)
            var state = false
            return closes.indices.map { i in
                guard let b = bands[i] else { return nil }
                if closes[i] < b.lower { state = true } else if closes[i] >= b.mid { state = false }
                return state
            }
        }
    }
}

public struct BacktestTrade: Sendable, Equatable, Identifiable {
    public var id: Date { entry }
    public let entry: Date
    public let exit: Date?
    public let entryPrice: Double
    public let exitPrice: Double
    /// Net of costs on both sides.
    public let returnPct: Double
}

public struct BacktestResult: Sendable, Equatable {
    public let dates: [Date]
    /// Strategy and buy-and-hold equity, both starting at 1.
    public let equity: [Double]
    public let benchmark: [Double]
    public let trades: [BacktestTrade]
    public let totalReturn: Double
    public let benchmarkReturn: Double
    public let cagr: Double?
    public let sharpe: Double?
    public let maxDrawdown: Double
    public let exposure: Double
    public var winRate: Double? {
        let closed = trades.filter { $0.exit != nil }
        return closed.isEmpty ? nil : Double(closed.filter { $0.returnPct > 0 }.count) / Double(closed.count)
    }
}

public enum Backtest {
    /// - Parameters:
    ///   - costBps: commission plus slippage charged on each side of a trade.
    ///   - periodsPerYear: 252 for equities, 365 for crypto.
    public static func run(_ bars: [Candle], strategy: Strategy, costBps: Double = 5, periodsPerYear: Double = 252) -> BacktestResult? {
        guard bars.count >= 3 else { return nil }
        let closes = bars.map(\.close)
        let target = strategy.targets(closes)
        let cost = costBps / 10_000
        var equity = [1.0], bench = [1.0], dayReturns: [Double] = []
        var held = false, daysIn = 0
        var trades: [BacktestTrade] = []
        var open: (date: Date, price: Double, equity: Double)?

        for t in 1..<bars.count {
            let want = target[t - 1] ?? held   // decided at yesterday's close
            let prevClose = closes[t - 1], o = bars[t].open > 0 ? bars[t].open : prevClose, c = closes[t]
            var r = 0.0
            switch (held, want) {
            case (false, true):                 // buy at today's open
                r = (c / o - 1) - cost
                open = (bars[t].time, o, equity.last!)
            case (true, false):                 // carry overnight, sell at today's open
                r = (o / prevClose - 1) - cost
            case (true, true):
                r = c / prevClose - 1
            case (false, false):
                r = 0
            }
            if held && !want, let e = open {
                let after = equity.last! * (1 + r)
                trades.append(BacktestTrade(entry: e.date, exit: bars[t].time, entryPrice: e.price, exitPrice: o, returnPct: after / e.equity - 1))
                open = nil
            }
            held = want
            if held { daysIn += 1 }
            equity.append(equity.last! * (1 + r))
            bench.append(c / closes[0])
            dayReturns.append(r)
        }
        if let e = open {   // still open at the end: mark to the last close
            trades.append(BacktestTrade(entry: e.date, exit: nil, entryPrice: e.price, exitPrice: closes.last!, returnPct: equity.last! / e.equity - 1))
        }

        let years = (bars.last!.time.timeIntervalSince(bars.first!.time)) / (365.25 * 86_400)
        let total = equity.last! - 1
        let mean = dayReturns.reduce(0, +) / Double(dayReturns.count)
        let sd = (dayReturns.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(dayReturns.count - 1, 1))).squareRoot()
        var peak = 1.0, mdd = 0.0
        for v in equity { peak = max(peak, v); mdd = max(mdd, 1 - v / peak) }
        return BacktestResult(
            dates: bars.map(\.time), equity: equity, benchmark: bench, trades: trades,
            totalReturn: total, benchmarkReturn: closes.last! / closes[0] - 1,
            cagr: years >= 0.25 ? pow(equity.last!, 1 / years) - 1 : nil,
            sharpe: sd > 0 ? mean / sd * periodsPerYear.squareRoot() : nil,
            maxDrawdown: mdd, exposure: Double(daysIn) / Double(bars.count - 1))
    }
}
