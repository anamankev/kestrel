import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// MARK: - Coinbase Advanced Trade WebSocket (public market-data channels, no key)

public enum CoinbaseEvent: Sendable, Equatable {
    case ticker(product: String, quote: Quote)
    case book(product: String, snapshot: Bool, updates: [BookUpdate])
    case trades(product: String, prints: [TapePrint])
    case other

    public struct BookUpdate: Sendable, Equatable {
        public var side: BookSide
        public var price: Double
        public var size: Double
    }
}

public enum CoinbaseFeed {
    public static let url = URL(string: "wss://advanced-trade-ws.coinbase.com")!

    public static func subscribe(_ channel: String, products: [String]) -> String {
        let ids = products.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"type":"subscribe","product_ids":[\#(ids)],"channel":"\#(channel)"}"#
    }

    private struct Envelope: Decodable {
        let channel: String
        let events: [Event]?
        let sequence_num: Int?
        let timestamp: String?
    }

    /// One fully decoded WebSocket message: transport header plus market events.
    public struct Message: Sendable, Equatable {
        public var sequence: Int?
        public var sent: Date?
        public var events: [CoinbaseEvent]
    }
    private struct Event: Decodable {
        let type: String?
        let product_id: String?
        let tickers: [Ticker]?
        let updates: [Level]?
        let trades: [Trade]?
    }
    private struct Ticker: Decodable {
        let product_id: String
        let price: String
        let volume_24_h: String?
        let low_24_h: String?
        let high_24_h: String?
        let low_52_w: String?
        let high_52_w: String?
        let price_percent_chg_24_h: String?
        let best_bid: String?
        let best_ask: String?
    }
    private struct Level: Decodable {
        let side: String
        let price_level: String
        let new_quantity: String
    }
    private struct Trade: Decodable {
        let trade_id: String
        let product_id: String
        let price: String
        let size: String
        let side: String
        let time: String
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Coinbase sends nanosecond fractions; ISO8601DateFormatter accepts at most milliseconds.
    public static func date(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        guard let dot = s.firstIndex(of: "."), let z = s.lastIndex(of: "Z"), dot < z else { return nil }
        let frac = s[s.index(after: dot)..<z].prefix(3)
        return iso.date(from: s[..<dot] + "." + frac + "Z")
    }

    public static func decode(_ data: Data, now: Date = .now) throws -> [CoinbaseEvent] {
        try decodeMessage(data, now: now).events
    }

    /// Decodes header and events in a single JSON pass (the stream previously parsed every
    /// message twice: once for sequence/timestamp, once for the body).
    public static func decodeMessage(_ data: Data, now: Date = .now) throws -> Message {
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return Message(sequence: env.sequence_num, sent: env.timestamp.flatMap(date), events: events(env, now: now))
    }

    private static func events(_ env: Envelope, now: Date) -> [CoinbaseEvent] {
        let events = env.events ?? []
        switch env.channel {
        case "ticker":
            return events.flatMap { $0.tickers ?? [] }.compactMap { t in
                guard let last = Double(t.price) else { return nil }
                let pct = t.price_percent_chg_24_h.flatMap(Double.init)
                let q = Quote(last: last,
                              previousClose: pct.map { last / (1 + $0 / 100) },
                              bid: t.best_bid.flatMap(Double.init), ask: t.best_ask.flatMap(Double.init),
                              high: t.high_24_h.flatMap(Double.init), low: t.low_24_h.flatMap(Double.init),
                              volume: t.volume_24_h.flatMap(Double.init),
                              high52: t.high_52_w.flatMap(Double.init), low52: t.low_52_w.flatMap(Double.init),
                              time: now)
                return .ticker(product: t.product_id, quote: q)
            }
        case "l2_data":
            return events.compactMap { e in
                guard let p = e.product_id else { return nil }
                let ups = (e.updates ?? []).compactMap { l -> CoinbaseEvent.BookUpdate? in
                    guard let px = Double(l.price_level), let q = Double(l.new_quantity) else { return nil }
                    return .init(side: l.side == "bid" ? .bid : .ask, price: px, size: q)
                }
                return .book(product: p, snapshot: e.type == "snapshot", updates: ups)
            }
        case "market_trades":
            var grouped: [String: [TapePrint]] = [:]
            var seen: [String] = []
            for t in events.flatMap({ $0.trades ?? [] }) {
                guard let px = Double(t.price), let sz = Double(t.size) else { continue }
                // Coinbase reports the maker side; the aggressor (what the tape shows) is the opposite.
                let p = TapePrint(id: t.trade_id, price: px, size: sz,
                                  side: t.side == "SELL" ? .buy : .sell, time: date(t.time) ?? now)
                if grouped[t.product_id] == nil { seen.append(t.product_id) }
                grouped[t.product_id, default: []].append(p)
            }
            return seen.map { .trades(product: $0, prints: grouped[$0]!.sorted { $0.time > $1.time }) }
        default:
            return [.other]
        }
    }

    /// Coinbase Exchange REST candles: `[[time, low, high, open, close, volume], ...]`, newest first.
    public static func candles(_ data: Data) throws -> [Candle] {
        let rows = try JSONDecoder().decode([[Double]].self, from: data)
        return rows.compactMap { r in
            guard r.count >= 6 else { return nil }
            return Candle(time: Date(timeIntervalSince1970: r[0]), open: r[3], high: r[2], low: r[1], close: r[4], volume: r[5])
        }.sorted { $0.time < $1.time }
    }
}

// MARK: - Yahoo Finance chart endpoint (delayed, no key)

public struct ChartSeries: Sendable, Equatable {
    public var name: String?
    public var exchange: String?
    public var currency: String?
    public var instrumentType: String?
    public var quote: Quote
    public var candles: [Candle]
    /// Cash dividends (ex-date, amount per share), when requested with `events: true`.
    public var dividends: [Dividend] = []
}

public struct Dividend: Sendable, Equatable, Hashable {
    public var date: Date
    public var amount: Double
    public init(date: Date, amount: Double) { self.date = date; self.amount = amount }
}

public enum YahooChart {
    /// - Parameter events: also return dividends and splits (and dividend-adjusted closes).
    public static func url(symbol: String, range: String, interval: String, events: Bool = false) -> URL {
        var c = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
        c.path += symbol
        c.queryItems = [.init(name: "range", value: range), .init(name: "interval", value: interval),
                        .init(name: "includePrePost", value: "false")]
        if events { c.queryItems?.append(.init(name: "events", value: "div,splits")) }
        return c.url!
    }

    private struct Root: Decodable { let chart: Chart }
    private struct Chart: Decodable { let result: [Result]? }
    private struct Result: Decodable {
        let meta: Meta
        let timestamp: [Double]?
        let indicators: Ind
        let events: Events?
    }
    private struct Events: Decodable { let dividends: [String: Div]? }
    private struct Div: Decodable { let amount: Double; let date: Double }
    private struct Meta: Decodable {
        let currency: String?
        let fullExchangeName: String?
        let instrumentType: String?
        let longName: String?
        let shortName: String?
        let regularMarketPrice: Double?
        let chartPreviousClose: Double?
        let previousClose: Double?
        let regularMarketDayHigh: Double?
        let regularMarketDayLow: Double?
        let regularMarketVolume: Double?
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
        let regularMarketTime: Double?
    }
    private struct Ind: Decodable { let quote: [Q]?; let adjclose: [Adj]? }
    private struct Adj: Decodable { let adjclose: [Double?]? }
    private struct Q: Decodable {
        let open, high, low, close, volume: [Double?]?
    }

    public enum DecodeError: Error { case noResult, noPrice }

    /// - Parameter intraday: when true, `previousClose` is yesterday's close (for day change);
    ///   otherwise it is the close before the chart window.
    /// - Parameter adjusted: scale each bar by adjclose / close, so closes include reinvested
    ///   dividends (total return). Needs a URL built with `events: true`.
    public static func decode(_ data: Data, intraday: Bool = true, adjusted: Bool = false) throws -> ChartSeries {
        guard let r = try JSONDecoder().decode(Root.self, from: data).chart.result?.first else { throw DecodeError.noResult }
        let m = r.meta
        var candles: [Candle] = []
        let adj = adjusted ? r.indicators.adjclose?.first?.adjclose : nil
        if let ts = r.timestamp, let q = r.indicators.quote?.first {
            for (i, t) in ts.enumerated() {
                guard let o = q.open?[safe: i] ?? nil, let h = q.high?[safe: i] ?? nil,
                      let l = q.low?[safe: i] ?? nil, let c = q.close?[safe: i] ?? nil else { continue }
                var k = 1.0
                if let a = adj?[safe: i] ?? nil, c > 0, a > 0 { k = a / c }
                candles.append(Candle(time: Date(timeIntervalSince1970: t), open: o * k, high: h * k, low: l * k, close: c * k,
                                      volume: (q.volume?[safe: i] ?? nil) ?? 0))
            }
        }
        let dividends = (r.events?.dividends?.values.map { Dividend(date: Date(timeIntervalSince1970: $0.date), amount: $0.amount) } ?? [])
            .filter { $0.amount > 0 }.sorted { $0.date < $1.date }
        guard let last = m.regularMarketPrice ?? candles.last?.close else { throw DecodeError.noPrice }
        let quote = Quote(last: last,
                          previousClose: intraday ? (m.previousClose ?? m.chartPreviousClose) : m.chartPreviousClose,
                          high: m.regularMarketDayHigh.flatMap { $0 > 0 ? $0 : nil }, low: m.regularMarketDayLow.flatMap { $0 > 0 ? $0 : nil }, volume: m.regularMarketVolume.flatMap { $0 > 0 ? $0 : nil },
                          high52: m.fiftyTwoWeekHigh, low52: m.fiftyTwoWeekLow,
                          time: m.regularMarketTime.map { Date(timeIntervalSince1970: $0) } ?? .now)
        return ChartSeries(name: m.longName ?? m.shortName, exchange: m.fullExchangeName, currency: m.currency,
                           instrumentType: m.instrumentType, quote: quote, candles: candles, dividends: dividends)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - RSS 2.0

public enum RSS {
    public static func parse(_ data: Data, source: String) -> [NewsItem] {
        let d = Delegate(source: source)
        let p = XMLParser(data: data)
        p.delegate = d
        p.shouldResolveExternalEntities = false // untrusted feed: no XXE
        p.parse()
        return d.items
    }

    static func date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            f.dateFormat = fmt
            if let d = f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines)) { return d }
        }
        return nil
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let source: String
        var items: [NewsItem] = []
        private var inItem = false
        private var field = ""
        private var text = ""
        private var title = "", link = "", pub = ""

        init(source: String) { self.source = source }

        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if e == "item" { inItem = true; title = ""; link = ""; pub = "" }
            field = e
            text = ""
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inItem { text += s } }
        func parser(_ p: XMLParser, foundCDATA d: Data) { if inItem { text += String(decoding: d, as: UTF8.self) } }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            guard inItem else { return }
            let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch e {
            case "title": title = v
            case "link": link = v
            case "pubDate": pub = v
            case "item":
                inItem = false
                // Untrusted links: only web URLs, always upgraded to HTTPS (no javascript:, file:, custom schemes).
                if !title.isEmpty, items.count < 200, var c = URLComponents(string: link),
                   c.scheme == "https" || c.scheme == "http", c.host?.isEmpty == false {
                    c.scheme = "https"
                    guard let url = c.url else { break }
                    items.append(NewsItem(title: title, link: url, source: source, published: RSS.date(pub)))
                }
            default: break
            }
            text = ""
        }
    }
}
