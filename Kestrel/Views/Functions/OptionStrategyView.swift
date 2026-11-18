import SwiftUI
import KestrelCore

/// OSA: build a multi-leg option position from the live Deribit chain and see its payoff at expiry,
/// its model value today, package greeks, breakevens and max profit/loss.
struct OptionStrategyView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    @State private var chain: OptionChain?
    @State private var failed = false
    @State private var expiry: Date?
    @State private var template: StrategyTemplate = .straddle
    @State private var legs: [StrategyLeg] = []

    private var supported: Bool { Deribit.currencies.contains(instrument.ticker) && instrument.assetClass == .crypto }

    var body: some View {
        Group {
            if !supported {
                EmptyNote(title: "No free options feed for \(instrument.ticker)",
                          detail: "OSA uses Deribit's public chain: try BTC OSA or ETH OSA.", icon: "function")
            } else if let chain, let expiry {
                content(chain, expiry)
            } else {
                if failed { EmptyNote(title: "Options data unavailable", detail: "Deribit didn't answer.") }
                else { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard supported else { return }
        do {
            let c = try await market.optionChain(for: instrument)
            chain = c
            // Default to the first expiry at least a week out: weeklies make flat, noisy payoffs.
            expiry = c.expiries.first { $0.timeIntervalSinceNow > 7 * 86_400 } ?? c.expiries.first
            rebuild()
        } catch { failed = true }
    }

    private func rebuild() {
        guard let chain, let expiry else { return }
        legs = template.legs(chain: chain, expiry: expiry) ?? []
    }

    // MARK: Layout

    private func content(_ chain: OptionChain, _ expiry: Date) -> some View {
        let a = StrategyAnalysis(legs: legs)
        let f = chain.forward(expiry: expiry) ?? 0
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(StrategyTemplate.allCases, id: \.self) { t in
                            Button { template = t; rebuild() } label: {
                                Text(t.rawValue).font(.mono(10, .bold))
                                    .foregroundStyle(template == t ? Theme.canvas : Theme.label)
                                    .padding(.horizontal, 9).frame(height: 24)
                                    .background(template == t ? Theme.accent : Theme.header, in: .rect(cornerRadius: 2))
                            }
                            .buttonStyle(.plain)
                        }
                        Divider().frame(height: 18).padding(.horizontal, 6)
                        Menu {
                            ForEach(chain.expiries, id: \.self) { e in
                                Button(e.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))) { self.expiry = e; rebuild() }
                            }
                        } label: {
                            Text("EXPIRY " + expiry.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)).uppercased() + " ▾")
                                .font(.mono(10, .bold)).foregroundStyle(Theme.text)
                                .padding(.horizontal, 9).frame(height: 24).background(Theme.header, in: .rect(cornerRadius: 2))
                        }
                    }
                    .padding(.horizontal, 8)
                }

                if legs.isEmpty {
                    EmptyNote(title: "This expiry is too sparse for \(template.rawValue.lowercased())", detail: "Pick a later expiry.", icon: "function")
                        .frame(height: 160)
                } else {
                    summary(a, f)
                    SectionBar(title: "P&L vs \(instrument.ticker) AT EXPIRY AND TODAY", trailing: "FORWARD \(Fmt.price(f, .crypto))")
                    PayoffChart(analysis: a, forward: f).frame(height: 240).padding(.horizontal, 8)
                    legend
                    legTable(chain, expiry)
                    Text("Model values use Black-76 at each leg's Deribit mark IV, with premiums at the mark. Paper trading supports long legs only; shorts here are for analysis.")
                        .font(.mono(9)).foregroundStyle(Theme.faint).padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func summary(_ a: StrategyAnalysis, _ f: Double) -> some View {
        let g = a.greeks()
        let debit = a.netPremium
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 2)], spacing: 2) {
            tile(debit >= 0 ? "NET DEBIT" : "NET CREDIT", Fmt.money(Decimal(abs(debit))), nil, debit >= 0 ? Theme.text : theme.up)
            tile("MAX PROFIT", a.maxProfit.map { Fmt.money(Decimal($0)) } ?? "UNLIMITED", nil, theme.up)
            tile("MAX LOSS", a.maxLoss.map { Fmt.money(Decimal(abs($0))) } ?? "UNLIMITED", nil, theme.down)
            tile("BREAKEVEN", a.breakevens.isEmpty ? "—" : a.breakevens.map { Fmt.price($0, .crypto) }.joined(separator: " / "),
                 a.breakevens.map { String(format: "%+.1f%%", ($0 / f - 1) * 100) }.joined(separator: " / "), Theme.warn)
            tile("DELTA", String(format: "%+.3f", g.delta), "coins", Theme.text)
            tile("GAMMA", String(format: "%+.6f", g.gamma), "per $1", Theme.text)
            tile("VEGA", String(format: "%+.2f", g.vega), "$ per vol pt", Theme.text)
            tile("THETA", String(format: "%+.2f", g.theta), "$ per day", theme.tint(g.theta))
        }
        .padding(.horizontal, 8)
    }

    private func tile(_ k: String, _ v: String, _ sub: String?, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(15, .semibold)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub ?? " ").font(.mono(8)).foregroundStyle(Theme.faint).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Theme.panel)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { Rectangle().fill(Theme.accent).frame(width: 14, height: 2); Text("AT EXPIRY") }
            HStack(spacing: 5) { Rectangle().fill(Theme.warn).frame(width: 14, height: 2); Text("TODAY (MODEL)") }
            HStack(spacing: 5) { Rectangle().fill(Theme.text).frame(width: 2, height: 10); Text("FORWARD") }
        }
        .font(.mono(9, .bold)).foregroundStyle(Theme.label).padding(.horizontal, 8)
    }

    /// Each leg: flip side, change size, or step the strike along the listed chain.
    private func legTable(_ chain: OptionChain, _ expiry: Date) -> some View {
        let strikes = chain.rows(expiry: expiry).filter { $0.call?.mark != nil && $0.put?.mark != nil }
        return VStack(spacing: 0) {
            SectionBar(title: "LEGS", trailing: "\(legs.count)")
            HStack {
                HeaderCell(text: "SIDE", width: 64, align: .leading); HeaderCell(text: "QTY", width: 92, align: .center)
                HeaderCell(text: "TYPE", width: 48, align: .leading); HeaderCell(text: "STRIKE", width: 150, align: .center)
                HeaderCell(text: "MARK"); HeaderCell(text: "IV"); HeaderCell(text: "DELTA")
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            ForEach(Array(legs.enumerated()), id: \.offset) { n, leg in
                let c = leg.contract
                HStack {
                    Button { legs[n].quantity = -legs[n].quantity } label: {
                        Text(leg.quantity > 0 ? "LONG" : "SHORT").font(.mono(10, .heavy))
                            .foregroundStyle(leg.quantity > 0 ? theme.up : theme.down)
                    }
                    .buttonStyle(.plain).frame(width: 64, alignment: .leading)
                    HStack(spacing: 6) {
                        step("minus") { let q = abs(legs[n].quantity); if q > 1 { legs[n].quantity = (q - 1) * (legs[n].quantity > 0 ? 1 : -1) } }
                        Text(Fmt.qty(Decimal(abs(leg.quantity)))).frame(minWidth: 22)
                        step("plus") { let q = abs(legs[n].quantity); if q < 50 { legs[n].quantity = (q + 1) * (legs[n].quantity > 0 ? 1 : -1) } }
                    }
                    .frame(width: 92)
                    Text(c.isCall ? "CALL" : "PUT").foregroundStyle(Theme.label).frame(width: 48, alignment: .leading)
                    HStack(spacing: 6) {
                        step("chevron.left") { shift(n, by: -1, in: strikes) }
                        Text(Fmt.price(c.strike, .crypto)).frame(minWidth: 70)
                        step("chevron.right") { shift(n, by: 1, in: strikes) }
                    }
                    .frame(width: 150)
                    Text(Fmt.price(c.mark, .crypto)).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(c.iv.map { String(format: "%.1f%%", $0 * 100) } ?? "—").frame(maxWidth: .infinity, alignment: .trailing).foregroundStyle(Theme.dim)
                    Text(c.greeks().map { String(format: "%+.2f", $0.delta * leg.quantity) } ?? "—").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.mono(11)).monospacedDigit().foregroundStyle(Theme.text)
                .padding(.horizontal, 8).frame(height: 28).rowBackground(n)
            }
        }
    }

    private func step(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent).frame(width: 18, height: 18) }
            .buttonStyle(.plain)
            .accessibilityLabel(["minus": "Fewer contracts", "plus": "More contracts", "chevron.left": "Lower strike", "chevron.right": "Higher strike"][icon] ?? icon)
    }

    private func shift(_ n: Int, by d: Int, in rows: [StrikeRow]) {
        let c = legs[n].contract
        guard let i = rows.firstIndex(where: { $0.strike == c.strike }), rows.indices.contains(i + d),
              let next = c.isCall ? rows[i + d].call : rows[i + d].put,
              !legs.contains(where: { $0.id == next.name }) else { return }
        legs[n].contract = next
    }
}

/// Expiry payoff (piecewise linear) and today's model value across ±35% of the forward.
struct PayoffChart: View {
    let analysis: StrategyAnalysis
    let forward: Double
    @Environment(Theme.self) private var theme

    var body: some View {
        let up = theme.up, down = theme.down
        Canvas { ctx, size in
            guard forward > 0 else { return }
            let n = 160
            let xs = (0...n).map { forward * (0.65 + 0.7 * Double($0) / Double(n)) }
            let exp = xs.map(analysis.payoffAtExpiry)
            let now = xs.map { analysis.valueToday($0) }
            let all = exp + now
            guard let lo0 = all.min(), let hi0 = all.max() else { return }
            let pad = max((hi0 - lo0) * 0.08, 1)
            let lo = min(lo0, 0) - pad, hi = max(hi0, 0) + pad
            func x(_ i: Int) -> CGFloat { size.width * CGFloat(i) / CGFloat(n) }
            func y(_ v: Double) -> CGFloat { size.height * CGFloat(1 - (v - lo) / (hi - lo)) }
            let zero = y(0)

            // Profit / loss fill under the expiry curve.
            var area = Path()
            area.move(to: .init(x: 0, y: zero))
            for i in 0...n { area.addLine(to: .init(x: x(i), y: y(exp[i]))) }
            area.addLine(to: .init(x: size.width, y: zero)); area.closeSubpath()
            var gain = ctx, loss = ctx
            gain.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: zero)))
            loss.clip(to: Path(CGRect(x: 0, y: zero, width: size.width, height: size.height - zero)))
            gain.fill(area, with: .color(up.opacity(0.14)))
            loss.fill(area, with: .color(down.opacity(0.14)))

            ctx.stroke(Path { $0.move(to: .init(x: 0, y: zero)); $0.addLine(to: .init(x: size.width, y: zero)) }, with: .color(Theme.faint), lineWidth: 0.7)
            let fx = x(n / 2)
            ctx.stroke(Path { $0.move(to: .init(x: fx, y: 0)); $0.addLine(to: .init(x: fx, y: size.height)) },
                       with: .color(Theme.text.opacity(0.5)), style: .init(lineWidth: 0.8, dash: [2, 3]))
            func line(_ v: [Double]) -> Path {
                Path { p in p.move(to: .init(x: 0, y: y(v[0]))); for i in 1...n { p.addLine(to: .init(x: x(i), y: y(v[i]))) } }
            }
            ctx.stroke(line(now), with: .color(Theme.warn), style: .init(lineWidth: 1.2, dash: [4, 3]))
            ctx.stroke(line(exp), with: .color(Theme.accent), lineWidth: 1.8)

            for i in stride(from: 0, through: n, by: n / 4) {
                ctx.draw(Text(Fmt.compact(xs[i])).font(.mono(9)).foregroundStyle(Theme.faint), at: .init(x: min(max(x(i), 18), size.width - 18), y: size.height - 7))
            }
            for v in [hi0, 0, lo0] where abs(y(v) - zero) > 12 || v == 0 {
                ctx.draw(Text((v >= 0 ? "+" : "−") + Fmt.compact(abs(v))).font(.mono(9)).foregroundStyle(Theme.faint),
                         at: .init(x: 4, y: min(max(y(v), 8), size.height - 18)), anchor: .leading)
            }
        }
        .background(Theme.panel)
    }
}
