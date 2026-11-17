import SwiftUI
import Charts
import KestrelCore

/// Distinct series colours for multi-security charts (readable on the dark canvas).
enum SeriesPalette {
    static let colors: [Color] = [Theme.accent, Theme.warn, Color(hex: 0xB78CFF), Color(hex: 0x22D27A),
                                  Color(hex: 0xFF7AB6), Color(hex: 0xFF9F1C), Color(hex: 0x7DD3FC), Color(hex: 0xE4EAF0),
                                  Color(hex: 0xA3E635), Color(hex: 0xF87171), Color(hex: 0x94A3B8), Color(hex: 0xFDE68A)]
    static func color(_ i: Int) -> Color { colors[i % colors.count] }
}

enum StudyWindow: String, CaseIterable {
    case m3 = "3M", m6 = "6M", y1 = "1Y", y2 = "2Y", y5 = "5Y"
    var yahoo: String { switch self { case .m3: "3mo"; case .m6: "6mo"; case .y1: "1y"; case .y2: "2y"; case .y5: "5y" } }
}

private func percent(_ v: Double?, digits: Int = 1) -> String {
    guard let v, v.isFinite else { return "—" }
    return String(format: "%+.\(digits)f%%", v * 100)
}

// MARK: - BETA

/// BETA: OLS regression of the security's returns on a benchmark's (alpha, beta with t-stats,
/// R², Blume-adjusted beta), with the scatter and fitted line. Defaults to 2 years of weekly returns.
struct BetaView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    enum Frequency: String, CaseIterable { case daily = "DAILY", weekly = "WEEKLY" }
    static let benchmarks = ["SPX", "CCMP", "RTY", "INDU", "UKX", "DAX", "SX5E", "NKY", "HSI", "BTC"]

    @AppStorage("beta.benchmark") private var benchmark = "SPX"
    @AppStorage("beta.window") private var window: StudyWindow = .y2
    @AppStorage("beta.frequency") private var frequency: Frequency = .weekly

    struct Result: Equatable {
        var fit: Regression
        var x: [Double], y: [Double], dates: [Date]
        var bench: Instrument
    }
    @State private var result: Result?
    @State private var loading = false
    @State private var failure: String?

    private var periods: Double { frequency == .weekly ? 52 : (instrument.isStreaming ? 365 : 252) }
    private var key: String { "\(instrument.symbol)|\(benchmark)|\(window.rawValue)|\(frequency.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            SectionBar(title: "\(instrument.ticker) VS \(benchmark) · OLS ON \(frequency.rawValue) RETURNS",
                       trailing: loading ? "COMPUTING…" : result.map { "\($0.fit.n) OBSERVATIONS · \(window.rawValue)" })
            if let r = result {
                tiles(r.fit)
                scatter(r).padding(8)
                Text("Raw beta = cov(r, rₘ) / var(rₘ). Adjusted beta = 0.67 × raw + 0.33 (Blume). Alpha is the intercept, annualized. t-stats use OLS standard errors; |t| > 2 is roughly 95% significance.")
                    .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8).padding(.bottom, 8)
            } else if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(title: failure ?? "Not enough shared history", detail: "Try a longer window or another benchmark.", icon: "chart.dots.scatter")
            }
        }
        .task(id: key) { await compute() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Benchmark", selection: $benchmark) { ForEach(Self.benchmarks, id: \.self) { Text($0) } }
                .labelsHidden().frame(maxWidth: 110)
            Picker("Window", selection: $window) { ForEach([StudyWindow.y1, .y2, .y5], id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 150)
            Picker("Frequency", selection: $frequency) { ForEach(Frequency.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 180)
            Spacer()
            if let r = result {
                ShareLink(item: CSVFile(name: "\(instrument.ticker)-vs-\(benchmark)-\(frequency.rawValue.lowercased()).csv", text: csv(r)),
                          preview: SharePreview("Regression data")) {
                    Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
        }
        .padding(8)
    }

    private func tiles(_ f: Regression) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
            StatTile(key: "RAW BETA", value: String(format: "%.3f", f.beta), sub: String(format: "SE %.3f · t %.1f", f.betaSE, f.betaT), color: Theme.accent)
            StatTile(key: "ADJUSTED BETA", value: String(format: "%.3f", f.adjustedBeta), sub: "BLUME 0.67 / 0.33")
            StatTile(key: "ALPHA (ANNUAL)", value: percent(f.alpha * periods, digits: 2),
                     sub: String(format: "t %.2f", f.alphaT), color: theme.tint(f.alpha))
            StatTile(key: "R²", value: String(format: "%.3f", f.r2), sub: String(format: "CORRELATION %.3f", f.correlation))
            StatTile(key: "RESIDUAL VOL", value: percent(f.residualSD * periods.squareRoot()).replacingOccurrences(of: "+", with: ""), sub: "IDIOSYNCRATIC, ANNUAL")
            StatTile(key: "SYSTEMATIC SHARE", value: String(format: "%.0f%%", f.r2 * 100), sub: "OF RETURN VARIANCE")
            StatTile(key: "OBSERVATIONS", value: "\(f.n)", sub: frequency.rawValue)
            StatTile(key: "BENCHMARK", value: benchmark, sub: result?.bench.name.uppercased())
        }
        .padding(.horizontal, 8)
    }

    private func scatter(_ r: Result) -> some View {
        let lo = r.x.min() ?? 0, hi = r.x.max() ?? 0
        return Chart {
            ForEach(Array(zip(r.x, r.y).enumerated()), id: \.offset) { _, p in
                PointMark(x: .value(benchmark, p.0 * 100), y: .value(instrument.ticker, p.1 * 100))
                    .symbolSize(14).foregroundStyle(Theme.accent.opacity(0.55))
            }
            LineMark(x: .value(benchmark, lo * 100), y: .value("Fit", (r.fit.alpha + r.fit.beta * lo) * 100), series: .value("s", "fit"))
                .foregroundStyle(Theme.warn)
            LineMark(x: .value(benchmark, hi * 100), y: .value("Fit", (r.fit.alpha + r.fit.beta * hi) * 100), series: .value("s", "fit"))
                .foregroundStyle(Theme.warn)
        }
        .chartXAxisLabel("\(benchmark) RETURN %", alignment: .center)
        .chartYAxisLabel("\(instrument.ticker) RETURN %")
        .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
        .frame(minHeight: 220)
    }

    private func csv(_ r: Result) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let rows = (0..<r.x.count).map { i in
            [r.dates.indices.contains(i) ? f.string(from: r.dates[i]) : "", CSV.number(r.x[i]), CSV.number(r.y[i])]
        }
        return CSV.make(header: ["Date", "\(benchmark) return", "\(instrument.ticker) return"], rows: rows)
    }

    private func compute() async {
        guard let bench = Universe.resolve(benchmark) else { return }
        guard bench.symbol != instrument.symbol else { result = nil; failure = "Pick a benchmark other than the security"; return }
        loading = true
        defer { loading = false }
        failure = nil
        let h = await market.histories([instrument, bench], range: window.yahoo, weekly: frequency == .weekly, minBars: 10)
        guard !Task.isCancelled else { return }
        guard h.count == 2 else { result = nil; failure = "No price history for \(h[instrument.symbol] == nil ? instrument.ticker : benchmark)"; return }
        let aligned = Risk.alignedCloses(h)
        let x = Risk.returns(aligned.closes[bench.symbol] ?? []), y = Risk.returns(aligned.closes[instrument.symbol] ?? [])
        guard let fit = Regression.ols(y: y, x: x) else { result = nil; return }
        result = Result(fit: fit, x: x, y: y, dates: Array(aligned.dates.dropFirst()), bench: bench)
    }
}

// MARK: - COMP

/// COMP: rebased total-return comparison of the active watchlist (up to 8), with annualized
/// return, volatility, Sharpe over T-bills and maximum drawdown.
struct ComparisonView: View {
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(UserData.self) private var user
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    @AppStorage("comp.window") private var window: StudyWindow = .y1
    @State private var dates: [Date] = []
    @State private var series: [(Instrument, [Double])] = []
    @State private var loading = false

    private var basket: [Instrument] { researchBasket(user.active.symbols, max: 8) }
    private var key: String { "\(window.rawValue)|\(basket.map(\.symbol).joined(separator: ","))" }
    private var periods: Double { basket.allSatisfy { $0.assetClass == .crypto } ? 365 : 252 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker("Window", selection: $window) { ForEach(StudyWindow.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                Spacer()
                if !series.isEmpty {
                    ShareLink(item: CSVFile(name: "comparison-\(window.rawValue).csv", text: csv), preview: SharePreview("Comparison")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            .padding(8)
            SectionBar(title: "TOTAL RETURN · REBASED TO 100 · \(user.active.name.uppercased())",
                       trailing: loading ? "LOADING…" : (dates.isEmpty ? nil : "\(dates.count) SHARED SESSIONS"))
            if series.count >= 2 {
                chart.padding(8)
                table
            } else if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(title: "Need two or more securities with history",
                          detail: "COMP compares the active watchlist. Add symbols with W or SECF.", icon: "chart.xyaxis.line")
            }
        }
        .task(id: key) { await compute() }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { n, s in
                ForEach(Array(zip(dates, PerformanceSummary.rebased(s.1)).enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Date", p.0), y: .value("Index", p.1), series: .value("Security", s.0.ticker))
                        .foregroundStyle(SeriesPalette.color(n)).lineStyle(.init(lineWidth: 1.5))
                }
            }
            RuleMark(y: .value("Base", 100)).foregroundStyle(Theme.faint).lineStyle(.init(dash: [3, 3]))
        }
        .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
        .chartLegend(.hidden)
        .frame(minHeight: 220)
    }

    private var table: some View {
        let rf = market.riskFree
        return VStack(spacing: 0) {
            HStack {
                Text("SECURITY").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["TOTAL", "ANN. RETURN", "ANN. VOL", "SHARPE", "MAX DD"], id: \.self) { Text($0).frame(width: 92, alignment: .trailing) }
            }
            .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
            ForEach(Array(series.enumerated()), id: \.offset) { n, s in
                let p = PerformanceSummary.of(s.1, periodsPerYear: periods, riskFree: rf)
                HStack {
                    Button { ws.link(s.0, from: panelID) } label: {
                        HStack(spacing: 6) {
                            Rectangle().fill(SeriesPalette.color(n)).frame(width: 10, height: 3)
                            Text(s.0.ticker).font(.mono(11, .bold)).foregroundStyle(Theme.text)
                            Text(market.displayName(s.0)).font(.ui(10)).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Group {
                        Text(percent(p?.totalReturn)).foregroundStyle(theme.tint(p?.totalReturn))
                        Text(percent(p?.annualizedReturn)).foregroundStyle(theme.tint(p?.annualizedReturn))
                        Text(p.map { String(format: "%.1f%%", $0.annualizedVol * 100) } ?? "—").foregroundStyle(Theme.text)
                        Text(p?.sharpe.map { String(format: "%.2f", $0) } ?? "—").foregroundStyle(Theme.text)
                        Text(percent(p?.maxDrawdown)).foregroundStyle(theme.down)
                    }
                    .font(.mono(11)).monospacedDigit().frame(width: 92, alignment: .trailing)
                }
                .padding(.horizontal, 8).padding(.vertical, 5).rowBackground(n)
            }
            Text(String(format: "Sharpe uses the 13-week T-bill (%.2f%%) as the risk-free rate. Returns are price returns on shared trading days; dividends are not included.", rf * 100))
                .font(.ui(10)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }

    private var csv: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let rows = dates.indices.map { i in [f.string(from: dates[i])] + series.map { CSV.number($0.1[i]) } }
        return CSV.make(header: ["Date"] + series.map { $0.0.ticker }, rows: rows)
    }

    private func compute() async {
        let list = basket
        guard list.count >= 2 else { series = []; dates = []; return }
        loading = true
        defer { loading = false }
        let h = await market.histories(list, range: window.yahoo)
        guard !Task.isCancelled else { return }
        let aligned = Risk.alignedCloses(h)
        dates = aligned.dates
        series = list.compactMap { i in aligned.closes[i.symbol].map { (i, $0) } }
    }
}

// MARK: - MVO

/// MVO: long-only mean-variance optimization of the active watchlist from historical daily
/// returns: the efficient frontier, minimum-variance and maximum-Sharpe portfolios.
struct OptimizerView: View {
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(UserData.self) private var user
    @Environment(Workspace.self) private var ws

    @AppStorage("mvo.window") private var window: StudyWindow = .y2

    struct Output {
        var assets: [Instrument]
        var mu: [Double]
        var vol: [Double]
        var frontier: [Portfolio]
        var minVariance: Portfolio
        var maxSharpe: Portfolio
        var days: Int
    }
    @State private var out: Output?
    @State private var loading = false

    private var basket: [Instrument] { researchBasket(user.active.symbols, max: 12) }
    private var key: String { "\(window.rawValue)|\(basket.map(\.symbol).joined(separator: ","))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker("Window", selection: $window) { ForEach([StudyWindow.y1, .y2, .y5], id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 160)
                Spacer()
                if let o = out {
                    ShareLink(item: CSVFile(name: "optimizer-\(window.rawValue).csv", text: csv(o)), preview: SharePreview("Weights")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            .padding(8)
            SectionBar(title: "EFFICIENT FRONTIER · LONG ONLY · \(user.active.name.uppercased())",
                       trailing: loading ? "OPTIMIZING…" : out.map { "\($0.days) DAILY RETURNS · \($0.assets.count) ASSETS" })
            if let o = out {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        tiles(o)
                        chart(o).frame(height: 260).padding(.horizontal, 8)
                        weights(o)
                        Text("Inputs are historical means and covariances, which are noisy estimates of the future; the optimizer amplifies their errors. Treat the weights as a study of risk and diversification, not as advice.")
                            .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
            } else if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(title: "Need two or more securities with history",
                          detail: "MVO optimizes the active watchlist (up to 12). Add symbols with W or SECF.", icon: "chart.pie")
            }
        }
        .task(id: key) { await compute() }
    }

    private func tiles(_ o: Output) -> some View {
        let rf = market.riskFree
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
            StatTile(key: "MAX SHARPE · RETURN", value: percent(o.maxSharpe.expectedReturn), sub: String(format: "VOL %.1f%%", o.maxSharpe.volatility * 100), color: Theme.accent)
            StatTile(key: "MAX SHARPE · RATIO", value: String(format: "%.2f", o.maxSharpe.sharpe(riskFree: rf)), sub: String(format: "RF %.2f%% (13W T-BILL)", rf * 100))
            StatTile(key: "MIN VARIANCE · RETURN", value: percent(o.minVariance.expectedReturn), sub: String(format: "VOL %.1f%%", o.minVariance.volatility * 100), color: Theme.warn)
            StatTile(key: "MIN VARIANCE · RATIO", value: String(format: "%.2f", o.minVariance.sharpe(riskFree: rf)), sub: "ANNUALIZED")
        }
        .padding(.horizontal, 8)
    }

    private func chart(_ o: Output) -> some View {
        Chart {
            ForEach(Array(o.frontier.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Volatility", p.volatility * 100), y: .value("Return", p.expectedReturn * 100), series: .value("s", "frontier"))
                    .foregroundStyle(Theme.accent).lineStyle(.init(lineWidth: 2))
            }
            ForEach(Array(o.assets.enumerated()), id: \.offset) { n, a in
                PointMark(x: .value("Volatility", o.vol[n] * 100), y: .value("Return", o.mu[n] * 100))
                    .foregroundStyle(Theme.dim).symbolSize(30)
                    .annotation(position: .trailing, spacing: 3) { Text(a.ticker).font(.mono(8, .bold)).foregroundStyle(Theme.dim) }
            }
            PointMark(x: .value("Volatility", o.maxSharpe.volatility * 100), y: .value("Return", o.maxSharpe.expectedReturn * 100))
                .foregroundStyle(Theme.accent).symbol(.diamond).symbolSize(110)
            PointMark(x: .value("Volatility", o.minVariance.volatility * 100), y: .value("Return", o.minVariance.expectedReturn * 100))
                .foregroundStyle(Theme.warn).symbol(.square).symbolSize(90)
        }
        .chartXAxisLabel("ANNUAL VOLATILITY %", alignment: .center)
        .chartYAxisLabel("ANNUAL RETURN %")
        .chartXAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
    }

    private func weights(_ o: Output) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("ASSET").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["ANN. RETURN", "ANN. VOL", "MIN VAR", "MAX SHARPE"], id: \.self) { Text($0).frame(width: 96, alignment: .trailing) }
            }
            .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
            ForEach(Array(o.assets.enumerated()), id: \.offset) { n, a in
                HStack {
                    Button { ws.link(a, from: panelID) } label: {
                        Text(a.ticker).font(.mono(11, .bold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Group {
                        Text(percent(o.mu[n])).foregroundStyle(Theme.text)
                        Text(String(format: "%.1f%%", o.vol[n] * 100)).foregroundStyle(Theme.text)
                        weight(o.minVariance.weights[n], Theme.warn)
                        weight(o.maxSharpe.weights[n], Theme.accent)
                    }
                    .font(.mono(11)).monospacedDigit().frame(width: 96, alignment: .trailing)
                }
                .padding(.horizontal, 8).padding(.vertical, 5).rowBackground(n)
            }
        }
    }

    private func weight(_ w: Double, _ c: Color) -> some View {
        Text(w < 0.0005 ? "—" : String(format: "%.1f%%", w * 100)).foregroundStyle(w < 0.0005 ? Theme.faint : c)
    }

    private func csv(_ o: Output) -> String {
        let rows = o.assets.indices.map { n in
            [o.assets[n].ticker, CSV.number(o.mu[n]), CSV.number(o.vol[n]), CSV.number(o.minVariance.weights[n]), CSV.number(o.maxSharpe.weights[n])]
        }
        return CSV.make(header: ["Asset", "Annual return", "Annual volatility", "Min variance weight", "Max Sharpe weight"], rows: rows)
    }

    private func compute() async {
        let list = basket
        guard list.count >= 2 else { out = nil; return }
        loading = true
        defer { loading = false }
        let h = await market.histories(list, range: window.yahoo, minBars: 40)
        guard !Task.isCancelled else { return }
        let kept = list.filter { h[$0.symbol] != nil }
        let returns = Risk.alignedReturns(h)
        let series = kept.compactMap { returns[$0.symbol] }
        let periods: Double = kept.allSatisfy { $0.assetClass == .crypto } ? 365 : 252
        let rf = market.riskFree
        let solved = await Task.detached(priority: .userInitiated) { () -> (mu: [Double], cov: [[Double]], f: (frontier: [Portfolio], minVariance: Portfolio, maxSharpe: Portfolio))? in
            guard let m = Frontier.moments(series, periodsPerYear: periods),
                  let f = Frontier.build(mu: m.mu, cov: m.cov, riskFree: rf) else { return nil }
            return (m.mu, m.cov, f)
        }.value
        guard !Task.isCancelled else { return }
        guard let s = solved, kept.count == s.mu.count else { out = nil; return }
        out = Output(assets: kept, mu: s.mu, vol: s.cov.indices.map { s.cov[$0][$0].squareRoot() },
                     frontier: s.f.frontier, minVariance: s.f.minVariance, maxSharpe: s.f.maxSharpe,
                     days: series.first?.count ?? 0)
    }
}
