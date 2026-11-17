import Foundation
import Testing
@testable import KestrelCore

@Suite struct CommandTests {
    @Test func tickerThenFunction() throws {
        let c = try CommandParser.parse("AAPL US <EQUITY> GP <GO>", current: nil)
        #expect(c.function == .gp)
        #expect(c.instrument?.symbol == "AAPL")
    }

    @Test func bareTickerDefaultsToDescription() throws {
        let c = try CommandParser.parse("btc", current: nil)
        #expect(c.function == .des)
        #expect(c.instrument?.symbol == "BTC-USD")
    }

    @Test func functionUsesLoadedSecurity() throws {
        let eth = Universe.resolve("ETH")!
        let c = try CommandParser.parse("DEPTH", current: eth)
        #expect(c.instrument == eth)
    }

    @Test func functionWithoutSecurityFails() {
        #expect(throws: CommandError.needsSecurity(.gp)) { try CommandParser.parse("GP", current: nil) }
    }

    @Test func alertUsesLoadedSecurityWhenPresent() throws {
        let btc = Universe.resolve("BTC")!
        #expect(try CommandParser.parse("ALRT", current: btc).instrument == btc)
        #expect(try CommandParser.parse("ALRT", current: nil).instrument == nil)
    }

    @Test func marketFunctionNeedsNoSecurity() throws {
        #expect(try CommandParser.parse("WEI <GO>", current: nil).function == .wei)
    }

    @Test func indexMnemonicsAndAliases() throws {
        let c = try CommandParser.parse("SPX INDEX G", current: nil)
        #expect(c.instrument?.symbol == "^GSPC")
        #expect(c.function == .gp)
        #expect(try CommandParser.parse("EURUSD CURNCY", current: nil).instrument?.symbol == "EURUSD=X")
        #expect(try CommandParser.parse("BRK/B", current: nil).instrument?.symbol == "BRK-B")
    }

    @Test func buyPrefillsSide() throws {
        let c = try CommandParser.parse("SOL BUY", current: nil)
        #expect(c.function == .trade && c.side == .buy && c.instrument?.ticker == "SOL")
    }

    @Test func rejectsGarbage() {
        #expect(throws: CommandError.empty) { try CommandParser.parse("  <GO> ", current: nil) }
        #expect(throws: CommandError.empty) { try CommandParser.parse(String(repeating: "A ", count: 40), current: nil) }
        #expect(throws: CommandError.unknownSecurity("$$$")) { try CommandParser.parse("$$$ GP", current: nil) }
    }

    @Test func suggestions() {
        #expect(CommandParser.suggestions(for: "NV").first?.completion == "NVDA")
        #expect(CommandParser.suggestions(for: "AAPL D").map(\.completion).contains("AAPL DES"))
        #expect(CommandParser.suggestions(for: "AAPL ").isEmpty)
    }
}

@Suite struct OrderBookTests {
    @Test func maintainsLevelsAndLadder() {
        var b = OrderBook()
        b.apply(.bid, price: 100, size: 1)
        b.apply(.bid, price: 99, size: 2)
        b.apply(.ask, price: 101, size: 3)
        b.apply(.ask, price: 102, size: 1)
        #expect(b.bestBid == 100 && b.bestAsk == 101 && b.spread == 1 && b.mid == 100.5)
        b.apply(.bid, price: 100, size: 0)
        #expect(b.bestBid == 99)
        let l = b.ladder(depth: 5)
        #expect(l.asks.map(\.cumulative) == [3, 4])
        #expect(b.imbalance() == 2.0 / 6.0)
    }
}

@Suite struct PaperAccountTests {
    let touch = Touch(bid: 99, ask: 100, last: 99.5)

    @Test func marketBuyLiftsAsk() throws {
        var a = PaperAccount(cash: 10_000)
        let o = try a.submit(symbol: "X", side: .buy, quantity: 10, type: .market, touch: touch)
        #expect(o.status == .filled && o.fillPrice == 100)
        #expect(a.cash == 9_000)
        #expect(a.positions["X"]?.averageCost == 100)
    }

    @Test func limitWorksThenFillsWithPriceImprovement() throws {
        var a = PaperAccount(cash: 10_000)
        let o = try a.submit(symbol: "X", side: .buy, quantity: 10, type: .limit(98), touch: touch)
        #expect(o.status == .working)
        #expect(a.buyingPower == 9_020)
        #expect(a.mark(symbol: "X", touch: Touch(bid: 97, ask: 98.5, last: 98)).isEmpty)
        let fills = a.mark(symbol: "X", touch: Touch(bid: 96, ask: 97, last: 96.5))
        #expect(fills.first?.price == 97)
        #expect(a.cash == 9_030 && a.buyingPower == 9_030)
    }

    @Test func rejectsOverspendIncludingReservations() throws {
        var a = PaperAccount(cash: 1_000)
        _ = try a.submit(symbol: "X", side: .buy, quantity: 9, type: .limit(100), touch: nil)
        #expect(throws: OrderReject.self) {
            try a.submit(symbol: "X", side: .buy, quantity: 2, type: .market, touch: touch)
        }
    }

    @Test func sellRealizesPnLAndBlocksShorts() throws {
        var a = PaperAccount(cash: 10_000)
        try a.submit(symbol: "X", side: .buy, quantity: 10, type: .market, touch: touch)
        try a.submit(symbol: "X", side: .buy, quantity: 10, type: .market, touch: Touch(bid: 109, ask: 110, last: 110))
        #expect(a.positions["X"]?.averageCost == 105)
        let s = try a.submit(symbol: "X", side: .sell, quantity: 5, type: .market, touch: Touch(bid: 120, ask: 121, last: 120))
        #expect(s.fillPrice == 120)
        #expect(a.realizedPnL == 75)
        #expect(throws: OrderReject.insufficientPosition(15)) {
            try a.submit(symbol: "X", side: .sell, quantity: 16, type: .market, touch: touch)
        }
        #expect(a.equity(marks: ["X": 120]) == a.cash + 15 * 120)
    }

    @Test func cancelReleasesReservation() throws {
        var a = PaperAccount(cash: 1_000)
        let o = try a.submit(symbol: "X", side: .buy, quantity: 5, type: .limit(100), touch: nil)
        a.cancel(o.id)
        #expect(a.buyingPower == 1_000 && a.workingOrders.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var a = PaperAccount(cash: 5_000)
        try a.submit(symbol: "X", side: .buy, quantity: 3, type: .market, touch: touch)
        let b = try JSONDecoder().decode(PaperAccount.self, from: JSONEncoder().encode(a))
        #expect(a == b)
    }
}

@Suite struct IndicatorTests {
    @Test func smaAndEma() {
        #expect(Indicators.sma([1, 2, 3, 4], period: 2) == [nil, 1.5, 2.5, 3.5])
        let e = Indicators.ema([1, 2, 3, 4], period: 2)
        #expect(e[1] == 1.5 && abs(e[3]! - 3.5 / 1.0 + 0.0167) < 0.05)
    }

    @Test func bollingerOfConstantIsFlat() {
        let b = Indicators.bollinger(Array(repeating: 5, count: 25), period: 20)
        #expect(b[24] == .init(mid: 5, upper: 5, lower: 5))
    }

    @Test func rsiBounds() {
        let up = Indicators.rsi((0..<30).map(Double.init))
        #expect(up.last! == 100)
        let zig = Indicators.rsi((0..<30).map { $0 % 2 == 0 ? 1.0 : 2.0 })
        #expect(abs(zig.last!! - 50) < 5)
    }
}

@Suite struct DecoderTests {
    @Test func coinbaseTicker() throws {
        let json = #"{"channel":"ticker","events":[{"type":"update","tickers":[{"type":"ticker","product_id":"BTC-USD","price":"110","volume_24_h":"5","low_24_h":"90","high_24_h":"120","price_percent_chg_24_h":"10","best_bid":"109.5","best_ask":"110.5"}]}]}"#
        guard case .ticker(let p, let q) = try CoinbaseFeed.decode(Data(json.utf8)).first else { Issue.record(); return }
        #expect(p == "BTC-USD" && q.bid == 109.5 && abs(q.previousClose! - 100) < 1e-9)
    }

    @Test func coinbaseBookAndTrades() throws {
        let l2 = #"{"channel":"l2_data","events":[{"type":"snapshot","product_id":"ETH-USD","updates":[{"side":"bid","event_time":"x","price_level":"10","new_quantity":"2"},{"side":"offer","event_time":"x","price_level":"11","new_quantity":"1"}]}]}"#
        guard case .book(_, let snap, let ups) = try CoinbaseFeed.decode(Data(l2.utf8)).first else { Issue.record(); return }
        #expect(snap && ups.map(\.side) == [.bid, .ask])

        let tr = #"{"channel":"market_trades","events":[{"type":"update","trades":[{"trade_id":"1","product_id":"ETH-USD","price":"10.5","size":"0.1","side":"SELL","time":"2026-11-16T21:48:17.882817123Z"}]}]}"#
        guard case .trades(let p, let prints) = try CoinbaseFeed.decode(Data(tr.utf8)).first else { Issue.record(); return }
        #expect(p == "ETH-USD" && prints[0].side == .buy)
        #expect(prints[0].time.timeIntervalSince1970 > 1_790_000_000)
    }

    @Test func yahooChart() throws {
        let json = #"{"chart":{"result":[{"meta":{"currency":"USD","longName":"Apple Inc.","regularMarketPrice":352.78,"previousClose":356.27,"fiftyTwoWeekHigh":360.83,"fiftyTwoWeekLow":243.42},"timestamp":[1,2,3],"indicators":{"quote":[{"open":[1,null,3],"high":[2,null,4],"low":[0.5,null,2],"close":[1.5,null,3.5],"volume":[10,null,30]}]}}],"error":null}}"#
        let s = try YahooChart.decode(Data(json.utf8))
        #expect(s.name == "Apple Inc." && s.candles.count == 2)
        #expect(abs(s.quote.changePercent! - (-0.9796)) < 0.001)
    }

    @Test func coinbaseCandlesAreChronological() throws {
        let c = try CoinbaseFeed.candles(Data("[[200,1,3,2,2.5,9],[100,1,3,2,2.5,9]]".utf8))
        #expect(c.map(\.time.timeIntervalSince1970) == [100, 200] && c[0].open == 2 && c[0].low == 1)
    }

    @Test func rss() {
        let xml = """
        <rss><channel><title>Feed</title><item><title><![CDATA[Stocks rally]]></title>
        <link>https://example.com/a</link><pubDate>Mon, 16 Nov 2026 14:00:00 +0000</pubDate></item>
        <item><title>Bad link</title><link>javascript:alert(1)</link></item></channel></rss>
        """
        let items = RSS.parse(Data(xml.utf8), source: "TEST")
        #expect(items.count == 1 && items[0].title == "Stocks rally" && items[0].published != nil)
        let plain = RSS.parse(Data("<rss><channel><item><title>T</title><link>http://example.com/x</link></item></channel></rss>".utf8), source: "T")
        #expect(plain.first?.link.scheme == "https")
    }
}

@Suite struct OptionsTests {
    @Test func black76ReferenceValues() {
        // F = K = 100, T = 1, σ = 20%: C = 100·(2N(0.1) − 1) = 7.9656, Δ = N(0.1) = 0.5398.
        let c = Black76.greeks(f: 100, k: 100, t: 1, sigma: 0.2, call: true)
        #expect(abs(c.price - 7.9656) < 1e-4)
        #expect(abs(c.delta - 0.5398) < 1e-4)
        #expect(abs(c.vega - 0.3970) < 1e-4)
    }

    @Test func putCallParity() {
        for k in [60.0, 90, 100, 130] {
            let c = Black76.greeks(f: 100, k: k, t: 0.3, sigma: 0.7, call: true)
            let p = Black76.greeks(f: 100, k: k, t: 0.3, sigma: 0.7, call: false)
            #expect(abs((c.price - p.price) - (100 - k)) < 1e-9)
            #expect(abs((c.delta - p.delta) - 1) < 1e-12)
            #expect(abs(c.gamma - p.gamma) < 1e-12)
        }
    }

    @Test func impliedVolRoundTrip() {
        for (k, s, call) in [(80.0, 0.35, true), (100, 0.9, false), (150, 1.5, true), (50, 0.6, false)] {
            let price = Black76.greeks(f: 100, k: k, t: 0.25, sigma: s, call: call).price
            let iv = Black76.impliedVol(price: price, f: 100, k: k, t: 0.25, call: call)
            #expect(iv != nil && abs(iv! - s) < 1e-6)
        }
        #expect(Black76.impliedVol(price: 0.5, f: 100, k: 80, t: 0.25, call: true) == nil) // below intrinsic
    }

    @Test func expiredOptionIsIntrinsic() {
        #expect(Black76.greeks(f: 110, k: 100, t: 0, sigma: 0.5, call: true).price == 10)
        #expect(Black76.greeks(f: 110, k: 100, t: 0, sigma: 0.5, call: false).price == 0)
    }

    @Test func parsesDeribitNames() {
        let p = Deribit.parse("BTC-4DEC26-70000-C")!
        #expect(p.underlying == "BTC" && p.strike == 70_000 && p.call)
        #expect(p.expiry == ISO8601DateFormatter().date(from: "2026-12-04T08:00:00Z"))
        #expect(Deribit.parse("BTC-PERPETUAL") == nil)
    }

    @Test func chainAnalytics() throws {
        let json = #"""
        {"result":[
         {"instrument_name":"BTC-25DEC26-60000-C","bid_price":0.08,"ask_price":0.081,"mark_price":0.0805,"mark_iv":50,"open_interest":10,"volume":1,"underlying_price":65000},
         {"instrument_name":"BTC-25DEC26-60000-P","bid_price":0.01,"ask_price":0.011,"mark_price":0.0105,"mark_iv":54,"open_interest":40,"volume":1,"underlying_price":65000},
         {"instrument_name":"BTC-25DEC26-65000-C","bid_price":0.04,"ask_price":0.041,"mark_price":0.0405,"mark_iv":48,"open_interest":30,"volume":1,"underlying_price":65000},
         {"instrument_name":"BTC-25DEC26-65000-P","bid_price":0.04,"ask_price":0.041,"mark_price":0.0405,"mark_iv":50,"open_interest":20,"volume":1,"underlying_price":65000},
         {"instrument_name":"BTC-25DEC26-70000-C","bid_price":0,"ask_price":0.02,"mark_price":0.019,"mark_iv":47,"open_interest":50,"volume":1,"underlying_price":65000}
        ]}
        """#
        let chain = try Deribit.decode(Data(json.utf8))
        let e = chain.expiries[0]
        #expect(chain.rows(expiry: e).map(\.strike) == [60_000, 65_000, 70_000])
        #expect(chain.atmStrike(expiry: e) == 65_000)
        #expect(abs(chain.atmIV(expiry: e)! - 0.49) < 1e-12)
        #expect(chain.putCallOIRatio() == 60.0 / 90.0)
        #expect(chain.maxPain(expiry: e) == 65_000)
        let c = chain.rows(expiry: e)[0].call!
        #expect(c.bid == 0.08 * 65_000 && c.isITM)
        #expect(chain.rows(expiry: e)[2].call?.bid == nil) // zero bid = no bid
    }
}

@Suite struct WatchlistTests {
    @Test func addRemoveMoveAndLimits() {
        var w = Watchlist(name: "  tech  ", symbols: ["AAPL", "MSFT", "AAPL"])
        #expect(w.name == "TECH" && w.symbols == ["AAPL", "MSFT"])
        #expect(w.add("NVDA") && !w.add("NVDA"))
        w.move("NVDA", by: -5)
        #expect(w.symbols == ["NVDA", "AAPL", "MSFT"])
        w.remove("AAPL")
        #expect(w.symbols == ["NVDA", "MSFT"])
        var full = Watchlist(name: "X", symbols: (0..<150).map { "S\($0)" })
        #expect(full.symbols.count == Watchlist.maxSymbols && !full.add("NEW"))
        w.rename(String(repeating: "a", count: 50))
        #expect(w.name.count == Watchlist.maxNameLength)
    }
}

@Suite struct AlertTests {
    @Test func levelAlertsFireOnceWhenCrossed() throws {
        var b = AlertBook()
        try b.add(symbol: "BTC-USD", condition: .above(70_000), last: 65_000)
        try b.add(symbol: "BTC-USD", condition: .below(60_000), last: 65_000)
        #expect(b.evaluate(symbol: "BTC-USD", last: 69_999, changePercent: nil).isEmpty)
        let fired = b.evaluate(symbol: "BTC-USD", last: 70_010, changePercent: nil)
        #expect(fired.count == 1 && fired[0].triggerPrice == 70_010)
        #expect(b.evaluate(symbol: "BTC-USD", last: 71_000, changePercent: nil).isEmpty) // once only
        #expect(b.active.count == 1 && b.history.count == 1)
    }

    @Test func rejectsLevelsAlreadyThroughAndBadInput() {
        var b = AlertBook()
        #expect(throws: AlertError.alreadyThrough(100)) { try b.add(symbol: "X", condition: .above(90), last: 100) }
        #expect(throws: AlertError.alreadyThrough(100)) { try b.add(symbol: "X", condition: .below(100), last: 100) }
        #expect(throws: AlertError.invalidLevel) { try b.add(symbol: "X", condition: .above(-1), last: nil) }
        #expect(throws: AlertError.invalidLevel) { try b.add(symbol: "X", condition: .movePercent(0), last: nil) }
        #expect(throws: AlertError.invalidLevel) { try b.add(symbol: "X", condition: .above(.infinity), last: nil) }
    }

    @Test func percentMoveEitherDirection() throws {
        var b = AlertBook()
        try b.add(symbol: "AAPL", condition: .movePercent(3), last: 100)
        #expect(b.evaluate(symbol: "AAPL", last: 98, changePercent: -2.5).isEmpty)
        #expect(b.evaluate(symbol: "AAPL", last: 96, changePercent: -3.2).count == 1)
    }

    @Test func cancelAndPersist() throws {
        var b = AlertBook()
        let a = try b.add(symbol: "X", condition: .above(10), last: 5)
        let copy = try JSONDecoder().decode(AlertBook.self, from: JSONEncoder().encode(b))
        #expect(copy == b)
        b.cancel(a.id)
        #expect(b.active.isEmpty && b.watchedSymbols.isEmpty)
    }
}
