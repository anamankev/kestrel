import SwiftUI
import KestrelCore

// MARK: - W: monitor

/// W: the active user watchlist, editable in place. Streaming and delayed securities are split
/// into separate sections so nobody mistakes a delayed print for a live one.
struct MonitorView: View {
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(UserData.self) private var user

    @State private var addText = ""
    @State private var addError: String?
    @State private var naming: NameMode?
    @State private var nameText = ""
    @State private var confirmDelete = false

    enum NameMode { case new, rename }

    private var instruments: [Instrument] {
        user.active.symbols.compactMap { Universe.instrument(symbol: $0) ?? Universe.resolve($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { g in
                let wide = g.size.width > 900
                let live = instruments.filter(\.isStreaming), delayed = instruments.filter { !$0.isStreaming }
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        if !live.isEmpty {
                            Section { rows(live, wide) } header: {
                                VStack(spacing: 0) { SectionBar(title: "STREAMING", trailing: "COINBASE"); QuoteHeader(wide: wide) }
                            }
                        }
                        if !delayed.isEmpty {
                            Section { rows(delayed, wide) } header: {
                                VStack(spacing: 0) { SectionBar(title: "DELAYED", trailing: refreshed); QuoteHeader(wide: wide) }
                            }
                        }
                    }
                }
                .overlay {
                    if instruments.isEmpty {
                        EmptyNote(title: "\(user.active.name) is empty", detail: "Type a ticker in the ADD box (AAPL, BTC, SPX, EURUSD).", icon: "list.bullet")
                    }
                }
            }
        }
        .alert(naming == .new ? "New watchlist" : "Rename watchlist", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameText)
            Button("Cancel", role: .cancel) {}
            Button(naming == .new ? "Create" : "Rename") {
                if naming == .new { user.newList(nameText) } else { user.renameActive(nameText) }
            }
        }
        .confirmationDialog("Delete \(user.active.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) { user.deleteActive() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Watchlists") {
                    ForEach(user.watchlists) { w in
                        Button { user.select(w.id) } label: {
                            if w.id == user.activeID { Label("\(w.name) (\(w.symbols.count))", systemImage: "checkmark") }
                            else { Text("\(w.name) (\(w.symbols.count))") }
                        }
                    }
                }
                Divider()
                Button("New list…") { nameText = ""; naming = .new }
                Button("Rename…") { nameText = user.active.name; naming = .rename }
                if user.watchlists.count > 1 { Button("Delete list…", role: .destructive) { confirmDelete = true } }
            } label: {
                HStack(spacing: 4) {
                    Text(user.active.name).font(.mono(11, .heavy)).foregroundStyle(Theme.text)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 8).frame(height: 24)
                .background(Theme.header, in: .rect(cornerRadius: 3))
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()

            HStack(spacing: 0) {
                Text("ADD").font(.mono(9, .heavy)).foregroundStyle(Theme.canvas).padding(.horizontal, 6).frame(height: 24).background(Theme.accent)
                TextField("", text: $addText, prompt: Text("ticker ↩").foregroundStyle(Theme.faint))
                    .font(.mono(11, .medium)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .padding(.horizontal, 6)
                    .onSubmit {
                        addError = user.add(addText)
                        if addError == nil { addText = "" }
                    }
                    .onChange(of: addText) { addError = nil }
            }
            .frame(maxWidth: 200).frame(height: 24)
            .background(Theme.canvas).overlay(Rectangle().stroke(Theme.rule))

            if let addError { Text(addError).font(.mono(10, .medium)).foregroundStyle(Theme.cancel).lineLimit(1) }
            Spacer(minLength: 0)
            Text("\(user.active.symbols.count)/\(Watchlist.maxSymbols)").font(.mono(9)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    private var refreshed: String {
        market.lastEquityRefresh.map { "UPDATED \($0.formatted(Fmt.clock))" } ?? "LOADING…"
    }

    private func rows(_ list: [Instrument], _ wide: Bool) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { n, i in
            QuoteRow(instrument: i, panelID: panelID, wide: wide, editable: true).rowBackground(n)
        }
    }
}

struct QuoteHeader: View {
    var wide: Bool
    var yields = false

    var body: some View {
        HStack(spacing: 6) {
            HeaderCell(text: "SECURITY", width: wide ? 210 : 130, align: .leading)
            HeaderCell(text: yields ? "YIELD" : "LAST")
            HeaderCell(text: yields ? "CHG BP" : "NET")
            HeaderCell(text: "%CHG")
            if wide && !yields {
                HeaderCell(text: "BID"); HeaderCell(text: "ASK")
                HeaderCell(text: "HIGH"); HeaderCell(text: "LOW"); HeaderCell(text: "VOLUME")
            }
            HeaderCell(text: "INTRADAY", width: 74, align: .center)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }
}

struct QuoteRow: View {
    let instrument: Instrument
    let panelID: Int
    var wide: Bool
    var yields = false
    var editable = false
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws
    @Environment(UserData.self) private var user

    var body: some View {
        let i = instrument
        let q = market.quotes[i.symbol]
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(i.ticker).font(.mono(12, .bold)).foregroundStyle(Theme.text).frame(width: 64, alignment: .leading)
                Text(market.displayName(i)).font(.ui(11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(width: wide ? 210 : 130, alignment: .leading)
            TickText(value: q?.last, cls: i.assetClass).frame(maxWidth: .infinity, alignment: .trailing)
            Group {
                if yields {
                    ChangeText(value: q?.change.map { $0 * 100 }, cls: .equity)
                } else {
                    ChangeText(value: q?.change, cls: i.assetClass)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            ChangeText(value: q?.changePercent, percent: true).frame(maxWidth: .infinity, alignment: .trailing)
            if wide && !yields {
                cell(Fmt.price(q?.bid, i.assetClass)); cell(Fmt.price(q?.ask, i.assetClass))
                cell(Fmt.price(q?.high, i.assetClass)); cell(Fmt.price(q?.low, i.assetClass))
                cell(Fmt.compact(q?.volume))
            }
            Sparkline(values: market.sparks[i.symbol] ?? [], baseline: q?.previousClose)
                .frame(width: 74, height: 18)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(.rect)
        .onTapGesture { ws.link(i, from: panelID) }
        .contextMenu {
            ForEach([TerminalFunction.des, .fa, .gp, .depth, .tas, .cn, .omon, .trade], id: \.self) { f in
                Button("\(f.rawValue) — \(f.title)") { ws.load(Command(function: f, instrument: i), in: panelID) }
            }
            Divider()
            Button("Set alert…", systemImage: "bell") { ws.load(Command(function: .alrt, instrument: i), in: panelID) }
            if editable {
                Button("Move up", systemImage: "arrow.up") { user.move(i.symbol, by: -1) }
                Button("Move down", systemImage: "arrow.down") { user.move(i.symbol, by: 1) }
                Button("Remove from \(user.active.name)", systemImage: "minus.circle", role: .destructive) { user.remove(i.symbol) }
            } else if !user.active.symbols.contains(i.symbol) {
                Button("Add to \(user.active.name)", systemImage: "plus.circle") { _ = user.add(i.symbol) }
            }
        }
    }

    private func cell(_ s: String) -> some View {
        Text(s).font(.mono(11)).monospacedDigit().foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - WEI / FX / COMD / RATES

struct QuoteBoard: View {
    let panelID: Int
    let groups: [(String, [Instrument])]
    var yields = false
    @Environment(MarketStore.self) private var market

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > 900
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(groups, id: \.0) { title, list in
                        Section {
                            ForEach(Array(list.enumerated()), id: \.element.id) { n, i in
                                QuoteRow(instrument: i, panelID: panelID, wide: wide, yields: yields).rowBackground(n)
                            }
                        } header: {
                            VStack(spacing: 0) { SectionBar(title: title, trailing: advancers(list)); QuoteHeader(wide: wide, yields: yields) }
                        }
                    }
                }
            }
        }
    }

    private func advancers(_ list: [Instrument]) -> String {
        let c = list.compactMap { market.quotes[$0.symbol]?.changePercent }
        guard !c.isEmpty else { return "DELAYED" }
        return "▲\(c.filter { $0 > 0 }.count) ▼\(c.filter { $0 < 0 }.count)"
    }
}

// MARK: - MOST

struct MoversView: View {
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @State private var mode = Mode.gainers

    enum Mode: String, CaseIterable { case gainers = "GAINERS", losers = "LOSERS", active = "$ VOLUME" }

    private var ranked: [(Instrument, Quote)] {
        let pool = (Universe.equities + Universe.crypto).compactMap { i in market.quotes[i.symbol].map { (i, $0) } }
        switch mode {
        case .gainers: return pool.sorted { ($0.1.changePercent ?? -.infinity) > ($1.1.changePercent ?? -.infinity) }
        case .losers: return pool.sorted { ($0.1.changePercent ?? .infinity) < ($1.1.changePercent ?? .infinity) }
        case .active: return pool.sorted { ($0.1.volume ?? 0) * $0.1.last > ($1.1.volume ?? 0) * $1.1.last }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).padding(6)
            GeometryReader { g in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        QuoteHeader(wide: g.size.width > 900)
                        ForEach(Array(ranked.enumerated()), id: \.element.0.id) { n, row in
                            QuoteRow(instrument: row.0, panelID: panelID, wide: g.size.width > 900).rowBackground(n)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - HMAP

struct HeatmapView: View {
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                tiles("US EQUITIES", Universe.equities)
                tiles("CRYPTO", Universe.crypto)
                tiles("WORLD INDICES", Universe.indices)
            }
            .padding(8)
        }
    }

    private func tiles(_ title: String, _ list: [Instrument]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.mono(10, .bold)).foregroundStyle(Theme.accent)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 3)], spacing: 3) {
                ForEach(list) { i in
                    let pct = market.quotes[i.symbol]?.changePercent
                    VStack(spacing: 2) {
                        Text(i.ticker).font(.mono(12, .bold))
                        Text(Fmt.pct(pct)).font(.mono(11, .medium)).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(color(pct), in: .rect(cornerRadius: 2))
                    .onTapGesture { ws.link(i, from: panelID) }
                }
            }
        }
    }

    /// Intensity saturates at ±3%.
    private func color(_ pct: Double?) -> Color {
        guard let pct else { return Theme.rule }
        let t = min(abs(pct) / 3, 1)
        return (pct >= 0 ? theme.up : theme.down).opacity(0.18 + 0.72 * t)
    }
}

// MARK: - DES

struct DescriptionView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(FundamentalsService.self) private var sec
    @Environment(Workspace.self) private var ws

    var body: some View {
        let i = instrument
        let q = market.quotes[i.symbol]
        let d = market.details[i.symbol]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(market.displayName(i)).font(.ui(18, .semibold)).foregroundStyle(Theme.text)
                    Text([i.ticker, i.assetClass.rawValue, d?.exchange ?? (i.isStreaming ? "Coinbase" : nil), d?.currency ?? "USD"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(11)).foregroundStyle(Theme.dim)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    TickText(value: q?.last, cls: i.assetClass, size: 30, weight: .semibold)
                    ChangeText(value: q?.change, cls: i.assetClass, size: 15)
                    ChangeText(value: q?.changePercent, percent: true, size: 15)
                    Spacer()
                    Text(i.isStreaming ? "STREAMING" : "DELAYED").font(.mono(9, .bold))
                        .foregroundStyle(i.isStreaming ? Theme.go : Theme.warn)
                }
                Sparkline(values: market.sparks[i.symbol] ?? [], baseline: q?.previousClose)
                    .frame(height: 80)
                    .padding(.vertical, 4)
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { stat("PREV CLOSE", Fmt.price(q?.previousClose, i.assetClass)); stat("VOLUME", Fmt.compact(q?.volume)) }
                    GridRow { stat(i.isStreaming ? "24H HIGH" : "DAY HIGH", Fmt.price(q?.high, i.assetClass)); stat(i.isStreaming ? "24H LOW" : "DAY LOW", Fmt.price(q?.low, i.assetClass)) }
                    GridRow { stat("BID", Fmt.price(q?.bid, i.assetClass)); stat("ASK", Fmt.price(q?.ask, i.assetClass)) }
                    if let f = sec.fundamentals(i.symbol), let last = q?.last {
                        GridRow {
                            stat("MARKET CAP", f.marketCap(price: last).map { "$" + Fmt.compact($0) } ?? "—")
                            stat("P/E (FY)", f.priceToEarnings(price: last).map { String(format: "%.1fx", $0) } ?? "—")
                        }
                    }
                    GridRow {
                        stat("SPREAD", spread(q))
                        stat("UPDATED", q.map { $0.time.formatted(Fmt.clock) } ?? "—")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("52-WEEK RANGE").font(.mono(10, .bold)).foregroundStyle(Theme.label)
                        Spacer()
                        Text("\(Fmt.price(q?.low52, i.assetClass)) — \(Fmt.price(q?.high52, i.assetClass))")
                            .font(.mono(11)).foregroundStyle(Theme.dim)
                    }
                    RangeBar(low: q?.low52, high: q?.high52, value: q?.last)
                }
                FlowHotspots(items: [(.gp, "Price Chart"), (.fa, "Financials"), (.depth, "Market Depth"), (.tas, "Time & Sales"), (.cn, "News"), (.omon, "Options"), (.trade, "Trade")]) { f in
                    ws.load(Command(function: f, instrument: i), in: panelID)
                }
            }
            .padding(14)
        }
        .task(id: i.symbol) { await sec.load(i) }
    }

    private func spread(_ q: Quote?) -> String {
        guard let b = q?.bid, let a = q?.ask, a > 0 else { return "—" }
        return String(format: "%.2f bp", (a - b) / ((a + b) / 2) * 10_000)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            Text(value).font(.mono(13, .medium)).monospacedDigit().foregroundStyle(Theme.text)
        }
    }
}

struct FlowHotspots: View {
    let items: [(TerminalFunction, String)]
    let action: (TerminalFunction) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                Hotspot(number: n + 1, title: "\(item.0.rawValue) \(item.1)") { action(item.0) }
            }
        }
    }
}
