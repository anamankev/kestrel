import Foundation
import KestrelCore
import os

nonisolated let marketLog = Logger(subsystem: "dev.kestrel.terminal", category: "market")

enum ChartRange: String, CaseIterable, Identifiable {
    case d1 = "1D", d5 = "5D", m1 = "1M", m6 = "6M", y1 = "1Y", y5 = "5Y"
    var id: String { rawValue }

    var yahoo: (range: String, interval: String) {
        switch self {
        case .d1: ("1d", "5m")
        case .d5: ("5d", "15m")
        case .m1: ("1mo", "60m")
        case .m6: ("6mo", "1d")
        case .y1: ("1y", "1d")
        case .y5: ("5y", "1wk")
        }
    }

    /// Coinbase granularity (seconds) and how many of the latest candles cover the range.
    var coinbase: (granularity: Int, count: Int) {
        switch self {
        case .d1: (300, 288)
        case .d5: (3600, 120)
        case .m1: (21600, 124)
        case .m6: (86400, 182)
        case .y1: (86400, 300)
        case .y5: (86400, 300)
        }
    }

    var isIntraday: Bool { self == .d1 || self == .d5 }
}

struct SecurityDetail: Equatable {
    var name: String?
    var exchange: String?
    var currency: String?
}

/// Single source of truth for market data on the main actor.
///
/// Crypto streams from `CoinbaseStream` and is pulled at ~10 Hz. Everything else is polled from
/// Yahoo's delayed chart endpoint: the whole universe on a slow cycle, and securities on screen
/// on a fast one.
@Observable final class MarketStore {
    private(set) var quotes: [String: Quote] = [:]
    private(set) var sparks: [String: [Double]] = [:]
    private(set) var books: [String: OrderBook] = [:]
    private(set) var tapes: [String: [TapePrint]] = [:]
    private(set) var details: [String: SecurityDetail] = [:]
    private(set) var link: CoinbaseStream.Link = .connecting
    private(set) var messagesPerSecond: Double = 0
    /// Feed diagnostics (PREF → Diagnostics, docs/PERFORMANCE.md).
    private(set) var feedLatencyP50: Double?
    private(set) var feedLatencyP95: Double?
    private(set) var processP50: Double?
    private(set) var processP99: Double?
    private(set) var mainApplyP50: Double?
    private(set) var mainApplyP99: Double?
    private(set) var clockOffsetMs: Double?
    private(set) var clockUncertaintyMs: Double?
    @ObservationIgnored private var mainApply = Samples()
    private(set) var lastEquityRefresh: Date?
    /// Tickers the data source says don't exist.
    private(set) var unknown: Set<String> = []

    /// Called with every fresh quote so the paper broker can work orders.
    @ObservationIgnored var onQuote: ((String, Quote) -> Void)?
    /// Securities visible in panels: refreshed every few seconds instead of every cycle.
    @ObservationIgnored var focusSymbols: Set<String> = []
    /// Watchlist/alert symbols outside the built-in universe, polled on the slow cycle.
    @ObservationIgnored var extraSymbols: () -> Set<String> = { [] }
    /// Option contracts held or worked in the paper account: marked from Deribit every 15 s.
    @ObservationIgnored var heldOptions: () -> Set<String> = { [] }
    /// Latest Deribit data (mark, IV, forward) for option contracts we track, for greeks.
    private(set) var optionContracts: [String: OptionContract] = [:]

    @ObservationIgnored private let stream = CoinbaseStream(products: Universe.crypto.map(\.symbol))
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let http: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Kestrel Terminal)"]
        cfg.timeoutIntervalForRequest = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    static let tapeDepth = 400

    func start() {
        guard tasks.isEmpty else { return }
        let stream = stream
        tasks.append(Task.detached { await stream.run() })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.apply(await stream.drain())
                try? await Task.sleep(for: .milliseconds(100))
            }
        })
        tasks.append(Task { [weak self] in
            await self?.loadCryptoSparks()
            while !Task.isCancelled {
                await self?.refreshUniverse()
                let every = UserDefaults.standard.double(forKey: "universeInterval")
                try? await Task.sleep(for: .seconds(every >= 15 ? every : 45))
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard let self else { return }
                let symbols = self.focusSymbols.compactMap { Universe.instrument(symbol: $0) ?? Universe.resolve($0) }
                await self.refresh(symbols.filter { !$0.isStreaming && $0.assetClass != .option })
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.markOptions()
                try? await Task.sleep(for: .seconds(15))
            }
        })
    }

    private func apply(_ b: CoinbaseStream.Batch) {
        let started = ContinuousClock.now
        defer {
            let d = ContinuousClock.now - started
            mainApply.add(Double(d.components.seconds) * 1e6 + Double(d.components.attoseconds) / 1e12)
        }
        link = b.link
        messagesPerSecond = b.messagesPerSecond
        if b.latencyP50 != nil {
            feedLatencyP50 = b.latencyP50; feedLatencyP95 = b.latencyP95
            processP50 = b.processP50; processP99 = b.processP99
            mainApplyP50 = mainApply.percentile(50); mainApplyP99 = mainApply.percentile(99)
            clockOffsetMs = b.clockOffsetMs; clockUncertaintyMs = b.clockUncertaintyMs
        }
        for (p, q) in b.quotes {
            quotes[p] = q
            if var s = sparks[p], !s.isEmpty { s[s.count - 1] = q.last; sparks[p] = s }
            onQuote?(p, q)
        }
        for (p, book) in b.books { books[p] = book }
        for (p, prints) in b.prints {
            var t = prints + (tapes[p] ?? [])
            if t.count > Self.tapeDepth { t.removeLast(t.count - Self.tapeDepth) }
            tapes[p] = t
        }
    }

    // MARK: Polling

    func refreshUniverse() async {
        let known = Set(Universe.all.map(\.symbol))
        let extra = extraSymbols().subtracting(known).compactMap { Universe.resolve($0) }.filter { $0.assetClass != .option }
        await refresh(Universe.all.filter { !$0.isStreaming } + extra)
        lastEquityRefresh = .now
    }

    /// Fetch now for a security just loaded into a panel.
    func touch(_ instrument: Instrument) {
        guard !instrument.isStreaming, instrument.assetClass != .option, quotes[instrument.symbol] == nil else { return }
        Task { await refresh([instrument]) }
    }

    func refresh(_ instruments: [Instrument]) async {
        await withTaskGroup(of: (String, ChartSeries?, Int).self) { group in
            var it = instruments.makeIterator()
            func next() -> Bool {
                guard let i = it.next() else { return false }
                let http = http
                group.addTask {
                    let url = YahooChart.url(symbol: i.symbol, range: "1d", interval: "5m")
                    do {
                        let (data, resp) = try await http.data(from: url)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        guard code == 200 else { marketLog.error("quote \(i.symbol, privacy: .public) HTTP \(code)"); return (i.symbol, nil, code) }
                        return (i.symbol, try YahooChart.decode(data), code)
                    } catch {
                        marketLog.error("quote \(i.symbol, privacy: .public) \(error.localizedDescription, privacy: .public)")
                        return (i.symbol, nil, 0)
                    }
                }
                return true
            }
            for _ in 0..<6 { _ = next() } // bounded concurrency: be polite to a free endpoint
            for await (symbol, series, code) in group {
                if code == 404 || code == 400 { unknown.insert(symbol) }
                if let series {
                    quotes[symbol] = series.quote
                    sparks[symbol] = series.candles.map(\.close)
                    details[symbol] = SecurityDetail(name: series.name, exchange: series.exchange, currency: series.currency)
                    onQuote?(symbol, series.quote)
                }
                _ = next()
            }
        }
    }

    private func loadCryptoSparks() async {
        await withTaskGroup(of: (String, [Double]).self) { group in
            for c in Universe.crypto {
                let http = http
                group.addTask {
                    let url = URL(string: "https://api.exchange.coinbase.com/products/\(c.symbol)/candles?granularity=900")!
                    guard let (data, _) = try? await http.data(from: url), let k = try? CoinbaseFeed.candles(data)
                    else { return (c.symbol, []) }
                    return (c.symbol, k.suffix(96).map(\.close))
                }
            }
            for await (s, closes) in group where !closes.isEmpty { sparks[s] = closes }
        }
    }

    // MARK: History

    func candles(for i: Instrument, range: ChartRange) async throws -> [Candle] {
        if i.isStreaming {
            let g = range.coinbase
            let url = URL(string: "https://api.exchange.coinbase.com/products/\(i.symbol)/candles?granularity=\(g.granularity)")!
            let (data, _) = try await http.data(from: url)
            return Array(try CoinbaseFeed.candles(data).suffix(g.count))
        }
        let y = range.yahoo
        let (data, _) = try await http.data(from: YahooChart.url(symbol: i.symbol, range: y.range, interval: y.interval))
        let series = try YahooChart.decode(data, intraday: true)
        if details[i.symbol] == nil {
            details[i.symbol] = SecurityDetail(name: series.name, exchange: series.exchange, currency: series.currency)
        }
        return series.candles
    }

    /// Daily (or weekly for multi-year) bars for HP. Crypto is capped at Coinbase's 300 bars.
    func history(for i: Instrument, range: String, weekly: Bool) async throws -> [Candle] {
        guard i.assetClass != .option else { return [] }
        if i.isStreaming {
            let url = URL(string: "https://api.exchange.coinbase.com/products/\(i.symbol)/candles?granularity=86400")!
            let (data, _) = try await http.data(from: url)
            return try CoinbaseFeed.candles(data)
        }
        let (data, _) = try await http.data(from: YahooChart.url(symbol: i.symbol, range: range, interval: weekly ? "1wk" : "1d"))
        return try YahooChart.decode(data, intraday: false).candles
    }

    /// Publishes a contract's Deribit touch as a quote (paper broker marks and fills from it).
    func ingest(_ c: OptionContract) {
        guard let mark = c.mark ?? c.bid ?? c.ask else { return }
        let q = Quote(last: mark, bid: c.bid, ask: c.ask, time: .now)
        quotes[c.name] = q
        optionContracts[c.name] = c
        onQuote?(c.name, q)
    }

    private func markOptions() async {
        let held = heldOptions()
        guard !held.isEmpty else { return }
        for currency in Set(held.compactMap { Deribit.parse($0)?.underlying }) {
            guard let i = Universe.resolve(currency, hint: .crypto),
                  let chain = try? await optionChain(for: i) else { continue }
            for c in chain.contracts where held.contains(c.name) { ingest(c) }
        }
    }

    /// Full listed option chain from Deribit's public API (BTC, ETH).
    func optionChain(for i: Instrument) async throws -> OptionChain {
        let (data, _) = try await http.data(from: Deribit.summaryURL(currency: i.ticker))
        return try await Task.detached(priority: .userInitiated) { try Deribit.decode(data) }.value
    }

    func displayName(_ i: Instrument) -> String {
        if i.name == i.ticker, let n = details[i.symbol]?.name { return n }
        return i.name
    }
}
