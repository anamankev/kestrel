import SwiftUI
import KestrelCore

// MARK: - DEPTH

struct DepthView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    var body: some View {
        if !instrument.isStreaming {
            EmptyNote(title: "Level 2 not on free feeds",
                      detail: "Full depth streams for crypto (Coinbase). Try BTC DEPTH or ETH DEPTH. Equity order books need a paid exchange feed.",
                      icon: "chart.bar.doc.horizontal")
        } else if let book = market.books[instrument.symbol], book.bestBid != nil {
            GeometryReader { g in
                let depth = max(Int((g.size.height - 90) / 18 / 2), 3)
                let l = book.ladder(depth: depth)
                let maxCum = max(l.bids.last?.cumulative ?? 0, l.asks.last?.cumulative ?? 0, 1e-12)
                VStack(spacing: 0) {
                    stats(book)
                    HStack {
                        HeaderCell(text: "PRICE", align: .leading); HeaderCell(text: "SIZE"); HeaderCell(text: "TOTAL"); HeaderCell(text: "NOTIONAL")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    ForEach(l.asks.reversed()) { lvl in row(lvl, maxCum, theme.down) }
                    HStack {
                        Text("SPREAD \(Fmt.price(book.spread, like: book.mid, instrument.assetClass))").foregroundStyle(Theme.dim)
                        Spacer()
                        Text("MID \(Fmt.price(book.mid, instrument.assetClass))").foregroundStyle(Theme.text)
                    }
                    .font(.mono(10, .bold)).padding(.horizontal, 8).frame(height: 20).background(Theme.header)
                    ForEach(l.bids) { lvl in row(lvl, maxCum, theme.up) }
                    Spacer(minLength: 0)
                }
            }
        } else {
            EmptyNote(title: "Waiting for book snapshot…")
        }
    }

    private func stats(_ b: OrderBook) -> some View {
        let imb = b.imbalance() ?? 0.5
        let bps = (b.spread ?? 0) / (b.mid ?? 1) * 10_000
        return VStack(spacing: 4) {
            HStack(spacing: 14) {
                kv("BID", Fmt.price(b.bestBid, instrument.assetClass), theme.up)
                kv("ASK", Fmt.price(b.bestAsk, instrument.assetClass), theme.down)
                kv("SPRD", String(format: bps < 0.1 ? "%.3f bp" : "%.2f bp", bps), Theme.text)
                kv("LEVELS", "\(b.bids.count)/\(b.asks.count)", Theme.dim)
                Spacer()
            }
            HStack(spacing: 6) {
                Text("BID \(Int(imb * 100))%").font(.mono(9, .bold)).foregroundStyle(theme.up)
                GeometryReader { g in
                    HStack(spacing: 0) {
                        theme.up.frame(width: g.size.width * imb)
                        theme.down
                    }
                }
                .frame(height: 4).clipShape(Capsule())
                Text("\(100 - Int(imb * 100))% ASK").font(.mono(9, .bold)).foregroundStyle(theme.down)
            }
            .help("Top-10-level size imbalance")
        }
        .padding(8)
    }

    private func kv(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(12, .semibold)).monospacedDigit().foregroundStyle(c)
        }
    }

    private func row(_ l: BookLevel, _ maxCum: Double, _ color: Color) -> some View {
        HStack {
            Text(Fmt.price(l.price, instrument.assetClass)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.size(l.size)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
            Text(Fmt.size(l.cumulative)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
            Text(Fmt.compact(l.cumulative * l.price)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.mono(11, .medium)).monospacedDigit()
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(alignment: .trailing) {
            GeometryReader { g in
                color.opacity(0.13).frame(width: g.size.width * CGFloat(l.cumulative / maxCum))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - TAS

struct TimeAndSalesView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme
    private static let time: Date.FormatStyle = Fmt.clock.secondFraction(.fractional(3))

    var body: some View {
        if !instrument.isStreaming {
            EmptyNote(title: "Tick data not on free feeds",
                      detail: "Every print streams for crypto. Try BTC TAS. Equity tapes need a paid feed.", icon: "list.bullet.rectangle")
        } else {
            let prints = market.tapes[instrument.symbol] ?? []
            let buy = prints.filter { $0.side == .buy }.reduce(0) { $0 + $1.size * $1.price }
            let sell = prints.filter { $0.side == .sell }.reduce(0) { $0 + $1.size * $1.price }
            let big = Self.blockThreshold(instrument)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LAST").font(.mono(8, .bold)).foregroundStyle(Theme.label)
                        TickText(value: prints.first?.price, cls: instrument.assetClass, size: 14, weight: .semibold)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("BUY $ / SELL $ · LAST \(prints.count)").font(.mono(8, .bold)).foregroundStyle(Theme.label)
                        HStack(spacing: 6) {
                            Text(Fmt.compact(buy)).foregroundStyle(theme.up)
                            Text("/").foregroundStyle(Theme.faint)
                            Text(Fmt.compact(sell)).foregroundStyle(theme.down)
                        }
                        .font(.mono(12, .semibold))
                    }
                    Spacer()
                    Text("BLOCK ≥ \(Fmt.compact(big))").font(.mono(9, .bold)).foregroundStyle(Theme.warn)
                }
                .padding(8)
                HStack {
                    HeaderCell(text: "TIME", align: .leading); HeaderCell(text: "PRICE"); HeaderCell(text: "SIZE"); HeaderCell(text: "VALUE")
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                if prints.isEmpty {
                    EmptyNote(title: "Waiting for prints…")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(prints) { p in
                                let value = p.price * p.size
                                let block = value >= big
                                HStack {
                                    Text(p.time.formatted(Self.time)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(Fmt.price(p.price, instrument.assetClass)).foregroundStyle(p.side == .buy ? theme.up : theme.down).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(Fmt.size(p.size)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(Fmt.compact(value)).foregroundStyle(block ? Theme.warn : Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .font(.mono(11, block ? .bold : .regular)).monospacedDigit()
                                .padding(.horizontal, 8).frame(height: 18)
                                .background((p.side == .buy ? theme.up : theme.down).opacity(block ? 0.16 : 0))
                            }
                        }
                    }
                }
            }
        }
    }

    static func blockThreshold(_ i: Instrument) -> Double { i.ticker == "BTC" || i.ticker == "ETH" ? 100_000 : 25_000 }
}

// MARK: - TOP / CN

struct NewsView: View {
    let instrument: Instrument?
    @Environment(NewsService.self) private var news
    @Environment(\.openURL) private var openURL

    var body: some View {
        let items = instrument.map { news.company[$0.symbol] ?? [] } ?? news.top
        Group {
            if items.isEmpty {
                if news.loading { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { EmptyNote(title: "No headlines yet", icon: "newspaper") }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.prefix(120).enumerated()), id: \.element.id) { n, item in
                            Button { openURL(item.link) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(item.published?.ago ?? "").font(.mono(10)).foregroundStyle(Theme.dim).frame(width: 30, alignment: .trailing)
                                    Text(item.source).font(.mono(9, .bold)).foregroundStyle(Theme.warn).frame(width: 64, alignment: .leading)
                                    Text(item.title).font(.ui(12, .medium)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .rowBackground(n)
                        }
                    }
                }
            }
        }
        .task(id: instrument?.symbol) {
            while !Task.isCancelled {
                if let i = instrument { await news.loadCompany(i) } else { await news.loadTop() }
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }
}

// MARK: - HELP

struct HelpView: View {
    let panelID: Int
    @Environment(Workspace.self) private var ws

    private static let groups: [(String, [(TerminalFunction, String)])] = [
        ("SECURITY", [(.des, "AAPL DES"), (.fa, "MSFT FA"), (.evts, "AAPL EVTS"), (.gp, "NVDA GP"), (.depth, "BTC DEPTH"), (.tas, "ETH TAS"), (.cn, "TSLA CN"), (.omon, "BTC OMON")]),
        ("MARKETS", [(.w, "W"), (.wei, "WEI"), (.most, "MOST"), (.hmap, "HMAP"), (.fx, "FX"), (.comd, "COMD"), (.rates, "RATES"), (.eco, "ECO"), (.top, "TOP")]),
        ("TRADING", [(.trade, "SOL BUY"), (.port, "PORT"), (.blot, "BLOT"), (.alrt, "NVDA ALRT")]),
        ("SYSTEM", [(.pref, "PREF")]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type a security, a function, or both, then press GO (↩).")
                    .font(.ui(12)).foregroundStyle(Theme.dim)
                Text("Syntax: TICKER [EXCH] [CLASS] FUNCTION. Classes: EQUITY CRYPTO INDEX CURNCY CMDTY GOVT")
                    .font(.mono(11)).foregroundStyle(Theme.label)
                ForEach(Self.groups, id: \.0) { title, fns in
                    VStack(alignment: .leading, spacing: 0) {
                        SectionBar(title: title)
                        ForEach(Array(fns.enumerated()), id: \.offset) { n, item in
                            Button { ws.run(item.1) } label: {
                                HStack {
                                    Text(item.0.rawValue).font(.mono(12, .heavy)).foregroundStyle(Theme.accent).frame(width: 60, alignment: .leading)
                                    Text(item.0.title).font(.ui(12)).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text(item.1 + " <GO>").font(.mono(11)).foregroundStyle(Theme.dim)
                                }
                                .padding(.horizontal, 8).frame(height: 26).contentShape(.rect)
                            }
                            .buttonStyle(.plain).rowBackground(n)
                        }
                    }
                }
                SectionBar(title: "KEYS")
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach([("⌘1 … ⌘6", "Focus panel"), ("⌘[", "Back (MENU)"), ("⌘↩", "Maximize panel"), ("⌘L", "Cycle layout"),
                             ("↑ ↓ Tab", "Pick an autocomplete suggestion"), ("Esc", "Clear command (CANCEL)"),
                             ("Tap a row", "Link that security into every security panel"), ("Long-press row", "Open a function")], id: \.0) { k, v in
                        GridRow {
                            Text(k).font(.mono(11, .bold)).foregroundStyle(Theme.text)
                            Text(v).font(.ui(11)).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .padding(.horizontal, 8)
                Text("Data: crypto streams live from Coinbase. Equities, indices, FX, commodities and rates are delayed snapshots from Yahoo Finance. News comes from public RSS wires. Trading is simulated (paper).")
                    .font(.ui(10)).foregroundStyle(Theme.faint)
            }
            .padding(12)
        }
    }
}
