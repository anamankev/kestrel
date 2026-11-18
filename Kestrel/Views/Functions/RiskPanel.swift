import SwiftUI
import KestrelCore

/// Portfolio risk for PORT: exposures, beta to the S&P 500, one-day historical VaR and expected
/// shortfall from a year of daily returns, and the account's equity curve.
struct RiskPanel: View {
    @Environment(PaperBroker.self) private var broker
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    struct Result: Equatable { var beta: Double?; var var95: Double?; var es95: Double?; var days: Int }
    @State private var result: Result?
    @State private var loading = false

    private static let benchmark = "^GSPC"

    private var exposures: [(Instrument, Double)] {
        broker.account.openPositions.compactMap { p in
            guard let i = Universe.instrument(symbol: p.symbol) ?? Universe.resolve(p.symbol) else { return nil }
            let mark = market.quotes[p.symbol]?.last ?? broker.marks[p.symbol]?.double ?? p.averageCost.double
            return (i, p.quantity.double * mark)
        }
    }

    /// Net delta per crypto underlying, in coins: spot positions plus Σ contracts × Black-76 delta.
    private var deltas: [(String, Double)] {
        var d: [String: Double] = [:]
        for p in broker.account.openPositions {
            if let o = Deribit.parse(p.symbol) {
                guard let g = market.optionContracts[p.symbol]?.greeks() else { continue }
                d[o.underlying, default: 0] += p.quantity.double * g.delta
            } else if Deribit.currencies.contains(String(p.symbol.prefix { $0 != "-" })), p.symbol.hasSuffix("-USD") {
                d[String(p.symbol.prefix { $0 != "-" }), default: 0] += p.quantity.double
            }
        }
        return d.sorted { $0.key < $1.key }
    }

    /// Recompute risk when holdings change (not on every tick).
    private var holdingsKey: String {
        broker.account.openPositions.map { "\($0.symbol):\($0.quantity)" }.joined(separator: ",")
    }

    var body: some View {
        let ex = exposures
        let equity = max(broker.equity.double, 1)
        let long = ex.map(\.1).filter { $0 > 0 }.reduce(0, +)
        let short = ex.map(\.1).filter { $0 < 0 }.reduce(0, +)
        VStack(alignment: .leading, spacing: 8) {
            if !ex.isEmpty {
                SectionBar(title: "RISK", trailing: result.map { "\($0.days) DAYS · HISTORICAL" } ?? (loading ? "COMPUTING…" : nil))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 4)], spacing: 4) {
                    tile("GROSS EXPOSURE", "$" + Fmt.compact(long - short), String(format: "%.0f%% of equity", (long - short) / equity * 100))
                    tile("NET EXPOSURE", (long + short < 0 ? "-$" : "$") + Fmt.compact(abs(long + short)), String(format: "%.0f%% of equity", (long + short) / equity * 100))
                    tile("LONG / SHORT", "$" + Fmt.compact(long) + " / $" + Fmt.compact(abs(short)), "\(ex.filter { $0.1 < 0 }.count) short")
                    tile("BETA (S&P 500)", result?.beta.map { String(format: "%.2f", $0) } ?? "—", "equity-weighted")
                    tile("1-DAY VaR 95%", result?.var95.map { "-$" + Fmt.compact($0) } ?? "—", "historical simulation", Theme.warn)
                    tile("EXP. SHORTFALL 95%", result?.es95.map { "-$" + Fmt.compact($0) } ?? "—", "avg loss beyond VaR", theme.down)
                    if !deltas.isEmpty {
                        tile("NET DELTA", deltas.map { "\($0.0) \(String(format: "%+.3f", $0.1))" }.joined(separator: "\n"), "spot + options, in coins", Theme.accent)
                    }
                }
                .padding(.horizontal, 8)
                classBars(ex, gross: long - short)
            }
            if broker.curve.count > 1 {
                SectionBar(title: "EQUITY CURVE", trailing: "\(broker.curve.count) SNAPSHOTS")
                EquityCurve(points: broker.curve.map(\.v), start: PaperAccount.startingCash.double)
                    .frame(height: 90.pt).padding(.horizontal, 8)
            }
        }
        .task(id: holdingsKey) { await compute() }
    }

    private func compute() async {
        let ex = exposures
        guard !ex.isEmpty, let spx = Universe.instrument(symbol: Self.benchmark) else { result = nil; return }
        loading = true
        defer { loading = false }
        var histories: [String: [Candle]] = [:]
        await withTaskGroup(of: (String, [Candle]).self) { g in
            for i in ex.map(\.0) + [spx] {
                g.addTask { (i.symbol, (try? await market.history(for: i, range: "1y", weekly: false)) ?? []) }
            }
            for await (s, c) in g where !c.isEmpty { histories[s] = c }
        }
        guard histories[Self.benchmark] != nil else { result = nil; return }
        let returns = Risk.alignedReturns(histories)
        let exposure = Dictionary(ex.map { ($0.0.symbol, $0.1) }, uniquingKeysWith: +).filter { returns[$0.key] != nil }
        let pnl = Risk.pnlSeries(exposure: exposure, returns: returns)
        let equity = max(broker.equity.double, 1)
        let beta = exposure.reduce(0.0) { acc, e in
            acc + (e.value / equity) * (Risk.beta(asset: returns[e.key] ?? [], market: returns[Self.benchmark] ?? []) ?? 0)
        }
        result = Result(beta: beta, var95: Risk.historicalVaR(pnl: pnl), es95: Risk.expectedShortfall(pnl: pnl), days: pnl.count)
    }

    private func classBars(_ ex: [(Instrument, Double)], gross: Double) -> some View {
        let byClass = Dictionary(grouping: ex, by: { $0.0.assetClass }).mapValues { $0.map { abs($0.1) }.reduce(0, +) }
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(byClass.sorted { $0.value > $1.value }, id: \.key) { cls, v in
                HStack(spacing: 8) {
                    Text(cls.rawValue).font(.mono(9, .bold)).foregroundStyle(Theme.label).frame(width: 60.pt, alignment: .leading)
                    GeometryReader { g in
                        Theme.accent.opacity(0.7).frame(width: g.size.width * CGFloat(gross > 0 ? v / gross : 0))
                    }
                    .frame(height: 8.pt)
                    Text(String(format: "%.0f%%", gross > 0 ? v / gross * 100 : 0)).font(.mono(9)).foregroundStyle(Theme.dim).frame(width: 40.pt, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func tile(_ k: String, _ v: String, _ sub: String?, _ c: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(14, .semibold)).monospacedDigit().foregroundStyle(c)
                .lineLimit(v.contains("\n") ? 3 : 1).minimumScaleFactor(0.6)
            if let sub { Text(sub).font(.mono(8)).foregroundStyle(Theme.faint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.panel)
    }
}

struct EquityCurve: View {
    let points: [Double]
    let start: Double
    @Environment(Theme.self) private var theme

    var body: some View {
        Canvas { ctx, size in
            guard points.count > 1, let lo0 = (points + [start]).min(), let hi0 = (points + [start]).max() else { return }
            let pad = max((hi0 - lo0) * 0.1, 1)
            let lo = lo0 - pad, hi = hi0 + pad
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(points.count - 1), y: size.height * CGFloat(1 - (points[i] - lo) / (hi - lo)))
            }
            let by = size.height * CGFloat(1 - (start - lo) / (hi - lo))
            ctx.stroke(Path { $0.move(to: .init(x: 0, y: by)); $0.addLine(to: .init(x: size.width, y: by)) },
                       with: .color(Theme.faint), style: .init(lineWidth: 0.6, dash: [3, 3]))
            var p = Path()
            p.move(to: pt(0))
            for i in 1..<points.count { p.addLine(to: pt(i)) }
            let color = points.last! >= start ? theme.up : theme.down
            var area = p
            area.addLine(to: .init(x: size.width, y: size.height)); area.addLine(to: .init(x: 0, y: size.height)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(.init(colors: [color.opacity(0.25), color.opacity(0)]), startPoint: .zero, endPoint: .init(x: 0, y: size.height)))
            ctx.stroke(p, with: .color(color), lineWidth: 1.4)
        }
    }
}
