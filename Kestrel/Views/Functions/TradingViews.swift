import SwiftUI
import KestrelCore

// MARK: - TRADE: order ticket

struct TicketView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(PaperBroker.self) private var broker
    @Environment(Theme.self) private var theme

    @State var side: TradeSide
    @State private var qtyText = ""
    @State private var isLimit = false
    @State private var limitText = ""
    @State private var message: (String, Bool)?
    @State private var confirming = false

    init(instrument: Instrument, side: TradeSide) {
        self.instrument = instrument
        _side = State(initialValue: side)
    }

    private var quote: Quote? { market.quotes[instrument.symbol] }
    private var qty: Decimal? { Decimal(string: qtyText.replacingOccurrences(of: ",", with: "")) }
    private var limit: Decimal? { Decimal(string: limitText.replacingOccurrences(of: ",", with: "")) }
    private var estPrice: Double? {
        if isLimit { return limit?.double }
        return side == .buy ? (quote?.ask ?? quote?.last) : (quote?.bid ?? quote?.last)
    }
    private var presets: [Decimal] {
        instrument.assetClass == .option ? [0.1, 1, 5, 10]
            : instrument.isStreaming ? (instrument.ticker == "BTC" ? [0.01, 0.1, 0.5, 1] : [0.1, 1, 10, 100]) : [1, 10, 50, 100]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    sideButton(.sell, quote?.bid ?? quote?.last, theme.down)
                    sideButton(.buy, quote?.ask ?? quote?.last, theme.up)
                }
                HStack {
                    Text(instrument.assetClass == .option ? "DERIBIT BOOK · USD PER CONTRACT · LONG ONLY"
                         : instrument.isStreaming ? "LIVE TOP OF BOOK" : "DELAYED · FILLS AT LAST").font(.mono(9, .bold))
                        .foregroundStyle(instrument.isStreaming || instrument.assetClass == .option ? Theme.go : Theme.warn)
                    Spacer()
                    if let b = quote?.bid, let a = quote?.ask {
                        Text("SPREAD \(Fmt.price(a - b, instrument.assetClass))").font(.mono(9)).foregroundStyle(Theme.dim)
                    }
                }

                if side == .sell, let q = qty, q > max(broker.account.positions[instrument.symbol]?.quantity ?? 0, 0) {
                    Text("This sell opens or extends a SHORT. 150% of its value is held as margin.")
                        .font(.mono(10, .semibold)).foregroundStyle(Theme.warn)
                }
                field("QUANTITY") {
                    TextField("0", text: $qtyText).font(.mono(16, .semibold)).textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { p in
                        Button { qtyText = "\(p)" } label: {
                            Text(Fmt.qty(p)).font(.mono(10, .bold)).foregroundStyle(Theme.label)
                                .frame(maxWidth: .infinity).frame(height: 22)
                                .background(Theme.header, in: .rect(cornerRadius: 2))
                        }.buttonStyle(.plain)
                    }
                }

                Picker("", selection: $isLimit) { Text("MARKET").tag(false); Text("LIMIT").tag(true) }
                    .pickerStyle(.segmented)
                    .onChange(of: isLimit) { if isLimit, limitText.isEmpty { prefillLimit() } }
                if isLimit {
                    field("LIMIT PRICE") {
                        TextField("0.00", text: $limitText).font(.mono(16, .semibold)).textFieldStyle(.plain)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { kv("EST. NOTIONAL", notional); kv("BUYING POWER", Fmt.money(broker.account.buyingPower)) }
                    GridRow {
                        kv("POSITION", { () -> String in
                            let q = broker.account.positions[instrument.symbol]?.quantity ?? 0
                            return q < 0 ? "\(Fmt.qty(q)) SHORT" : Fmt.qty(q)
                        }())
                        kv("AVG COST", broker.account.positions[instrument.symbol].map { Fmt.price($0.averageCost.double, instrument.assetClass) } ?? "—")
                    }
                }

                // Two-step send: the first press arms the order, the second sends it.
                HStack(spacing: 6) {
                    Button {
                        if confirming { confirming = false; send() } else { confirming = true }
                    } label: {
                        Text(confirming
                             ? "CONFIRM \(side.rawValue) \(qtyText) \(instrument.ticker) \(isLimit ? "@ \(limitText)" : "AT MARKET")"
                             : "\(side.rawValue) \(qtyText.isEmpty ? "" : qtyText + " ")\(instrument.ticker)\(isLimit ? " LMT" : " MKT")")
                            .font(.mono(14, .heavy))
                            .foregroundStyle(confirming ? Theme.canvas : .white)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(confirming ? Theme.warn : (side == .buy ? theme.up : theme.down), in: .rect(cornerRadius: 3))
                            .opacity(qty == nil ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(qty == nil)
                    if confirming {
                        Button { confirming = false } label: {
                            Text("CXL").font(.mono(12, .heavy)).foregroundStyle(.white)
                                .frame(width: 56, height: 40).background(Theme.cancel, in: .rect(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onChange(of: qtyText) { confirming = false }
                .onChange(of: limitText) { confirming = false }
                .onChange(of: side) { confirming = false }
                .onChange(of: isLimit) { confirming = false }
                if confirming {
                    Text("Paper order: simulated execution, no real money moves.").font(.mono(9)).foregroundStyle(Theme.dim)
                }

                if let (text, ok) = message {
                    Text(text).font(.mono(11, .medium)).foregroundStyle(ok ? theme.up : Theme.cancel)
                }

                let working = broker.account.workingOrders.filter { $0.symbol == instrument.symbol }
                if !working.isEmpty {
                    SectionBar(title: "WORKING ORDERS")
                    ForEach(working) { o in OrderRow(order: o) }
                }
            }
            .padding(12)
        }
        .onAppear { if limitText.isEmpty { prefillLimit() } }
    }

    private var notional: String {
        guard let q = qty, let p = estPrice else { return "—" }
        return Fmt.money(q * (Decimal.price(p) ?? 0))
    }

    private func prefillLimit() {
        guard let q = quote else { return }
        let p = side == .buy ? (q.bid ?? q.last) : (q.ask ?? q.last)
        limitText = Fmt.price(p, instrument.assetClass).replacingOccurrences(of: ",", with: "")
    }

    private func send() {
        guard let q = qty else { return }
        let type: OrderType
        if isLimit {
            guard let l = limit else { message = ("Enter a limit price", false); return }
            type = .limit(l)
        } else {
            type = .market
        }
        do {
            let o = try broker.submit(instrument, side: side, quantity: q, type: type, quote: quote)
            message = o.status == .filled
                ? ("Filled #\(o.id) @ \(Fmt.price(o.fillPrice?.double, instrument.assetClass))", true)
                : ("Order #\(o.id) working", true)
            qtyText = ""
        } catch {
            message = (error.errorDescription ?? "Rejected", false)
        }
    }

    private func sideButton(_ s: TradeSide, _ price: Double?, _ color: Color) -> some View {
        Button { side = s; prefillLimit() } label: {
            VStack(spacing: 2) {
                Text(s.rawValue).font(.mono(10, .heavy))
                Text(Fmt.price(price, instrument.assetClass)).font(.mono(17, .bold)).monospacedDigit()
            }
            .foregroundStyle(side == s ? .white : color)
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(side == s ? color : color.opacity(0.08), in: .rect(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.6)))
        }
        .buttonStyle(.plain)
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            content()
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8).frame(height: 34)
                .background(Theme.canvas)
                .overlay(Rectangle().stroke(Theme.rule))
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(12, .medium)).monospacedDigit().foregroundStyle(Theme.text)
        }
    }
}

struct OrderRow: View {
    let order: Order
    @Environment(PaperBroker.self) private var broker
    @Environment(Theme.self) private var theme

    var body: some View {
        let o = order
        HStack(spacing: 8) {
            Text("#\(o.id)").foregroundStyle(Theme.dim).frame(width: 36, alignment: .leading)
            Text(o.created.formatted(Fmt.clock)).foregroundStyle(Theme.dim)
            Text(o.side.rawValue).foregroundStyle(o.side == .buy ? theme.up : theme.down).frame(width: 34, alignment: .leading)
            Text(Fmt.qty(o.quantity)).foregroundStyle(Theme.text)
            Text(Universe.instrument(symbol: o.symbol)?.ticker ?? o.symbol).foregroundStyle(Theme.text).bold()
            Text(o.type.limitPrice.map { "LMT \(Fmt.price($0.double))" } ?? "MKT").foregroundStyle(Theme.label)
            Spacer()
            if let p = o.fillPrice { Text("@ \(Fmt.price(p.double))").foregroundStyle(Theme.text) }
            Text(o.status.rawValue).foregroundStyle(statusColor(o.status)).bold()
            if o.status == .working {
                Button { broker.cancel(o.id) } label: {
                    Text("CXL").font(.mono(9, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(height: 18).background(Theme.cancel, in: .rect(cornerRadius: 2))
                }.buttonStyle(.plain)
            }
        }
        .font(.mono(11)).monospacedDigit().lineLimit(1)
        .padding(.horizontal, 8).frame(height: 24)
        .help(o.note ?? "")
    }

    private func statusColor(_ s: OrderStatus) -> Color {
        switch s {
        case .working: Theme.warn
        case .filled: theme.up
        case .cancelled: Theme.dim
        case .rejected: Theme.cancel
        }
    }
}

// MARK: - PORT

struct PortfolioView: View {
    let panelID: Int
    @Environment(PaperBroker.self) private var broker
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme
    @State private var confirmReset = false

    var body: some View {
        let a = broker.account
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 4)], spacing: 4) {
                    tile("NET LIQUIDATION", Fmt.money(broker.equity), Theme.text)
                    tile("TOTAL P&L", signedMoney(broker.totalPnL), theme.tint(broker.totalPnL.double))
                    tile("UNREALIZED", signedMoney(broker.unrealized), theme.tint(broker.unrealized.double))
                    tile("REALIZED", signedMoney(a.realizedPnL), theme.tint(a.realizedPnL.double))
                    tile("CASH", Fmt.money(a.cash), Theme.text)
                    tile("BUYING POWER", Fmt.money(a.buyingPower), Theme.text)
                }

                RiskPanel()
                SectionBar(title: "POSITIONS", trailing: "\(a.openPositions.count) OPEN")
                HStack {
                    HeaderCell(text: "SECURITY", width: 180, align: .leading)
                    HeaderCell(text: "QTY"); HeaderCell(text: "AVG COST"); HeaderCell(text: "MARK")
                    HeaderCell(text: "MKT VALUE"); HeaderCell(text: "UNRL P&L"); HeaderCell(text: "%")
                }
                .padding(.horizontal, 8)
                if a.openPositions.isEmpty {
                    Text("No positions. Try BTC BUY or AAPL TRADE.").font(.mono(11)).foregroundStyle(Theme.dim).padding(8)
                }
                ForEach(Array(a.openPositions.enumerated()), id: \.element.symbol) { n, p in
                    let inst = Universe.instrument(symbol: p.symbol) ?? Universe.resolve(p.symbol)
                    let mark = market.quotes[p.symbol].flatMap { Decimal.price($0.last) } ?? broker.marks[p.symbol] ?? p.averageCost
                    let u = p.unrealized(mark: mark)
                    let basis = abs(p.quantity) * p.averageCost
                    let pct = basis == 0 ? 0 : (u / basis * 100).double
                    HStack {
                        Text(inst.map { $0.assetClass == .option ? $0.name : $0.ticker } ?? p.symbol)
                            .font(.mono(12, .bold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: 180, alignment: .leading)
                        cell(Fmt.qty(p.quantity)); cell(Fmt.price(p.averageCost.double)); cell(Fmt.price(mark.double))
                        cell(Fmt.money(p.quantity * mark))
                        Text(signedMoney(u)).foregroundStyle(theme.tint(u.double)).frame(maxWidth: .infinity, alignment: .trailing)
                        ChangeText(value: pct, percent: true, size: 11).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.mono(11)).monospacedDigit()
                    .padding(.horizontal, 8).frame(height: 26).rowBackground(n)
                    .contentShape(.rect)
                    .onTapGesture { if let inst { ws.link(inst, from: panelID) } }
                }

                HStack {
                    Spacer()
                    Button("Reset paper account") { confirmReset = true }
                        .font(.mono(10, .bold)).foregroundStyle(Theme.cancel).buttonStyle(.plain)
                        .confirmationDialog("Reset to $1,000,000 and erase all orders?", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Reset", role: .destructive) { broker.reset() }
                        }
                }
                .padding(.top, 8)
            }
            .padding(10)
        }
    }

    private func signedMoney(_ d: Decimal) -> String { (d > 0 ? "+" : "") + Fmt.money(d) }

    private func cell(_ s: String) -> some View {
        Text(s).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func tile(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(16, .semibold)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.panel)
    }
}

// MARK: - BLOT

struct BlotterView: View {
    @Environment(PaperBroker.self) private var broker
    @Environment(Theme.self) private var theme

    var body: some View {
        let a = broker.account
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    if a.orders.isEmpty { Text("No orders yet.").font(.mono(11)).foregroundStyle(Theme.dim).padding(8) }
                    ForEach(Array(a.orders.reversed().enumerated()), id: \.element.id) { n, o in OrderRow(order: o).rowBackground(n) }
                } header: { SectionBar(title: "ORDERS", trailing: "\(a.workingOrders.count) WORKING") }
                Section {
                    ForEach(Array(a.fills.reversed().enumerated()), id: \.element.id) { n, f in
                        HStack(spacing: 8) {
                            Text(f.time.formatted(Fmt.clock)).foregroundStyle(Theme.dim)
                            Text(f.side.rawValue).foregroundStyle(f.side == .buy ? theme.up : theme.down).frame(width: 34, alignment: .leading)
                            Text("\(Fmt.qty(f.quantity)) \(Universe.instrument(symbol: f.symbol)?.ticker ?? f.symbol)").foregroundStyle(Theme.text)
                            Text("@ \(Fmt.price(f.price.double))").foregroundStyle(Theme.text)
                            Spacer()
                            Text("NOTIONAL \(Fmt.money(f.quantity * f.price))").foregroundStyle(Theme.dim)
                            if f.side == .sell {
                                Text("RLZD " + (f.realized >= 0 ? "+" : "") + Fmt.money(f.realized)).foregroundStyle(theme.tint(f.realized.double))
                            }
                        }
                        .font(.mono(11)).monospacedDigit().lineLimit(1)
                        .padding(.horizontal, 8).frame(height: 24).rowBackground(n)
                    }
                } header: { SectionBar(title: "EXECUTIONS", trailing: "\(a.fills.count)") }
            }
        }
    }
}
