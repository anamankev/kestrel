import Foundation
import KestrelCore

/// Main-actor wrapper around the pure `PaperAccount`: persistence, live marking and fill alerts.
@Observable final class PaperBroker {
    private(set) var account: PaperAccount
    private(set) var marks: [String: Decimal] = [:]
    var lastFill: Fill?
    /// Account value over time, sampled every 5 minutes while the app runs and on each fill.
    private(set) var curve: [EquityPoint] = []

    struct EquityPoint: Codable, Equatable { var t: Date; var v: Double }
    @ObservationIgnored private let curveURL: URL
    @ObservationIgnored private let url: URL

    @ObservationIgnored private let store: SecureStore

    /// - Parameters: `dir` is the signed-in user's folder; `store` seals files with their key.
    init(dir: URL, store: SecureStore = SecureStore(key: nil)) {
        self.store = store
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appending(path: "paper-account.json")
        curveURL = dir.appending(path: "equity-curve.json")
        account = store.read(url).flatMap { try? JSONDecoder().decode(PaperAccount.self, from: $0) } ?? PaperAccount()
        curve = store.read(curveURL).flatMap { try? JSONDecoder().decode([EquityPoint].self, from: $0) } ?? []
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                self?.recordEquity()
            }
        }
    }

    func recordEquity() {
        // Only meaningful once every open position has a live mark.
        guard account.openPositions.allSatisfy({ marks[$0.symbol] != nil }) else { return }
        let v = equity.double
        if let last = curve.last, abs(last.v - v) < 0.005, Date().timeIntervalSince(last.t) < 3600 { return }
        curve.append(EquityPoint(t: .now, v: v))
        if curve.count > 3000 { curve.removeFirst(curve.count - 3000) }
        if let data = try? JSONEncoder().encode(curve) { store.write(data, to: curveURL) }
    }

    /// Rewrites everything through the store (used once to encrypt legacy plaintext files).
    func persistAll() {
        save()
        if let data = try? JSONEncoder().encode(curve) { store.write(data, to: curveURL) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(account) else { return }
        store.write(data, to: url)
    }

    func touch(_ q: Quote) -> Touch? { Touch(market: q.bid, ask: q.ask, last: q.last) }

    /// Feed from the market store. Only symbols we hold or work orders in cost anything.
    func mark(_ symbol: String, _ q: Quote) {
        guard let t = touch(q) else { return }
        let relevant = account.positions[symbol] != nil || account.workingOrders.contains { $0.symbol == symbol }
        guard relevant else { return }
        marks[symbol] = t.last
        let fills = account.mark(symbol: symbol, touch: t)
        if let f = fills.last { lastFill = f }
        if !fills.isEmpty { save(); recordEquity() }
    }

    func submit(_ i: Instrument, side: TradeSide, quantity: Decimal, type: OrderType, quote: Quote?) throws(OrderReject) -> Order {
        let order = try account.submit(symbol: i.symbol, side: side, quantity: quantity, type: type,
                                       touch: quote.flatMap(touch))
        if let q = quote { marks[i.symbol] = Decimal.price(q.last) }
        if order.status == .filled, let f = account.fills.last { lastFill = f }
        save()
        recordEquity()
        return order
    }

    func cancel(_ id: Int) { account.cancel(id); save() }

    func reset() {
        account = PaperAccount(); marks = [:]; save()
        curve = []; try? FileManager.default.removeItem(at: curveURL)
    }

    var equity: Decimal { account.equity(marks: marks) }
    var unrealized: Decimal {
        account.openPositions.reduce(0) { $0 + $1.unrealized(mark: marks[$1.symbol] ?? $1.averageCost) }
    }
    var totalPnL: Decimal { equity - PaperAccount.startingCash }
}
