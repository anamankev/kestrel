import SwiftUI
import KestrelCore

/// CORR: pairwise correlation of daily returns, as a heat-mapped matrix. Two baskets: a fixed
/// cross-asset set (equities, rates proxies, FX, commodities, crypto) or the active watchlist.
struct CorrelationView: View {
    let panelID: Int
    @Environment(MarketStore.self) private var market
    @Environment(UserData.self) private var user
    @Environment(Workspace.self) private var ws
    @Environment(Theme.self) private var theme

    enum Basket: String, CaseIterable { case cross = "CROSS-ASSET", watchlist = "WATCHLIST" }
    enum Window: String, CaseIterable {
        case m3 = "3M", y1 = "1Y", y2 = "2Y"
        var yahoo: String { rawValue.lowercased() == "3m" ? "3mo" : rawValue.lowercased() }
    }

    struct Matrix: Equatable { var symbols: [Instrument]; var values: [[Double?]]; var days: Int }

    @AppStorage("corr.basket") private var basket: Basket = .cross
    @AppStorage("corr.window") private var window: Window = .y1
    @State private var matrix: Matrix?
    @State private var loading = false
    @State private var hover: (Int, Int)?

    private static let maxSymbols = 14
    private static let crossAsset = ["SPX", "CCMP", "RTY", "UKX", "DAX", "VIX", "EURUSD", "USDJPY", "GC1", "CL1", "BTC", "ETH"]

    private var instruments: [Instrument] {
        let list: [Instrument] = switch basket {
        case .cross: Self.crossAsset.compactMap { Universe.resolve($0) }
        case .watchlist: user.active.symbols.compactMap { Universe.instrument(symbol: $0) ?? Universe.resolve($0) }
        }
        var seen = Set<String>()
        return Array(list.filter { Deribit.parse($0.symbol) == nil && seen.insert($0.symbol).inserted }.prefix(Self.maxSymbols))
    }

    private var key: String { "\(basket.rawValue)|\(window.rawValue)|\(instruments.map(\.symbol).joined(separator: ","))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            SectionBar(title: "DAILY RETURNS · PEARSON",
                       trailing: loading ? "COMPUTING…" : matrix.map { "\($0.days) SHARED DAYS · \($0.symbols.count) SECURITIES" })
            if let m = matrix, m.symbols.count >= 2 {
                GeometryReader { g in grid(m, size: g.size) }
                    .padding(8)
                legend
            } else if !loading {
                EmptyNote(title: "Need at least two securities with history",
                          detail: basket == .watchlist ? "Add symbols to \(user.active.name) with W, or switch to CROSS-ASSET." : nil,
                          icon: "square.grid.3x3")
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: key) { await compute() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Basket", selection: $basket) { ForEach(Basket.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).frame(maxWidth: 260)
            Picker("Window", selection: $window) { ForEach(Window.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).frame(maxWidth: 150)
            Spacer()
            if let (r, c) = hover, let m = matrix, r < m.symbols.count, c < m.symbols.count {
                Text("\(m.symbols[r].ticker) × \(m.symbols[c].ticker)  \(fmt(m.values[r][c]))")
                    .font(.mono(11, .semibold)).foregroundStyle(Theme.text)
            }
        }
        .padding(8)
    }

    private func grid(_ m: Matrix, size: CGSize) -> some View {
        let n = m.symbols.count
        let label: CGFloat = 58
        let cell = max(min((size.width - label - CGFloat(n)) / CGFloat(n), (size.height - 21 - CGFloat(n)) / CGFloat(n)), 18)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 1) {
                Color.clear.frame(width: label, height: 20)
                ForEach(0..<n, id: \.self) { c in
                    Text(m.symbols[c].ticker).font(.mono(cell > 40 ? 9 : 7, .bold)).foregroundStyle(Theme.label)
                        .lineLimit(1).minimumScaleFactor(0.6).frame(width: cell, height: 20)
                }
            }
            ForEach(0..<n, id: \.self) { r in
                HStack(spacing: 1) {
                    Button { ws.link(m.symbols[r], from: panelID) } label: {
                        Text(m.symbols[r].ticker).font(.mono(10, .bold)).foregroundStyle(Theme.label)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(width: label, height: cell, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    ForEach(0..<n, id: \.self) { c in
                        let v = m.values[r][c]
                        Text(cell > 34 ? fmt(v, short: true) : "")
                            .font(.mono(cell > 50 ? 11 : 9, .semibold)).monospacedDigit()
                            .foregroundStyle(r == c ? Theme.faint : Theme.text)
                            .frame(width: cell, height: cell)
                            .background(color(v, diagonal: r == c))
                            .overlay { if hover.map({ $0 == (r, c) || $0 == (c, r) }) == true { Rectangle().stroke(Theme.accent, lineWidth: 1) } }
                            .onTapGesture { hover = (r, c) }
                            #if os(macOS)
                            .onHover { if $0 { hover = (r, c) } }
                            #endif
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("−1").font(.mono(9)).foregroundStyle(Theme.dim)
            LinearGradient(colors: [color(-1), color(-0.5), color(0), color(0.5), color(1)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 180, height: 8)
            Text("+1").font(.mono(9)).foregroundStyle(Theme.dim)
            Spacer()
            Text("Tap a cell for the pair · tap a row label to load the security").font(.mono(9)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 8).padding(.bottom, 8)
    }

    private func fmt(_ v: Double?, short: Bool = false) -> String {
        guard let v else { return "—" }
        return short ? String(format: "%.2f", v).replacingOccurrences(of: "0.", with: ".") : String(format: "%+.2f", v)
    }

    /// Diverging scale: positive correlation in the accent, negative in the warning colour.
    private func color(_ v: Double?, diagonal: Bool = false) -> Color {
        guard let v, !diagonal else { return Theme.panel }
        let a = 0.12 + 0.78 * min(abs(v), 1)
        return (v >= 0 ? Theme.accent : Theme.warn).opacity(abs(v) < 0.05 ? 0.06 : a)
    }

    private func compute() async {
        let list = instruments
        guard list.count >= 2 else { matrix = nil; return }
        loading = true
        defer { loading = false }
        let range = window.yahoo
        var histories: [String: [Candle]] = [:]
        await withTaskGroup(of: (String, [Candle]).self) { g in
            for i in list {
                g.addTask { (i.symbol, (try? await market.history(for: i, range: range, weekly: false)) ?? []) }
            }
            for await (s, c) in g where c.count > 20 { histories[s] = c }
        }
        guard !Task.isCancelled else { return }
        let kept = list.filter { histories[$0.symbol] != nil }
        let returns = Risk.alignedReturns(histories)
        let symbols = kept.map(\.symbol)
        let values = await Task.detached { Risk.correlationMatrix(returns, symbols: symbols) }.value
        matrix = Matrix(symbols: kept, values: values, days: returns.values.first?.count ?? 0)
        hover = nil
    }
}
