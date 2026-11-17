import SwiftUI
import KestrelCore

struct TerminalView: View {
    @Environment(Workspace.self) private var ws
    @Environment(MarketStore.self) private var market
    @Environment(PaperBroker.self) private var broker
    @State private var commandText = ""
    @FocusState private var commandFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar(text: $commandText, focused: $commandFocused).zIndex(2) // dropdown floats over panels
            TickerTape()
            PanelGrid()
            FunctionKeyBar(commandText: $commandText, commandFocused: $commandFocused)
        }
        // The command line lives at the top and is always focused, so iPadOS keeps its keyboard
        // shortcut bar up. Don't let that (or the full keyboard) re-lay out the terminal: the
        // key bar stays pinned and the canvas paints to the screen edge, so no black strip.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) { FillToast(); AlertToast() }.padding(.top, 92).padding(.trailing, 12)
        }
        .onChange(of: ws.symbolsOnScreen, initial: true) { _, symbols in
            market.focusSymbols = symbols
            for s in symbols { if let i = Universe.instrument(symbol: s) ?? Universe.resolve(s) { market.touch(i) } }
        }
        .onAppear { if !DemoTour.isEnabled { commandFocused = true } }
        .task {
            guard DemoTour.isEnabled else { return }
            await DemoTour.run(ws) { commandText = $0 }
        }
    }
}

// MARK: - Top bar: brand, command line, clocks, link status

struct TopBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    @Environment(Workspace.self) private var ws
    @Environment(MarketStore.self) private var market
    @Environment(PaperBroker.self) private var broker
    @Environment(Theme.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Wordmark()
            CommandBar(text: $text, focused: focused)
            Spacer(minLength: 0)
            AccountChip()
            LinkStatus()
            Clocks()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Theme.header)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            KestrelMark().frame(width: 18, height: 18)
            Text("KESTREL").font(.mono(13, .heavy)).tracking(2.5).foregroundStyle(Theme.text)
        }
    }
}

/// The brand mark: a stooping wing drawn as two chevrons.
struct KestrelMark: View {
    var body: some View {
        Canvas { ctx, s in
            var a = Path()
            a.move(to: .init(x: 0, y: s.height * 0.15))
            a.addLine(to: .init(x: s.width * 0.55, y: s.height * 0.55))
            a.addLine(to: .init(x: s.width, y: s.height * 0.05))
            a.addLine(to: .init(x: s.width * 0.55, y: s.height * 0.95))
            a.closeSubpath()
            ctx.fill(a, with: .linearGradient(.init(colors: [Theme.accent, Theme.accentDim]),
                                              startPoint: .zero, endPoint: .init(x: s.width, y: s.height)))
        }
    }
}

struct CommandBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    @Environment(Workspace.self) private var ws
    @State private var selection = 0

    private var suggestions: [CommandParser.Suggestion] {
        focused.wrappedValue ? CommandParser.suggestions(for: text) : []
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(ws.focused + 1)")
                .font(.mono(11, .bold)).foregroundStyle(Theme.canvas)
                .frame(width: 22, height: 28)
                .background(Theme.accent)
            Text(">").font(.mono(13, .bold)).foregroundStyle(Theme.accent).padding(.leading, 8)
            TextField("", text: $text, prompt: Text("AAPL GP · BTC DEPTH · WEI · HELP").foregroundStyle(Theme.faint))
                .font(.mono(13, .medium))
                .foregroundStyle(Theme.text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                #endif
                .focused(focused)
                .padding(.horizontal, 6)
                .onSubmit(submit)
                .onChange(of: text) { selection = 0 }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.tab) { accept() }
                .onKeyPress(.escape) { text = ""; ws.error = nil; return .handled }
            Button(action: submit) {
                Text("GO").font(.mono(11, .heavy)).foregroundStyle(Theme.canvas)
                    .frame(width: 38, height: 28).background(Theme.go)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 520)
        .background(Theme.canvas)
        .task(id: ws.error) {
            guard ws.error != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            ws.error = nil
        }
        .overlay(Rectangle().stroke(focused.wrappedValue ? Theme.accentDim : Theme.rule))
        .overlay(alignment: .topLeading) {
            if !suggestions.isEmpty {
                SuggestionList(items: suggestions, selection: selection) { s in
                    text = s.completion
                    submit()
                }
                .offset(y: 32)
            } else if let err = ws.error {
                Text(err).font(.mono(11, .medium)).foregroundStyle(Theme.cancel)
                    .padding(6).background(Theme.header).overlay(Rectangle().stroke(Theme.cancel.opacity(0.5)))
                    .offset(y: 32)
            }
        }
        .zIndex(10)
    }

    private func move(_ d: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        selection = (selection + d + suggestions.count) % suggestions.count
        return .handled
    }

    private func accept() -> KeyPress.Result {
        guard let s = suggestions[safe: selection] else { return .ignored }
        text = s.completion + " "
        return .handled
    }

    private func submit() {
        if let s = suggestions[safe: selection], selection > 0 { text = s.completion }
        if ws.run(text) { text = "" }
        focused.wrappedValue = true
    }
}

struct SuggestionList: View {
    let items: [CommandParser.Suggestion]
    let selection: Int
    let pick: (CommandParser.Suggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, s in
                Button { pick(s) } label: {
                    HStack {
                        Text(s.label).font(.mono(12, .semibold)).foregroundStyle(Theme.accent)
                        Spacer(minLength: 16)
                        Text(s.detail).font(.ui(11)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(i == selection ? Theme.selection : Theme.header)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 420)
        .overlay(Rectangle().stroke(Theme.accentDim))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
    }
}

struct Clocks: View {
    private static let zones: [(String, String)] = [("NY", "America/New_York"), ("LDN", "Europe/London"), ("TYO", "Asia/Tokyo")]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 10) {
                ForEach(Self.zones, id: \.0) { label, tz in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(label).font(.mono(8, .bold)).foregroundStyle(Theme.label)
                        Text(ctx.date.formatted({ var s = Fmt.clock; s.timeZone = TimeZone(identifier: tz)!; return s }()))
                            .font(.mono(11, .medium)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                }
            }
        }
    }
}

struct LinkStatus: View {
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    var body: some View {
        let live = market.link == .live
        HStack(spacing: 6) {
            Circle().fill(live ? theme.up : Theme.warn).frame(width: 7, height: 7)
                .shadow(color: live ? theme.up : Theme.warn, radius: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(market.link.rawValue).font(.mono(9, .bold)).foregroundStyle(live ? theme.up : Theme.warn)
                Text("\(Int(market.messagesPerSecond)) msg/s").font(.mono(9)).foregroundStyle(Theme.dim)
            }
        }
        .help("Crypto: Coinbase WebSocket, tick-by-tick. Equities, indices, FX, rates: delayed snapshots.")
    }
}

struct AccountChip: View {
    @Environment(PaperBroker.self) private var broker
    @Environment(AuthService.self) private var auth
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    var body: some View {
        HStack(spacing: 8) {
        Button { ws.run("PORT") } label: {
            VStack(alignment: .trailing, spacing: 0) {
                Text("PAPER · \(Fmt.money(broker.equity))").font(.mono(10, .semibold)).foregroundStyle(Theme.text)
                Text("P&L " + (broker.totalPnL >= 0 ? "+" : "") + Fmt.money(broker.totalPnL))
                    .font(.mono(10, .medium)).foregroundStyle(theme.tint(broker.totalPnL.double))
            }
        }
        .buttonStyle(.plain)
        if let me = auth.current {
            Button { ws.run("PREF") } label: {
                Text(me.initials).font(.mono(10, .heavy)).foregroundStyle(Theme.canvas)
                    .frame(width: 24, height: 24).background(Theme.accent, in: .circle)
            }
            .buttonStyle(.plain)
            .help("\(me.displayName) · \(me.email)")
        }
        }
    }
}

// MARK: - Ticker tape

struct TickerTape: View {
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme
    @State private var contentWidth: CGFloat = 1

    private static let tickers = ["SPX", "INDU", "CCMP", "RTY", "VIX", "US10Y", "BTC", "ETH", "SOL", "EURUSD", "USDJPY",
                                  "CL1", "GC1", "UKX", "DAX", "NKY", "HSI", "NVDA", "AAPL", "MSFT"]
    private var items: [Instrument] {
        Self.tickers.compactMap { t in Universe.all.first { $0.ticker == t } }
    }

    var body: some View {
        // The marquee lives in an overlay so its (very wide) ideal size never reaches the window:
        // on macOS a window sizes itself to its content's ideal width.
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
                    let x = -CGFloat(ctx.date.timeIntervalSinceReferenceDate * 40).truncatingRemainder(dividingBy: contentWidth)
                    HStack(spacing: 0) { strip; strip }
                        .offset(x: x)
                }
            }
            .clipped()
        .background(Theme.canvas)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }

    private var strip: some View {
        HStack(spacing: 22) {
            ForEach(items) { i in
                let q = market.quotes[i.symbol]
                Button { ws.load(Command(function: .des, instrument: i), in: ws.focused) } label: {
                    HStack(spacing: 6) {
                        Text(i.ticker).font(.mono(11, .bold)).foregroundStyle(Theme.label)
                        Text(Fmt.price(q?.last, i.assetClass)).font(.mono(11, .medium)).monospacedDigit().foregroundStyle(Theme.text)
                        Text(Fmt.pct(q?.changePercent)).font(.mono(11, .medium)).monospacedDigit()
                            .foregroundStyle(theme.tint(q?.changePercent))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 22)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = max($0, 1) }
    }
}

// MARK: - Panels

struct PanelGrid: View {
    @Environment(Workspace.self) private var ws

    var body: some View {
        GeometryReader { g in
            let panels = ws.visible
            let portrait = g.size.width < g.size.height
            let cols: Int = switch panels.count {
            case 1: 1
            case 2: portrait ? 1 : 2
            case 4: 2
            default: portrait ? 2 : 3
            }
            let rows = Int((Double(panels.count) / Double(cols)).rounded(.up))
            // Explicit cell sizes: panel content can never push its neighbours around.
            let w = (g.size.width - CGFloat(cols - 1)) / CGFloat(cols)
            let h = (g.size.height - CGFloat(rows - 1)) / CGFloat(rows)
            VStack(spacing: 1) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 1) {
                        ForEach(panels[(r * cols)..<min(panels.count, (r + 1) * cols)]) { p in
                            PanelView(panel: p).frame(width: w, height: h).clipped()
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .background(Theme.rule)
        }
    }
}

struct PanelView: View {
    let panel: Panel
    @Environment(Workspace.self) private var ws
    @Environment(MarketStore.self) private var market

    var body: some View {
        let focused = ws.focused == panel.id
        VStack(spacing: 0) {
            header(focused)
            FunctionView(panel: panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Theme.panel)
        .overlay(Rectangle().stroke(focused ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1))
        .simultaneousGesture(TapGesture().onEnded { ws.focused = panel.id })
    }

    private func header(_ focused: Bool) -> some View {
        let c = panel.command
        return HStack(spacing: 8) {
            Text("\(panel.id + 1)")
                .font(.mono(10, .bold))
                .foregroundStyle(focused ? Theme.canvas : Theme.dim)
                .frame(width: 18, height: 18)
                .background(focused ? Theme.accent : Theme.rule, in: .rect(cornerRadius: 2))
            if panel.canGoBack {
                Button { ws.back(panel.id) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
                }.buttonStyle(.plain).help("Back (⌘[)").accessibilityLabel("Back")
            }
            Text(c.function.rawValue).font(.mono(11, .heavy)).foregroundStyle(Theme.accent)
            if let i = c.instrument {
                Text(i.ticker).font(.mono(11, .bold)).foregroundStyle(Theme.text)
                Text(i.assetClass.rawValue).font(.mono(9, .bold)).foregroundStyle(Theme.warn)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.warn.opacity(0.4)))
                Text(market.displayName(i)).font(.ui(11)).foregroundStyle(Theme.dim).lineLimit(1)
            } else {
                Text(c.function.title).font(.ui(11)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 4)
            if c.instrument != nil {
                Text(c.function.title.uppercased()).font(.mono(9, .semibold)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Button { ws.toggleMaximize(panel.id) } label: {
                Image(systemName: ws.maximized == panel.id ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .help("Maximize (⌘↩)")
            .accessibilityLabel(ws.maximized == panel.id ? "Restore panel" : "Maximize panel")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Theme.header)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1) }
    }
}

struct FunctionView: View {
    let panel: Panel
    @Environment(MarketStore.self) private var market

    var body: some View {
        let c = panel.command
        switch c.function {
        case .w: MonitorView(panelID: panel.id)
        case .hmap: HeatmapView(panelID: panel.id)
        case .corr: CorrelationView(panelID: panel.id)
        case .wei: QuoteBoard(panelID: panel.id, groups: Region.allCases.map { r in (r.rawValue, Universe.indices.filter { $0.region == r }) })
        case .fx: QuoteBoard(panelID: panel.id, groups: [("G10 & EM SPOT", Universe.currencies)])
        case .comd: QuoteBoard(panelID: panel.id, groups: [("ENERGY", Array(Universe.commodities.prefix(3))), ("METALS", Array(Universe.commodities[3..<6])), ("AGRICULTURE", Array(Universe.commodities.suffix(2)))])
        case .rates: QuoteBoard(panelID: panel.id, groups: [("US TREASURY YIELDS", Universe.rates)], yields: true)
        case .most: MoversView(panelID: panel.id)
        case .top: NewsView(instrument: nil)
        case .alrt: AlertsView(instrument: c.instrument, panelID: panel.id)
        case .pref: SettingsView()
        case .eco: EconomyView(panelID: panel.id)
        case .port: PortfolioView(panelID: panel.id)
        case .blot: BlotterView()
        case .help: HelpView(panelID: panel.id)
        case .des, .fa, .evts, .gp, .hp, .bt, .osa, .depth, .tas, .cn, .omon, .trade:
            if let i = c.instrument, i.assetClass == .option, c.function != .trade {
                EmptyNote(title: "\(i.name)", detail: "Option contracts support TRADE. See the full chain, greeks and smile in \(Deribit.parse(i.symbol)?.underlying ?? "BTC") OMON.",
                          icon: "function")
            } else if let i = c.instrument, market.unknown.contains(i.symbol) {
                EmptyNote(title: "\(i.ticker): security not found",
                          detail: "No market data exists for this ticker. Check the symbol or press MENU to go back.",
                          icon: "questionmark.diamond")
            } else if let i = c.instrument {
                switch c.function {
                case .des: DescriptionView(instrument: i, panelID: panel.id)
                case .fa: FundamentalsView(instrument: i, panelID: panel.id)
                case .evts: EventsView(instrument: i, panelID: panel.id)
                case .gp: ChartView(instrument: i).id(i.symbol)
                case .hp: HistoryView(instrument: i).id(i.symbol)
                case .bt: BacktestView(instrument: i).id(i.symbol)
                case .osa: OptionStrategyView(instrument: i).id(i.symbol)
                case .depth: DepthView(instrument: i)
                case .tas: TimeAndSalesView(instrument: i)
                case .cn: NewsView(instrument: i)
                case .omon: OptionMonitorView(instrument: i, panelID: panel.id).id(i.symbol)
                default: TicketView(instrument: i, side: panel.side ?? .buy).id("\(i.symbol)-\(panel.side?.rawValue ?? "")")
                }
            } else {
                EmptyNote(title: "No security loaded")
            }
        }
    }
}

// MARK: - Function key bar

struct FunctionKeyBar: View {
    @Binding var commandText: String
    var commandFocused: FocusState<Bool>.Binding
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    private static let quick: [TerminalFunction] = [.w, .wei, .most, .hmap, .eco, .top, .fx, .comd, .rates, .alrt, .port, .blot, .pref]

    var body: some View {
        @Bindable var ws = ws
        @Bindable var theme = theme
        HStack(spacing: 6) {
            key("MENU", Color(hex: 0x2A3A4A), Theme.text) { ws.back() }
            key("HELP", Color(hex: 0x2A3A4A), Theme.text) { ws.run("HELP") }
            key("CANCEL", Theme.cancel, .white) { commandText = ""; ws.error = nil; ws.maximized = nil }
            key("GO", Theme.go, Theme.canvas) {
                if ws.run(commandText) { commandText = "" }
                commandFocused.wrappedValue = true
            }
            Theme.rule.frame(width: 1, height: 18).padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Self.quick, id: \.self) { f in
                        Button { ws.run(f.rawValue) } label: {
                            Text(f.rawValue).font(.mono(10, .bold)).foregroundStyle(Theme.label)
                                .padding(.horizontal, 8).frame(height: 22)
                                .background(Theme.panel, in: .rect(cornerRadius: 2))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.rule))
                        }
                        .buttonStyle(.plain)
                        .help(f.title)
                    }
                }
            }
            Spacer(minLength: 8)
            PagesMenu()
            Picker("Layout", selection: $ws.layout) {
                ForEach(PanelLayout.allCases) { l in Image(systemName: l.symbol).accessibilityLabel("\(l.count) panels").tag(l) }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .onChange(of: ws.layout) { ws.maximized = nil; if ws.focused >= ws.layout.count { ws.focused = 0 } }
            Toggle(isOn: $theme.colorBlindSafe) {
                Image(systemName: "eye").font(.system(size: 11))
            }
            .toggleStyle(.button)
            .help("Colour-vision-safe up/down palette")
            .accessibilityLabel("Colour-vision-safe colours")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Theme.header)
        .overlay(alignment: .top) { Theme.rule.frame(height: 1) }
    }

    private func key(_ title: String, _ bg: Color, _ fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.mono(10, .heavy)).foregroundStyle(fg)
                .padding(.horizontal, 10).frame(height: 22)
                .background(bg, in: .rect(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}

struct FillToast: View {
    @Environment(PaperBroker.self) private var broker
    @Environment(Theme.self) private var theme
    @State private var visible: Fill?

    var body: some View {
        Group {
            if let f = visible {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(f.side == .buy ? theme.up : theme.down)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FILLED · ORDER #\(f.orderID)").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                        Text("\(f.side.rawValue) \(Fmt.qty(f.quantity)) \(Universe.instrument(symbol: f.symbol)?.ticker ?? f.symbol) @ \(Fmt.price(f.price.double))")
                            .font(.mono(12, .semibold)).foregroundStyle(Theme.text)
                    }
                }
                .padding(10)
                .background(Theme.header, in: .rect(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accentDim))
                .shadow(color: .black.opacity(0.5), radius: 10)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onChange(of: broker.lastFill) { _, f in
            guard let f else { return }
            withAnimation(.spring(duration: 0.3)) { visible = f }
            Task {
                try? await Task.sleep(for: .seconds(4))
                if visible == f { withAnimation { visible = nil } }
            }
        }
    }
}


/// Named layouts (like Launchpad views): save the current panels, recall them in one tap.
struct PagesMenu: View {
    @Environment(Workspace.self) private var ws
    @State private var naming = false
    @State private var name = ""
    @State private var pages = Workspace.pages

    var body: some View {
        Menu {
            Section("Pages") {
                if pages.isEmpty { Text("No saved pages") }
                ForEach(pages) { p in Button(p.name) { ws.open(p) } }
            }
            Button("Save current as…", systemImage: "plus") { name = ""; naming = true }
            if !pages.isEmpty {
                Menu("Delete") {
                    ForEach(pages) { p in Button(p.name, role: .destructive) { Workspace.deletePage(p.name); pages = Workspace.pages } }
                }
            }
        } label: {
            Text("PAGES").font(.mono(10, .bold)).foregroundStyle(Theme.label)
                .padding(.horizontal, 8).frame(height: 22)
                .background(Theme.panel, in: .rect(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.rule))
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
        .onAppear { pages = Workspace.pages }
        .alert("Save page", isPresented: $naming) {
            TextField("Name (e.g. MORNING)", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { ws.savePage(name); pages = Workspace.pages }
        } message: {
            Text("Saves this window's layout and all six panels.")
        }
    }
}
