import Foundation

/// Market-model event study (MacKinlay 1997): for each event, fit rᵢ = α + β·rₘ over an estimation
/// window that ends before the event, then measure abnormal returns AR = rᵢ − (α + β·rₘ) around it.
public struct EventStudy: Sendable, Equatable {
    public struct Event: Sendable, Equatable {
        /// Trading day treated as day 0 (the first session on or after the event date).
        public var day0: Date
        /// Abnormal returns for each day of the window, in order.
        public var abnormal: [Double]
        public var alpha: Double
        public var beta: Double
        public var estimationDays: Int
    }

    public var window: ClosedRange<Int>
    public var events: [Event]
    /// Average abnormal return per window day, and its cumulative sum (CAAR).
    public var aar: [Double]
    public var caar: [Double]
    /// Cross-sectional standard error of the cumulative abnormal return up to each day.
    public var caarSE: [Double]

    public var days: [Int] { Array(window) }

    /// Cumulative abnormal return of one event over [from, to] (window-relative days).
    public func car(_ e: Event, from: Int, to: Int) -> Double {
        let lo = max(from, window.lowerBound) - window.lowerBound, hi = min(to, window.upperBound) - window.lowerBound
        return lo <= hi ? e.abnormal[lo...hi].reduce(0, +) : 0
    }

    /// Mean CAR across events with a cross-sectional t-statistic.
    public func summary(from: Int, to: Int) -> (mean: Double, t: Double?, positive: Double) {
        let cars = events.map { car($0, from: from, to: to) }
        let n = Double(cars.count)
        let mean = cars.reduce(0, +) / max(n, 1)
        var t: Double?
        if cars.count >= 2 {
            let sd = (cars.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1)).squareRoot()
            if sd > 0 { t = mean / (sd / n.squareRoot()) }
        }
        return (mean, t, Double(cars.filter { $0 > 0 }.count) / max(n, 1))
    }

    /// - Parameters:
    ///   - asset, market: daily bars (total return), any order; aligned on shared UTC dates.
    ///   - estimation: days in the estimation window, which ends `gap` days before the window opens
    ///     and skips any day inside another event's window.
    ///   - minimumEstimation: events with fewer usable estimation days are skipped.
    public static func run(asset: [Candle], market: [Candle], events dates: [Date], window: ClosedRange<Int> = -5...5,
                           estimation: Int = 250, gap: Int = 10, minimumEstimation: Int = 120) -> EventStudy? {
        let aligned = Risk.alignedCloses(["a": asset, "m": market])
        guard let ca = aligned.closes["a"], let cm = aligned.closes["m"], ca.count > 2 else { return nil }
        // Return t is from close t-1 to close t, dated at day t.
        let ra = Risk.returns(ca), rm = Risk.returns(cm)
        let rdates = Array(aligned.dates.dropFirst())
        guard ra.count == rdates.count, rm.count == rdates.count else { return nil }

        // Day-0 index of each event (first session on or after its date), de-duplicated.
        var zero: [Int] = []
        for date in dates.sorted() {
            let key = yyyymmdd(date)
            if let k = rdates.firstIndex(where: { yyyymmdd($0) >= key }), !zero.contains(k) { zero.append(k) }
        }
        // Other events' windows are left out of each estimation window, so an earlier earnings
        // jump doesn't distort alpha and beta.
        var contaminated = Set<Int>()
        for k in zero { for d in window { contaminated.insert(k + d) } }

        var events: [Event] = []
        for k in zero {
            let first = k + window.lowerBound, last = k + window.upperBound
            guard first >= 0, last < ra.count else { continue }
            let estEnd = first - gap
            var idx: [Int] = []
            var i = estEnd - 1
            while i >= 0, idx.count < estimation {
                if !contaminated.contains(i) { idx.append(i) }
                i -= 1
            }
            guard idx.count >= minimumEstimation,
                  let fit = Regression.ols(y: idx.map { ra[$0] }, x: idx.map { rm[$0] }) else { continue }
            let ar = (first...last).map { ra[$0] - (fit.alpha + fit.beta * rm[$0]) }
            events.append(Event(day0: rdates[k], abnormal: ar, alpha: fit.alpha, beta: fit.beta, estimationDays: idx.count))
        }
        guard !events.isEmpty else { return nil }

        let width = window.count, n = Double(events.count)
        let aar = (0..<width).map { d in events.map { $0.abnormal[d] }.reduce(0, +) / n }
        var caar: [Double] = [], se: [Double] = [], running = 0.0
        for d in 0..<width {
            running += aar[d]
            caar.append(running)
            let cars = events.map { $0.abnormal[0...d].reduce(0, +) }
            let sd = events.count >= 2 ? (cars.map { ($0 - running) * ($0 - running) }.reduce(0, +) / (n - 1)).squareRoot() : 0
            se.append(sd / n.squareRoot())
        }
        return EventStudy(window: window, events: events, aar: aar, caar: caar, caarSE: se)
    }
}
