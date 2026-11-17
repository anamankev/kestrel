import SwiftUI
import KestrelCore

/// SECF: find any listed security by name or ticker, across every exchange and asset class.
/// Tap a row to load its description; + adds it to the active watchlist.
struct SecurityFinderView: View {
    let panelID: Int
    /// Query typed on the command line.
    var initial: String?
    @Environment(MarketStore.self) private var market
    @Environment(UserData.self) private var user
    @Environment(Workspace.self) private var ws

    enum Filter: String, CaseIterable {
        case all = "ALL", equity = "STOCKS & FUNDS", index = "INDICES", fx = "FX", futures = "FUTURES", crypto = "CRYPTO"
        func admits(_ c: AssetClass) -> Bool {
            switch self {
            case .all: true
            case .equity: c == .equity
            case .index: c == .index
            case .fx: c == .fx
            case .futures: c == .commodity
            case .crypto: c == .crypto
            }
        }
    }

    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var filter: Filter = .all
    @State private var note: String?
    @FocusState private var focused: Bool

    private var shown: [SearchHit] { hits.filter { filter.admits($0.instrument.assetClass) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.dim)
                TextField("", text: $query)
                    .placeholder("Company or ticker: toyota, nestle, 7203.T, gold, GBPJPY", when: query.isEmpty)
                    .font(.mono(13, .medium)).foregroundStyle(Theme.text).textFieldStyle(.plain)
                    .autocorrectionDisabled().focused($focused)
                if searching { ProgressView().controlSize(.small).tint(Theme.accent) }
            }
            .padding(10).background(Theme.canvas)
            .overlay(Rectangle().stroke(focused ? Theme.accentDim : Theme.rule))
            .padding(8)
            Picker("Type", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 8).padding(.bottom, 8)
            SectionBar(title: "SECURITY FINDER · ALL EXCHANGES",
                       trailing: note ?? (hits.isEmpty ? nil : "\(shown.count) OF \(hits.count) MATCHES"))
            if !shown.isEmpty { header }
            if shown.isEmpty {
                EmptyNote(title: query.count < 2 ? "Search every market" : (searching ? "Searching…" : "No matches"),
                          detail: query.count < 2 ? "Stocks and ETFs on exchanges worldwide, indices, currency pairs, futures and crypto. Results come from Yahoo Finance; prices are delayed except Coinbase crypto." : nil,
                          icon: "globe")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { n, h in row(h).rowBackground(n) }
                    }
                }
            }
        }
        .onAppear { if let initial { query = initial.lowercased() } else { focused = true } }
        .onChange(of: initial) { if let initial { query = initial.lowercased() } }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            let found = await market.search(q, limit: 25)
            guard !Task.isCancelled else { return }
            hits = found
            searching = false
        }
        .task(id: note) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            note = nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("TICKER").frame(width: 150, alignment: .leading)
            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("TYPE").frame(width: 110, alignment: .leading)
            Text("EXCHANGE").frame(width: 120, alignment: .leading)
            Color.clear.frame(width: 28, height: 1)
        }
        .font(.mono(9, .bold)).foregroundStyle(Theme.label)
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func row(_ h: SearchHit) -> some View {
        HStack(spacing: 8) {
            Button { ws.load(Command(function: .des, instrument: h.instrument), in: panelID) } label: {
                HStack(spacing: 8) {
                    Text(h.token).font(.mono(12, .bold)).foregroundStyle(Theme.accent).lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                    Text(h.instrument.name).font(.ui(12)).foregroundStyle(Theme.text).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(h.kind.uppercased()).font(.mono(10)).foregroundStyle(Theme.dim).lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    Text(h.exchange).font(.mono(10)).foregroundStyle(Theme.dim).lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button {
                note = user.add(h.token) ?? "ADDED \(h.token) TO \(user.active.name.uppercased())"
            } label: {
                Image(systemName: user.active.symbols.contains(h.instrument.symbol) ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent).frame(width: 28, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(h.token) to watchlist")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}
