import SwiftUI
import KestrelCore

/// FA: five fiscal years of 10-K financials straight from SEC EDGAR, with margins, growth and a
/// trend bar per line.
struct FundamentalsView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(FundamentalsService.self) private var sec
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme
    @Environment(\.openURL) private var openURL

    private enum Kind { case money, perShare, percent }
    private struct Line {
        let label: String
        let kind: Kind
        let value: (FiscalYear) -> Double?
        var growth: KeyPath<FiscalYear, Double?>? = nil
        var bold = false
    }

    private let lines: [Line] = [
        Line(label: "Revenue", kind: .money, value: { $0.revenue }, growth: \.revenue, bold: true),
        Line(label: "  Gross margin", kind: .percent, value: { $0.grossMargin }),
        Line(label: "Operating income", kind: .money, value: { $0.operatingIncome }, growth: \.operatingIncome),
        Line(label: "  Operating margin", kind: .percent, value: { $0.operatingMargin }),
        Line(label: "Net income", kind: .money, value: { $0.netIncome }, growth: \.netIncome, bold: true),
        Line(label: "  Net margin", kind: .percent, value: { $0.netMargin }),
        Line(label: "Diluted EPS (as reported)", kind: .perShare, value: { $0.epsDiluted }, growth: \.epsDiluted),
        Line(label: "Operating cash flow", kind: .money, value: { $0.operatingCashFlow }),
        Line(label: "Capital expenditure", kind: .money, value: { $0.capex.map { -$0 } }),
        Line(label: "Free cash flow", kind: .money, value: { $0.freeCashFlow }, growth: \.freeCashFlow, bold: true),
        Line(label: "Cash & equivalents", kind: .money, value: { $0.cash }),
        Line(label: "Long-term debt", kind: .money, value: { $0.longTermDebt }),
        Line(label: "Shareholders' equity", kind: .money, value: { $0.equity }),
        Line(label: "  Return on equity", kind: .percent, value: { $0.returnOnEquity }),
        Line(label: "  Debt / equity", kind: .percent, value: { $0.debtToEquity }),
    ]

    var body: some View {
        Group {
            switch sec.state(for: instrument) {
            case .needsContact:
                VStack(spacing: 12) {
                    EmptyNote(title: "Fundamentals need a contact email",
                              detail: "SEC EDGAR is free, but asks every app to identify itself with a contact email. Add yours once in PREF; it is sent only to sec.gov.",
                              icon: "building.columns")
                    Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
                }
            case .loading:
                ProgressView("Loading 10-K data from SEC…").tint(Theme.accent).font(.mono(10)).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                EmptyNote(title: "No SEC filings for \(instrument.ticker)",
                          detail: "FA covers US-listed companies that file 10-Ks. ETFs, indices, FX and crypto don't file.", icon: "doc.text.magnifyingglass")
            case .failed(let why):
                EmptyNote(title: "SEC request failed", detail: why, icon: "exclamationmark.triangle")
            case .ready(let f):
                table(f)
            }
        }
        .task(id: "\(instrument.symbol)|\(sec.hasValidContact)") { await sec.load(instrument) }
    }

    private func table(_ f: CompanyFundamentals) -> some View {
        let years = f.years
        let price = market.quotes[instrument.symbol]?.last
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    kv("MARKET CAP", price.flatMap { f.marketCap(price: $0) }.map { "$" + Fmt.compact($0) } ?? "—")
                    kv("P/E (FY EPS)", price.flatMap { f.priceToEarnings(price: $0) }.map { String(format: "%.1fx", $0) } ?? "—")
                    kv("FCF YIELD", { () -> String in
                        guard let p = price, let cap = f.marketCap(price: p), cap > 0, let fcf = f.latest?.freeCashFlow else { return "—" }
                        return Fmt.pct(fcf / cap * 100)
                    }())
                    kv("SHARES", Fmt.compact(f.sharesOutstanding))
                    Spacer()
                    Button { openURL(SECFacts.filingURL(cik: f.cik)) } label: {
                        Text("SEC 10-K FILINGS ↗").font(.mono(9, .bold)).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)

                HStack(spacing: 0) {
                    HeaderCell(text: "USD · FISCAL YEAR", width: 200.pt, align: .leading)
                    ForEach(years) { y in HeaderCell(text: "FY\(y.year % 100)") }
                    HeaderCell(text: "YOY", width: 64.pt)
                    HeaderCell(text: "TREND", width: 70.pt, align: .center)
                }
                .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.header)

                ForEach(Array(lines.enumerated()), id: \.offset) { n, line in
                    row(line, years, f).rowBackground(n)
                }

                Text("Source: SEC EDGAR XBRL company facts, annual 10-K figures. Period ends \(years.map { $0.periodEnd.formatted(.dateTime.month(.abbreviated).year()) }.joined(separator: ", ")). EPS is as reported (not split-adjusted for older years).")
                    .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
    }

    private func row(_ line: Line, _ years: [FiscalYear], _ f: CompanyFundamentals) -> some View {
        let values = years.map(line.value)
        let yoy: Double? = { guard let g = line.growth, let y = years.last else { return nil }; return f.growth(g, year: y.year) }()
        return HStack(spacing: 0) {
            Text(line.label).font(.ui(11, line.bold ? .semibold : .regular))
                .foregroundStyle(line.kind == .percent ? Theme.dim : Theme.text)
                .frame(width: 200.pt, alignment: .leading).lineLimit(1)
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                Text(format(v, line.kind)).font(.mono(11, line.bold ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle((v ?? 0) < 0 ? theme.down : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Text(yoy.map { Fmt.pct($0 * 100) } ?? "").font(.mono(10)).foregroundStyle(theme.tint(yoy))
                .frame(width: 64.pt, alignment: .trailing)
            TrendBars(values: values).frame(width: 70.pt, height: 14.pt)
        }
        .padding(.horizontal, 8).frame(height: 24.pt)
    }

    private func format(_ v: Double?, _ kind: Kind) -> String {
        guard let v else { return "—" }
        switch kind {
        case .money: return (v < 0 ? "-" : "") + Fmt.compact(abs(v))
        case .perShare: return String(format: "%.2f", v)
        case .percent: return String(format: "%.1f%%", v * 100)
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(13, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
        }
    }
}

/// Tiny per-row bar chart: one bar per year, negative values hang below the baseline.
struct TrendBars: View {
    let values: [Double?]
    @Environment(Theme.self) private var theme

    var body: some View {
        Canvas { ctx, size in
            let vs = values.compactMap { $0 }
            guard let hi = vs.map(abs).max(), hi > 0 else { return }
            let hasNeg = vs.contains { $0 < 0 }
            let base = hasNeg ? size.height / 2 : size.height
            let scale = (hasNeg ? size.height / 2 : size.height) / hi
            let w = size.width / CGFloat(max(values.count, 1))
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let h = CGFloat(abs(v)) * scale
                let r = CGRect(x: CGFloat(i) * w + 1, y: v >= 0 ? base - h : base, width: max(w - 2, 1), height: max(h, 0.5))
                ctx.fill(Path(r), with: .color((v >= 0 ? Theme.accent : theme.down).opacity(i == values.count - 1 ? 1 : 0.55)))
            }
        }
    }
}
