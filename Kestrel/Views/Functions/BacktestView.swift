import SwiftUI
import KestrelCore

/// BT: run a rules-based long/flat strategy over daily history and compare it with buy and hold.
struct BacktestView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    enum Rule: String, CaseIterable { case sma = "SMA CROSS", rsi = "RSI", bands = "BOLLINGER", hold = "BUY & HOLD" }
    enum Span: String, CaseIterable { case y1 = "1Y", y2 = "2Y", y5 = "5Y" }

    @AppStorage("bt.rule") private var rule: Rule = .sma
    @AppStorage("bt.span") private var span: Span = .y2
    @AppStorage("bt.fast") private var fast = 20
    @AppStorage("bt.slow") private var slow = 50
    @AppStorage("bt.rsiLo") private var rsiLo = 30.0
    @AppStorage("bt.rsiHi") private var rsiHi = 70.0
    @AppStorage("bt.cost") private var costBps = 5.0

    @State private var bars: [Candle] = []
    /// 3-month T-bill yield (Yahoo ^IRX, in %) by UTC day, for cash yield and excess returns.
    @State private var tbill: [Date: Double] = [:]
    @State private var loading = false
    @State private var failed = false

    private var strategy: Strategy {
        switch rule {
        case .sma: .smaCross(fast: fast, slow: max(slow, fast + 1))
        case .rsi: .rsi(period: 14, buyBelow: rsiLo, sellAbove: rsiHi)
        case .bands: .bollinger(period: 20, k: 2)
        case .hold: .buyAndHold
        }
    }
    private var perYear: Double { instrument.assetClass == .crypto ? 365 : 252 }
    private var result: BacktestResult? {
        Backtest.run(bars, strategy: strategy, costBps: costBps, periodsPerYear: perYear, riskFree: riskFreeSeries)
    }

    /// T-bill rate aligned to each bar (carried forward over holidays and weekends), as a decimal.
    private var riskFreeSeries: [Double]? {
        guard !tbill.isEmpty else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let days = tbill.keys.sorted()
        var last = tbill[days[0]]! / 100, j = 0
        return bars.map { b in
            let d = cal.startOfDay(for: b.time)
            while j < days.count, days[j] <= d { last = tbill[days[j]]! / 100; j += 1 }
            return last
        }
    }

    var body: some View {
        let r = result
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                controls
                if let r {
                    stats(r)
                    SectionBar(title: "EQUITY · \(strategy.label.uppercased())", trailing: "vs BUY & HOLD · \(bars.count) DAILY BARS")
                    BacktestChart(result: r).frame(height: 220).padding(.horizontal, 8)
                    legend
                    trades(r)
                    Text("Hypothetical results on past data: long or flat, signals at the close, fills at the next open, \(Int(costBps)) bp per side; idle cash earns the 3-month T-bill. Not a forecast.")
                        .font(.mono(9)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
                } else if loading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    EmptyNote(title: failed ? "No history for \(instrument.ticker)" : "Not enough history", icon: "chart.line.uptrend.xyaxis")
                        .frame(minHeight: 200)
                }
            }
            .padding(.vertical, 8)
        }
        .task(id: span) { await load() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Rule", selection: $rule) { ForEach(Rule.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                Picker("Span", selection: $span) { ForEach(Span.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 150)
                Spacer()
            }
            HStack(spacing: 18) {
                switch rule {
                case .sma:
                    stepper("FAST", $fast, 2...100)
                    stepper("SLOW", $slow, 5...250)
                case .rsi:
                    stepper("BUY BELOW", Binding(get: { Int(rsiLo) }, set: { rsiLo = Double($0) }), 5...50)
                    stepper("SELL ABOVE", Binding(get: { Int(rsiHi) }, set: { rsiHi = Double($0) }), 50...95)
                case .bands:
                    Text("Buy a close below the lower band (20, 2σ); sell back at the middle band.").font(.mono(10)).foregroundStyle(Theme.dim)
                case .hold:
                    Text("Baseline: buy on day one and never sell.").font(.mono(10)).foregroundStyle(Theme.dim)
                }
                Spacer()
                stepper("COST BP", Binding(get: { Int(costBps) }, set: { costBps = Double($0) }), 0...50)
            }
        }
        .padding(.horizontal, 8)
    }

    private func stepper(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - (value.wrappedValue > 20 ? 5 : 1)) } label: { Image(systemName: "minus") }
                .accessibilityLabel("Decrease \(label)")
            Text("\(value.wrappedValue)").font(.mono(12, .semibold)).monospacedDigit().foregroundStyle(Theme.text).frame(minWidth: 28)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + (value.wrappedValue >= 20 ? 5 : 1)) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Increase \(label)")
        }
        .buttonStyle(.plain).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
    }

    // MARK: Results

    private func stats(_ r: BacktestResult) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 2)], spacing: 2) {
            tile("TOTAL RETURN", pct(r.totalReturn), "B&H " + pct(r.benchmarkReturn), theme.tint(r.totalReturn))
            tile("EXCESS vs B&H", pct(r.totalReturn - r.benchmarkReturn), nil, theme.tint(r.totalReturn - r.benchmarkReturn))
            tile("CAGR", r.cagr.map(pct) ?? "—", nil, theme.tint(r.cagr))
            tile("SHARPE", r.sharpe.map { String(format: "%.2f", $0) } ?? "—", r.riskFree > 0 ? String(format: "vs %.2f%% T-bill", r.riskFree * 100) : "rf = 0 (no T-bill data)", Theme.text)
            tile("SORTINO", r.sortino.map { String(format: "%.2f", $0) } ?? "—", "downside risk only", Theme.text)
            tile("VOLATILITY", r.volatility.map { String(format: "%.1f%%", $0 * 100) } ?? "—", "annualised", Theme.text)
            tile("CALMAR", r.calmar.map { String(format: "%.2f", $0) } ?? "—", "CAGR / max DD", Theme.text)
            tile("MAX DRAWDOWN", "-" + String(format: "%.1f%%", r.maxDrawdown * 100), nil, theme.down)
            tile("WIN RATE", r.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—", "\(r.trades.count) trades", Theme.text)
            tile("TIME IN MARKET", String(format: "%.0f%%", r.exposure * 100), nil, Theme.text)
        }
        .padding(.horizontal, 8)
    }

    private func tile(_ k: String, _ v: String, _ sub: String?, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(16, .semibold)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
            Text(sub ?? " ").font(.mono(8)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Theme.panel)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { Rectangle().fill(Theme.accent).frame(width: 14, height: 2); Text("STRATEGY") }
            HStack(spacing: 5) { Rectangle().fill(Theme.dim).frame(width: 14, height: 2); Text("BUY & HOLD") }
            HStack(spacing: 5) { Rectangle().fill(Theme.accent.opacity(0.12)).frame(width: 14, height: 8); Text("IN MARKET") }
        }
        .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8)
    }

    private func trades(_ r: BacktestResult) -> some View {
        VStack(spacing: 0) {
            SectionBar(title: "TRADES", trailing: r.trades.count > 25 ? "LAST 25 OF \(r.trades.count)" : "\(r.trades.count)")
            HStack {
                HeaderCell(text: "ENTRY", width: 110, align: .leading); HeaderCell(text: "EXIT", width: 110, align: .leading)
                HeaderCell(text: "IN"); HeaderCell(text: "OUT"); HeaderCell(text: "RETURN")
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            ForEach(Array(r.trades.suffix(25).reversed().enumerated()), id: \.element.id) { n, t in
                HStack {
                    Text(t.entry.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))).frame(width: 110, alignment: .leading).foregroundStyle(Theme.dim)
                    Text(t.exit?.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) ?? "OPEN").frame(width: 110, alignment: .leading)
                        .foregroundStyle(t.exit == nil ? Theme.warn : Theme.dim)
                    Text(Fmt.price(t.entryPrice, instrument.assetClass)).frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(Theme.text)
                    Text(Fmt.price(t.exitPrice, instrument.assetClass)).frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(Theme.text)
                    Text(pct(t.returnPct)).frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(theme.tint(t.returnPct))
                }
                .font(.mono(11)).monospacedDigit()
                .padding(.horizontal, 8).frame(height: 22).rowBackground(n)
            }
        }
    }

    private func pct(_ v: Double) -> String { String(format: "%+.1f%%", v * 100) }

    private func load() async {
        loading = true
        defer { loading = false }
        let range = span.rawValue.lowercased()
        do {
            bars = try await market.history(for: instrument, range: range, weekly: false)
            failed = bars.isEmpty
            if let irx = Universe.instrument(symbol: "^IRX"),
               let t = try? await market.history(for: irx, range: range, weekly: false) {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
                tbill = Dictionary(t.filter { $0.close > 0 }.map { (cal.startOfDay(for: $0.time), $0.close) }, uniquingKeysWith: { _, b in b })
            }
        } catch {
            bars = []; failed = true
        }
    }
}

/// Strategy vs buy-and-hold equity on one scale, with in-market spans shaded.
struct BacktestChart: View {
    let result: BacktestResult

    var body: some View {
        Canvas { ctx, size in
            let e = result.equity, b = result.benchmark
            let all = e + b
            guard e.count > 1, let lo0 = all.min(), let hi0 = all.max() else { return }
            let pad = max((hi0 - lo0) * 0.06, 0.01)
            let lo = lo0 - pad, hi = hi0 + pad
            func x(_ i: Int) -> CGFloat { size.width * CGFloat(i) / CGFloat(e.count - 1) }
            func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (v - lo) / (hi - lo)) }

            // Shade each trade's holding period.
            let index = Dictionary(result.dates.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            for t in result.trades {
                guard let s = index[t.entry] else { continue }
                let f = t.exit.flatMap { index[$0] } ?? e.count - 1
                ctx.fill(Path(CGRect(x: x(s), y: 0, width: max(x(f) - x(s), 1), height: size.height)), with: .color(Theme.accent.opacity(0.08)))
            }
            // Break-even line.
            ctx.stroke(Path { $0.move(to: .init(x: 0, y: y(1))); $0.addLine(to: .init(x: size.width, y: y(1))) },
                       with: .color(Theme.faint), style: .init(lineWidth: 0.6, dash: [3, 3]))
            func line(_ v: [Double]) -> Path {
                Path { p in
                    p.move(to: .init(x: x(0), y: y(v[0])))
                    for i in 1..<v.count { p.addLine(to: .init(x: x(i), y: y(v[i]))) }
                }
            }
            ctx.stroke(line(b), with: .color(Theme.dim), lineWidth: 1)
            ctx.stroke(line(e), with: .color(Theme.accent), lineWidth: 1.6)
            // Axis labels: top, break-even, bottom, as % change.
            for v in [hi0, 1, lo0] {
                let t = Text(String(format: "%+.0f%%", (v - 1) * 100)).font(.mono(9)).foregroundStyle(Theme.faint)
                ctx.draw(t, at: .init(x: size.width - 4, y: min(max(y(v), 8), size.height - 8)), anchor: .trailing)
            }
        }
        .background(Theme.panel)
    }
}
