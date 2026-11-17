import Foundation

public struct Quote: Sendable, Equatable {
    public var last: Double
    public var previousClose: Double?
    public var bid: Double?
    public var ask: Double?
    public var high: Double?
    public var low: Double?
    public var volume: Double?
    public var high52: Double?
    public var low52: Double?
    public var time: Date

    public init(last: Double, previousClose: Double? = nil, bid: Double? = nil, ask: Double? = nil,
                high: Double? = nil, low: Double? = nil, volume: Double? = nil,
                high52: Double? = nil, low52: Double? = nil, time: Date = .now) {
        self.last = last; self.previousClose = previousClose; self.bid = bid; self.ask = ask
        self.high = high; self.low = low; self.volume = volume; self.high52 = high52; self.low52 = low52
        self.time = time
    }

    public var change: Double? { previousClose.map { last - $0 } }
    public var changePercent: Double? {
        guard let p = previousClose, p != 0 else { return nil }
        return (last - p) / p * 100
    }
}

public struct Candle: Sendable, Equatable, Identifiable {
    public var time: Date
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    public var volume: Double
    public var id: Date { time }

    public init(time: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.time = time; self.open = open; self.high = high; self.low = low; self.close = close; self.volume = volume
    }
}

public enum TradeSide: String, Sendable, Codable { case buy = "BUY", sell = "SELL" }

/// One print on the tape (time & sales).
public struct TapePrint: Sendable, Equatable, Identifiable {
    public var id: String
    public var price: Double
    public var size: Double
    public var side: TradeSide
    public var time: Date

    public init(id: String, price: Double, size: Double, side: TradeSide, time: Date) {
        self.id = id; self.price = price; self.size = size; self.side = side; self.time = time
    }
}

public struct BookLevel: Sendable, Equatable, Identifiable {
    public var price: Double
    public var size: Double
    /// Running total from the inside of the book outwards.
    public var cumulative: Double
    public var id: Double { price }
}

public enum BookSide: String, Sendable { case bid, ask }

/// A price-level aggregated limit order book maintained from snapshot + incremental updates.
public struct OrderBook: Sendable, Equatable {
    public private(set) var bids: [Double: Double] = [:]
    public private(set) var asks: [Double: Double] = [:]
    public private(set) var updated: Date = .distantPast

    public init() {}

    public mutating func reset() { bids.removeAll(keepingCapacity: true); asks.removeAll(keepingCapacity: true) }

    /// Sets the resting size at a level; a size of zero deletes the level.
    public mutating func apply(_ side: BookSide, price: Double, size: Double, at time: Date = .now) {
        switch side {
        case .bid: if size > 0 { bids[price] = size } else { bids.removeValue(forKey: price) }
        case .ask: if size > 0 { asks[price] = size } else { asks.removeValue(forKey: price) }
        }
        updated = time
    }

    public var bestBid: Double? { bids.keys.max() }
    public var bestAsk: Double? { asks.keys.min() }
    public var mid: Double? {
        guard let b = bestBid, let a = bestAsk else { return nil }
        return (a + b) / 2
    }
    public var spread: Double? {
        guard let b = bestBid, let a = bestAsk else { return nil }
        return a - b
    }

    /// The best `depth` levels per side, inside-out, with cumulative size.
    public func ladder(depth: Int) -> (bids: [BookLevel], asks: [BookLevel]) {
        func build(_ levels: some Sequence<(key: Double, value: Double)>) -> [BookLevel] {
            var total = 0.0
            return levels.prefix(depth).map { lvl in
                total += lvl.value
                return BookLevel(price: lvl.key, size: lvl.value, cumulative: total)
            }
        }
        return (build(bids.sorted { $0.key > $1.key }), build(asks.sorted { $0.key < $1.key }))
    }

    /// Bid size share of the top `depth` levels, in 0...1. Positive pressure > 0.5.
    public func imbalance(depth: Int = 10) -> Double? {
        let l = ladder(depth: depth)
        let b = l.bids.last?.cumulative ?? 0, a = l.asks.last?.cumulative ?? 0
        return b + a > 0 ? b / (b + a) : nil
    }
}

public struct NewsItem: Sendable, Equatable, Identifiable, Hashable {
    public var title: String
    public var link: URL
    public var source: String
    public var published: Date?
    public var id: String { link.absoluteString }

    public init(title: String, link: URL, source: String, published: Date?) {
        self.title = title; self.link = link; self.source = source; self.published = published
    }
}
