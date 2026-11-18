import SwiftUI
import UniformTypeIdentifiers
import KestrelCore

/// A CSV file handed to the system share sheet (Files, Mail, AirDrop…).
struct CSVFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName { $0.name }
    }
}

/// HP: daily price table with return/volatility/drawdown stats and CSV export.
struct HistoryView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    enum Span: String, CaseIterable { case m1 = "1M", m6 = "6M", y1 = "1Y", y5 = "5Y" }
    @State private var span = Span.y1
    @State private var bars: [Candle] = []
    @State private var failed = false

    private var yahooRange: String { ["1M": "1mo", "6M": "6mo", "1Y": "1y", "5Y": "5y"][span.rawValue]! }
    private var weekly: Bool { span == .y5 }
    private var perYear: Double { weekly ? 52 : (instrument.assetClass == .crypto ? 365 : 252) }

    private var shown: [Candle] {
        guard instrument.isStreaming else { return bars }
        let days = ["1M": 31, "6M": 183, "1Y": 366, "5Y": 300][span.rawValue]!
        return Array(bars.suffix(days))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Span.allCases, id: \.self) { s in
                    Button { span = s } label: {
                        Text(s.rawValue).font(.mono(10, .bold)).foregroundStyle(span == s ? Theme.canvas : Theme.dim)
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(span == s ? Theme.accent : Theme.header, in: .rect(cornerRadius: 2))
                    }.buttonStyle(.plain)
                }
                Text(weekly ? "WEEKLY BARS" : "DAILY BARS").font(.mono(9)).foregroundStyle(Theme.faint).padding(.leading, 6)
                Spacer()
                if !shown.isEmpty {
                    ShareLink(item: CSVFile(name: "\(instrument.ticker)-\(span.rawValue)-\(weekly ? "weekly" : "daily").csv",
                                            text: CSV.candles(shown, intraday: false)),
                              preview: SharePreview("\(instrument.ticker) \(span.rawValue) prices")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                            .foregroundStyle(Theme.canvas).padding(.horizontal, 8).frame(height: 22)
                            .background(Theme.accent, in: .rect(cornerRadius: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            if let s = ReturnStats(closes: shown.map(\.close), periodsPerYear: perYear) {
                HStack(spacing: 18) {
                    stat("RETURN", Fmt.pct(s.totalReturn * 100), theme.tint(s.totalReturn))
                    stat("ANN. VOL", String(format: "%.1f%%", s.annualizedVolatility * 100), Theme.text)
                    stat("MAX DRAWDOWN", Fmt.pct(s.maxDrawdown * 100), theme.down)
                    stat(weekly ? "BEST WEEK" : "BEST DAY", Fmt.pct(s.bestPeriod * 100), theme.up)
                    stat(weekly ? "WORST WEEK" : "WORST DAY", Fmt.pct(s.worstPeriod * 100), theme.down)
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
            }
            HStack {
                HeaderCell(text: "DATE", width: 110, align: .leading)
                ForEach(["OPEN", "HIGH", "LOW", "CLOSE", "CHG %", "VOLUME"], id: \.self) { HeaderCell(text: $0) }
            }
            .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.header)
            if shown.isEmpty {
                if failed { EmptyNote(title: "History unavailable", detail: "The free data source didn't answer.") }
                else { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else {
                let rows = Array(shown.enumerated()).reversed()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.element.id) { n, pair in
                            let (i, k) = pair
                            let prev = i > 0 ? shown[i - 1].close : nil
                            let chg = prev.map { (k.close / $0 - 1) * 100 }
                            HStack {
                                Text(k.time.formatted(Self.day)).foregroundStyle(Theme.dim).frame(width: 110, alignment: .leading)
                                cell(k.open); cell(k.high); cell(k.low)
                                Text(Fmt.price(k.close, instrument.assetClass)).foregroundStyle(Theme.text).bold().frame(maxWidth: .infinity, alignment: .trailing)
                                Text(Fmt.pct(chg)).foregroundStyle(theme.tint(chg)).frame(maxWidth: .infinity, alignment: .trailing)
                                Text(Fmt.compact(k.volume)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .font(.mono(11)).monospacedDigit()
                            .padding(.horizontal, 8).frame(height: 22).rowBackground(n)
                        }
                    }
                }
            }
        }
        .task(id: span) {
            failed = false
            do { bars = try await market.history(for: instrument, range: yahooRange, weekly: weekly) }
            catch { failed = true }
        }
    }

    private static let day: Date.FormatStyle = {
        var f = Date.FormatStyle.dateTime.year().month(.twoDigits).day(.twoDigits)
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }()

    private func cell(_ v: Double) -> some View {
        Text(Fmt.price(v, instrument.assetClass)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func stat(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(13, .semibold)).monospacedDigit().foregroundStyle(c)
        }
    }
}
