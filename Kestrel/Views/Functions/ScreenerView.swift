import SwiftUI
import KestrelCore

/// EQS: screen every SEC-reporting company on last year's audited fundamentals (revenue,
/// earnings, margins, returns on equity and assets, leverage). Tap a row for its FA.
struct ScreenerView: View {
    let panelID: Int
    @Environment(FundamentalsService.self) private var sec
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    enum Column: String, CaseIterable {
        case size = "SIZE", revenue = "REVENUE", income = "NET INCOME", margin = "NET MARGIN", roe = "ROE", roa = "ROA", leverage = "LIAB/ASSETS"
        func value(_ r: ScreenRow) -> Double? {
            switch self {
            case .size: Double(-r.sizeRank)
            case .revenue: r.revenue
            case .income: r.netIncome
            case .margin: r.netMargin
            case .roe: r.roe
            case .roa: r.roa
            case .leverage: r.leverage
            }
        }
    }

    @AppStorage("eqs.minRevenue") private var minRevenue = 0.0
    @AppStorage("eqs.minMargin") private var minMargin = -1.0
    @AppStorage("eqs.minROE") private var minROE = -1.0
    @AppStorage("eqs.maxLeverage") private var maxLeverage = 10.0
    @AppStorage("eqs.sort") private var sort: Column = .size
    @AppStorage("eqs.descending") private var descending = true
    @State private var text = ""
    @State private var size: CGSize = .zero

    /// Columns in display order; narrow panels keep the highest-priority ones.
    private var columns: [Column] {
        let priority: [Column] = [.revenue, .margin, .roe, .income, .roa, .leverage]
        let keep = Set(priority.prefix(columnsThatFit(size.width, reserved: 190, column: 84, max: 6)))
        return [Column.revenue, .income, .margin, .roe, .roa, .leverage].filter(keep.contains)
    }

    private static let revenueSteps: [(String, Double)] = [("ANY", 0), ("$100M+", 1e8), ("$1B+", 1e9), ("$10B+", 1e10), ("$100B+", 1e11)]
    private static let marginSteps: [(String, Double)] = [("ANY", -1), ("PROFITABLE", 0), ("10%+", 0.1), ("20%+", 0.2)]
    private static let roeSteps: [(String, Double)] = [("ANY", -1), ("10%+", 0.1), ("15%+", 0.15), ("25%+", 0.25)]
    private static let leverageSteps: [(String, Double)] = [("ANY", 10), ("< 80%", 0.8), ("< 60%", 0.6), ("< 40%", 0.4)]
    private static let shown = 250

    private func passes(_ r: ScreenRow) -> Bool {
        if minRevenue > 0, (r.revenue ?? 0) < minRevenue { return false }
        if minMargin > -1, (r.netMargin ?? -.infinity) < minMargin { return false }
        if minROE > -1, (r.roe ?? -.infinity) < minROE { return false }
        if maxLeverage < 10, (r.leverage ?? .infinity) > maxLeverage { return false }
        let q = text.trimmingCharacters(in: .whitespaces).uppercased()
        return q.isEmpty || r.ticker.hasPrefix(q) || r.name.uppercased().contains(q)
    }

    private func filtered(_ rows: [ScreenRow]) -> [ScreenRow] {
        rows.filter(passes).sorted { a, b in
            switch (sort.value(a), sort.value(b)) {
            case let (x?, y?): descending ? x > y : x < y
            case (nil, _?): false
            case (_?, nil): true
            default: a.sizeRank < b.sizeRank
            }
        }
    }

    var body: some View {
        Group {
            if !sec.hasValidContact {
                VStack(spacing: 12) {
                    EmptyNote(title: "The screener needs a contact email",
                              detail: "SEC EDGAR is free, but asks every app to identify itself with a contact email. Add yours once in PREF; it is sent only to sec.gov.",
                              icon: "building.columns")
                    Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
                }
            } else {
                switch sec.screen {
                case .idle, .loading:
                    ProgressView("Loading annual filings for every SEC registrant…").tint(Theme.accent).font(.mono(10))
                        .foregroundStyle(Theme.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let why):
                    EmptyNote(title: "SEC request failed", detail: why, icon: "exclamationmark.triangle")
                case .ready(let rows, let year):
                    content(rows, year: year)
                }
            }
        }
        .readSize($size)
        .task(id: sec.hasValidContact) { await sec.loadScreen() }
    }

    private func content(_ all: [ScreenRow], year: Int) -> some View {
        let rows = filtered(all)
        return VStack(alignment: .leading, spacing: 0) {
            filters(rows, year: year)
            SectionBar(title: "EQUITY SCREEN · FY\(year) 10-K DATA · SEC XBRL",
                       trailing: "\(rows.count) OF \(all.count) COMPANIES\(rows.count > Self.shown ? " · TOP \(Self.shown) SHOWN" : "")")
            header
            if rows.isEmpty {
                EmptyNote(title: "No companies pass these filters", detail: "Loosen a filter.", icon: "line.3.horizontal.decrease.circle")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.prefix(Self.shown).enumerated()), id: \.element.id) { n, r in row(r).rowBackground(n) }
                    }
                }
            }
        }
    }

    private func filters(_ rows: [ScreenRow], year: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("", text: $text)
                    .accessibilityLabel("Filter companies by name or ticker")
                    .placeholder("filter by name or ticker", when: text.isEmpty)
                    .font(.mono(11, .medium)).foregroundStyle(Theme.text).textFieldStyle(.plain).autocorrectionDisabled()
                    .padding(6).background(Theme.canvas).overlay(Rectangle().stroke(Theme.rule)).frame(maxWidth: 240.pt)
                Spacer()
                Button("RESET") { minRevenue = 0; minMargin = -1; minROE = -1; maxLeverage = 10; text = "" }
                    .font(.mono(10, .bold)).foregroundStyle(Theme.dim).buttonStyle(.terminal)
                CopyTableButton(csv: csv(rows))
                ShareLink(item: CSVFile(name: "screen-FY\(year).csv", text: csv(rows)), preview: SharePreview("Screen results")) {
                    Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
                }
                .buttonStyle(.terminal).foregroundStyle(Theme.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    step("REVENUE", Self.revenueSteps, $minRevenue)
                    step("NET MARGIN", Self.marginSteps, $minMargin)
                    step("ROE", Self.roeSteps, $minROE)
                    step("LIAB/ASSETS", Self.leverageSteps, $maxLeverage)
                }
            }
        }
        .padding(8)
    }

    private func step(_ title: String, _ options: [(String, Double)], _ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            Picker(title, selection: value) { ForEach(options, id: \.1) { Text($0.0).tag($0.1) } }
                .labelsHidden().font(.mono(10)).fixedSize()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            sortButton(.size, "COMPANY").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { c in
                sortButton(c, c.rawValue).frame(width: 84.pt, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func sortButton(_ c: Column, _ title: String) -> some View {
        Button {
            if sort == c { descending.toggle() } else { sort = c; descending = true }
        } label: {
            Text(title + (sort == c ? (descending ? " ▼" : " ▲") : ""))
                .font(.mono(9, .bold)).foregroundStyle(sort == c ? Theme.accent : Theme.label)
        }
        .buttonStyle(.terminal)
    }

    private func row(_ r: ScreenRow) -> some View {
        Button {
            if let i = Universe.resolve(r.ticker, hint: .equity) { ws.load(Command(function: .fa, instrument: i), in: panelID) }
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(r.ticker).font(.mono(11, .bold)).foregroundStyle(Theme.accent).lineLimit(1).frame(width: 58.pt, alignment: .leading)
                    Text(r.name).font(.ui(11)).foregroundStyle(Theme.text).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(columns, id: \.self) { c in
                    Group {
                        switch c {
                        case .revenue: Text(Fmt.compact(r.revenue)).foregroundStyle(Theme.text)
                        case .income: Text(Fmt.compact(r.netIncome)).foregroundStyle(theme.tint(r.netIncome))
                        case .margin: pct(r.netMargin, tinted: true)
                        case .roe: pct(r.roe, tinted: true)
                        case .roa: pct(r.roa, tinted: true)
                        case .leverage, .size: pct(r.leverage, tinted: false)
                        }
                    }
                    .font(.mono(11)).monospacedDigit().lineLimit(1).frame(width: 84.pt, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5).contentShape(.rect)
        }
        .buttonStyle(.terminal)
    }

    private func pct(_ v: Double?, tinted: Bool) -> some View {
        Text(v.map { abs($0) >= 10 ? ">999%" : String(format: "%.1f%%", $0 * 100) } ?? "—")
            .foregroundStyle(v == nil ? Theme.faint : (tinted ? theme.tint(v) : Theme.text))
    }

    private func csv(_ rows: [ScreenRow]) -> String {
        CSV.make(header: ["Ticker", "Company", "CIK", "SEC size rank", "Revenue", "Net income", "Total assets", "Total liabilities",
                          "Stockholders equity", "Net margin", "ROE", "ROA", "Liabilities/assets"],
                 rows: rows.map { r in
                     [r.ticker, r.name, String(r.cik), String(r.sizeRank), CSV.number(r.revenue, digits: 0), CSV.number(r.netIncome, digits: 0),
                      CSV.number(r.assets, digits: 0), CSV.number(r.liabilities, digits: 0), CSV.number(r.equity, digits: 0),
                      CSV.number(r.netMargin), CSV.number(r.roe), CSV.number(r.roa), CSV.number(r.leverage)]
                 })
    }
}
