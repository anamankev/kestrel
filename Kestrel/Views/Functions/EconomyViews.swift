import SwiftUI
import KestrelCore

/// ECO: US policy rates, the Treasury curve, inflation and the labour market in one screen.
struct EconomyView: View {
    let panelID: Int
    @Environment(MacroService.self) private var macro
    @Environment(MarketStore.self) private var market
    @Environment(Theme.self) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                policy
                curve
                ForEach(["INFLATION", "LABOR"], id: \.self) { g in
                    VStack(spacing: 0) {
                        SectionBar(title: g, trailing: "BLS · MONTHLY")
                        header
                        ForEach(Array(MacroIndicator.all.filter { $0.group == g }.enumerated()), id: \.element.id) { n, ind in
                            indicatorRow(ind).rowBackground(n)
                        }
                    }
                }
                HStack {
                    if let e = macro.error { Text(e).foregroundStyle(Theme.cancel) }
                    else if macro.loading { Text("Loading…").foregroundStyle(Theme.dim) }
                    Spacer()
                    Text(macro.updated.map { "UPDATED \($0.formatted(Fmt.clock))" } ?? "").foregroundStyle(Theme.faint)
                }
                .font(.mono(9)).padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
        }
        .task { await macro.load() }
    }

    private var policy: some View {
        HStack(spacing: 1) {
            rateTile("FED FUNDS (EFFR)", macro.effr, target: true)
            rateTile("SOFR", macro.sofr, target: false)
        }
        .background(Theme.rule)
        .padding(.horizontal, 8)
    }

    private func rateTile(_ title: String, _ r: NYFed.Rates?, target: Bool) -> some View {
        let last = r?.series.last
        let prior = r?.series.dropLast().last
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.mono(9, .bold)).foregroundStyle(Theme.label)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(last.map { String(format: "%.2f%%", $0.value) } ?? "—").font(.mono(20, .semibold)).foregroundStyle(Theme.text)
                if let l = last, let p = prior {
                    let bp = ((l.value - p.value) * 100).rounded()
                    Text(String(format: "%+.0f bp d/d", bp)).font(.mono(11, .medium)).foregroundStyle(theme.tint(bp))
                }
            }
            if target, let lo = r?.targetLow, let hi = r?.targetHigh {
                Text(String(format: "TARGET %.2f–%.2f%%", lo, hi)).font(.mono(10, .semibold)).foregroundStyle(Theme.warn)
            }
            Sparkline(values: r?.series.map(\.value) ?? []).frame(height: 28.pt)
            Text(last.map { "as of \($0.date.formatted(.dateTime.month(.abbreviated).day()))" } ?? "").font(.mono(9)).foregroundStyle(Theme.faint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
    }

    /// Treasury curve from the delayed quotes already streaming in, plus the 10Y–3M spread
    /// (an inverted curve historically precedes recessions).
    private var curve: some View {
        let tenors = Universe.rates
        let ys = tenors.map { market.quotes[$0.symbol]?.last }
        let spread: Double? = {
            guard let t10 = market.quotes["^TNX"]?.last, let t3m = market.quotes["^IRX"]?.last else { return nil }
            return (t10 - t3m) * 100
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TREASURY CURVE").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                Spacer()
                if let s = spread {
                    Text(String(format: "10Y–3M %+.0f bp", s)).font(.mono(10, .bold)).foregroundStyle(s < 0 ? theme.down : theme.up)
                    if s < 0 { Text("INVERTED").font(.mono(9, .heavy)).foregroundStyle(Theme.canvas).padding(.horizontal, 4).background(theme.down) }
                }
            }
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array(tenors.enumerated()), id: \.offset) { i, t in
                    VStack(spacing: 2) {
                        Text(ys[i].map { String(format: "%.2f", $0) } ?? "—").font(.mono(13, .semibold)).foregroundStyle(Theme.text)
                        Text(t.ticker.replacingOccurrences(of: "US", with: "")).font(.mono(9, .bold)).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
            }
        }
        .padding(10)
        .background(Theme.panel)
        .padding(.horizontal, 8)
    }

    private var header: some View {
        HStack {
            Text("INDICATOR").font(.mono(10, .semibold)).foregroundStyle(Theme.label).lineLimit(1)
                .frame(minWidth: 110.pt, idealWidth: 260.pt, maxWidth: 260.pt, alignment: .leading)
            HeaderCell(text: "LATEST"); HeaderCell(text: "PRIOR"); HeaderCell(text: "CHG")
            HeaderCell(text: "PERIOD", width: 60.pt)
            HeaderCell(text: "2Y TREND", width: 90.pt, align: .center)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
    }

    /// BLS months are stored as the 1st at 00:00 UTC; format in UTC or US timezones show the prior month.
    private static let month: Date.FormatStyle = {
        var f = Date.FormatStyle.dateTime.month(.abbreviated).year(.twoDigits)
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }()

    private func indicatorRow(_ ind: MacroIndicator) -> some View {
        let s = ind.series(macro.series[ind.id] ?? [])
        let last = s.last, prior = s.dropLast().last
        func fmt(_ v: Double?) -> String {
            guard let v else { return "—" }
            return ind.unit == "K" ? String(format: "%+.0fK", v) : String(format: "%.1f%%", v)
        }
        let chg = (last?.value).flatMap { l in prior.map { l - $0.value } }
        return HStack {
            Text(ind.name).font(.ui(12)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 110.pt, idealWidth: 260.pt, maxWidth: 260.pt, alignment: .leading)
            Text(fmt(last?.value)).font(.mono(12, .semibold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
            Text(fmt(prior?.value)).font(.mono(11)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
            Text(chg.map { ind.unit == "K" ? String(format: "%+.0fK", $0) : String(format: "%+.1f", $0) } ?? "—")
                .font(.mono(11)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
            Text(last.map { $0.date.formatted(Self.month) } ?? "—")
                .font(.mono(10)).foregroundStyle(Theme.dim).frame(width: 60.pt, alignment: .trailing)
            Sparkline(values: s.suffix(24).map(\.value)).frame(width: 90.pt, height: 18.pt)
        }
        .monospacedDigit()
        .padding(.horizontal, 8).frame(height: 26.pt)
    }
}

/// EVTS: material SEC filings as a timeline, with an estimated next earnings date and insider
/// activity count.
struct EventsView: View {
    let instrument: Instrument
    let panelID: Int
    @Environment(FundamentalsService.self) private var sec
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if instrument.assetClass != .equity {
                EmptyNote(title: "No SEC filings for \(instrument.ticker)", detail: "EVTS covers US-listed companies.", icon: "calendar")
            } else if !sec.hasValidContact {
                VStack(spacing: 12) {
                    EmptyNote(title: "Filings need a contact email", detail: "SEC EDGAR asks apps to identify themselves. Add a contact once in PREF.", icon: "calendar")
                    Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
                }
            } else {
                switch sec.filings[instrument.symbol] {
                case nil: ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure(.notFound): EmptyNote(title: "\(instrument.ticker) has no SEC filer record", icon: "calendar")
                case .failure(.failed(let why)): EmptyNote(title: "SEC request failed", detail: why, icon: "exclamationmark.triangle")
                case .success(let f): timeline(f)
                }
            }
        }
        .task(id: "\(instrument.symbol)|\(sec.hasValidContact)") { await sec.loadFilings(instrument) }
    }

    private func timeline(_ all: [Filing]) -> some View {
        let insiders = all.filter { $0.form == "4" && $0.date > Date().addingTimeInterval(-90 * 86_400) }.count
        let shown = all.filter { $0.form != "4" }
        let next = SECFilings.estimatedNextEarnings(all)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT EARNINGS (EST.)").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                        Text(next.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "—").font(.mono(15, .semibold)).foregroundStyle(Theme.warn)
                        Text("from the company's own reporting cadence").font(.mono(8)).foregroundStyle(Theme.faint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INSIDER FILINGS · 90D").font(.mono(9, .bold)).foregroundStyle(Theme.label)
                        Text("\(insiders) Form 4").font(.mono(15, .semibold)).foregroundStyle(Theme.text)
                    }
                    Spacer()
                }
                .padding(10)
                SectionBar(title: "MATERIAL FILINGS", trailing: "SEC EDGAR")
                ForEach(Array(shown.enumerated()), id: \.element.id) { n, f in
                    Button { openURL(f.url) } label: {
                        HStack(spacing: 10) {
                            Text(f.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))).font(.mono(10)).foregroundStyle(Theme.dim).frame(width: 82.pt, alignment: .leading)
                            Text(f.form).font(.mono(9, .heavy))
                                .foregroundStyle(f.isEarnings ? Theme.canvas : Theme.label)
                                .padding(.horizontal, 5).frame(height: 16.pt)
                                .background(f.isEarnings ? Theme.warn : Theme.header, in: .rect(cornerRadius: 2))
                                .frame(width: 70.pt, alignment: .leading)
                            Text(f.title).font(.ui(12, f.isEarnings ? .semibold : .regular)).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(Theme.faint)
                        }
                        .padding(.horizontal, 8).frame(height: 26.pt).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .rowBackground(n)
                }
            }
        }
    }
}
