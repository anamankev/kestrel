import Foundation
import KestrelCore

/// Live crypto market data over Coinbase's public WebSocket.
///
/// Runs off the main actor: every message is decoded and applied to order books here, and the UI
/// pulls a coalesced `Batch` at display rate. Hundreds of L2 messages per second therefore cost the
/// main thread one small diff per frame. Sequence gaps or socket errors trigger a reconnect with
/// exponential backoff, and the fresh snapshot rebuilds every book.
actor CoinbaseStream {
    enum Link: String, Sendable { case connecting = "CONNECTING", live = "LIVE", reconnecting = "RECONNECTING", stale = "STALE" }

    nonisolated struct Batch: Sendable {
        var quotes: [String: Quote] = [:]
        var books: [String: OrderBook] = [:]
        var prints: [String: [TapePrint]] = [:]
        var link: Link = .connecting
        var messagesPerSecond: Double = 0
    }

    private let products: [String]
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var books: [String: OrderBook] = [:]
    private var pending = Batch()
    private var dirtyBooks: Set<String> = []
    private var lastSequence: Int?
    private var link: Link = .connecting
    private var messageCount = 0
    private var lastMessageAt = Date()
    private var rateWindowStart = Date()
    private var rate = 0.0

    init(products: [String]) {
        self.products = products
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        session = URLSession(configuration: cfg)
    }

    /// Connects and keeps the feed alive until the calling task is cancelled.
    func run() async {
        var backoff: Duration = .milliseconds(500)
        while !Task.isCancelled {
            let ws = session.webSocketTask(with: CoinbaseFeed.url)
            ws.maximumMessageSize = 16 << 20 // L2 snapshots are large
            socket = ws
            lastSequence = nil
            ws.resume()
            do {
                for channel in ["heartbeats", "ticker", "level2", "market_trades"] {
                    try await ws.send(.string(CoinbaseFeed.subscribe(channel, products: products)))
                }
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    try handle(message)
                    if link != .live { link = .live; backoff = .milliseconds(500) }
                }
            } catch {
                ws.cancel(with: .goingAway, reason: nil)
                link = .reconnecting
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, .seconds(30))
            }
        }
    }

    private struct SequenceGap: Error {}
    private struct Header: Decodable { let sequence_num: Int? }

    private func handle(_ message: URLSessionWebSocketTask.Message) throws {
        let data: Data
        switch message {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: return
        }
        messageCount += 1
        lastMessageAt = Date()

        if let seq = try? JSONDecoder().decode(Header.self, from: data).sequence_num {
            if let last = lastSequence, seq != last + 1 { throw SequenceGap() } // books may be stale: resync
            lastSequence = seq
        }

        for event in (try? CoinbaseFeed.decode(data)) ?? [] {
            switch event {
            case .ticker(let p, let q):
                pending.quotes[p] = q
            case .book(let p, let snapshot, let updates):
                // Mutate in place: a copy-out/copy-back would duplicate the whole book per message.
                if snapshot { books[p, default: OrderBook()].reset() }
                for u in updates { books[p, default: OrderBook()].apply(u.side, price: u.price, size: u.size) }
                dirtyBooks.insert(p)
            case .trades(let p, let prints):
                pending.prints[p, default: []].insert(contentsOf: prints, at: 0)
            case .other:
                break
            }
        }
    }

    /// Everything that changed since the last drain.
    func drain() -> Batch {
        let now = Date()
        // Watchdog: heartbeats arrive every second, so 15 s of silence means a dead socket
        // that never errored (sleep, network handoff). Cancelling makes receive() throw → reconnect.
        if link == .live, now.timeIntervalSince(lastMessageAt) > 15 {
            link = .stale
            socket?.cancel(with: .abnormalClosure, reason: nil)
        }
        let dt = now.timeIntervalSince(rateWindowStart)
        if dt >= 1 {
            rate = Double(messageCount) / dt
            messageCount = 0
            rateWindowStart = now
        }
        var out = pending
        for p in dirtyBooks { out.books[p] = books[p] }
        out.link = link
        out.messagesPerSecond = rate
        pending = Batch()
        dirtyBooks.removeAll(keepingCapacity: true)
        return out
    }
}
