import SwiftUI
import KestrelCore

/// DCF: intrinsic value per share from SEC free cash flow, with editable assumptions and a sensitivity grid.
/// Mirrors web DCF.tsx.
struct DCFView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(FundamentalsService.self) private var sec
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws

    var body: some View {
        Group {
            if instrument.assetClass != .equity {
                EmptyNote(title: "DCF values companies", detail: "Load a US-listed stock, e.g. AAPL DCF.", icon: "building.2")
            } else {
                switch sec.state(for: instrument) {
                case .needsContact:
                    VStack(spacing: 12) {
                        EmptyNote(title: "DCF needs a contact email",
                                  detail: "SEC EDGAR is free, but asks every app to identify itself with a contact email. Add yours once in PREF; it is sent only to sec.gov.",
                                  icon: "building.columns")
                        Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
                    }
                case .loading:
                    ProgressView("Loading 10-K cash flows from SEC…").tint(Theme.accent).font(.mono(10)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notFound:
                    EmptyNote(title: "No SEC filings for \(instrument.ticker)", detail: "DCF uses 10-K cash flows, so it covers US-listed companies.", icon: "doc.text.magnifyingglass")
                case .failed(let why):
                    EmptyNote(title: "SEC request failed", detail: why, icon: "exclamationmark.triangle")
                case .ready(let f):
                    DCFModel(instrument: instrument, f: f).id(instrument.symbol)
                }
            }
        }
        .task(id: "\(instrument.symbol)|\(sec.hasValidContact)") {
            market.touch(instrument)
            if let t = Universe.resolve("US10Y") { market.touch(t) }
            await sec.load(instrument)
        }
    }
}

private struct DCFModel: View {
    let instrument: Instrument
    let f: CompanyFundamentals
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    @State private var inputs: DCF.Inputs?
    @State private var base = ""
    @State private var growth = ""
    @State private var terminal = ""
    @State private var discount = ""

    private var tenYear: Double? { Universe.resolve("US10Y").flatMap { market.quotes[$0.symbol]?.last }.map { $0 / 100 } }
    private var start: (inputs: DCF.Inputs, baseKnown: Bool) { DCF.defaults(f.years, tenYear: tenYear) }

    private func load(_ i: DCF.Inputs) {
        base = String(format: "%.0f", i.baseFCF / 1e6); growth = String(format: "%.1f", i.growth * 100)
        terminal = String(format: "%.2f", i.terminalGrowth * 100); discount = String(format: "%.2f", i.discount * 100)
    }
    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) ?? .nan }
    private var current: DCF.Inputs { .init(baseFCF: num(base) * 1e6, growth: num(growth) / 100, terminalGrowth: num(terminal) / 100, discount: num(discount) / 100) }

    private func pct(_ v: Double?, _ d: Int = 1) -> String { v.map { String(format: "%.\(d)f%%", $0 * 100) } ?? "—" }
    private func money(_ v: Double?) -> String { v.map { ($0 < 0 ? "-" : "") + "$" + Fmt.compact(abs($0)) } ?? "—" }
    private func px(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "—" }

    var body: some View {
        let last = f.years.last
        let netCash = (last?.cash ?? 0) - (last?.longTermDebt ?? 0)
        let i = current
        let problem = DCF.problem(i, netCash: netCash)
        let r = DCF.value(i, netCash: netCash, shares: f.sharesOutstanding)
        let price = market.quotes[instrument.symbol]?.last
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140.pt), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                    field("BASE FCF $M", $base); field("GROWTH YRS 1–5 %", $growth); field("TERMINAL GROWTH %", $terminal); field("DISCOUNT RATE %", $discount)
                    Button("RESET") { load(start.inputs) }.font(.mono(10, .bold)).foregroundStyle(Theme.dim).buttonStyle(.terminal)
                }
                .padding(.horizontal, 8)
                if !start.baseKnown {
                    Text("\(f.name)'s latest free cash flow is \(money(last?.freeCashFlow)), so there is nothing positive to grow. Enter the base you expect to model a turnaround.")
                        .font(.ui(12)).foregroundStyle(Theme.warn).padding(.horizontal, 8)
                }
                if let r {
                    report(r, netCash: netCash, price: price, last: last, inputs: i)
                } else {
                    EmptyNote(title: "Check the inputs", detail: problem, icon: "slider.horizontal.3")
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear { if inputs == nil { inputs = start.inputs; load(start.inputs) } }
        .onChange(of: tenYear != nil) { load(start.inputs) }   // the 10-year yield arrived after the screen opened
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            TextField(label, text: text).accessibilityLabel(label).font(.mono(14, .semibold)).textFieldStyle(.plain)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .padding(.horizontal, 8).frame(minHeight: barHeight(30)).background(Theme.panel).overlay(Rectangle().stroke(Theme.rule))
        }
    }

    @ViewBuilder private func report(_ r: DCF.Result, netCash: Double, price: Double?, last: FiscalYear?, inputs i: DCF.Inputs) -> some View {
        let upside = r.perShare.flatMap { v in price.map { v / $0 - 1 } }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 4), spacing: 1) {
            StatTile(key: "INTRINSIC VALUE / SHARE", value: px(r.perShare), sub: f.sharesOutstanding.map { "\(Fmt.compact($0)) SHARES (SEC)" } ?? "SHARE COUNT UNAVAILABLE")
            StatTile(key: "PRICE", value: px(price), sub: "DELAYED")
            StatTile(key: "UPSIDE", value: upside.map { String(format: "%+.0f%%", $0 * 100) } ?? "—",
                     sub: upside.map { $0 > 0 ? "MODEL ABOVE PRICE" : "MODEL BELOW PRICE" } ?? "", color: theme.tint(upside))
            StatTile(key: "TERMINAL SHARE OF VALUE", value: pct(r.terminalShare, 0), sub: r.terminalShare > 0.75 ? "MOST VALUE IS BEYOND YEAR 10" : "OF ENTERPRISE VALUE",
                     color: r.terminalShare > 0.75 ? Theme.warn : Theme.text)
        }
        .background(Theme.rule).padding(.horizontal, 8)
        HStack {
            Spacer()
            CopyTableButton(csv: csv(r, netCash: netCash, inputs: i))
            ShareLink(item: CSVFile(name: "\(instrument.ticker)-dcf.csv", text: csv(r, netCash: netCash, inputs: i)), preview: SharePreview("DCF")) {
                Label("EXPORT CSV", systemImage: "square.and.arrow.up").font(.mono(10, .bold))
            }
            .buttonStyle(.terminal).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 8)
        SectionBar(title: "\(instrument.ticker) · FREE CASH FLOW HISTORY (10-K)", trailing: f.name.uppercased())
        grid(["FISCAL YEAR", "REVENUE", "OPERATING CASH FLOW", "CAPEX", "FREE CASH FLOW", "FCF MARGIN"],
             f.years.map { y in ["FY\(y.year)", money(y.revenue), money(y.operatingCashFlow), money(y.capex), money(y.freeCashFlow),
                                 y.freeCashFlow.flatMap { fcf in y.revenue.map { pct(fcf / $0) } } ?? "—"] })
        SectionBar(title: "PROJECTION", trailing: "DISCOUNTED AT \(pct(i.discount, 2))")
        grid(["YEAR", "GROWTH", "FREE CASH FLOW", "DISCOUNT FACTOR", "PRESENT VALUE"],
             r.flows.map { ["\($0.year)", pct($0.growth), money($0.fcf), String(format: "%.3f", $0.factor), money($0.pv)] }
             + [["TERMINAL", pct(i.terminalGrowth), money(r.terminalValue), String(format: "%.3f", r.flows[DCF.years - 1].factor), money(r.pvTerminal)]])
        SectionBar(title: "FROM ENTERPRISE VALUE TO VALUE PER SHARE", trailing: nil)
        grid(["STEP", "VALUE"], [
            ["Present value of years 1–10", money(r.pvFlows)], ["+ Present value of terminal value", money(r.pvTerminal)],
            ["= Enterprise value", money(r.enterprise)], ["+ Cash − long-term debt (FY\(last.map { String($0.year) } ?? "—"))", money(netCash)],
            ["= Equity value", money(r.equity)], ["÷ Shares outstanding", f.sharesOutstanding.map { Fmt.compact($0) } ?? "—"],
            ["= Value per share", px(r.perShare)],
        ])
        if let shares = f.sharesOutstanding {
            let discounts = [-0.02, -0.01, 0, 0.01, 0.02].map { i.discount + $0 }, terminals = [0.015, 0.02, 0.025, 0.03, 0.035]
            let table = DCF.sensitivity(i, netCash: netCash, shares: shares, discounts: discounts, terminals: terminals)
            SectionBar(title: "SENSITIVITY · VALUE PER SHARE", trailing: "ROWS: DISCOUNT RATE · COLUMNS: TERMINAL GROWTH")
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HeaderCell(text: "DISCOUNT ↓ / TERMINAL →", width: 190.pt, align: .leading)
                    ForEach(terminals, id: \.self) { HeaderCell(text: pct($0)) }
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                ForEach(Array(table.enumerated()), id: \.offset) { a, row in
                    HStack(spacing: 0) {
                        Text(pct(discounts[a], 2)).font(.mono(11, .bold)).foregroundStyle(Theme.text).frame(width: 190.pt, alignment: .leading)
                        ForEach(Array(row.enumerated()), id: \.offset) { b, v in
                            Text(px(v)).font(.mono(11)).monospacedDigit()
                                .foregroundStyle(v.flatMap { v in price.map { v > $0 ? theme.up : theme.down } } ?? Theme.dim)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .overlay(a == 2 && b == 2 ? Rectangle().stroke(Theme.accent) : nil)
                        }
                    }
                    .padding(.horizontal, 8).frame(minHeight: 24.pt).rowBackground(a)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Discount rate \(pct(discounts[a], 2)): " + zip(terminals, row).map { "terminal \(pct($0)) gives \(px($1))" }.joined(separator: ", "))
                }
            }
        }
        Text("Free cash flow = operating cash flow − capital expenditures from 10-K filings. Years 1–5 grow at the stage-1 rate, years 6–10 fade to terminal growth, and the terminal value is a growing perpetuity. The discount rate starts at the 10-year Treasury plus beta 1 × 5.5% equity risk premium. A teaching model, not advice; banks and insurers are poorly suited to free-cash-flow DCF.")
            .font(.ui(10)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
    }

    private func grid(_ header: [String], _ rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HeaderCell(text: header[0], width: 220.pt, align: .leading)
                ForEach(header.dropFirst(), id: \.self) { HeaderCell(text: $0) }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            ForEach(Array(rows.enumerated()), id: \.offset) { n, row in
                HStack(spacing: 0) {
                    Text(row[0]).font(.mono(11, row[0].hasPrefix("=") || row[0].hasPrefix("FY") ? .bold : .regular)).foregroundStyle(Theme.text).frame(width: 220.pt, alignment: .leading)
                    ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { _, c in
                        Text(c).font(.mono(11)).monospacedDigit().foregroundStyle(c.hasPrefix("-") ? theme.down : Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 8).frame(minHeight: 24.pt).rowBackground(n)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func csv(_ r: DCF.Result, netCash: Double, inputs i: DCF.Inputs) -> String {
        CSV.make(header: ["Year", "Growth", "Free cash flow", "Discount factor", "Present value"],
                 rows: r.flows.map { ["\($0.year)", CSV.number($0.growth), CSV.number($0.fcf, digits: 0), CSV.number($0.factor), CSV.number($0.pv, digits: 0)] }
                 + [["Terminal", CSV.number(i.terminalGrowth), CSV.number(r.terminalValue, digits: 0), CSV.number(r.flows[DCF.years - 1].factor), CSV.number(r.pvTerminal, digits: 0)],
                    ["Enterprise value", "", "", "", CSV.number(r.enterprise, digits: 0)], ["Cash minus long-term debt", "", "", "", CSV.number(netCash, digits: 0)],
                    ["Equity value", "", "", "", CSV.number(r.equity, digits: 0)], ["Value per share", "", "", "", CSV.number(r.perShare)]])
    }
}
