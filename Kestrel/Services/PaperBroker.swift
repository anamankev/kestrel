import Foundation
import KestrelCore

/// Main-actor wrapper around the pure `PaperAccount`: persistence, live marking and fill alerts.
@Observable final class PaperBroker {
    private(set) var account: PaperAccount
    private(set) var marks: [String: Decimal] = [:]
    var lastFill: Fill?

    @ObservationIgnored private let url: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Kestrel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "paper-account.json")
    }()

    init() {
        account = (try? JSONDecoder().decode(PaperAccount.self, from: Data(contentsOf: url))) ?? PaperAccount()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(account) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
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
        if !fills.isEmpty { save() }
    }

    func submit(_ i: Instrument, side: TradeSide, quantity: Decimal, type: OrderType, quote: Quote?) throws(OrderReject) -> Order {
        let order = try account.submit(symbol: i.symbol, side: side, quantity: quantity, type: type,
                                       touch: quote.flatMap(touch))
        if let q = quote { marks[i.symbol] = Decimal.price(q.last) }
        if order.status == .filled, let f = account.fills.last { lastFill = f }
        save()
        return order
    }

    func cancel(_ id: Int) { account.cancel(id); save() }

    func reset() { account = PaperAccount(); marks = [:]; save() }

    var equity: Decimal { account.equity(marks: marks) }
    var unrealized: Decimal {
        account.openPositions.reduce(0) { $0 + $1.unrealized(mark: marks[$1.symbol] ?? $1.averageCost) }
    }
    var totalPnL: Decimal { equity - PaperAccount.startingCash }
}
