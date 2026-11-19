import SwiftUI
import KestrelCore

/// RV: the company against same-industry peers (SEC SIC code), sized by revenue and valued at delayed prices.
struct ValuationView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(FundamentalsService.self) private var sec
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    enum Column: String, CaseIterable {
        case cap = "MKT CAP", pe = "P/E", ps = "P/S", pb = "P/B", revenue = "REVENUE", growth = "REV GROWTH", margin = "NET MARGIN", roe = "ROE", leverage = "LIAB/ASSETS"
        func value(_ r: RelativeValuation.Row) -> Double? {
            switch self {
            case .cap: r.marketCap
            case .pe: r.pe
            case .ps: r.ps
            case .pb: r.pb
            case .revenue: r.revenue
            case .growth: r.growth
            case .margin: r.margin
            case .roe: r.roe
            case .leverage: r.leverage
            }
        }
        func format(_ v: Double?) -> String {
            guard let v, v.isFinite else { return "—" }
            switch self {
            case .cap: return "$" + Fmt.compact(v)
            case .pe, .ps, .pb: return String(format: "%.1fx", v)
            case .revenue: return Fmt.compact(v)
            case .growth, .margin, .roe: return Fmt.pct(v * 100)
            case .leverage: return String(format: "%.0f%%", v * 100)
            }
        }
    }

    @State private var size: CGSize = .zero
    private var columns: [Column] {
        let priority: [Column] = [.pe, .cap, .margin, .growth, .ps, .roe, .revenue, .pb, .leverage]
        let keep = Set(priority.prefix(columnsThatFit(size.width, reserved: 200, column: 82, max: 9)))
        return Column.allCases.filter(keep.contains)
    }

    private func instrument(for ticker: String) -> Instrument? { Universe.resolve(ticker, hint: .equity) }

    private func rows(_ d: FundamentalsService.RVData) -> [RelativeValuation.Row] {
        ([d.target] + d.peers).enumerated().map { k, r in
            let price = instrument(for: r.ticker).flatMap { market.quotes[$0.symbol]?.last }
            return RelativeValuation.row(r, isTarget: k == 0, price: price, shares: d.shares[r.cik], priorRevenue: d.priorRevenue[r.cik])
        }
    }

    var body: some View {
        Group {
            if instrument.assetClass != .equity {
                EmptyNote(title: "RV compares companies", detail: "Load a US-listed stock, e.g. AAPL RV.", icon: "building.2")
            } else if !sec.hasValidContact {
                VStack(spacing: 12) {
                    EmptyNote(title: "RV needs a contact email",
                              detail: "SEC EDGAR is free, but asks every app to identify itself with a contact email. Add yours once in PREF; it is sent only to sec.gov.",
                              icon: "building.columns")
                    Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
                }
            } else {
                switch sec.rv[instrument.symbol] {
                case .ready(let d): table(d)
                case .notFound: EmptyNote(title: "\(instrument.ticker) doesn't file with the SEC", detail: "RV uses SEC annual reports, so it covers US-listed companies.", icon: "building.2")
                case .noData(let y): EmptyNote(title: "No \(y.map { "FY\($0) " } ?? "")annual data for \(instrument.ticker) yet", detail: "It appears once the company's 10-K is in SEC's XBRL frames.", icon: "calendar")
                case .failed(let e): EmptyNote(title: "SEC request failed", detail: e, icon: "exclamationmark.triangle")
                default:
                    ProgressView("Finding industry peers in SEC filings…").tint(Theme.accent).font(.mono(10)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: instrument.symbol) { await sec.loadRV(instrument) }
    }

    private func table(_ d: FundamentalsService.RVData) -> some View {
        let all = rows(d), target = all[0], peers = Array(all.dropFirst())
        let median = Dictionary(uniqueKeysWithValues: Column.allCases.map { c in (c, RelativeValuation.median(peers.map { c.value($0) })) })
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SIC \(d.sic) · \(d.industry.uppercased())\(d.widened ? " · WIDENED TO \(d.sic.prefix(3))x" : "")")
                        .font(.mono(10, .bold)).foregroundStyle(Theme.label)
                    Spacer()
                    ShareLink(item: CSVFile(name: "\(instrument.ticker)-relative-valuation.csv", text: csv(all)), preview: SharePreview("Relative valuation")) {
                        Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                    }
                    .buttonStyle(.terminal).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 1)], spacing: 1) {
                    tile("P/E VS PEERS", target.pe, median[.pe] ?? nil, .pe)
                    tile("P/S VS PEERS", target.ps, median[.ps] ?? nil, .ps)
                    StatTile(key: "NET MARGIN", value: Column.margin.format(target.margin), sub: "PEER MEDIAN \(Column.margin.format(median[.margin] ?? nil))",
                             color: theme.tint((target.margin ?? 0) - ((median[.margin] ?? nil) ?? 0)))
                    StatTile(key: "REVENUE GROWTH", value: Column.growth.format(target.growth), sub: "PEER MEDIAN \(Column.growth.format(median[.growth] ?? nil))",
                             color: theme.tint((target.growth ?? 0) - ((median[.growth] ?? nil) ?? 0)))
                }
                .background(Theme.rule).padding(.horizontal, 8)
                SectionBar(title: "\(instrument.ticker) VS \(peers.count) PEERS · FY\(d.year) 10-K · CLOSEST IN REVENUE", trailing: "\(d.filers) FILERS IN THIS INDUSTRY")
                if peers.isEmpty {
                    EmptyNote(title: "No peers with annual data in this industry", detail: "SEC lists no other 10-K filer under this code with complete figures.", icon: "person.2.slash")
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            HeaderCell(text: "COMPANY", width: 190.pt, align: .leading)
                            ForEach(columns, id: \.self) { HeaderCell(text: $0.rawValue) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        ForEach(Array(all.enumerated()), id: \.element.id) { n, r in
                            Button { if let i = instrument(for: r.ticker) { ws.load(Command(function: .fa, instrument: i), in: panelID) } } label: {
                                HStack(spacing: 0) {
                                    HStack(spacing: 6) {
                                        Text(r.ticker).font(.mono(11, .bold)).foregroundStyle(Theme.accent)
                                        Text(r.name).font(.ui(11)).foregroundStyle(Theme.text).lineLimit(1)
                                        if r.isTarget { Text("TARGET").font(.mono(8, .heavy)).foregroundStyle(Theme.canvas).padding(.horizontal, 4).background(Theme.accent) }
                                    }
                                    .frame(width: 190.pt, alignment: .leading)
                                    ForEach(columns, id: \.self) { c in
                                        Text(c.format(c.value(r))).font(.mono(11)).monospacedDigit().foregroundStyle(Theme.text)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                .padding(.horizontal, 8).frame(minHeight: 26.pt).rowBackground(n)
                                .overlay(r.isTarget ? Rectangle().stroke(Theme.accentDim) : nil)
                            }
                            .buttonStyle(.terminal)
                            .accessibilityLabel("\(r.ticker), \(r.name)\(r.isTarget ? ", target" : ""): P/E \(Column.pe.format(r.pe)), market cap \(Column.cap.format(r.marketCap)), net margin \(Column.margin.format(r.margin))")
                            .accessibilityHint("Opens financials")
                        }
                        HStack(spacing: 0) {
                            Text("PEER MEDIAN").font(.mono(10, .bold)).foregroundStyle(Theme.label).frame(width: 190.pt, alignment: .leading)
                            ForEach(columns, id: \.self) { c in
                                Text(c.format(median[c] ?? nil)).font(.mono(11)).monospacedDigit().foregroundStyle(Theme.label).frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 8).frame(minHeight: 26.pt)
                    }
                    .readSize($size)
                }
                Text("Peers: other 10-K filers under the same SEC SIC industry code (or its 3-digit group when the code has fewer than 5), closest in revenue. Market cap = delayed price × shares outstanding from the latest SEC filing. P/E is blank for losses. Tap a row for its financials.")
                    .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
        .task(id: d.peers.map(\.ticker).joined()) {
            for r in [d.target] + d.peers { if let i = instrument(for: r.ticker) { market.touch(i) } }
        }
    }

    private func tile(_ key: String, _ v: Double?, _ med: Double?, _ c: Column) -> some View {
        StatTile(key: key, value: RelativeValuation.premium(v, med).map { String(format: "%+.0f%%", $0 * 100) } ?? "—",
                 sub: "\(c.format(v)) VS MEDIAN \(c.format(med))")
    }

    private func csv(_ rows: [RelativeValuation.Row]) -> String {
        CSV.make(header: ["Ticker", "Company", "Price", "Market cap", "P/E", "P/S", "P/B", "Revenue", "Revenue growth", "Net margin", "ROE", "Liabilities/assets"],
                 rows: rows.map { r in
                     [r.ticker, r.name, CSV.number(r.price), CSV.number(r.marketCap, digits: 0), CSV.number(r.pe), CSV.number(r.ps), CSV.number(r.pb),
                      CSV.number(r.revenue, digits: 0), CSV.number(r.growth), CSV.number(r.margin), CSV.number(r.roe), CSV.number(r.leverage)]
                 })
    }
}
