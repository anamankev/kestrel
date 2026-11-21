import Foundation

/// DCF: a two-stage discounted free-cash-flow valuation from SEC annual data. Mirrors web/src/core/dcf.ts.
/// Stage 1 (years 1–5) grows at `growth`; stage 2 (years 6–10) fades linearly to `terminalGrowth`;
/// the terminal value is a Gordon growth perpetuity on year 10.
public enum DCF {
    public static let years = 10, high = 5
    public static let equityRiskPremium = 0.055, beta = 1.0, terminal = 0.025

    public struct Inputs: Sendable, Equatable {
        public var baseFCF, growth, terminalGrowth, discount: Double
        public init(baseFCF: Double, growth: Double, terminalGrowth: Double, discount: Double) {
            self.baseFCF = baseFCF; self.growth = growth; self.terminalGrowth = terminalGrowth; self.discount = discount
        }
    }
    public struct Year: Sendable, Equatable, Identifiable { public var year: Int; public var growth, fcf, factor, pv: Double; public var id: Int { year } }
    public struct Result: Sendable, Equatable {
        public var flows: [Year]
        public var pvFlows, terminalValue, pvTerminal, enterprise, equity, terminalShare: Double
        public var perShare: Double?
    }

    /// Growth for each projected year: `growth` for years 1–5, then a straight line to `terminalGrowth` by year 10.
    public static func growthPath(_ growth: Double, _ terminalGrowth: Double) -> [Double] {
        (0..<years).map { k in k < high ? growth : growth + (terminalGrowth - growth) * Double(k + 1 - high) / Double(years - high) }
    }

    /// The valuation, or an explanation when the inputs can't produce one. `netCash` = cash − long-term debt.
    public static func value(_ i: Inputs, netCash: Double, shares: Double?) -> Result? {
        problem(i, netCash: netCash) == nil ? compute(i, netCash: netCash, shares: shares) : nil
    }

    public static func problem(_ i: Inputs, netCash: Double) -> String? {
        if ![i.baseFCF, i.growth, i.terminalGrowth, i.discount, netCash].allSatisfy(\.isFinite) { return "Enter numbers in every field." }
        if i.baseFCF <= 0 { return "A DCF needs positive free cash flow to start from. Enter the base you expect." }
        if i.discount <= i.terminalGrowth + 0.005 { return "The discount rate must exceed terminal growth by at least 0.5 points, or the terminal value is infinite." }
        if i.discount > 0.5 || i.growth < -0.5 || i.growth > 1 || i.terminalGrowth < -0.05 || i.terminalGrowth > 0.06 { return "Inputs are outside sensible ranges." }
        return nil
    }

    private static func compute(_ i: Inputs, netCash: Double, shares: Double?) -> Result {
        var fcf = i.baseFCF, pvFlows = 0.0
        let flows = growthPath(i.growth, i.terminalGrowth).enumerated().map { k, g -> Year in
            fcf *= 1 + g
            let factor = 1 / pow(1 + i.discount, Double(k + 1)), pv = fcf * factor
            pvFlows += pv
            return Year(year: k + 1, growth: g, fcf: fcf, factor: factor, pv: pv)
        }
        let tv = fcf * (1 + i.terminalGrowth) / (i.discount - i.terminalGrowth)
        let pvTV = tv * flows[years - 1].factor
        let ev = pvFlows + pvTV, equity = ev + netCash
        return Result(flows: flows, pvFlows: pvFlows, terminalValue: tv, pvTerminal: pvTV, enterprise: ev, equity: equity,
                      terminalShare: pvTV / ev, perShare: (shares ?? 0) > 0 ? equity / shares! : nil)
    }

    /// Compound annual revenue growth across the years given (oldest first).
    public static func revenueCAGR(_ ys: [FiscalYear]) -> Double? {
        let r = ys.filter { ($0.revenue ?? 0) > 0 }
        guard let a = r.first, let b = r.last, b.year > a.year else { return nil }
        return pow(b.revenue! / a.revenue!, 1 / Double(b.year - a.year)) - 1
    }

    /// Starting inputs: last year's free cash flow; growth = revenue CAGR clamped to −5%…20% (0.5-point steps);
    /// discount = CAPM with the 10-year Treasury, beta 1 and a 5.5% equity risk premium; terminal growth 2.5%.
    public static func defaults(_ ys: [FiscalYear], tenYear: Double?) -> (inputs: Inputs, baseKnown: Bool) {
        let base = ys.last?.freeCashFlow
        let g = revenueCAGR(Array(ys.suffix(5))) ?? 0.05
        let rf = tenYear.flatMap { $0.isFinite && $0 > 0 && $0 < 0.2 ? $0 : nil } ?? 0.045
        func round(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }
        let known = (base ?? 0) > 0
        return (Inputs(baseFCF: known ? base! : 0, growth: round(min(0.2, max(-0.05, g)), 0.005),
                       terminalGrowth: terminal, discount: round(rf + beta * equityRiskPremium, 0.0025)), known)
    }

    /// Value per share across discount rates (rows) and terminal growth rates (columns).
    public static func sensitivity(_ i: Inputs, netCash: Double, shares: Double, discounts: [Double], terminals: [Double]) -> [[Double?]] {
        discounts.map { d in terminals.map { t in
            var x = i; x.discount = d; x.terminalGrowth = t
            return value(x, netCash: netCash, shares: shares)?.perShare
        } }
    }
}
