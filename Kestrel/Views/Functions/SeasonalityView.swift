import SwiftUI
import Charts
import KestrelCore

/// SEAS: average return in each calendar month, from Yahoo's monthly total-return history. Mirrors web Seasonality.tsx.
struct SeasonalityView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    enum Span: String, CaseIterable {
        case y5 = "5Y", y10 = "10Y", all = "ALL"
        var yahoo: String { self == .all ? "max" : rawValue.lowercased() }
    }

    struct Result { var rets: [Seasonality.MonthReturn]; var stats: [Seasonality.MonthStat] }

    @AppStorage("seas.span") private var span: Span = .y10
    @State private var result: Result?
    @State private var error: String?

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private var now: Int { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c.component(.month, from: .now) - 1 }

    private func pc(_ v: Double?, _ d: Int = 1) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%+.\(d)f%%", v * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("History", selection: $span) { ForEach(Span.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 200.pt)
                    .accessibilityLabel("History length")
                Spacer()
                if let r = result {
                    CopyTableButton(csv: csv(r))
                    ShareLink(item: CSVFile(name: "\(instrument.ticker)-seasonality.csv", text: csv(r)), preview: SharePreview("Seasonality")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                    }
                    .buttonStyle(.terminal).foregroundStyle(Theme.accent)
                }
            }
            .padding(8)
            content
        }
        .task(id: "\(instrument.symbol)|\(span.rawValue)") { await load() }
    }

    @ViewBuilder private var content: some View {
        if instrument.assetClass == .option {
            EmptyNote(title: "Seasonality needs a price history", detail: "Try CL1 SEAS, SPY SEAS or BTC SEAS.", icon: "calendar")
        } else if let error {
            EmptyNote(title: "History unavailable", detail: error, icon: "exclamationmark.triangle")
        } else if let r = result {
            if r.rets.count < 12 {
                EmptyNote(title: "Not enough monthly history", detail: "Seasonality needs at least a year of monthly closes.", icon: "calendar")
            } else {
                report(r)
            }
        } else {
            ProgressView("Loading monthly history…").tint(Theme.accent).font(.mono(10)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func report(_ r: Result) -> some View {
        let ranked = r.stats.filter { $0.mean != nil }.sorted { $0.mean! > $1.mean! }
        let best = ranked.first!, worst = ranked.last!, cur = r.stats[now]
        func up(_ s: Seasonality.MonthStat) -> String { String(format: "%.0f%%", (s.positive ?? 0) * 100) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
                    StatTile(key: "STRONGEST MONTH", value: Self.months[best.month], sub: "AVG \(pc(best.mean)) · UP \(up(best)) OF YEARS", color: theme.up)
                    StatTile(key: "WEAKEST MONTH", value: Self.months[worst.month], sub: "AVG \(pc(worst.mean)) · UP \(up(worst)) OF YEARS", color: theme.down)
                    StatTile(key: "\(Self.months[now]) (THIS MONTH)", value: pc(cur.mean), sub: "UP IN \(up(cur)) OF \(cur.n) YEARS", color: theme.tint(cur.mean))
                }
                .background(Theme.rule).padding(.horizontal, 8)
                SectionBar(title: "\(instrument.ticker) · AVERAGE RETURN BY CALENDAR MONTH",
                           trailing: "\(r.rets.first!.year)–\(r.rets.last!.year) · \(r.rets.count) MONTHS")
                Chart(r.stats) { s in
                    BarMark(x: .value("Month", Self.months[s.month]), y: .value("Average", (s.mean ?? 0) * 100))
                        .foregroundStyle(((s.mean ?? 0) >= 0 ? theme.up : theme.down).opacity(s.month == now ? 1 : 0.6))
                        .annotation(position: (s.mean ?? 0) >= 0 ? .top : .bottom) {
                            Text(String(format: "%.1f", (s.mean ?? 0) * 100)).font(.mono(8)).foregroundStyle(Theme.dim)
                        }
                }
                .chartXScale(domain: Self.months)
                .chartYAxis { AxisMarks { v in AxisGridLine().foregroundStyle(Theme.rule); AxisValueLabel { if let d = v.as(Double.self) { Text("\(d, specifier: "%.0f")%").font(.mono(9)).foregroundStyle(Theme.dim) } } } }
                .chartXAxis { AxisMarks { v in AxisValueLabel { if let m = v.as(String.self) { Text(m).font(.mono(9)).foregroundStyle(Theme.dim) } } } }
                .frame(height: 190.pt).padding(.horizontal, 8)
                .accessibilityLabel("Average return by month. Strongest \(Self.months[best.month]) \(pc(best.mean)), weakest \(Self.months[worst.month]) \(pc(worst.mean)).")
                table(r)
                Text("Monthly total returns (dividends reinvested) from month-end closes; the current month is left out until it ends. Past seasonality is a tendency, not a forecast.")
                    .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
            }
            .padding(.bottom, 8)
        }
    }

    private func table(_ r: Result) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HeaderCell(text: "MONTH", width: 70.pt, align: .leading)
                ForEach(["AVERAGE", "MEDIAN", "% UP", "BEST", "WORST", "YEARS"], id: \.self) { HeaderCell(text: $0) }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            ForEach(r.stats) { s in
                HStack(spacing: 0) {
                    Text(Self.months[s.month]).font(.mono(11, .bold)).foregroundStyle(Theme.text).frame(width: 70.pt, alignment: .leading)
                    cell(pc(s.mean, 2), theme.tint(s.mean))
                    cell(pc(s.median, 2), theme.tint(s.median))
                    cell(s.positive.map { String(format: "%.0f%%", $0 * 100) } ?? "—", Theme.text)
                    cell(pc(s.best), theme.up)
                    cell(pc(s.worst), theme.down)
                    cell("\(s.n)", Theme.dim)
                }
                .padding(.horizontal, 8).frame(minHeight: 24.pt).rowBackground(s.month)
                .overlay(s.month == now ? Rectangle().stroke(Theme.accentDim) : nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Self.months[s.month]): average \(pc(s.mean, 2)), up in \(s.positive.map { String(format: "%.0f", $0 * 100) } ?? "0") percent of \(s.n) years, best \(pc(s.best)), worst \(pc(s.worst))")
            }
        }
    }

    private func cell(_ t: String, _ c: Color) -> some View {
        Text(t).font(.mono(11)).monospacedDigit().foregroundStyle(c).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func load() async {
        guard instrument.assetClass != .option else { return }
        result = nil; error = nil
        do {
            let rets = Seasonality.monthlyReturns(try await market.monthly(for: instrument, range: span.yahoo))
            result = Result(rets: rets, stats: Seasonality.stats(rets))
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func csv(_ r: Result) -> String {
        CSV.make(header: ["Month", "Average return", "Median return", "Share positive", "Best", "Worst", "Years"],
                 rows: r.stats.map { s in [Self.months[s.month], CSV.number(s.mean), CSV.number(s.median), CSV.number(s.positive), CSV.number(s.best), CSV.number(s.worst), "\(s.n)"] })
    }
}
