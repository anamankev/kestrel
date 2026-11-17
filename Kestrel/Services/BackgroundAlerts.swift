import Foundation
import KestrelCore
#if os(iOS)
import BackgroundTasks
#endif

/// Price alerts while Kestrel isn't on screen.
/// - iPad: a background app-refresh task fetches the alerted symbols and runs the same alert
///   check as the live feed (which posts a local notification). iPadOS chooses when it runs,
///   typically every 15 minutes or more, so it complements the live feed rather than replacing it.
/// - Mac: the app keeps running in the menu bar after its window closes, so the live feed and
///   alerts continue (see `AlertsMenu`).
@MainActor
enum BackgroundAlerts {
    static let taskID = "dev.kestrel.terminal.alerts"
    static weak var auth: AuthService?
    static weak var market: MarketStore?

    /// Fetches current quotes for every symbol with an active alert and checks them.
    /// Returns the number of alerts that fired.
    @discardableResult
    static func checkNow() async -> Int {
        guard let data = auth?.space?.data, let market else { return 0 }
        let symbols = data.alerts.watchedSymbols
        guard !symbols.isEmpty else { return 0 }
        let before = data.alerts.history.count
        let instruments = symbols.compactMap { Universe.instrument(symbol: $0) ?? Universe.resolve($0) }
        for i in instruments where i.isStreaming {
            if let q = await market.restTicker(i) { data.check(i.symbol, q) }
        }
        let delayed = instruments.filter { !$0.isStreaming && $0.assetClass != .option }
        if !delayed.isEmpty {
            await market.refresh(delayed)
            for i in delayed { if let q = market.quotes[i.symbol] { data.check(i.symbol, q) } }
        }
        return data.alerts.history.count - before
    }

    #if os(iOS)
    static func schedule() {
        guard auth?.space?.data.alerts.active.isEmpty == false else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request) } catch { marketLog.error("alert refresh not scheduled: \(error.localizedDescription, privacy: .public)") }
    }

    static func handleRefresh() async {
        let fired = await checkNow()
        marketLog.info("background alert check: \(fired) fired")
        schedule()
    }
    #endif
}

extension MarketStore {
    /// One-shot Coinbase ticker for a streaming product (used when the WebSocket isn't running).
    func restTicker(_ i: Instrument) async -> Quote? {
        struct Ticker: Decodable { let price: String; let bid: String?; let ask: String?; let volume: String? }
        guard let url = URL(string: "https://api.exchange.coinbase.com/products/\(i.symbol)/ticker"),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let t = try? JSONDecoder().decode(Ticker.self, from: data), let last = Double(t.price) else { return nil }
        var q = quotes[i.symbol] ?? Quote(last: last)
        q.last = last
        q.bid = t.bid.flatMap(Double.init); q.ask = t.ask.flatMap(Double.init)
        q.time = .now
        return q
    }
}
