import SwiftUI
import KestrelCore

/// ERN: next earnings for every equity on the active watchlist, projected from each company's
/// own reporting cadence in its SEC filings, soonest first. Tap a row for its filings (EVTS).
struct EarningsCalendarView: View {
    let panelID: Int
    @Environment(FundamentalsService.self) private var sec
    @Environment(UserData.self) private var user
    @Environment(MarketStore.self) private var market
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    private var equities: [Instrument] {
        user.active.symbols.compactMap { Universe.instrument(symbol: $0) ?? Universe.resolve($0) }.filter { $0.assetClass == .equity }
    }

    private struct Row: Identifiable {
        let instrument: Instrument
        let estimate: SECFilings.EarningsEstimate?
        let state: String?
        var id: String { instrument.symbol }
    }

    private var rows: [Row] {
        equities.map { i in
            switch sec.filings[i.symbol] {
            case .success(let f): Row(instrument: i, estimate: SECFilings.earningsEstimate(f), state: nil)
            case .failure(.notFound): Row(instrument: i, estimate: nil, state: "no SEC filer")
            case .failure(.failed): Row(instrument: i, estimate: nil, state: "SEC error")
            case nil: Row(instrument: i, estimate: nil, state: "loading")
            }
        }
        .sorted { ($0.estimate?.next ?? .distantFuture) < ($1.estimate?.next ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if !sec.hasValidContact {
                VStack(spacing: 12) {
                    EmptyNote(title: "Earnings need a contact email", detail: "SEC EDGAR asks apps to identify themselves. Add a contact once in PREF.", icon: "calendar.badge.clock")
                    Hotspot(number: 1, title: "PREF Open settings") { ws.load(Command(function: .pref), in: panelID) }
                }
            } else if equities.isEmpty {
                EmptyNote(title: "No equities on \(user.active.name)", detail: "Add stocks with W, then come back to ERN.", icon: "calendar.badge.clock")
            } else {
                table
            }
        }
        // SEC fair access is 10 requests/s: load one company at a time with a small gap.
        .task(id: "\(equities.map(\.symbol).joined(separator: ","))|\(sec.hasValidContact)") {
            for i in equities where sec.filings[i.symbol] == nil {
                await sec.loadFilings(i)
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
        }
    }

    private var table: some View {
        let all = rows
        let now = Date()
        func bucket(_ r: Row) -> String {
            guard let n = r.estimate?.next else { return "UNKNOWN" }
            let days = n.timeIntervalSince(now) / 86_400
            return days <= 7 ? "NEXT 7 DAYS" : days <= 30 ? "NEXT 30 DAYS" : "LATER"
        }
        let order = ["NEXT 7 DAYS", "NEXT 30 DAYS", "LATER", "UNKNOWN"]
        let loaded = all.filter { $0.state != "loading" }.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionBar(title: "EARNINGS · \(user.active.name.uppercased())", trailing: loaded < all.count ? "LOADING \(loaded)/\(all.count) FROM SEC" : "\(all.count) COMPANIES · SEC EDGAR")
                header
                ForEach(order, id: \.self) { b in
                    let group = all.filter { bucket($0) == b }
                    if !group.isEmpty {
                        Text(b).font(.mono(9, .heavy)).foregroundStyle(b == "NEXT 7 DAYS" ? Theme.warn : Theme.accent)
                            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 3)
                        ForEach(Array(group.enumerated()), id: \.element.id) { n, r in row(r, now).rowBackground(n) }
                    }
                }
                Text("Estimated: last earnings release (8-K item 2.02) plus the company's median gap between its recent releases; ± is the median deviation of those gaps. Companies announce exact dates themselves.")
                    .font(.mono(9)).foregroundStyle(Theme.faint).padding(8)
            }
        }
    }

    private var header: some View {
        HStack {
            HeaderCell(text: "TICKER", width: 64, align: .leading)
            HeaderCell(text: "NAME", width: 170, align: .leading)
            HeaderCell(text: "LAST")
            HeaderCell(text: "LAST REPORT")
            HeaderCell(text: "NEXT (EST.)")
            HeaderCell(text: "IN")
            HeaderCell(text: "CADENCE")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
    }

    private func row(_ r: Row, _ now: Date) -> some View {
        let i = r.instrument, e = r.estimate
        let days = e.map { Int(($0.next.timeIntervalSince(now) / 86_400).rounded(.up)) }
        return Button { ws.run("\(i.ticker) EVTS") } label: {
            HStack {
                Text(i.ticker).font(.mono(12, .bold)).foregroundStyle(Theme.text).frame(width: 64, alignment: .leading)
                Text(i.name).font(.ui(11)).foregroundStyle(Theme.dim).lineLimit(1).frame(width: 170, alignment: .leading)
                Text(Fmt.price(market.quotes[i.symbol]?.last, i.assetClass)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
                Text(e.map { $0.last.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)) } ?? "—").foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
                Text(e.map { $0.next.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? (r.state ?? "—"))
                    .foregroundStyle(e == nil ? Theme.faint : Theme.warn).frame(maxWidth: .infinity, alignment: .trailing)
                Text(days.map { "\($0)d" + (e?.spreadDays.map { String(format: " ±%.0f", $0) } ?? "") } ?? "")
                    .foregroundStyle((days ?? 99) <= 7 ? Theme.warn : Theme.text).frame(maxWidth: .infinity, alignment: .trailing)
                Text(e.map { String(format: "%.0fd · %d", $0.cadenceDays, $0.releases) } ?? "").foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.mono(11)).monospacedDigit()
            .padding(.horizontal, 8).frame(height: 26).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open \(i.ticker) filings")
    }
}
