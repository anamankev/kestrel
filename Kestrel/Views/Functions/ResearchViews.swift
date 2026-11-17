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
    @State private var size: CGSize = .zero

    private var periods: Double { frequency == .weekly ? 52 : (instrument.isStreaming ? 365 : 252) }
    private var key: String { "\(instrument.symbol)|\(benchmark)|\(window.rawValue)|\(frequency.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            SectionBar(title: "\(instrument.ticker) VS \(benchmark) · OLS ON \(frequency.rawValue) RETURNS",
                       trailing: loading ? "COMPUTING…" : result.map { "\($0.fit.n) OBSERVATIONS · \(window.rawValue)" })
            if let r = result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        tiles(r.fit)
                        scatter(r).frame(height: max(200, size.height - 240)).padding(8)
                        Text("Raw beta = cov(r, rₘ) / var(rₘ). Adjusted beta = 0.67 × raw + 0.33 (Blume). Alpha is the intercept, annualized. t-stats use OLS standard errors; |t| > 2 is roughly 95% significance.")
                            .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
            } else if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(title: failure ?? "Not enough shared history", detail: "Try a longer window or another benchmark.", icon: "chart.dots.scatter")
            }
        }
        .readSize($size)
        .task(id: key) { await compute() }
    }

    private var controls: some View {
        ControlBar {
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
        let h = await market.histories([instrument, bench], range: window.yahoo, weekly: frequency == .weekly, adjusted: true, minBars: 10)
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
    @State private var size: CGSize = .zero

    private var basket: [Instrument] { researchBasket(user.active.symbols, max: 8) }
    private var key: String { "\(window.rawValue)|\(basket.map(\.symbol).joined(separator: ","))" }
    private var periods: Double { basket.allSatisfy { $0.assetClass == .crypto } ? 365 : 252 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlBar {
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
            SectionBar(title: "TOTAL RETURN · REBASED TO 100 · \(user.active.name.uppercased())",
                       trailing: loading ? "LOADING…" : (dates.isEmpty ? nil : "\(dates.count) SHARED SESSIONS"))
            if series.count >= 2 {
                ScrollView {
                    VStack(spacing: 0) {
                        chart.frame(height: max(200, size.height * 0.5)).padding(8)
                        table
                    }
                }
            } else if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(title: "Need two or more securities with history",
                          detail: "COMP compares the active watchlist. Add symbols with W or SECF.", icon: "chart.xyaxis.line")
            }
        }
        .readSize($size)
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
    }

    private var table: some View {
        let rf = market.riskFree
        // Narrow panels keep the leftmost statistics; names show only when there's room.
        let shown = columnsThatFit(size.width, reserved: 110, column: 80, max: 5)
        let roomy = size.width == 0 || size.width >= 660
        return VStack(spacing: 0) {
            HStack {
                Text("SECURITY").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(["TOTAL", "ANN. RETURN", "ANN. VOL", "SHARPE", "MAX DD"].prefix(shown)), id: \.self) { Text($0).frame(width: 80, alignment: .trailing) }
            }
            .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
            ForEach(Array(series.enumerated()), id: \.offset) { n, s in
                let p = PerformanceSummary.of(s.1, periodsPerYear: periods, riskFree: rf)
                HStack {
                    Button { ws.link(s.0, from: panelID) } label: {
                        HStack(spacing: 6) {
                            Rectangle().fill(SeriesPalette.color(n)).frame(width: 10, height: 3)
                            Text(s.0.ticker).font(.mono(11, .bold)).foregroundStyle(Theme.text)
                            if roomy { Text(market.displayName(s.0)).font(.ui(10)).foregroundStyle(Theme.dim).lineLimit(1) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    let cells: [(String, Color)] = [
                        (percent(p?.totalReturn), theme.tint(p?.totalReturn)),
                        (percent(p?.annualizedReturn), theme.tint(p?.annualizedReturn)),
                        (p.map { String(format: "%.1f%%", $0.annualizedVol * 100) } ?? "—", Theme.text),
                        (p?.sharpe.map { String(format: "%.2f", $0) } ?? "—", Theme.text),
                        (percent(p?.maxDrawdown), theme.down),
                    ]
                    ForEach(0..<shown, id: \.self) { k in
                        Text(cells[k].0).foregroundStyle(cells[k].1).font(.mono(11)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5).rowBackground(n)
            }
            Text(String(format: "Sharpe uses the 13-week T-bill (%.2f%%) as the risk-free rate. Total returns (dividends reinvested) on shared trading days.", rf * 100))
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
        let h = await market.histories(list, range: window.yahoo, adjusted: true)
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
            ControlBar {
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
                ForEach(["ANN. RET", "ANN. VOL", "MIN VAR", "MAX SHARPE"], id: \.self) { Text($0).frame(width: 82, alignment: .trailing) }
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
                    .font(.mono(11)).monospacedDigit().frame(width: 82, alignment: .trailing)
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
        let h = await market.histories(list, range: window.yahoo, adjusted: true, minBars: 40)
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

// MARK: - FACT

/// FACT: Fama-French factor regression of the security's daily excess total returns
/// (CAPM, three-factor, Carhart four-factor, five-factor), with loadings, t-stats and alpha.
struct FactorView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    @AppStorage("fact.model") private var model: FactorModel = .ff3
    @AppStorage("fact.window") private var window: StudyWindow = .y2

    struct Output { var fit: LinearFit; var first: Int; var last: Int; var dataEnds: Int }
    @State private var out: Output?
    @State private var loading = false
    @State private var failure: String?

    private var supported: Bool { instrument.assetClass == .equity || instrument.assetClass == .index }
    private var key: String { "\(instrument.symbol)|\(model.rawValue)|\(window.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlBar {
                Picker("Model", selection: $model) { ForEach(FactorModel.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 340)
                Picker("Window", selection: $window) { ForEach([StudyWindow.y1, .y2, .y5], id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 150)
                Spacer()
                if let o = out {
                    ShareLink(item: CSVFile(name: "\(instrument.ticker)-\(model.rawValue.replacingOccurrences(of: " ", with: ""))-\(window.rawValue).csv", text: csv(o)),
                              preview: SharePreview("Factor loadings")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            SectionBar(title: "\(instrument.ticker) · \(model.rawValue) · DAILY EXCESS TOTAL RETURNS",
                       trailing: loading ? "LOADING FACTORS…" : out.map { "\($0.fit.n) DAYS · \(day($0.first)) → \(day($0.last))" })
            if !supported {
                EmptyNote(title: "Factor models describe stock returns", detail: "Load a US stock or ETF, e.g. MSFT FACT or SPY FACT.", icon: "function")
            } else if let o = out {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        tiles(o.fit)
                        loadings(o.fit)
                        chart(o.fit).frame(height: 180).padding(.horizontal, 8)
                        Text("Excess return (total return − 1-month T-bill) regressed on Fama-French factors from the Kenneth R. French Data Library, built from US stocks; data runs to \(day(o.dataEnds)), so the regression uses the overlap. Alpha is annualized ×252. |t| > 2 ≈ 95% significance; bars show ±1.96 standard errors.")
                            .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8).padding(.bottom, 8)
                    }
                }
            } else if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(title: failure ?? "Not enough overlapping history", detail: "Try a longer window.", icon: "function")
            }
        }
        .task(id: key) { await compute() }
    }

    private func day(_ d: Int) -> String { String(format: "%04d-%02d-%02d", d / 10000, d / 100 % 100, d % 100) }

    private func tiles(_ f: LinearFit) -> some View {
        let a = f.terms[0]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
            StatTile(key: "ALPHA (ANNUAL)", value: percent(a.coefficient * 252, digits: 2), sub: String(format: "t %.2f%@", a.t, abs(a.t) > 2 ? " · SIGNIFICANT" : ""), color: theme.tint(a.coefficient))
            StatTile(key: "MARKET BETA", value: String(format: "%.3f", f.terms[1].coefficient), sub: String(format: "t %.1f", f.terms[1].t), color: Theme.accent)
            StatTile(key: "R² / ADJ. R²", value: String(format: "%.3f", f.r2), sub: String(format: "ADJUSTED %.3f", f.adjustedR2))
            StatTile(key: "RESIDUAL VOL", value: String(format: "%.1f%%", f.residualSD * 252.0.squareRoot() * 100), sub: "ANNUALIZED, UNEXPLAINED")
        }
        .padding(.horizontal, 8)
    }

    private func loadings(_ f: LinearFit) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("FACTOR").frame(width: 70, alignment: .leading)
                Text("MEANING").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["LOADING", "STD ERR", "T-STAT"], id: \.self) { Text($0).frame(width: 84, alignment: .trailing) }
            }
            .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
            ForEach(Array(f.terms.dropFirst().enumerated()), id: \.offset) { n, t in
                HStack {
                    Text(t.name).font(.mono(11, .bold)).foregroundStyle(Theme.text).frame(width: 70, alignment: .leading)
                    Text(FactorModel.describe(t.name)).font(.ui(11)).foregroundStyle(Theme.dim).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        Text(String(format: "%+.3f", t.coefficient)).foregroundStyle(abs(t.t) > 2 ? Theme.text : Theme.dim)
                        Text(String(format: "%.3f", t.standardError)).foregroundStyle(Theme.dim)
                        Text(String(format: "%.2f", t.t) + (abs(t.t) > 2.58 ? " **" : abs(t.t) > 1.96 ? " *" : "")).foregroundStyle(abs(t.t) > 1.96 ? Theme.accent : Theme.dim)
                    }
                    .font(.mono(11)).monospacedDigit().frame(width: 84, alignment: .trailing)
                }
                .padding(.horizontal, 8).padding(.vertical, 5).rowBackground(n)
            }
        }
    }

    private func chart(_ f: LinearFit) -> some View {
        let terms = Array(f.terms.dropFirst())
        return Chart {
            ForEach(Array(terms.enumerated()), id: \.offset) { _, t in
                BarMark(x: .value("Factor", t.name), y: .value("Loading", t.coefficient))
                    .foregroundStyle(t.coefficient >= 0 ? Theme.accent.opacity(0.75) : Theme.warn.opacity(0.75))
                RuleMark(x: .value("Factor", t.name), yStart: .value("Low", t.coefficient - 1.96 * t.standardError),
                         yEnd: .value("High", t.coefficient + 1.96 * t.standardError))
                    .foregroundStyle(Theme.text).lineStyle(.init(lineWidth: 1))
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.faint)
        }
        .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(Theme.dim) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
    }

    private func csv(_ o: Output) -> String {
        CSV.make(header: ["Term", "Coefficient", "Std error", "t-stat"],
                 rows: o.fit.terms.map { [$0.name, CSV.number($0.coefficient, digits: 8), CSV.number($0.standardError, digits: 8), CSV.number($0.t, digits: 4)] }
                     + [["R2", CSV.number(o.fit.r2), "", ""], ["Adjusted R2", CSV.number(o.fit.adjustedR2), "", ""], ["Observations", String(o.fit.n), "", ""],
                        ["Model", model.rawValue, "", ""], ["From", day(o.first), "", ""], ["To", day(o.last), "", ""]])
    }

    private func compute() async {
        guard supported else { out = nil; return }
        loading = true
        defer { loading = false }
        failure = nil
        do {
            async let table = market.factors(model)
            async let bars = market.history(for: instrument, range: window.yahoo, weekly: false, adjusted: true)
            let (t, candles) = try await (table, bars)
            guard !Task.isCancelled else { return }
            guard let rf = t.column("RF") else { out = nil; failure = "Factor file has no risk-free column"; return }
            let idx = model.factors.compactMap { t.column($0) }
            guard idx.count == model.factors.count else { out = nil; failure = "Factor file is missing a column"; return }
            var y: [Double] = [], cols = Array(repeating: [Double](), count: idx.count), dates: [Int] = []
            for (prev, cur) in zip(candles, candles.dropFirst()) where prev.close > 0 {
                let d = yyyymmdd(cur.time)
                guard let row = t.rows[d] else { continue }
                y.append(cur.close / prev.close - 1 - row[rf])
                for (k, c) in idx.enumerated() { cols[k].append(row[c]) }
                dates.append(d)
            }
            guard let fit = LinearFit.ols(y: y, columns: cols, names: model.factors), let first = dates.first, let last = dates.last else {
                out = nil; failure = "Not enough days overlap the factor data"; return
            }
            out = Output(fit: fit, first: first, last: last, dataEnds: t.lastDate)
        } catch {
            out = nil
            failure = "Couldn't load factor data: \(error.localizedDescription)"
        }
    }
}

// MARK: - DVD

/// DVD: ten years of cash dividends: trailing yield, frequency, 5-year growth, annual totals and every payment.
struct DividendView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    @State private var divs: [Dividend] = []
    @State private var price: Double?
    @State private var loading = true
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionBar(title: "\(instrument.ticker) · CASH DIVIDENDS · 10 YEARS", trailing: loading ? "LOADING…" : "\(divs.count) PAYMENTS")
            if let s = DividendSummary.of(divs, price: market.quotes[instrument.symbol]?.last ?? price) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Spacer()
                            ShareLink(item: CSVFile(name: "\(instrument.ticker)-dividends.csv", text: csv), preview: SharePreview("Dividends")) {
                                Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 8).padding(.top, 6)
                        tiles(s)
                        annual(s).frame(height: 170).padding(.horizontal, 8)
                        payments
                    }
                }
            } else if loading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyNote(title: failure ?? "No cash dividends in the last 10 years", detail: failure == nil ? "\(instrument.ticker) hasn't paid a dividend in this period." : nil, icon: "dollarsign.circle")
            }
        }
        .task(id: instrument.symbol) {
            loading = true
            defer { loading = false }
            do {
                let r = try await market.dividends(for: instrument)
                divs = r.dividends; price = r.price; failure = nil
            } catch { failure = "Couldn't load dividends: \(error.localizedDescription)" }
        }
    }

    /// Dividends per share: cents precision, more only for sub-cent payouts.
    private func amount(_ v: Double) -> String { String(format: v >= 0.1 ? "%.2f" : "%.4f", v) }

    /// The 10-year window starts mid-year, so the first year is usually partial: leave it out.
    private func fullYears(_ s: DividendSummary) -> [(year: Int, total: Double)] {
        guard let first = s.annual.first, s.paymentsPerYear > 0 else { return s.annual }
        let cal = Calendar(identifier: .gregorian)
        let count = divs.filter { cal.component(.year, from: $0.date) == first.year }.count
        return count < s.paymentsPerYear ? Array(s.annual.dropFirst()) : s.annual
    }

    private func frequency(_ n: Int) -> String {
        switch n { case 12: "MONTHLY"; case 4: "QUARTERLY"; case 2: "SEMIANNUAL"; case 1: "ANNUAL"; case 0: "IRREGULAR"; default: "\(n)× A YEAR" }
    }

    private func tiles(_ s: DividendSummary) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
            StatTile(key: "TRAILING 12M", value: amount(s.trailing12M), sub: "PER SHARE", color: Theme.accent)
            StatTile(key: "YIELD (TTM)", value: s.yield.map { String(format: "%.2f%%", $0 * 100) } ?? "—", sub: "ON THE LAST PRICE")
            StatTile(key: "5Y GROWTH", value: s.growth5Y.map { percent($0, digits: 1) } ?? "—", sub: "CAGR, COMPLETE YEARS", color: theme.tint(s.growth5Y))
            StatTile(key: "FREQUENCY", value: frequency(s.paymentsPerYear),
                     sub: divs.last.map { "LAST \(amount($0.amount)) · \($0.date.formatted(.dateTime.month(.abbreviated).day().year()).uppercased())" })
        }
        .padding(.horizontal, 8)
    }

    private func annual(_ s: DividendSummary) -> some View {
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: .now)
        return Chart {
            ForEach(fullYears(s), id: \.year) { a in
                BarMark(x: .value("Year", String(a.year)), y: .value("Dividends", a.total))
                    .foregroundStyle(a.year == thisYear ? Theme.accent.opacity(0.35) : Theme.accent.opacity(0.8))
                    .annotation(position: .top) { Text(amount(a.total)).font(.mono(8)).foregroundStyle(Theme.dim) }
            }
        }
        .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(Theme.dim) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
    }

    private var payments: some View {
        let rows = Array(divs.enumerated().reversed())
        return VStack(spacing: 0) {
            HStack {
                Text("EX-DATE").frame(maxWidth: .infinity, alignment: .leading)
                Text("AMOUNT").frame(width: 100, alignment: .trailing)
                Text("CHANGE").frame(width: 100, alignment: .trailing)
            }
            .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
            ForEach(Array(rows.enumerated()), id: \.offset) { n, e in
                let change = e.offset > 0 ? e.element.amount / divs[e.offset - 1].amount - 1 : nil
                HStack {
                    Text(e.element.date.formatted(.dateTime.year().month(.abbreviated).day())).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                    Text(amount(e.element.amount)).foregroundStyle(Theme.text).frame(width: 100, alignment: .trailing)
                    Text(change.map { abs($0) < 0.0005 ? "—" : percent($0) } ?? "—").foregroundStyle(change.map { abs($0) < 0.0005 ? Theme.faint : theme.tint($0) } ?? Theme.faint)
                        .frame(width: 100, alignment: .trailing)
                }
                .font(.mono(11)).monospacedDigit().padding(.horizontal, 8).padding(.vertical, 4).rowBackground(n)
            }
        }
    }

    private var csv: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return CSV.make(header: ["Ex-date", "Amount"], rows: divs.map { [f.string(from: $0.date), CSV.number($0.amount)] })
    }
}

// MARK: - EVST

/// EVST: earnings event study. Abnormal returns around each earnings release (8-K item 2.02)
/// from a market model fitted before each event; average and cumulative abnormal returns with
/// cross-sectional t-statistics.
struct EventStudyView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(FundamentalsService.self) private var sec
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    enum Span: Int, CaseIterable { case five = 5, ten = 10; var label: String { "±\(rawValue) DAYS" } }
    @AppStorage("evst.benchmark") private var benchmark = "SPY"
    @AppStorage("evst.span") private var span: Span = .five

    @State private var study: EventStudy?
    @State private var loading = false
    @State private var failure: String?
    @State private var size: CGSize = .zero

    private var w: Int { span.rawValue }
    private var key: String { "\(instrument.symbol)|\(benchmark)|\(span.rawValue)|\(sec.releases[instrument.symbol]?.count ?? -1)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlBar {
                Picker("Benchmark", selection: $benchmark) { ForEach(["SPY", "QQQ", "IWM", "DIA"], id: \.self) { Text($0) } }
                    .labelsHidden().frame(maxWidth: 100)
                Picker("Window", selection: $span) { ForEach(Span.allCases, id: \.self) { Text($0.label) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 220)
                Spacer()
                if let s = study {
                    ShareLink(item: CSVFile(name: "\(instrument.ticker)-earnings-event-study.csv", text: csv(s)), preview: SharePreview("Event study")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            SectionBar(title: "\(instrument.ticker) · EARNINGS EVENT STUDY · MARKET MODEL VS \(benchmark)",
                       trailing: loading ? "LOADING…" : study.map { "\($0.events.count) RELEASES" + ($0.pending.isEmpty ? "" : " · \($0.pending.count) IN PROGRESS") })
            content
        }
        .readSize($size)
        .task(id: instrument.symbol) { await sec.loadFilings(instrument) }
        .task(id: key) { await compute() }
    }

    @ViewBuilder private var content: some View {
        if instrument.assetClass != .equity {
            EmptyNote(title: "Event studies need a company that reports earnings", detail: "Load a US-listed stock, e.g. NVDA EVST.", icon: "calendar.badge.exclamationmark")
        } else if !sec.hasValidContact {
            VStack(spacing: 12) {
                EmptyNote(title: "Earnings dates come from SEC filings",
                          detail: "SEC EDGAR asks every app to identify itself with a contact email. Add yours once in PREF; it is sent only to sec.gov.",
                          icon: "building.columns")
                Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
            }
        } else if let s = study {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !s.events.isEmpty {
                        tiles(s)
                        chart(s).frame(height: 220).padding(.horizontal, 8)
                    }
                    table(s)
                    Text("Day 0 is the first session on or after the earnings 8-K filing date. Companies usually file it the day of the release, but a filing can trail the announcement by a day or two; releases after the close move the stock on day +1, so [−1, +1] is the headline window. Each event's market model is fitted on up to 250 earlier sessions, ending 10 days before the window and skipping other earnings windows. Total returns. Releases whose window is still open (such as today's) are shown as IN PROGRESS (~ marks drift so far) and left out of the averages. t-stats are cross-sectional; |t| > 2 ≈ 95% significance; the band is ±1.96 standard errors.")
                        .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        } else if loading || sec.releases[instrument.symbol] == nil {
            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyNote(title: failure ?? "No earnings releases with enough price history", detail: "EVST covers companies that file earnings 8-Ks with the SEC.", icon: "calendar.badge.exclamationmark")
        }
    }

    /// Sessions are matched on UTC dates, so they're shown in UTC too (never a local-time Sunday).
    private static let utcDay: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()

    private func stat(_ s: EventStudy, _ from: Int, _ to: Int) -> (String, String, Color) {
        let r = s.summary(from: from, to: to)
        return (percent(r.mean, digits: 2), r.t.map { String(format: "t %.2f · %.0f%% POSITIVE", $0, r.positive * 100) } ?? "", theme.tint(r.mean))
    }

    private func tiles(_ s: EventStudy) -> some View {
        let around = stat(s, -1, 1), day0 = stat(s, 0, 0), drift = stat(s, 2, w), pre = stat(s, -w, -2)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
            StatTile(key: "CAR [−1, +1]", value: around.0, sub: around.1, color: around.2)
            StatTile(key: "DAY 0 ABNORMAL", value: day0.0, sub: day0.1, color: day0.2)
            StatTile(key: "DRIFT [+2, +\(w)]", value: drift.0, sub: drift.1, color: drift.2)
            StatTile(key: "RUN-UP [−\(w), −2]", value: pre.0, sub: pre.1, color: pre.2)
        }
        .padding(.horizontal, 8)
    }

    private func chart(_ s: EventStudy) -> some View {
        Chart {
            ForEach(Array(s.days.enumerated()), id: \.offset) { i, d in
                AreaMark(x: .value("Day", d), yStart: .value("Low", (s.caar[i] - 1.96 * s.caarSE[i]) * 100),
                         yEnd: .value("High", (s.caar[i] + 1.96 * s.caarSE[i]) * 100))
                    .foregroundStyle(Theme.accent.opacity(0.12))
                LineMark(x: .value("Day", d), y: .value("CAAR", s.caar[i] * 100)).foregroundStyle(Theme.accent).lineStyle(.init(lineWidth: 2))
                BarMark(x: .value("Day", d), y: .value("AAR", s.aar[i] * 100), width: 6).foregroundStyle(Theme.warn.opacity(0.6))
            }
            RuleMark(x: .value("Event", 0)).foregroundStyle(Theme.faint).lineStyle(.init(dash: [3, 3]))
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.faint)
        }
        .chartXAxisLabel("TRADING DAYS FROM EARNINGS (LINE: CUMULATIVE · BARS: DAILY AVERAGE ABNORMAL RETURN %)", alignment: .center)
        .chartXAxis { AxisMarks(values: .stride(by: span == .five ? 1 : 2)) { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel().foregroundStyle(Theme.dim) } }
    }

    private func table(_ s: EventStudy) -> some View {
        // Narrow panels drop β, then drift; the headline [−1, +1] window always shows.
        let shown = columnsThatFit(size.width, reserved: 200, column: 84, max: 4)
        return VStack(spacing: 0) {
            HStack {
                Text("EARNINGS (DAY 0)").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(["CAR [−1,+1]", "DAY 0", "DRIFT [+2,+\(w)]", "β (EST.)"].prefix(shown)), id: \.self) { Text($0).frame(width: 84, alignment: .trailing) }
            }
            .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8).padding(.vertical, 5)
            ForEach(Array((s.pending.reversed() + s.events.reversed()).enumerated()), id: \.offset) { n, e in
                let last = s.lastDay(e)
                let a: Double? = last >= 1 ? s.car(e, from: -1, to: 1) : nil
                let d0: Double? = last >= 0 ? s.car(e, from: 0, to: 0) : nil
                let dr: Double? = last >= w ? s.car(e, from: 2, to: w) : nil
                HStack {
                    HStack(spacing: 6) {
                        Text(Self.utcDay.string(from: e.day0)).foregroundStyle(Theme.text)
                        if last < w {
                            Text("IN PROGRESS \(last >= 0 ? "+" : "")\(last)/+\(w)").font(.mono(8, .bold)).foregroundStyle(Theme.canvas).lineLimit(1)
                                .padding(.horizontal, 4).frame(height: 14).background(Theme.warn, in: .rect(cornerRadius: 2))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    let cells: [(String, Color)] = [
                        (a.map { percent($0, digits: 2) } ?? "—", a.map { theme.tint($0) } ?? Theme.faint),
                        (d0.map { percent($0, digits: 2) } ?? "—", d0.map { theme.tint($0) } ?? Theme.faint),
                        (dr.map { percent($0, digits: 2) } ?? (last >= 2 ? "~" + percent(s.car(e, from: 2, to: last), digits: 2) : "—"), dr.map { theme.tint($0) } ?? Theme.faint),
                        (String(format: "%.2f", e.beta), Theme.dim),
                    ]
                    ForEach(0..<shown, id: \.self) { k in
                        Text(cells[k].0).foregroundStyle(cells[k].1).lineLimit(1).frame(width: 84, alignment: .trailing)
                    }
                }
                .font(.mono(11)).monospacedDigit().padding(.horizontal, 8).padding(.vertical, 4).rowBackground(n)
            }
        }
    }

    private func csv(_ s: EventStudy) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return CSV.make(header: ["Day 0", "Alpha", "Beta", "Estimation days"] + s.days.map { "AR[\($0)]" },
                        rows: (s.events + s.pending).map { e in
                            [f.string(from: e.day0), CSV.number(e.alpha, digits: 8), CSV.number(e.beta, digits: 4), String(e.estimationDays)]
                                + e.abnormal.map { CSV.number($0, digits: 8) }
                        })
    }

    private func compute() async {
        guard instrument.assetClass == .equity, let dates = sec.releases[instrument.symbol] else { study = nil; return }
        guard !dates.isEmpty else { study = nil; failure = "No earnings 8-Ks on file for \(instrument.ticker)"; return }
        guard let bench = Universe.resolve(benchmark) else { return }
        loading = true
        defer { loading = false }
        failure = nil
        let h = await market.histories([instrument, bench], range: "10y", adjusted: true, minBars: 200)
        guard !Task.isCancelled else { return }
        guard let a = h[instrument.symbol], let m = h[bench.symbol] else { study = nil; failure = "No price history"; return }
        let window = -w...w
        study = await Task.detached(priority: .userInitiated) { EventStudy.run(asset: a, market: m, events: dates, window: window) }.value
    }
}
