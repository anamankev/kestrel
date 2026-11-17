import SwiftUI
import KestrelCore

/// OMON: listed option chain with greeks computed locally (Black-76), the volatility smile for the
/// selected expiry and the ATM term structure across all expiries.
struct OptionMonitorView: View {
    let instrument: Instrument
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    @State private var chain: OptionChain?
    @State private var expiry: Date?
    @State private var failed = false
    @State private var updated: Date?

    var body: some View {
        Group {
            if !Deribit.currencies.contains(instrument.ticker) || instrument.assetClass != .crypto {
                EmptyNote(title: "No free options feed for \(instrument.ticker)",
                          detail: "Listed options stream for BTC and ETH from Deribit. Try BTC OMON. Equity options need a paid OPRA licence.",
                          icon: "function")
            } else if let chain, let e = expiry ?? chain.expiries.first {
                content(chain, e)
            } else {
                if failed { EmptyNote(title: "Options data unavailable", detail: "Deribit didn't answer. Retrying shortly.") }
                else { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .task {
            guard Deribit.currencies.contains(instrument.ticker) else { return }
            while !Task.isCancelled {
                do {
                    let c = try await market.optionChain(for: instrument)
                    chain = c
                    if expiry == nil || !c.expiries.contains(expiry!) {
                        // Default to the first expiry at least a week out: weeklies are noisy.
                        expiry = c.expiries.first { $0.timeIntervalSinceNow > 6 * 86_400 } ?? c.expiries.first
                    }
                    updated = .now
                    failed = false
                } catch {
                    failed = chain == nil
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func content(_ chain: OptionChain, _ e: Date) -> some View {
        let rows = chain.rows(expiry: e)
        let fwd = chain.forward(expiry: e) ?? 0
        let atm = chain.atmStrike(expiry: e)
        return VStack(spacing: 0) {
            expiryBar(chain, e)
            stats(chain, e, fwd)
            GeometryReader { g in
                let wide = g.size.width > 760
                VStack(spacing: 0) {
                    HStack(spacing: 1) {
                        SmileChart(rows: rows, forward: fwd, theme: theme)
                        if wide { TermStructureChart(chain: chain, selected: e) }
                    }
                    .frame(height: min(170, g.size.height * 0.34))
                    .background(Theme.rule)
                    chainTable(rows, atm: atm, wide: wide)
                }
            }
        }
    }

    // MARK: Pieces

    private func expiryBar(_ chain: OptionChain, _ selected: Date) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(chain.expiries, id: \.self) { e in
                    let days = Int((e.timeIntervalSinceNow / 86_400).rounded(.up))
                    Button { expiry = e } label: {
                        VStack(spacing: 0) {
                            Text(e.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)).uppercased())
                                .font(.mono(10, .bold))
                            Text("\(days)D").font(.mono(8, .semibold)).opacity(0.7)
                        }
                        .foregroundStyle(e == selected ? Theme.canvas : Theme.label)
                        .padding(.horizontal, 7).frame(height: 30)
                        .background(e == selected ? Theme.accent : Theme.header, in: .rect(cornerRadius: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
    }

    private func stats(_ chain: OptionChain, _ e: Date, _ fwd: Double) -> some View {
        let spot = market.quotes[instrument.symbol]?.last
        let basis = spot.map { (fwd / $0 - 1) * 100 }
        return HStack(spacing: 16) {
            kv("FORWARD", Fmt.price(fwd), Theme.text)
            kv("BASIS", Fmt.pct(basis), theme.tint(basis))
            kv("ATM IV", chain.atmIV(expiry: e).map { String(format: "%.1f%%", $0 * 100) } ?? "—", Theme.accent)
            kv("MAX PAIN", chain.maxPain(expiry: e).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", Theme.warn)
            kv("P/C OI", chain.putCallOIRatio(expiry: e).map { String(format: "%.2f", $0) } ?? "—", Theme.text)
            Spacer(minLength: 0)
            Text(updated.map { "DERIBIT · \($0.formatted(Fmt.clock))" } ?? "")
                .font(.mono(9)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private func kv(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.mono(8, .bold)).foregroundStyle(Theme.label)
            Text(v).font(.mono(12, .semibold)).monospacedDigit().foregroundStyle(c).lineLimit(1)
        }
    }

    private func chainTable(_ rows: [StrikeRow], atm: Double?, wide: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("CALLS").frame(maxWidth: .infinity)
                Text("STRIKE").frame(width: 76)
                Text("PUTS").frame(maxWidth: .infinity)
            }
            .font(.mono(9, .heavy)).foregroundStyle(Theme.accent)
            .padding(.vertical, 3).background(Theme.header)
            HStack(spacing: 0) {
                sideHeader(call: true, wide: wide)
                Text("").frame(width: 76)
                sideHeader(call: false, wide: wide)
            }
            .padding(.vertical, 3)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in
                            HStack(spacing: 0) {
                                side(r.call, call: true, wide: wide)
                                Text(Fmt.price(r.strike).replacingOccurrences(of: ".00", with: ""))
                                    .font(.mono(11, .bold)).foregroundStyle(r.strike == atm ? Theme.canvas : Theme.text)
                                    .frame(width: 76, height: 22)
                                    .background(r.strike == atm ? Theme.accent : Theme.header)
                                side(r.put, call: false, wide: wide)
                            }
                            .id(r.strike)
                        }
                    }
                }
                .onAppear { if let atm { proxy.scrollTo(atm, anchor: .center) } }
                .onChange(of: atm) { _, a in if let a { proxy.scrollTo(a, anchor: .center) } }
            }
        }
    }

    private func columns(call: Bool, wide: Bool) -> [String] {
        let base = wide ? ["OI", "IV", "Δ", "VEGA", "BID", "ASK"] : ["IV", "Δ", "BID", "ASK"]
        return call ? base : base.reversed()
    }

    private func sideHeader(call: Bool, wide: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(columns(call: call, wide: wide), id: \.self) { HeaderCell(text: $0) }
        }
        .padding(.horizontal, 4)
    }

    private func side(_ c: OptionContract?, call: Bool, wide: Bool) -> some View {
        let g = c?.greeks()
        let values: [String: String] = [
            "OI": Fmt.compact(c?.openInterest),
            "IV": c?.iv.map { String(format: "%.1f", $0 * 100) } ?? "—",
            "Δ": g.map { String(format: "%.2f", $0.delta) } ?? "—",
            "VEGA": g.map { String(format: "%.1f", $0.vega) } ?? "—",
            "BID": Fmt.price(c?.bid),
            "ASK": Fmt.price(c?.ask),
        ]
        return HStack(spacing: 0) {
            ForEach(columns(call: call, wide: wide), id: \.self) { k in
                Text(values[k] ?? "—")
                    .font(.mono(10, k == "BID" || k == "ASK" ? .semibold : .regular))
                    .foregroundStyle(k == "BID" ? theme.up : k == "ASK" ? theme.down : k == "IV" ? Theme.accent : Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background((c?.isITM ?? false) ? Theme.selection.opacity(0.55) : Theme.panel)
    }
}

/// IV vs strike for one expiry, using out-of-the-money options on each side (the market convention).
struct SmileChart: View {
    let rows: [StrikeRow]
    let forward: Double
    let theme: Theme

    var body: some View {
        let pts: [(Double, Double)] = rows.compactMap { r in
            let otm = r.strike >= forward ? r.call : r.put
            guard let iv = otm?.iv, abs(log(r.strike / forward)) < 0.6 else { return nil }
            return (r.strike, iv * 100)
        }
        Canvas { ctx, size in
            ctx.draw(Text("VOL SMILE · OTM MARK IV").font(.mono(9, .bold)).foregroundStyle(Theme.label), at: .init(x: 6, y: 4), anchor: .topLeading)
            guard pts.count > 2, let k0 = pts.first?.0, let k1 = pts.last?.0,
                  let v0 = pts.map(\.1).min(), let v1 = pts.map(\.1).max(), k1 > k0 else { return }
            let pad: CGFloat = 22, axis: CGFloat = 44
            let lo = v0 - (v1 - v0) * 0.1 - 0.5, hi = v1 + (v1 - v0) * 0.1 + 0.5
            func x(_ k: Double) -> CGFloat { pad + (size.width - pad - axis) * CGFloat((k - k0) / (k1 - k0)) }
            func y(_ v: Double) -> CGFloat { pad + (size.height - pad * 2) * CGFloat(1 - (v - lo) / (hi - lo)) }
            for t in ChartCanvas.ticks(lo, hi, count: 3) {
                ctx.stroke(Path { $0.move(to: .init(x: pad, y: y(t))); $0.addLine(to: .init(x: size.width - axis, y: y(t))) }, with: .color(Theme.rule), lineWidth: 0.5)
                ctx.draw(Text(String(format: "%.0f%%", t)).font(.mono(8)).foregroundStyle(Theme.dim), at: .init(x: size.width - axis + 4, y: y(t)), anchor: .leading)
            }
            if forward > k0, forward < k1 {
                ctx.stroke(Path { $0.move(to: .init(x: x(forward), y: pad)); $0.addLine(to: .init(x: x(forward), y: size.height - pad)) },
                           with: .color(Theme.warn.opacity(0.7)), style: .init(lineWidth: 0.8, dash: [3, 3]))
                ctx.draw(Text("FWD").font(.mono(8, .bold)).foregroundStyle(Theme.warn), at: .init(x: x(forward) + 3, y: size.height - pad + 2), anchor: .topLeading)
            }
            var p = Path()
            for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: .init(x: x(pt.0), y: y(pt.1))) : p.addLine(to: .init(x: x(pt.0), y: y(pt.1))) }
            ctx.stroke(p, with: .color(Theme.accent), lineWidth: 1.5)
            for pt in pts {
                let c = pt.0 >= forward ? theme.up : theme.down
                ctx.fill(Path(ellipseIn: CGRect(x: x(pt.0) - 2, y: y(pt.1) - 2, width: 4, height: 4)), with: .color(c))
            }
            ctx.draw(Text("\(Fmt.compact(k0)) — \(Fmt.compact(k1)) STRIKE").font(.mono(8)).foregroundStyle(Theme.faint),
                     at: .init(x: pad, y: size.height - pad + 2), anchor: .topLeading)
        }
        .background(Theme.panel)
    }
}

/// ATM implied vol by expiry: contango (upward) is normal; inversion signals near-term stress.
struct TermStructureChart: View {
    let chain: OptionChain
    let selected: Date

    var body: some View {
        let pts: [(Date, Double, Double)] = chain.expiries.compactMap { e in
            chain.atmIV(expiry: e).map { (e, max(e.timeIntervalSinceNow / 86_400, 0.1), $0 * 100) }
        }
        Canvas { ctx, size in
            ctx.draw(Text("ATM TERM STRUCTURE").font(.mono(9, .bold)).foregroundStyle(Theme.label), at: .init(x: 6, y: 4), anchor: .topLeading)
            guard pts.count > 1, let lo0 = pts.map(\.2).min(), let hi0 = pts.map(\.2).max() else { return }
            let pad: CGFloat = 22, axis: CGFloat = 40
            let lo = lo0 - 1, hi = hi0 + 1
            // sqrt time axis spreads the dense front end, as desks plot it.
            let d1 = pts.last!.1.squareRoot(), d0 = pts.first!.1.squareRoot()
            func x(_ d: Double) -> CGFloat { pad + (size.width - pad - axis) * CGFloat((d.squareRoot() - d0) / max(d1 - d0, 1e-9)) }
            func y(_ v: Double) -> CGFloat { pad + (size.height - pad * 2) * CGFloat(1 - (v - lo) / (hi - lo)) }
            for t in ChartCanvas.ticks(lo, hi, count: 3) {
                ctx.stroke(Path { $0.move(to: .init(x: pad, y: y(t))); $0.addLine(to: .init(x: size.width - axis, y: y(t))) }, with: .color(Theme.rule), lineWidth: 0.5)
                ctx.draw(Text(String(format: "%.0f%%", t)).font(.mono(8)).foregroundStyle(Theme.dim), at: .init(x: size.width - axis + 4, y: y(t)), anchor: .leading)
            }
            var p = Path()
            for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: .init(x: x(pt.1), y: y(pt.2))) : p.addLine(to: .init(x: x(pt.1), y: y(pt.2))) }
            ctx.stroke(p, with: .color(Color(hex: 0xC48CFF)), lineWidth: 1.5)
            for pt in pts {
                let sel = pt.0 == selected
                let r: CGFloat = sel ? 4 : 2.5
                ctx.fill(Path(ellipseIn: CGRect(x: x(pt.1) - r, y: y(pt.2) - r, width: r * 2, height: r * 2)),
                         with: .color(sel ? Theme.accent : Color(hex: 0xC48CFF)))
                if sel {
                    ctx.draw(Text(String(format: "%.1f%%", pt.2)).font(.mono(9, .bold)).foregroundStyle(Theme.accent),
                             at: .init(x: x(pt.1), y: y(pt.2) - 8), anchor: .bottom)
                }
            }
            ctx.draw(Text("\(Int(pts.first!.1.rounded()))D — \(Int(pts.last!.1.rounded()))D").font(.mono(8)).foregroundStyle(Theme.faint),
                     at: .init(x: pad, y: size.height - pad + 2), anchor: .topLeading)
        }
        .background(Theme.panel)
    }
}
