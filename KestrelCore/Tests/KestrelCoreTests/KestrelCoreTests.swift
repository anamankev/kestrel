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
        #expect(CommandParser.suggestions(for: "3").isEmpty)
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
        var a = PaperAccount(cash: 10_000, allowShort: false)
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

@Suite struct FundamentalsTests {
    static let json = #"""
    {"cik":320193,"entityName":"Apple Inc.","facts":{
     "dei":{"EntityCommonStockSharesOutstanding":{"units":{"shares":[
       {"end":"2025-10-01","val":15000000000,"filed":"2025-10-30"},{"end":"2026-10-01","val":14800000000,"filed":"2026-11-03"}]}}},
     "us-gaap":{
      "Revenues":{"units":{"USD":[{"start":"2023-10-01","end":"2024-09-28","val":1,"form":"10-K","filed":"2024-11-01"}]}},
      "RevenueFromContractWithCustomerExcludingAssessedTax":{"units":{"USD":[
        {"start":"2024-09-29","end":"2025-09-27","val":400,"form":"10-K","filed":"2025-10-31"},
        {"start":"2025-06-29","end":"2025-09-27","val":100,"form":"10-K","filed":"2025-10-31"},
        {"start":"2025-09-28","end":"2026-09-26","val":480,"form":"10-K","filed":"2026-11-03"},
        {"start":"2025-09-28","end":"2026-09-26","val":470,"form":"10-Q","filed":"2026-08-01"}]}},
      "NetIncomeLoss":{"units":{"USD":[
        {"start":"2023-10-01","end":"2024-09-28","val":90,"form":"10-K","filed":"2024-11-01"},
        {"start":"2024-09-29","end":"2025-09-27","val":100,"form":"10-K","filed":"2025-10-31"},
        {"start":"2024-09-29","end":"2025-09-27","val":110,"form":"10-K/A","filed":"2026-01-15"},
        {"start":"2025-09-28","end":"2026-09-26","val":132,"form":"10-K","filed":"2026-11-03"}]}},
      "EarningsPerShareDiluted":{"units":{"USD/shares":[{"start":"2025-09-28","end":"2026-09-26","val":8.98,"form":"10-K","filed":"2026-11-03"}]}},
      "NetCashProvidedByUsedInOperatingActivities":{"units":{"USD":[{"start":"2025-09-28","end":"2026-09-26","val":145,"form":"10-K","filed":"2026-11-03"}]}},
      "PaymentsToAcquirePropertyPlantAndEquipment":{"units":{"USD":[{"start":"2025-09-28","end":"2026-09-26","val":9,"form":"10-K","filed":"2026-11-03"}]}},
      "StockholdersEquity":{"units":{"USD":[{"end":"2026-09-26","val":112,"form":"10-K","filed":"2026-11-03"}]}},
      "LongTermDebt":{"units":{"USD":[{"end":"2026-09-26","val":78,"form":"10-K","filed":"2026-11-03"}]}}
     }}}
    """#

    @Test func annualSeriesFromTenKs() throws {
        let f = try SECFacts.decode(Data(Self.json.utf8))
        #expect(f.name == "Apple Inc." && f.cik == 320193)
        #expect(f.years.map(\.year) == [2024, 2025, 2026])
        // Preferred concept wins; fallback concept only fills 2024; quarterly + 10-Q values ignored.
        #expect(f.years.map(\.revenue) == [1, 400, 480])
        // Restatement (later 10-K/A) wins.
        #expect(f.years[1].netIncome == 110)
        let y = f.latest!
        #expect(y.freeCashFlow == 136 && y.debtToEquity == 78.0 / 112.0)
        #expect(abs(y.netMargin! - 132.0 / 480.0) < 1e-12)
        #expect(f.growth(\.revenue, year: 2026) == 0.2)
        #expect(f.sharesOutstanding == 14_800_000_000)
        #expect(abs(f.priceToEarnings(price: 269.4)! - 30) < 1e-9)
        #expect(f.marketCap(price: 100) == 1_480_000_000_000)
    }

    @Test func tickersAndContact() throws {
        let m = try SECFacts.decodeTickers(Data(#"{"0":{"cik_str":320193,"ticker":"AAPL","title":"Apple"},"1":{"cik_str":1067983,"ticker":"BRK.B","title":"Berkshire"}}"#.utf8))
        #expect(m["AAPL"] == 320193 && m["BRK-B"] == 1067983)
        #expect(SECFacts.factsURL(cik: 320193).absoluteString.hasSuffix("CIK0000320193.json"))
        #expect(SECFacts.isValidContact("me@school.edu"))
        #expect(!SECFacts.isValidContact("not an email") && !SECFacts.isValidContact("a@b"))
    }
}

/// Opt-in check against real EDGAR downloads: KESTREL_FACTS_DIR=/path swift test --filter liveFacts
@Test func liveFacts() throws {
    guard let dir = ProcessInfo.processInfo.environment["KESTREL_FACTS_DIR"] else { return }
    for file in try FileManager.default.contentsOfDirectory(atPath: dir) where file.hasPrefix("facts-") {
        let f = try SECFacts.decode(Data(contentsOf: URL(fileURLWithPath: dir).appending(path: file)))
        let rows = f.years.map { "FY\($0.year) rev=\(Fmt($0.revenue)) ni=\(Fmt($0.netIncome)) eps=\($0.epsDiluted ?? .nan) fcf=\(Fmt($0.freeCashFlow)) eq=\(Fmt($0.equity))" }
        print("LIVE \(f.name) shares=\(Fmt(f.sharesOutstanding))\n  " + rows.joined(separator: "\n  "))
        #expect(f.years.count >= 3)
    }
}
private func Fmt(_ v: Double?) -> String { v.map { String(format: "%.1fB", $0 / 1e9) } ?? "nil" }

@Suite struct MacroTests {
    @Test func blsDecodeAndTransforms() throws {
        var points: [String] = []
        for m in 1...12 { points.append(#"{"year":"2025","period":"M\#(String(format: "%02d", m))","value":"\#(100 + m)"}"#) }
        points.append(#"{"year":"2026","period":"M01","value":"113.3"}"#)
        points.append(#"{"year":"2025","period":"M13","value":"999"}"#)
        let json = #"{"status":"REQUEST_SUCCEEDED","Results":{"series":[{"seriesID":"X","data":[\#(points.joined(separator: ","))]}]}}"#
        let raw = try BLS.decode(Data(json.utf8))["X"]!
        #expect(raw.count == 13 && raw.first!.value == 101 && raw.last!.value == 113.3) // sorted, M13 dropped
        let yoy = MacroIndicator(id: "X", name: "", group: "", transform: .yearOverYear, unit: "%", source: "").series(raw)
        #expect(yoy.count == 1 && abs(yoy[0].value - 12.178) < 0.001)
        let chg = MacroIndicator(id: "X", name: "", group: "", transform: .change, unit: "K", source: "").series(raw)
        #expect(chg.count == 12 && chg[0].value == 1)
        #expect(throws: BLS.DecodeError.self) { try BLS.decode(Data(#"{"status":"REQUEST_NOT_PROCESSED"}"#.utf8)) }
    }

    @Test func nyFedRates() throws {
        let json = #"{"refRates":[{"effectiveDate":"2026-11-13","type":"EFFR","percentRate":3.88,"targetRateFrom":3.75,"targetRateTo":4.00},{"effectiveDate":"2026-11-12","type":"EFFR","percentRate":3.87}]}"#
        let r = try NYFed.decode(Data(json.utf8))
        #expect(r.series.map(\.value) == [3.87, 3.88] && r.targetLow == 3.75 && r.targetHigh == 4)
    }

    @Test func filingsAndEarningsEstimate() throws {
        let json = #"""
        {"cik":"320193","filings":{"recent":{
         "accessionNumber":["0000320193-26-000030","0000320193-26-000029","0000320193-26-000028","0000320193-26-000027","0000320193-26-000026"],
         "filingDate":["2026-11-12","2026-11-09","2026-10-30","2026-10-30","2026-08-01"],
         "form":["4","8-K","8-K","144","10-Q"],
         "items":["","9.01","2.02,9.01","",""],
         "primaryDocument":["f4.xml","a.htm","earn.htm","p.xml","q.htm"]}}}
        """#
        let f = try SECFilings.decode(Data(json.utf8))
        #expect(f.map(\.form) == ["4", "8-K", "10-Q"]) // 8-K with only exhibits and Form 144 dropped
        #expect(f[1].isEarnings && f[1].title == "Earnings release")
        #expect(f[1].url.absoluteString == "https://www.sec.gov/Archives/edgar/data/320193/000032019326000028/earn.htm")
        let now = SECFacts.day.date(from: "2026-11-16")!
        #expect(SECFilings.estimatedNextEarnings(f, now: now) == SECFacts.day.date(from: "2026-10-30")!.addingTimeInterval(91 * 86_400))
    }
}

@Suite struct CompareTests {
    func k(_ t: Double, _ c: Double) -> Candle { Candle(time: Date(timeIntervalSince1970: t), open: c, high: c, low: c, close: c, volume: 1) }

    @Test func rebasesBothSeriesFromFirstBar() {
        let main = [k(100, 50), k(200, 55), k(300, 45)]
        let other = [k(50, 10), k(150, 11), k(250, 12)]    // misaligned timestamps
        let r = Indicators.rebase(main, against: other)
        #expect(r.main.map(\.close) == [0, 10.000000000000009, -9.999999999999998])
        // At t=100 the latest other close is 10 (t=50) → base; t=200 → 11 (+10%); t=300 → 12 (+20%).
        #expect(r.other.map { $0.map { ($0 * 1e6).rounded() / 1e6 } } == [0, 10, 20])
    }

    @Test func comparisonStartingLaterIsNilUntilData() {
        let r = Indicators.rebase([k(100, 1), k(200, 2)], against: [k(150, 5)])
        #expect(r.other == [nil, 0])
    }
}

@Suite struct HistoryTests {
    @Test func returnStats() throws {
        let s = try #require(ReturnStats(closes: [100, 110, 99, 120], periodsPerYear: 252))
        #expect(abs(s.totalReturn - 0.2) < 1e-12)
        #expect(abs(s.maxDrawdown - (99.0 / 110 - 1)) < 1e-12)
        #expect(abs(s.bestPeriod - (120.0 / 99 - 1)) < 1e-12 && abs(s.worstPeriod - (-0.1)) < 1e-12)
        #expect(s.periods == 3 && s.annualizedVolatility > 0)
        // Constant prices: zero vol, zero drawdown.
        let flat = try #require(ReturnStats(closes: [5, 5, 5, 5], periodsPerYear: 365))
        #expect(flat.annualizedVolatility == 0 && flat.maxDrawdown == 0)
        #expect(ReturnStats(closes: [1, 2], periodsPerYear: 252) == nil)
    }

    @Test func csvExport() {
        let k = [Candle(time: Date(timeIntervalSince1970: 86_400), open: 2, high: 3, low: 1, close: 2.5, volume: 10),
                 Candle(time: Date(timeIntervalSince1970: 0), open: 1, high: 2, low: 0.5, close: 1.5, volume: 5)]
        let csv = CSV.candles(k, intraday: false)
        #expect(csv == "Date,Open,High,Low,Close,Volume\r\n1970-01-01,1.0,2.0,0.5,1.5,5.0\r\n1970-01-02,2.0,3.0,1.0,2.5,10.0\r\n")
        #expect(CSV.field("a,\"b\"") == "\"a,\"\"b\"\"\"")
    }
}


@Suite struct ShortSellingTests {
    let t100 = Touch(bid: 100, ask: 100, last: 100)

    @Test func shortThenCoverRealizesPnLAndReleasesMargin() throws {
        var a = PaperAccount(cash: 10_000)
        try a.submit(symbol: "X", side: .sell, quantity: 10, type: .market, touch: t100)
        #expect(a.positions["X"]?.quantity == -10 && a.positions["X"]?.averageCost == 100)
        #expect(a.cash == 11_000)                       // proceeds credited
        #expect(a.shortMarginHeld == 1_500 && a.buyingPower == 9_500)
        #expect(a.equity(marks: ["X": 90]) == Decimal(10_100)) // short gains when price falls
        try a.submit(symbol: "X", side: .buy, quantity: 10, type: .market, touch: Touch(bid: 90, ask: 90, last: 90))
        #expect(a.positions["X"]?.quantity == 0 && a.realizedPnL == 100)
        #expect(a.cash == 10_100 && a.buyingPower == 10_100)
    }

    @Test func sellThroughLongFlipsToShort() throws {
        var a = PaperAccount(cash: 10_000)
        try a.submit(symbol: "X", side: .buy, quantity: 5, type: .market, touch: t100)
        try a.submit(symbol: "X", side: .sell, quantity: 8, type: .market, touch: Touch(bid: 110, ask: 110, last: 110))
        #expect(a.positions["X"]?.quantity == -3 && a.positions["X"]?.averageCost == 110)
        #expect(a.realizedPnL == 50)
    }

    @Test func marginLimitsShortSize() {
        var a = PaperAccount(cash: 1_000)
        // Needs 50% of 10 × 300 = 1,500 > 1,000.
        #expect(throws: OrderReject.self) {
            try a.submit(symbol: "X", side: .sell, quantity: 10, type: .market, touch: Touch(bid: 300, ask: 300, last: 300))
        }
    }

    @Test func oldAccountsWithoutShortFlagStillDecode() throws {
        var a = PaperAccount(cash: 5_000)
        try a.submit(symbol: "X", side: .buy, quantity: 1, type: .market, touch: t100)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        json.removeValue(forKey: "allowShort")
        let b = try JSONDecoder().decode(PaperAccount.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(b.allowShort && b.positions == a.positions && b.cash == a.cash)
    }
}

@Suite struct RiskTests {
    @Test func betaOfScaledSeries() {
        let m = (0..<60).map { sin(Double($0)) * 0.01 }
        #expect(abs(Risk.beta(asset: m.map { $0 * 1.5 }, market: m)! - 1.5) < 1e-9)
        #expect(Risk.beta(asset: [0.01], market: [0.02]) == nil) // too short
    }

    @Test func historicalVaRAndShortfall() {
        let pnl = (1...100).map { Double($0) - 50 }   // -49 … +50
        #expect(Risk.historicalVaR(pnl: pnl, confidence: 0.95) == 44)  // 5th worst-ish day
        #expect(Risk.expectedShortfall(pnl: pnl, confidence: 0.95) == 47)
        #expect(Risk.historicalVaR(pnl: Array(repeating: 1, count: 30)) == 0)
    }

    @Test func alignsOnSharedDatesAndBuildsPnL() {
        func k(_ day: Int, _ c: Double) -> Candle { Candle(time: Date(timeIntervalSince1970: Double(day) * 86_400 + 3600), open: c, high: c, low: c, close: c, volume: 0) }
        let r = Risk.alignedReturns(["A": [k(0, 100), k(1, 110), k(2, 121), k(3, 133.1)],
                                     "B": [k(1, 50), k(3, 55)]])          // B missing day 0 and 2
        #expect(r["A"]!.count == 1 && abs(r["A"]![0] - 0.21) < 1e-9)      // day1 → day3
        #expect(abs(r["B"]![0] - 0.1) < 1e-12)
        let pnl = Risk.pnlSeries(exposure: ["A": 1000, "B": -500], returns: r)
        #expect(abs(pnl[0] - (210 - 50)) < 1e-6)
    }
}


@Suite struct OptionTradingTests {
    @Test func resolvesOptionSymbols() {
        let o = Universe.resolve("btc-27nov26-70000-c")!
        #expect(o.assetClass == .option && o.symbol == "BTC-27NOV26-70000-C" && o.name == "BTC 27NOV26 70000 Call")
        #expect(!o.isStreaming)
        #expect((try? CommandParser.parse("BTC-27NOV26-70000-C TRADE", current: nil))?.instrument == o)
    }

    @Test func optionsAreLongPremiumOnly() throws {
        var a = PaperAccount(cash: 10_000)
        let sym = "BTC-27NOV26-70000-C"
        let t = Touch(bid: 400, ask: 420, last: 410)
        try a.submit(symbol: sym, side: .buy, quantity: 2, type: .market, touch: t)
        #expect(a.positions[sym]?.quantity == 2 && a.cash == 9_160)
        try a.submit(symbol: sym, side: .sell, quantity: 2, type: .market, touch: t)   // closing is fine
        #expect(a.positions[sym]?.quantity == 0 && a.realizedPnL == -40)
        #expect(throws: OrderReject.insufficientPosition(0)) {                          // writing is not
            try a.submit(symbol: sym, side: .sell, quantity: 1, type: .market, touch: t)
        }
    }
}


@Suite struct SamplesTests {
    @Test func percentilesAndRollingWindow() {
        var s = Samples(capacity: 100)
        for v in 1...100 { s.add(Double(v)) }
        #expect(s.percentile(50) == 50 && s.percentile(95) == 95 && s.percentile(100) == 100)
        for _ in 0..<100 { s.add(1000) }          // window rolls over completely
        #expect(s.percentile(50) == 1000 && s.values.count == 100)
        #expect(Samples().percentile(50) == nil)
    }
}


@Suite struct CoinbaseMessageTests {
    @Test func headerAndEventsInOnePass() throws {
        let json = #"{"channel":"ticker","timestamp":"2026-11-16T21:48:17.918785762Z","sequence_num":42,"events":[{"type":"update","tickers":[{"type":"ticker","product_id":"BTC-USD","price":"100"}]}]}"#
        let m = try CoinbaseFeed.decodeMessage(Data(json.utf8))
        #expect(m.sequence == 42 && m.events.count == 1)
        #expect(abs(m.sent!.timeIntervalSince1970 - 1_794_865_697.918) < 0.001)
        let sub = try CoinbaseFeed.decodeMessage(Data(#"{"channel":"subscriptions","sequence_num":1,"events":[]}"#.utf8))
        #expect(sub.sequence == 1 && sub.sent == nil && sub.events == [.other])
    }
}

@Suite struct CorrelationTests {
    let x = (0..<60).map { sin(Double($0)) * 0.01 }
    @Test func identicalSeriesIsOne() { #expect(abs(Risk.correlation(x, x)! - 1) < 1e-12) }
    @Test func negatedSeriesIsMinusOne() { #expect(abs(Risk.correlation(x, x.map { -$0 })! + 1) < 1e-12) }
    @Test func scaleInvariant() { #expect(abs(Risk.correlation(x, x.map { $0 * 3 + 0.002 })! - 1) < 1e-12) }
    @Test func tooShortOrFlatIsNil() {
        #expect(Risk.correlation(Array(x.prefix(10)), Array(x.prefix(10))) == nil)
        #expect(Risk.correlation(x, Array(repeating: 0.01, count: 60)) == nil)
    }
    @Test func matrixIsSymmetricWithUnitDiagonal() {
        let y = (0..<60).map { cos(Double($0)) * 0.02 }
        let m = Risk.correlationMatrix(["A": x, "B": y], symbols: ["A", "B", "C"])
        #expect(m[0][0] == 1 && m[1][1] == 1)
        #expect(m[0][1] == m[1][0])
        #expect(m[2][0] == nil && m[2][2] == nil)
    }
    @Test func parsesCorr() throws {
        #expect(try CommandParser.parse("CORR", current: nil).function == .corr)
        #expect(try CommandParser.parse("CORREL", current: nil).function == .corr)
    }
}

@Suite struct StopOrderTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func touch(_ last: Decimal) -> Touch { Touch(bid: last - 1, ask: last + 1, last: last) }

    @Test func sellStopRestsThenFillsAtBidWhenTriggered() throws {
        var a = PaperAccount()
        try a.submit(symbol: "BTC-USD", side: .buy, quantity: 1, type: .market, touch: touch(100), now: t0)
        let o = try a.submit(symbol: "BTC-USD", side: .sell, quantity: 1, type: .stop(95), touch: touch(100), now: t0)
        #expect(o.status == .working && o.isPendingStop)
        #expect(a.mark(symbol: "BTC-USD", touch: touch(96), now: t0).isEmpty)
        let fills = a.mark(symbol: "BTC-USD", touch: touch(94), now: t0)
        #expect(fills.first?.price == 93)                       // gaps through: fills at the bid, not the stop
        #expect(a.orders.last?.triggered == true)
        #expect(a.positions["BTC-USD"]?.quantity == 0)
    }

    @Test func buyStopTriggersOnLastAtOrAbove() throws {
        var a = PaperAccount()
        try a.submit(symbol: "ETH-USD", side: .buy, quantity: 2, type: .stop(110), touch: touch(100), now: t0)
        #expect(a.mark(symbol: "ETH-USD", touch: touch(109), now: t0).isEmpty)
        #expect(a.mark(symbol: "ETH-USD", touch: touch(110), now: t0).first?.price == 111)
    }

    @Test func stopLimitBecomesRestingLimitAfterTrigger() throws {
        var a = PaperAccount()
        try a.submit(symbol: "SOL-USD", side: .buy, quantity: 1, type: .stopLimit(stop: 50, limit: 52), touch: touch(45), now: t0)
        #expect(a.mark(symbol: "SOL-USD", touch: touch(55), now: t0).isEmpty)   // triggered, but ask 56 > limit 52
        #expect(a.orders.last?.triggered == true && a.orders.last?.status == .working)
        #expect(a.mark(symbol: "SOL-USD", touch: touch(50), now: t0).first?.price == 51)  // stays live after trigger
    }

    @Test func rejectsStopsThroughTheMarket() {
        var a = PaperAccount()
        #expect(throws: OrderReject.stopThroughMarket(.buy)) {
            try a.submit(symbol: "BTC-USD", side: .buy, quantity: 1, type: .stop(99), touch: touch(100), now: t0)
        }
        #expect(throws: OrderReject.invalidStop) {
            try a.submit(symbol: "BTC-USD", side: .buy, quantity: 1, type: .stop(0), touch: touch(100), now: t0)
        }
    }

    @Test func buyStopReservesCash() throws {
        var a = PaperAccount(cash: 1_000)
        try a.submit(symbol: "BTC-USD", side: .buy, quantity: 9, type: .stop(105), touch: touch(100), now: t0)
        #expect(a.buyingPower == Decimal(55))         // 9 × 105 reserved
        #expect(throws: OrderReject.self) {
            try a.submit(symbol: "BTC-USD", side: .buy, quantity: 1, type: .market, touch: touch(100), now: t0)
        }
    }

    @Test func olderSavedOrdersStillDecode() throws {
        var a = PaperAccount()
        try a.submit(symbol: "BTC-USD", side: .buy, quantity: 1, type: .limit(90), touch: touch(100), now: t0)
        var json = String(decoding: try JSONEncoder().encode(a), as: UTF8.self)
        json = json.replacingOccurrences(of: ",\"triggered\":null", with: "")
        let back = try JSONDecoder().decode(PaperAccount.self, from: Data(json.utf8))
        #expect(back.orders.first?.isPendingStop == false)
        #expect(back == a)
    }
}

@Suite struct AccountTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let pw = "correct horse battery"
    func dir() throws -> (AccountDirectory, AccountRecord) {
        var d = AccountDirectory()
        let r = try d.register(name: "Ada Lovelace", email: " Ada@Example.com ", password: pw, confirm: pw, kdf: .testing, now: t0)
        return (d, r)
    }

    @Test func pbkdf2MatchesRFC7914Vector() {
        // RFC 7914 §11: PBKDF2-HMAC-SHA256("passwd", "salt", c=1, dkLen=64), first 32 bytes.
        let dk = Credentials.derive("passwd", salt: Data("salt".utf8), iterations: 1)
        #expect(dk.map { String(format: "%02x", $0) }.joined() == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
    }

    @Test func registersWithNormalisedEmailAndNoPlaintext() throws {
        let (d, r) = try dir()
        #expect(r.email == "ada@example.com" && r.initials == "AL")
        let json = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
        #expect(!json.contains(pw))
    }

    @Test func signInChecksPasswordCaseInsensitiveEmail() throws {
        var (d, r) = try dir()
        #expect(try d.signIn(email: "ADA@example.com", password: pw, now: t0).id == r.id)
        #expect(throws: AuthError.invalidCredentials) { try d.signIn(email: "ada@example.com", password: pw + "x", now: t0) }
        #expect(throws: AuthError.invalidCredentials) { try d.signIn(email: "nobody@example.com", password: pw, now: t0) }
    }

    @Test func locksAfterFiveFailuresThenUnlocks() throws {
        var (d, _) = try dir()
        for _ in 0..<4 { #expect(throws: AuthError.invalidCredentials) { try d.signIn(email: "ada@example.com", password: "wrong-password", now: t0) } }
        #expect(throws: AuthError.locked(until: t0.addingTimeInterval(30))) { try d.signIn(email: "ada@example.com", password: "wrong-password", now: t0) }
        // Even the right password is refused while locked.
        #expect(throws: AuthError.self) { try d.signIn(email: "ada@example.com", password: pw, now: t0.addingTimeInterval(10)) }
        #expect(try d.signIn(email: "ada@example.com", password: pw, now: t0.addingTimeInterval(31)).failedAttempts == 0)
    }

    @Test func rejectsBadSignUps() throws {
        var (d, _) = try dir()
        #expect(throws: AuthError.emailTaken) { try d.register(name: "A", email: "ada@example.com", password: pw, confirm: pw, kdf: .testing) }
        #expect(throws: AuthError.invalidEmail) { try d.register(name: "A", email: "ada@", password: pw, confirm: pw, kdf: .testing) }
        #expect(throws: AuthError.nameRequired) { try d.register(name: "  ", email: "b@example.com", password: pw, confirm: pw, kdf: .testing) }
        #expect(throws: AuthError.passwordsDiffer) { try d.register(name: "B", email: "b@example.com", password: pw, confirm: pw + "!", kdf: .testing) }
        #expect(Credentials.passwordProblem("short", email: "b@example.com") != nil)
        #expect(Credentials.passwordProblem("aaaaaaaaaaaa", email: "b@example.com") != nil)
        #expect(Credentials.passwordProblem("mypassword99", email: "b@example.com") != nil)
        #expect(Credentials.passwordProblem("bobsmith-trades", email: "bobsmith@example.com") != nil)
        #expect(Credentials.passwordProblem(pw, email: "b@example.com") == nil)
    }
}

@Suite struct BacktestTests {
    /// Bars that open at the previous close, so a buy-and-hold with no costs matches the benchmark.
    func bars(_ closes: [Double]) -> [Candle] {
        closes.enumerated().map { i, c in
            Candle(time: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400),
                   open: i == 0 ? c : closes[i - 1], high: c, low: c, close: c, volume: 1)
        }
    }

    @Test func buyAndHoldWithoutCostsTracksTheBenchmark() throws {
        let r = try #require(Backtest.run(bars([100, 110, 99, 121]), strategy: .buyAndHold, costBps: 0))
        #expect(abs(r.equity.last! - r.benchmark.last!) < 1e-12)
        #expect(abs(r.totalReturn - 0.21) < 1e-12)
        #expect(abs(r.maxDrawdown - 0.1) < 1e-12)         // 110 → 99
        #expect(r.trades.count == 1 && r.trades[0].exit == nil)
    }

    @Test func smaCrossTradesOnceOnRiseThenFall() throws {
        let up = (0..<30).map { 100 + Double($0) }, down = (0..<30).map { 129 - Double($0) * 2 }
        let r = try #require(Backtest.run(bars(up + down), strategy: .smaCross(fast: 3, slow: 10), costBps: 0))
        #expect(r.trades.filter { $0.exit != nil }.count == 1)
        #expect(r.exposure > 0 && r.exposure < 1)
    }

    @Test func costsAreChargedOnBothSides() throws {
        let flat = bars(Array(repeating: 100, count: 40) + Array(repeating: 100, count: 40))
        // RSI is undefined on a flat line, so force round trips with Bollinger on a sawtooth instead.
        let pattern: [Double] = [100, 99, 98, 97, 96, 100, 101, 102, 103, 104]
        let saw = bars((0..<80).map { (i: Int) -> Double in pattern[i % 10] })
        let free = try #require(Backtest.run(saw, strategy: .bollinger(period: 5, k: 1), costBps: 0))
        let paid = try #require(Backtest.run(saw, strategy: .bollinger(period: 5, k: 1), costBps: 10))
        #expect(!paid.trades.isEmpty && paid.equity.last! < free.equity.last!)
        #expect(try #require(Backtest.run(flat, strategy: .buyAndHold, costBps: 10)).totalReturn < 0)
    }

    @Test func neverTradesOnTheBarItSignalsOn() throws {
        // A spike on the last bar can't be captured: the signal would trade tomorrow.
        let closes = Array(repeating: 100.0, count: 30) + [200]
        let r = try #require(Backtest.run(bars(closes), strategy: .smaCross(fast: 2, slow: 5), costBps: 0))
        #expect(r.totalReturn == 0)
    }
}

@Suite struct OptionStrategyTests {
    let exp = Date(timeIntervalSince1970: 1_900_000_000)
    func c(_ k: Double, call: Bool, mark: Double) -> OptionContract {
        OptionContract(name: "BTC-X-\(Int(k))-\(call ? "C" : "P")", underlying: "BTC", expiry: exp, strike: k, isCall: call,
                       bid: nil, ask: nil, mark: mark, iv: 0.5, openInterest: 0, volume: 0, forward: 100)
    }

    @Test func longCallHasCappedLossAndUnlimitedProfit() {
        let a = StrategyAnalysis(legs: [StrategyLeg(c(100, call: true, mark: 5), 1)])
        #expect(a.netPremium == 5)
        #expect(a.maxProfit == nil && a.maxLoss == -5)
        #expect(a.breakevens == [105])
        #expect(a.payoffAtExpiry(120) == 15)
    }

    @Test func bullCallSpreadIsBoundedBothWays() {
        let a = StrategyAnalysis(legs: [StrategyLeg(c(100, call: true, mark: 6), 1), StrategyLeg(c(110, call: true, mark: 2), -1)])
        #expect(a.netPremium == 4)
        #expect(a.maxProfit == 6 && a.maxLoss == -4)
        #expect(a.breakevens == [104])
    }

    @Test func shortStraddleHasUnlimitedLossAndTwoBreakevens() {
        let a = StrategyAnalysis(legs: [StrategyLeg(c(100, call: true, mark: 5), -1), StrategyLeg(c(100, call: false, mark: 5), -1)])
        #expect(a.netPremium == -10)
        #expect(a.maxLoss == nil && a.maxProfit == 10)
        #expect(a.breakevens == [90, 110])
    }

    @Test func todayValueConvergesToPayoffAtExpiry() {
        let a = StrategyAnalysis(legs: [StrategyLeg(c(100, call: true, mark: 5), 1)])
        #expect(abs(a.valueToday(120, now: exp) - a.payoffAtExpiry(120)) < 1e-9)
        #expect(a.valueToday(100, now: exp.addingTimeInterval(-30 * 86_400)) > a.payoffAtExpiry(100))   // time value
    }

    @Test func templatesPickListedStrikes() throws {
        let chain = OptionChain(stride(from: 80.0, through: 120, by: 2).flatMap { [c($0, call: true, mark: 3), c($0, call: false, mark: 3)] })
        let condor = try #require(StrategyTemplate.condor.legs(chain: chain, expiry: exp))
        #expect(condor.map(\.contract.strike) == [88, 94, 106, 112] && condor.map(\.quantity) == [1, -1, -1, 1])
        let fly = try #require(StrategyTemplate.butterfly.legs(chain: chain, expiry: exp))
        #expect(StrategyAnalysis(legs: fly).netPremium == 0)
    }
}

@Suite struct NewsQueryTests {
    @Test func termsAreAndedAtWordStarts() {
        let q = NewsQuery("fed rate")
        #expect(q.matches("Fed signals rates stay higher"))
        #expect(!q.matches("Fed holds steady"))
        #expect(!NewsQuery("ai").matches("CEO said demand is strong"))
        #expect(NewsQuery("ai").matches("AI chips lift Nvidia"))
    }

    @Test func phrasesAndExclusions() {
        #expect(NewsQuery("\"interest rates\"").matches("Interest rates hit a new high"))
        #expect(!NewsQuery("\"interest rates\"").matches("Rates of interest"))
        #expect(!NewsQuery("bitcoin -etf").matches("Bitcoin ETF inflows surge"))
        #expect(NewsQuery("bitcoin -etf").matches("Bitcoin slips below 65,000"))
        #expect(!NewsQuery("tariffs -\"trade war\"").matches("Tariffs revive trade war fears"))
        #expect(NewsQuery("  ").isEmpty)
    }

    @Test func accentAndCaseInsensitiveWithHighlights() {
        let q = NewsQuery("societe")
        let title = "Société Générale beats estimates"
        #expect(q.matches(title))
        #expect(q.highlights(in: title).map { String(title[$0]) } == ["Société"])
    }

    @Test func tagsMentionedSecurities() {
        let tickers = NewsQuery.mentions("Nvidia and MSFT rally while Apple's shares slip").map(\.ticker)
        #expect(tickers.contains("NVDA") && tickers.contains("MSFT") && tickers.contains("AAPL"))
        #expect(NewsQuery.mentions("Pineapple prices rise").isEmpty)
    }
}

@Suite struct SessionTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func setup() throws -> (AccountDirectory, AccountRecord, Data) {
        var d = AccountDirectory()
        let r = try d.register(name: "Ada", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine", kdf: .testing, now: t0)
        let token = AccountDirectory.newSessionToken()
        d.beginSession(id: r.id, token: token, now: t0)
        return (d, r, token)
    }

    @Test func validTokenResumesAndSlidesExpiry() throws {
        var (d, r, token) = try setup()
        #expect(token.count == 32)
        let later = t0.addingTimeInterval(20 * 86_400)
        #expect(d.resumeSession(id: r.id, token: token, now: later)?.id == r.id)
        #expect(d.account(id: r.id)?.sessionExpires == later.addingTimeInterval(AccountDirectory.sessionLifetime))
    }

    @Test func wrongExpiredOrRevokedTokensFail() throws {
        var (d, r, token) = try setup()
        #expect(d.resumeSession(id: r.id, token: AccountDirectory.newSessionToken(), now: t0) == nil)   // forged
        #expect(d.resumeSession(id: UUID(), token: token, now: t0) == nil)                               // other id
        #expect(d.resumeSession(id: r.id, token: token, now: t0.addingTimeInterval(31 * 86_400)) == nil) // expired
        d.endSession(id: r.id)
        #expect(d.resumeSession(id: r.id, token: token, now: t0) == nil)                                 // revoked
    }

    @Test func tokenNeverStoredInPlaintext() throws {
        let (d, _, token) = try setup()
        let json = try JSONEncoder().encode(d)
        #expect(json.range(of: token) == nil && json.range(of: Data(token.base64EncodedString().utf8)) == nil)
    }
}


@Suite struct InputBoundsTests {
    let touch = Touch(bid: 99, ask: 101, last: 100)
    @Test func rejectsAbsurdOrders() {
        var a = PaperAccount()
        #expect(throws: OrderReject.invalidQuantity) { try a.submit(symbol: "BTC-USD", side: .buy, quantity: Decimal(string: "1e12")!, type: .market, touch: touch) }
        #expect(throws: OrderReject.invalidLimit) { try a.submit(symbol: "BTC-USD", side: .buy, quantity: 1, type: .limit(Decimal(string: "1e15")!), touch: touch) }
        #expect(throws: OrderReject.invalidQuantity) { try a.submit(symbol: "BTC-USD", side: .buy, quantity: -1, type: .market, touch: touch) }
    }

    @Test func parsersSurviveHostileInput() {
        let junk = [String(repeating: "A", count: 10_000), "\u{0}\u{202E}DES", "'; DROP TABLE x;--", "<script>alert(1)</script> GP", "../../etc/passwd", "%00%0d%0a"]
        for j in junk {
            _ = try? CommandParser.parse(j, current: nil)
            #expect(NewsQuery(j).include.joined().count <= NewsQuery.maxLength)
            #expect(!Credentials.isValidEmail(j))
        }
    }
}


@Suite struct BacktestRiskFreeTests {
    func bars(_ closes: [Double]) -> [Candle] {
        closes.enumerated().map { i, c in
            Candle(time: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400), open: i == 0 ? c : closes[i - 1], high: c, low: c, close: c, volume: 1)
        }
    }

    @Test func idleCashEarnsTheRiskFreeRate() throws {
        // Flat market, a rule that never trades: equity should compound at the T-bill rate.
        let flat = bars(Array(repeating: 100, count: 253))
        let r = try #require(Backtest.run(flat, strategy: .smaCross(fast: 300, slow: 400), costBps: 0, periodsPerYear: 252,
                                         riskFree: Array(repeating: 0.05, count: 253)))
        #expect(abs(r.totalReturn - (pow(1 + 0.05 / 252, 252) - 1)) < 1e-9)
        #expect(abs(r.riskFree - 0.05) < 1e-12)
    }

    @Test func sharpeIsOnExcessReturns() throws {
        let up = bars((0..<253).map { 100 * pow(1.0004, Double($0)) + ($0 % 2 == 0 ? 0.05 : -0.05) })
        let zero = try #require(Backtest.run(up, strategy: .buyAndHold, costBps: 0))
        let withRF = try #require(Backtest.run(up, strategy: .buyAndHold, costBps: 0, riskFree: Array(repeating: 0.08, count: 253)))
        #expect(withRF.sharpe! < zero.sharpe!)          // a higher hurdle lowers Sharpe
        #expect(zero.sortino != nil && zero.volatility! > 0 && zero.calmar != nil)
    }
}


@Suite struct VaultTests {
    @Test func sealsAndDetectsTampering() throws {
        let key = Vault.newKey(), plain = Data("{\"cash\":1000000}".utf8)
        var sealed = try Vault.seal(plain, key: key)
        #expect(Vault.isSealed(sealed) && sealed.range(of: Data("cash".utf8)) == nil)
        #expect(try Vault.open(sealed, key: key) == plain)
        #expect(throws: Vault.Failure.wrongKey) { try Vault.open(sealed, key: Vault.newKey()) }
        sealed[sealed.count - 1] ^= 0x01                       // flip one bit of the tag
        #expect(throws: Vault.Failure.wrongKey) { try Vault.open(sealed, key: key) }
        #expect(throws: Vault.Failure.notSealed) { try Vault.open(plain, key: key) }
    }

    @Test func dataKeyIsStableAndPasswordBound() throws {
        var d = AccountDirectory()
        let r = try d.register(name: "Ada", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine", kdf: .testing)
        #expect(d.account(id: r.id)?.hasDataKey == false)
        let k1 = try d.unlockDataKey(id: r.id, password: "analytical engine")      // created
        let k2 = try d.unlockDataKey(id: r.id, password: "analytical engine")      // unwrapped
        #expect(k1 == k2 && k1.count == 32 && d.account(id: r.id)?.hasDataKey == true)
        #expect(throws: AuthError.invalidCredentials) { try d.unlockDataKey(id: r.id, password: "wrong password!") }
        let json = try JSONEncoder().encode(d)
        #expect(json.range(of: k1) == nil && json.range(of: Data(k1.base64EncodedString().utf8)) == nil)
    }
}


@Suite struct EarningsEstimateTests {
    let day: TimeInterval = 86_400
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func f(_ d: Double, earnings: Bool = true) -> Filing {
        Filing(form: "8-K", date: t0.addingTimeInterval(d * 86_400), title: "", url: URL(string: "https://www.sec.gov/x/\(d)")!, isEarnings: earnings)
    }

    @Test func learnsTheCompanysOwnCadence() throws {
        // Reports every ~84 days (not 91), with one amended 8-K a few days after a release.
        // Extra 2.02 filings 30 days after a release (as some companies file) are not quarters.
        let filings = [f(0), f(84), f(87), f(114), f(168), f(252), f(336), f(100, earnings: false)]
        let e = try #require(SECFilings.earningsEstimate(filings, now: t0.addingTimeInterval(340 * day)))
        #expect(e.cadenceDays == 84 && e.releases == 5 && e.spreadDays == 0)
        #expect(e.next == SECFilings.nearestWeekday(t0.addingTimeInterval(420 * day)))
    }

    @Test func singleReleaseFallsBackToAQuarter() throws {
        let e = try #require(SECFilings.earningsEstimate([f(0)], now: t0.addingTimeInterval(10 * day)))
        #expect(e.cadenceDays == 91 && e.spreadDays == nil && e.next == SECFilings.nearestWeekday(t0.addingTimeInterval(91 * day)))
        #expect(SECFilings.earningsEstimate([f(0, earnings: false)]) == nil)
    }
}

@Suite struct Argon2Tests {
    func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    /// Argon2id vectors from the reference implementation's test suite (src/test.c, version 0x13).
    @Test func matchesReferenceVectors() {
        let salt = Data("somesalt".utf8)
        #expect(hex(Credentials.argon2id("password", salt: salt, memoryKiB: 1 << 16, passes: 2, lanes: 1)) == "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7")
        #expect(hex(Credentials.argon2id("password", salt: salt, memoryKiB: 1 << 8, passes: 2, lanes: 1)) == "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe")
        #expect(hex(Credentials.argon2id("password", salt: salt, memoryKiB: 1 << 8, passes: 2, lanes: 2)) == "6d093c501fd5999645e0ea3bf620d7b8be7fd2db59c20d9fff9539da2bf57037")
        #expect(hex(Credentials.argon2id("password", salt: salt, memoryKiB: 1 << 16, passes: 1, lanes: 1)) == "f6a5adc1ba723dddef9b5ac1d464e180fcd9dffc9d1cbf76cca2fed795d9ca98")
        #expect(hex(Credentials.argon2id("differentpassword", salt: salt, memoryKiB: 1 << 16, passes: 2, lanes: 1)) == "0b84d652cf6b0c4beaef0dfe278ba6a80df6696281d7e0d2891b817d8c458fde")
        #expect(hex(Credentials.argon2id("password", salt: Data("diffsalt".utf8), memoryKiB: 1 << 16, passes: 2, lanes: 1)) == "bdf32b05ccc42eb15d58fd19b1f856b113da1e9a5874fdcc544308565aa8141c")
    }

    @Test func newAccountsUseArgon2id() throws {
        var d = AccountDirectory()
        let r = try d.register(name: "Ada", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine")
        #expect(r.passwordKDF == .standard && KDF.standard == .argon2id(memoryKiB: 65_536, passes: 3, lanes: 1))
    }

    /// Accounts created before Argon2id open with PBKDF2 once, then are re-keyed; data and password survive.
    @Test func upgradesLegacyAccountsAtSignIn() throws {
        var d = AccountDirectory()
        let pw = "analytical engine"
        let r = try d.register(name: "Ada", email: "ada@example.com", password: pw, confirm: pw, kdf: .pbkdf2(iterations: 1_000))
        let k0 = try d.unlockDataKey(id: r.id, password: pw, upgradeTo: .pbkdf2(iterations: 1_000))     // a pre-Argon2 account
        let legacy = d.account(id: r.id)!
        #expect(legacy.passwordKDF == .pbkdf2(iterations: 1_000) && legacy.kdf == nil)
        // A record saved by an older build (no "kdf" field) still decodes.
        let old = try JSONDecoder().decode(AccountDirectory.self, from: try JSONEncoder().encode(d))
        #expect(old.account(id: r.id)?.passwordKDF == .pbkdf2(iterations: 1_000))

        _ = try d.signIn(email: "ada@example.com", password: pw)
        let k1 = try d.unlockDataKey(id: r.id, password: pw, upgradeTo: .testing)
        let up = d.account(id: r.id)!
        #expect(k1 == k0)                                                       // same data key: files still open
        #expect(up.passwordKDF == .testing && up.iterations == 0 && up.salt != legacy.salt && up.keySalt != legacy.keySalt)
        #expect(try d.signIn(email: "ada@example.com", password: pw).id == r.id)
        #expect(throws: AuthError.invalidCredentials) { try d.signIn(email: "ada@example.com", password: pw + "x") }
        #expect(try d.unlockDataKey(id: r.id, password: pw, upgradeTo: .testing) == k0)
        #expect(throws: AuthError.invalidCredentials) { try d.unlockDataKey(id: r.id, password: "wrong password!") }
    }
}

@Suite struct TransferTests {
    func bundle() -> TransferBundle {
        var book = AlertBook()
        _ = try? book.add(symbol: "BTC-USD", condition: .above(100_000), last: 64_000)
        return TransferBundle(watchlists: [Watchlist.core], activeID: Watchlist.core.id, alerts: book, account: PaperAccount(cash: 12_345))
    }

    @Test func roundTripsWithThePassphrase() throws {
        let file = try bundle().seal(passphrase: "move my desk please", iterations: 1_000)
        #expect(file.range(of: Data("BTC-USD".utf8)) == nil)                     // nothing readable
        let back = try TransferBundle.open(file, passphrase: "move my desk please")
        #expect(back.account.cash == 12_345 && back.alerts.active.count == 1)
    }

    @Test func rejectsWrongPassphraseTamperingAndJunk() throws {
        var file = try bundle().seal(passphrase: "move my desk please", iterations: 1_000)
        #expect(throws: TransferBundle.Failure.wrongPassphrase) { try TransferBundle.open(file, passphrase: "not the passphrase") }
        file[file.count - 5] ^= 0xFF
        #expect(throws: TransferBundle.Failure.wrongPassphrase) { try TransferBundle.open(file, passphrase: "move my desk please") }
        #expect(throws: TransferBundle.Failure.notATransferFile) { try TransferBundle.open(Data("{}".utf8), passphrase: "move my desk please") }
        #expect(throws: TransferBundle.Failure.weakPassphrase) { try self.bundle().seal(passphrase: "short") }
    }

    @Test func writesArgon2idFilesAndStillOpensPBKDF2Ones() throws {
        let file = try bundle().seal(passphrase: "move my desk please", kdf: .testing)
        #expect(file.prefix(4) == Data("KXF2".utf8))
        #expect(try TransferBundle.open(file, passphrase: "move my desk please").account.cash == 12_345)
        #expect(throws: TransferBundle.Failure.wrongPassphrase) { try TransferBundle.open(file, passphrase: "not the passphrase") }
        let old = try bundle().seal(passphrase: "move my desk please", iterations: 1_000)
        #expect(old.prefix(4) == Data("KXF1".utf8))
        #expect(try TransferBundle.open(old, passphrase: "move my desk please").alerts.active.count == 1)
    }

    @Test func rejectsHostileArgon2Settings() throws {
        var file = try bundle().seal(passphrase: "move my desk please", kdf: .testing)
        file.replaceSubrange(20..<24, with: [0x7F, 0xFF, 0xFF, 0xFF])               // 2 TiB of memory
        #expect(throws: TransferBundle.Failure.notATransferFile) { try TransferBundle.open(file, passphrase: "move my desk please") }
        file.replaceSubrange(20..<24, with: [0, 0, 0, 64]); file.replaceSubrange(24..<28, with: [0, 0, 1, 0])   // 256 passes
        #expect(throws: TransferBundle.Failure.notATransferFile) { try TransferBundle.open(file, passphrase: "move my desk please") }
    }

    @Test func rejectsHostileIterationCounts() throws {
        var file = try bundle().seal(passphrase: "move my desk please", iterations: 1_000)
        file.replaceSubrange(20..<24, with: [0xFF, 0xFF, 0xFF, 0xFF])               // 4 billion rounds: a DoS
        #expect(throws: TransferBundle.Failure.notATransferFile) { try TransferBundle.open(file, passphrase: "move my desk please") }
    }

    /// A file exported by the web app (web/src/core/transfer.ts) must open here unchanged.
    @Test func opensFilesExportedByTheWebApp() throws {
        let web = Data(base64Encoded: "S1hGMfLGLjeJGvy064HjgDWELbUAAAPoS1NWMcuiwOgJs4gJklTu7cNDQm973Z2aTxmojThlYInP7FFnA3g6cK9ymED/GanZgBEN70X+wp2IpJKupt2+Vs+PO6/LWQToacDkyul5CUam3lIzv4HFKeMvRmwYszGEDPnM6Zzmju9MBJynwLvEo8Vg/6j0cilRD7CDe2P2cSod0RnV3z1vf1qTrHKhlhk5Krd1DDIMy85bdOH8yr1BBFsk9sUmQQQier/RhXirBWXIhKLgtPVSY/XwdVLYT1q/3or1IU7H2wqiR7K5+vpsAQa45GX0giRSIs+YDbTYSEb7KEpngtyxhUA6X7m3X7zHKVeCZ/SPzw+eCxRNL5Ue9EwKoTAnC5obtU7Opdy0an+YM1aiC+/7dss06b4ySWSD0cJiJcRsYCUPIoO71cJeTenZU7S3w6ZMowuRYtLdtW7fkuFtqwbMZxvOFRv5c0HDozOAgfrTr8ZtAyZyBsHhs3bKiSctGEoV4RDQzGV03YNwEaLAz+dEsed1Zc56FY2bzjxq+OyAABPXBe7y+dx0xTHUilw/y/5S9woN7oenV6x3Titp8JZ65UskRVSzt+p7/6PBm0uU0+MwGDaHu5BJE63Mb3Lb5S5obNlYuv7NqgMUs25XuVB310rdqNN75Sv8y4fX7ZtyTQwlHIshtQeUuaHF1gbKTCgkEXoA9ZygJ2nCp38wiij0Wg2/Ki/hRsRWKvuIQ/LZxBSado2IRcd+fivMWgPU5O0MjpFW4t2q5WM56TvQnCRhHYl8ExtvmqAbZ/jorsoiijw/UsFLAmOANKwL1IotlHFz7J5aNd243Vv6e33OiZZAOS6hp1s8puMDr9ut/u5WYDOHeK+zr6ZKVobBOtK7d1ezYxcpOEMlIUx7jHcG3Z/epWYPMcUG3Hl2Ok37S4y+pd77XrmqCulFtZzuI9ggtJT57zcG/zzG9YiWRibSGKeunoMyc1kgV5g0aXjSrHxr4PG+GQuXYYVXARi/Sdj9TLGB+MWYlrImFz01YNyVi3teNt8xpEA8uO2O3COnzR3k07QgqFVEbY67+kM7cBZgDJtGjzxTVFjlCALAU70Zs8W91qiUAfG4waZtxtqn1nGNBqxRwrf4U1lZjui14MkdO03nqL+vLPxmZRARb6GQvPXlzNfUscLNB6Oj/t6D/nBPqv7nTb1vSLmFgCere3AfoxHzwUkmBx/QMMxyOI/EiDRz0JIsMWofPojmWShS6Rl5vCN2S6qY6H24BNKZ9bm75c7BJeumZgOidRGs4XA+LHUM9AdNoArGQFFfsOphe10Xw6BA6OYvVd/mEa8EsVUm3FHOOiRv0r5VmwsT2f22E8TBJSyVHs/IBz4nnCfm65IeYA/c5sOeq159Q0MByYrvWgmI1r1u7bwDgYkNzBrpd1yuumPXEIUQ4lr1t6/J3Nx7c4iXu+xWhiL332ZjecDuP/0dehGEMuEhJ7dqg5/Jhf56yUsyxAf36bzoQMchCTeGWu7GDRs+26TphzkjI5W2uI82bnJfduKdDfTtenTJu/F6tNKpjFnG3YwT7EyWwxWutRaYTLDQq95mMBScEd4CjRlJ+TU2VX5nxWbZ2qEXNwfyNFfecbba4e/fOwAjJsVFy2YTGTQwfvutZI0xmORVh4hxKH1bd+CfxtDCrGO57emUUYCNNnTFCdkuyIfINFzsf1dJ0+itJfZCrhPYBPLSSqyZO6zsbM/cKNga7lEYMFWTHh0oagFRcB7GSGvIc8ffN5qUYojF1ulCkrSjcfYPHzs+20M3D3kPawzAyazaVZrA8CNg7ZEFExZ2M6q6bCw50WvV7+uf33yPiDeOh2MijwsFNYk8gsfIurRIgKR64t1p4qkIsdqPYtxb8EPIXZEovGfZ9MYBDbOnsCUPsj72GnxB/89Zhv0tRTd1ecNFRFdNqb9deLE5J+6RGAdcrA4bDPbLydTtYEm+FZ8rwnR/YE0HXxmL+cLcEGzx56x3z6IdLPIuP7wBKtALRwUHQFBZgtzwNyApIl2ODdhU5CPKDqBhz0Sn5gVZDuoqrsqm5DYNirL4N29kdPkK00mwcBt3pb38qIhxZRMPd+ylCzNPYMrtlypMwaS7piU1dTMa3bnkpqFcBwz0/A3z74lOqo171Dv8S1LnsNPjgtGkHl02sUpIKR2feKUCQ9HIrkKDWa7uZw==")!
        let b = try TransferBundle.open(web, passphrase: "move my desk please")
        #expect(b.watchlists.map(\.name) == ["CORE", "TECH"] && b.watchlists[0].symbols.contains("EURUSD=X"))
        #expect(b.watchlists.contains { $0.id == b.activeID })
        #expect(b.alerts.active.count == 2 && b.alerts.active.contains { $0.condition == .movePercent(5) })
        #expect(b.account.positions["AAPL"]?.quantity == 10 && b.account.positions["TSLA"]?.quantity == -3)
        #expect(b.account.workingOrders.contains { $0.type == .stopLimit(stop: 180, limit: 179) })
        #expect(b.account.workingOrders.contains { $0.type == .limit(60_000) })
        #expect(b.exported == Date(timeIntervalSince1970: 1_800_000_000))
        // The reverse direction: write an app-made file for the web test suite to open.
        if let out = ProcessInfo.processInfo.environment["KESTREL_FIXTURE_OUT"] {
            try bundle().seal(passphrase: "move my desk please", iterations: 1_000).base64EncodedString().write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    /// The same for the Argon2id format (KXF2) the web app now writes.
    @Test func opensArgon2FilesExportedByTheWebApp() throws {
        let web = Data(base64Encoded: "S1hGMpkPtGKIX4JrFdqjPeVjOFcAAABAAAAAAQAAAAFLU1YxmheTVpROf3TgY6yePtFESxd7mcjDfa5RJZxf/uqbJQfaMDydqU0FR+wHYtNxC89ZV4JG7WtDPVKCBIL4lQv3PUT2QS4PezUcueY0P1F6uW4a2WJUWCC0PgaMPjhrs4TTdf0gEu8rC/7gcjRUfarJlhtGl6Ao4IRVCC2Y+bOc7nln6M1/eHUQEM+JCuxN/OqLe1fbd1qie43OUp8TP0YyX4N6GpaJKxeknHV+hV+F44FSNVzPF/31Ly3FW0ood3LqqRTgNUJiYQwE8O+F8nt/PMJi002ypn1ENGIrQA9HLYN8P25BOUbZ/jOO7KGsSqlsZwTc7Lqg4bDj7EDnKgYuN6tINviQWwQaCq+SlV9wS5Qe01a1UMQzKBYW7AE0d46zAhjSu4HO2bXfp6Qdw7U/7r4YbmaFLIoQVad/PPmCou6q+4okJ8Z2mTVItTyTEbfbWTzh5bVLd1bQquOZvCMoIMtM7JmDpGpTy1bzMFhTESqMMYvL5lw+YcH+g4xJFMVzGHWTXIU+cW2bYAOdChj2F9a8hDwsU71USOveVZXy8ZvQtuJ7y89vjNC+T2+Cieb4SBMdyS1pGMSkUxjGsPgplNXwhfEoHdaTjqZmpuRzPmvtoawqxf6PlKE6W16ezroVTYnOwFqOgfXcF3IwFz4soiBUKiCMx8B7K6hn219JdBNuCFOXP4y8SnYLupiOAOiv5IogwWRIl8Fti2uL/9pcXxlPYYdg9NyrnvcUVCYovB0ToHBsimddww8OqYZp1fFB5xderqdMXPmrvZAaPGrh73Ahjsr/HMF6lvHL4K6XR1bD4dGOC05RNTco8et/mA6TwsriBHwbLXmMq6laZ09jnfrZ7NLZVCI18CV6rB0YbGYns0DhO802iday1/3s5iSKZcqOe7t/evY8Q6EnuM5fLSrh3ulIfAa/P6z1pCDjqPTiWNoRPI5+a9pBYDNPov4EBgglNjtu0bz6/0uL1JbuDTPvh5nqYwP42Y2DDnOAEX7Of7o5aKTttxIAxnFgAg==")!
        #expect(web.prefix(4) == Data("KXF2".utf8))
        let b = try TransferBundle.open(web, passphrase: "move my desk please")
        #expect(b.account.positions["AAPL"]?.quantity == 7 && b.alerts.active.first?.condition == .movePercent(5))
        #expect(b.watchlists.first?.symbols == ["AAPL", "BTC-USD"])
        if let out = ProcessInfo.processInfo.environment["KESTREL_FIXTURE_OUT2"] {
            try bundle().seal(passphrase: "move my desk please", kdf: .testing).base64EncodedString().write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    @Test func validatesContentsLikeTypedInput() {
        var b = bundle()
        b.activeID = UUID()
        #expect(throws: TransferBundle.Failure.self) { try b.validate() }
    }
}


@Suite struct WeekdayTests {
    @Test func weekendsRollToBusinessDays() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let sat = cal.date(from: DateComponents(year: 2026, month: 12, day: 12, hour: 12))!   // Saturday
        let sun = cal.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 12))!    // Sunday
        #expect(cal.component(.weekday, from: SECFilings.nearestWeekday(sat)) == 6)
        #expect(cal.component(.weekday, from: SECFilings.nearestWeekday(sun)) == 2)
    }
}


@Suite struct SubscriptionTests {
    @Test func catalogueMatchesTheThreePlans() {
        #expect(ProPlan.allCases.map(\.months) == [1, 6, 12])
        #expect(ProPlan(productID: "dev.kestrel.pro.annual") == .annual && ProPlan(productID: "x") == nil)
    }

    @Test func perMonthAndSavings() throws {
        let monthly: Decimal = 9.99
        #expect(ProPlan.halfYear.perMonth(Decimal(string: "49.99")!) < 8.34)
        let half = try #require(ProPlan.halfYear.saving(price: Decimal(string: "49.99")!, monthlyPrice: monthly))
        let year = try #require(ProPlan.annual.saving(price: Decimal(string: "99.99")!, monthlyPrice: monthly))
        #expect(abs(half - 0.166) < 0.001 && abs(year - 0.166) < 0.001)    // same per-month value
        #expect(ProPlan.monthly.saving(price: monthly, monthlyPrice: monthly) == nil)
    }

    @Test func gatesOnlyTheProFunctions() {
        let pro = TerminalFunction.allCases.filter { $0.proFeature != nil }
        #expect(Set(pro) == [.bt, .osa, .corr, .ern])
        #expect(TerminalFunction.gp.proFeature == nil && TerminalFunction.trade.proFeature == nil)
    }

    @Test func entitlementFromTransactions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Entitlement.from([], now: now) == .free)
        #expect(Entitlement.from([("dev.kestrel.pro.monthly", now.addingTimeInterval(-1), false)], now: now) == .free)          // expired
        #expect(Entitlement.from([("dev.kestrel.pro.monthly", now.addingTimeInterval(86_400), true)], now: now) == .free)       // refunded
        #expect(Entitlement.from([("com.other.app", now.addingTimeInterval(86_400), false)], now: now) == .free)                // not ours
        let e = Entitlement.from([("dev.kestrel.pro.monthly", now.addingTimeInterval(86_400), false),
                                  ("dev.kestrel.pro.annual", now.addingTimeInterval(300 * 86_400), false)], now: now)
        #expect(e == .pro(plan: .annual, expires: now.addingTimeInterval(300 * 86_400), willRenew: true))
    }
}


@Suite struct ReferencePriceTests {
    @Test func crossedOutPriceIsTheMonthlyEquivalent() {
        let m = Decimal(string: "9.99")!
        #expect(ProPlan.halfYear.referencePrice(monthlyPrice: m) == Decimal(string: "59.94")!)
        #expect(ProPlan.annual.referencePrice(monthlyPrice: m) == Decimal(string: "119.88")!)
        #expect(ProPlan.monthly.referencePrice(monthlyPrice: m) == nil)
    }
}

struct GlobalCoverageTests {
    @Test func listingsOutsideTheUSKeepTheirExchange() {
        let toyota = Universe.resolve("7203.t")
        #expect(toyota?.symbol == "7203.T" && toyota?.assetClass == .equity && toyota?.region == .apac)
        #expect(Universe.resolve("VOD.L")?.region == .emea)
        #expect(Universe.resolve("RY.TO")?.symbol == "RY.TO")
        #expect(Universe.resolve("0700.HK")?.symbol == "0700.HK")
        #expect(Universe.resolve("BRK.B")?.symbol == "BRK-B")          // US share class, not an exchange
        #expect(Universe.resolve("3") == nil)                           // hotspot numbers stay numbers
    }

    @Test func anyCurrencyFutureIndexAndCoinResolves() {
        let gj = Universe.resolve("GBPJPY")
        #expect(gj?.symbol == "GBPJPY=X" && gj?.assetClass == .fx)
        #expect(Universe.resolve("EURUSD") == Universe.currencies.first)
        #expect(Universe.resolve("ES=F")?.assetClass == .commodity)
        #expect(Universe.resolve("^STI")?.assetClass == .index)
        let pepe = Universe.resolve("PEPE", hint: .crypto)
        #expect(pepe?.symbol == "PEPE-USD" && pepe?.isStreaming == false)
        #expect(Universe.resolve("BTC")?.isStreaming == true)
        #expect(Universe.resolve("GOOGLE")?.assetClass == .equity)
    }

    @Test func tokensRoundTrip() {
        for t in ["7203.T", "GBPJPY", "ES=F", "^STI", "SPX", "BTC", "DOGE-USD", "AAPL", "PEPE-USD"] {
            let i = Universe.resolve(t)!
            #expect(Universe.resolve(Universe.token(for: i)) == i, "\(t)")
        }
    }

    @Test func searchDecodesEveryAssetClass() throws {
        let json = #"""
        {"quotes":[
         {"symbol":"7203.T","shortname":"TOYOTA MOTOR CORP","longname":"Toyota Motor Corporation","quoteType":"EQUITY","exchDisp":"Tokyo","typeDisp":"Equity"},
         {"symbol":"VWRL.L","shortname":"Vanguard FTSE All-World","quoteType":"ETF","exchDisp":"London","typeDisp":"ETF"},
         {"symbol":"^GSPC","shortname":"S&P 500","quoteType":"INDEX","exchDisp":"SNP","typeDisp":"Index"},
         {"symbol":"GBPJPY=X","shortname":"GBP/JPY","quoteType":"CURRENCY","exchDisp":"CCY","typeDisp":"Currency"},
         {"symbol":"ES=F","shortname":"E-Mini S&P 500","quoteType":"FUTURE","exchDisp":"CME","typeDisp":"Futures"},
         {"symbol":"PEPE24478-USD","shortname":"Pepe USD","quoteType":"CRYPTOCURRENCY","exchDisp":"CCC","typeDisp":"Cryptocurrency"},
         {"symbol":"BTC-EUR","shortname":"Bitcoin EUR","quoteType":"CRYPTOCURRENCY"},
         {"symbol":"AAPL250117C00200000","quoteType":"OPTION"}
        ]}
        """#
        let hits = try YahooSearch.decode(Data(json.utf8))
        #expect(hits.map(\.instrument.assetClass) == [.equity, .equity, .index, .fx, .commodity, .crypto])
        #expect(hits[0].instrument.name == "Toyota Motor Corporation" && hits[0].exchange == "Tokyo")
        #expect(hits[2].token == "SPX" && hits[3].token == "GBPJPY")
        for h in hits { #expect(Universe.resolve(h.token)?.symbol == h.instrument.symbol, "\(h.token)") }
        #expect(YahooSearch.url("") == nil)
    }
}

struct SecurityFinderCommandTests {
    @Test func secfKeepsFreeText() throws {
        #expect(try CommandParser.parse("SECF nestle sa", current: nil) == Command(function: .secf, query: "NESTLE SA"))
        #expect(try CommandParser.parse("toyota secf <GO>", current: nil).query == "TOYOTA")
        #expect(try CommandParser.parse("FIND", current: nil) == Command(function: .secf))
        #expect(try CommandParser.parse("7203.T DES", current: nil).instrument?.symbol == "7203.T")
    }
}

struct ResearchTests {
    @Test func olsRecoversAKnownLine() throws {
        let x = (0..<200).map { sin(Double($0) * 0.37) * 0.02 }
        let noise = (0..<200).map { cos(Double($0) * 1.91) * 0.001 }
        let y = zip(x, noise).map { 0.0005 + 1.3 * $0 + $1 }
        let r = try #require(Regression.ols(y: y, x: x))
        #expect(abs(r.beta - 1.3) < 0.02 && abs(r.alpha - 0.0005) < 0.0002)
        #expect(r.r2 > 0.98 && r.n == 200 && r.betaT > 50)
        #expect(abs(r.adjustedBeta - (0.67 * r.beta + 0.33)) < 1e-12)
        #expect(Regression.ols(y: [1, 2, 3], x: [1, 1, 1]) == nil)   // no variance in x
    }

    @Test func performanceSummary() throws {
        let closes = [100.0, 110, 99, 121]
        let p = try #require(PerformanceSummary.of(closes, periodsPerYear: 252))
        #expect(abs(p.totalReturn - 0.21) < 1e-12)
        #expect(abs(p.maxDrawdown - (99.0 / 110 - 1)) < 1e-12)
        #expect(PerformanceSummary.rebased(closes).first == 100)
    }

    @Test func simplexProjection() {
        let w = Frontier.projectToSimplex([0.9, 0.8, -2])
        #expect(abs(w.reduce(0, +) - 1) < 1e-12 && w.allSatisfy { $0 >= 0 } && w[2] == 0)
        #expect(Frontier.projectToSimplex([0.2, 0.3, 0.5]) == [0.2, 0.3, 0.5])
    }

    @Test func frontierMatchesTwoAssetClosedForm() throws {
        // Uncorrelated assets: minimum variance weight on A is σB² / (σA² + σB²).
        let mu = [0.08, 0.12], cov = [[0.04, 0.0], [0.0, 0.09]]
        let f = try #require(Frontier.build(mu: mu, cov: cov, riskFree: 0.02))
        #expect(abs(f.minVariance.weights[0] - 0.09 / 0.13) < 1e-4)
        // Tangency weights ∝ Σ⁻¹(μ − rf) = [1.5, 1.111…] → A ≈ 0.574.
        #expect(abs(f.maxSharpe.weights[0] - 1.5 / (1.5 + 0.1 / 0.09)) < 0.03)
        #expect(f.frontier.count >= 5)
        #expect(zip(f.frontier, f.frontier.dropFirst()).allSatisfy { $1.expectedReturn > $0.expectedReturn })
        // Long only: never short the low-return asset, even for very high λ.
        #expect(Frontier.optimize(mu: mu, cov: cov, lambda: 100).weights[0] >= 0)
    }

    @Test func secFramesJoinOntoListings() throws {
        let tickers = #"{"0":{"cik_str":320193,"ticker":"AAPL","title":"Apple Inc."},"7":{"cik_str":1652044,"ticker":"GOOGL","title":"Alphabet Inc."},"9":{"cik_str":1652044,"ticker":"GOOG","title":"Alphabet Inc."},"12":{"cik_str":1067983,"ticker":"BRK.B","title":"Berkshire"}}"#
        let l = try SECFrames.listings(Data(tickers.utf8))
        #expect(l[1652044]?.ticker == "GOOGL" && l[1067983]?.ticker == "BRK-B")
        let rev = try SECFrames.decode(Data(#"{"data":[{"cik":320193,"val":400},{"cik":999,"val":5}]}"#.utf8))
        let rows = SECFrames.rows(listings: l, revenues: rev, contractRevenues: [1652044: 300], netIncome: [320193: 100, 1652044: 60],
                                  assets: [320193: 350], liabilities: [320193: 280], equity: [320193: 70])
        #expect(rows.map(\.ticker) == ["AAPL", "GOOGL"])                 // Berkshire has no facts here; 999 isn't listed
        #expect(abs(rows[0].netMargin! - 0.25) < 1e-12 && abs(rows[0].leverage! - 0.8) < 1e-12)
        #expect(rows[1].revenue == 300 && rows[1].roe == nil)
        #expect(SECFrames.url(concept: "Assets", period: .yearEnd(2025)).absoluteString.hasSuffix("/Assets/USD/CY2025Q4I.json"))
    }

    @Test func csvNeutralizesFormulas() {
        #expect(CSV.field("=HYPERLINK(\"x\")").hasPrefix("\"'="))
        #expect(CSV.field("-0.25") == "-0.25")
        #expect(CSV.make(header: ["a", "b"], rows: [["1", "x,y"]]) == "a,b\r\n1,\"x,y\"\r\n")
    }
}

struct ScreenFallbackTests {
    @Test func derivesMissingTotals() {
        let l = [1: SECFrames.Listing(ticker: "AMZN", name: "Amazon", rank: 4)]
        let rows = SECFrames.rows(listings: l, revenues: [:], contractRevenues: [1: 700], netIncome: [:], assets: [:],
                                  liabilities: [:], equity: [:], profitLoss: [1: 70], equityWithNCI: [1: 300], liabilitiesAndEquity: [1: 800])
        #expect(rows.first?.liabilities == 500 && rows.first?.assets == 800 && rows.first?.netIncome == 70)
        #expect(abs((rows.first?.roe ?? 0) - 70.0 / 300) < 1e-12)
    }
}

struct FactorTests {
    @Test func unzipsAndParsesAFrenchFile() throws {
        let zip = try #require(Data(base64Encoded: "UEsDBBQAAAAIAK5ycV3w2s7pjQAAAMsAAAAFAAAAZi5jc3ZFjUEKgzAURPc5xRzgKzGi6LItSBcVSuwFvprWULFgIqW3r9JId4+Zx8xtsA53Oxq82aGbDXvTo/1gcXZ6wA8GSqpcljjp5oqePbfsTCwE1U8f6Yqa+kjn+kK6Ej9TlQQgkrFKAsg0QCY3wJokQU7lLuehSlVIiuIvCxymaeERFXf+Nbv9fVvJCMkqiS9QSwECFAMUAAAACACucnFd8NrO6Y0AAADLAAAABQAAAAAAAAAAAAAAgAEAAAAAZi5jc3ZQSwUGAAAAAAEAAQAzAAAAsAAAAAAA"))
        let csv = try #require(String(data: try Zip.firstFile(zip), encoding: .utf8))
        let t = FactorTable.parse(csv)
        #expect(t.names == ["Mkt-RF", "SMB", "HML", "RF"])
        #expect(t.rows.count == 2 && t.lastDate == 20260930)          // stops before the annual block
        #expect(abs(t.rows[20260930]![2] - (-0.0088)) < 1e-12)
        let mom = FactorTable(names: ["Mom"], rows: [20260930: [0.0032]])
        let m = t.merged(with: mom)
        #expect(m.names.last == "Mom" && m.rows.count == 1 && m.rows[20260930]!.count == 5)
        #expect(throws: Zip.ZipError.self) { try Zip.firstFile(Data("not a zip at all, honestly".utf8)) }
    }

    @Test func multipleRegressionRecoversLoadings() throws {
        let n = 300
        let a = (0..<n).map { sin(Double($0) * 0.3) * 0.01 }
        let b = (0..<n).map { cos(Double($0) * 0.71) * 0.01 }
        let c = (0..<n).map { sin(Double($0) * 1.37 + 1) * 0.01 }
        let e = (0..<n).map { sin(Double($0) * 5.1) * 0.0005 }
        let y = (0..<n).map { 0.0002 + 1.1 * a[$0] + 0.4 * b[$0] - 0.3 * c[$0] + e[$0] }
        let f = try #require(LinearFit.ols(y: y, columns: [a, b, c], names: ["A", "B", "C"]))
        #expect(f.terms.map(\.name) == ["Alpha", "A", "B", "C"])
        #expect(abs(f.terms[1].coefficient - 1.1) < 0.01 && abs(f.terms[2].coefficient - 0.4) < 0.01 && abs(f.terms[3].coefficient + 0.3) < 0.01)
        #expect(abs(f.terms[0].coefficient - 0.0002) < 0.0001 && f.r2 > 0.99 && f.adjustedR2 <= f.r2)
        // Agrees with the single-regressor OLS.
        let one = try #require(LinearFit.ols(y: y, columns: [a], names: ["A"]))
        let simple = try #require(Regression.ols(y: y, x: a))
        #expect(abs(one.terms[1].coefficient - simple.beta) < 1e-9 && abs(one.terms[1].standardError - simple.betaSE) < 1e-9)
        #expect(LinearFit.ols(y: y, columns: [a, a], names: ["A", "A2"]) == nil)   // collinear
    }

    @Test func dividendSummary() throws {
        func d(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }
        var divs: [Dividend] = []
        for (year, amount) in [(2019, 0.40), (2020, 0.41), (2021, 0.42), (2022, 0.44), (2023, 0.46), (2024, 0.485), (2025, 0.51)] {
            for m in ["03", "06", "09", "11"] { divs.append(Dividend(date: d("\(year)-\(m)-14"), amount: amount)) }
        }
        let s = try #require(DividendSummary.of(divs, price: 68, now: d("2026-01-10")))
        #expect(s.paymentsPerYear == 4)
        #expect(abs(s.trailing12M - 0.51 * 4) < 1e-9 && abs(s.yield! - 2.04 / 68) < 1e-9)
        #expect(abs(s.growth5Y! - (pow(0.51 / 0.41, 0.2) - 1)) < 1e-9)
        #expect(DividendSummary.of([], price: 10) == nil)
    }

    @Test func yahooAdjustedClosesAndDividends() throws {
        let json = #"{"chart":{"result":[{"meta":{"regularMarketPrice":99},"timestamp":[1,2],"events":{"dividends":{"2":{"amount":0.5,"date":2}}},"indicators":{"quote":[{"open":[100,100],"high":[101,101],"low":[99,99],"close":[100,100],"volume":[1,1]}],"adjclose":[{"adjclose":[99.5,100]}]}}]}}"#
        let raw = try YahooChart.decode(Data(json.utf8), adjusted: false)
        let adj = try YahooChart.decode(Data(json.utf8), adjusted: true)
        #expect(raw.candles[0].close == 100 && adj.candles[0].close == 99.5 && abs(adj.candles[0].high - 100.495) < 1e-9)
        #expect(adj.dividends == [Dividend(date: Date(timeIntervalSince1970: 2), amount: 0.5)])
        #expect(YahooChart.url(symbol: "KO", range: "1y", interval: "1d", events: true).query?.contains("events=div") == true)
    }
}

struct WorldBankTests {
    @Test func decodesCountriesSeriesAndLatest() throws {
        let countries = #"[{"page":1,"total":3},[{"id":"JPN","name":"Japan","region":{"id":"EAS","value":"East Asia & Pacific "},"incomeLevel":{"id":"HIC","value":"High income"}},{"id":"WLD","name":"World","region":{"id":"NA","value":"Aggregates"},"incomeLevel":{"id":"NA","value":"Aggregates"}},{"id":"DEU","name":"Germany","region":{"id":"ECS","value":"Europe & Central Asia"},"incomeLevel":{"id":"HIC","value":"High income"}}]]"#
        let c = try WorldBank.decodeCountries(Data(countries.utf8))
        #expect(c.map(\.id) == ["DEU", "JPN"] && c[1].region == "East Asia & Pacific")
        #expect(WorldBank.match("jpn", in: c)?.name == "Japan" && WorldBank.match("germ", in: c)?.id == "DEU")
        #expect(WorldBank.match("", in: c) == nil)

        let panel = #"[{"page":1},[{"countryiso3code":"JPN","date":"2025","value":0.9},{"countryiso3code":"JPN","date":"2024","value":null},{"countryiso3code":"JPN","date":"2023","value":1.5},{"countryiso3code":"DEU","date":"2023","value":-0.3},{"countryiso3code":"","date":"2023","value":2}]]"#
        let p = try WorldBank.decodePanel(Data(panel.utf8))
        #expect(p["JPN"] == [.init(year: 2023, value: 1.5), .init(year: 2025, value: 0.9)] && p.count == 2)
        #expect(WorldBank.latest(p)["JPN"]?.year == 2025 && WorldBank.latest(p)["DEU"]?.value == -0.3)
        #expect(try WorldBank.decodePanel(Data(#"[{"message":[{"id":"120","value":"Invalid value"}]}]"#.utf8)).isEmpty)
        #expect(WorldBank.panelURL(indicator: "SP.POP.TOTL", from: 2011, to: 2026).absoluteString.contains("country/all/indicator/SP.POP.TOTL"))
    }
}

struct EconomyCommandTests {
    @Test func ecstTakesACountry() throws {
        #expect(try CommandParser.parse("ECST japan", current: nil) == Command(function: .ecst, query: "JAPAN"))
        #expect(try CommandParser.parse("united kingdom ecst", current: nil).query == "UNITED KINGDOM")
        #expect(try CommandParser.parse("WB", current: nil).instrument?.ticker == "WB")   // Weibo stays a ticker
    }
}

struct WorldBankBulkTests {
    @Test func decodesTheBulkZip() throws {
        let zip = try #require(Data(base64Encoded: "UEsDBBQAAAAIANx6cV01FPLXBgAAAAQAAAAcAAAATWV0YWRhdGFfSW5kaWNhdG9yX0FQSV9YLmNzdstNLUkEAFBLAwQUAAAACADcenFd69XeWdUAAABAAQAAGQAAAEFQSV9YX0RTMl9lbl9jc3ZfdjJfMS5jc3ZtTs1qwkAQvucphgWhQlwam3pXk4ooqRiK4m3MjkXQTNjdSPtsHvpIvoITbeqlMMzM9zPf7uX8oxL0CDnXtiAVqhXbg4GETnTg6kilh2lp9gV6tk6FQaDm6Dx8VAY9iU+6HPWf+4NeFEndLGOuS2+/IcNjo7ZwzKaBf3mt/iB+HRL3ch/xfbxKrJqxJQxhSZUWdva+lJ5+VWy9A97BJ7NxgKUBR/a0L8jBU6cRJsmiK9Ys1el6oSfZW643uRBxrOW7qtkifXthaOstCh6OVo/s/07bCq5QSwMEFAAAAAgA3HpxXZVWXVkEAAAAAgAAABoAAABNZXRhZGF0YV9Db3VudHJ5X0FQSV9YLmNzdss1AgBQSwECFAMUAAAACADcenFdNRTy1wYAAAAEAAAAHAAAAAAAAAAAAAAAgAEAAAAATWV0YWRhdGFfSW5kaWNhdG9yX0FQSV9YLmNzdlBLAQIUAxQAAAAIANx6cV3r1d5Z1QAAAEABAAAZAAAAAAAAAAAAAACAAUAAAABBUElfWF9EUzJfZW5fY3N2X3YyXzEuY3N2UEsBAhQDFAAAAAgA3HpxXZVWXVkEAAAAAgAAABoAAAAAAAAAAAAAAIABTAEAAE1ldGFkYXRhX0NvdW50cnlfQVBJX1guY3N2UEsFBgAAAAADAAMA2QAAAIgBAAAAAA=="))
        let p = try WorldBank.decodeBulk(zip)
        #expect(p["KOR"] == [.init(year: 2023, value: 44.1), .init(year: 2025, value: 41.5)])
        #expect(p["ABW"] == nil && p.count == 1)
        #expect(WorldBank.csvFields(#""a, b","c""d",,e"#) == ["a, b", "c\"d", "", "e"])
        #expect(throws: Zip.ZipError.self) { try Zip.file(zip) { $0 == "missing.csv" } }
    }
}

struct EventStudyTests {
    /// Weekday sessions from 2024-01-02, at 14:30 UTC (a US open).
    static func sessions(_ n: Int) -> [Date] {
        var out: [Date] = [], d = ISO8601DateFormatter().date(from: "2024-01-02T14:30:00Z")!
        let cal = Calendar(identifier: .gregorian)
        while out.count < n {
            if !cal.isDateInWeekend(d) { out.append(d) }
            d = d.addingTimeInterval(86_400)
        }
        return out
    }

    @Test func recoversKnownEventReturns() throws {
        let days = Self.sessions(620)
        let rm = days.indices.map { sin(Double($0) * 0.41) * 0.01 + cos(Double($0) * 1.3) * 0.004 }
        let eventIdx = [100, 300, 420, 540, 617]          // 100 lacks estimation history; 617 lacks the post window
        var ra = days.indices.map { 0.0001 + 1.2 * rm[$0] + sin(Double($0) * 7.7) * 0.0003 }
        for k in eventIdx { ra[k] += 0.05; if k + 1 < ra.count { ra[k + 1] -= 0.01 } }
        func bars(_ r: [Double]) -> [Candle] {
            var p = 100.0
            return days.indices.map { i in
                if i > 0 { p *= 1 + r[i] }
                return Candle(time: days[i], open: p, high: p, low: p, close: p, volume: 1)
            }
        }
        // Events dated on the calendar day (and one duplicate, which must collapse).
        let dates = eventIdx.map { days[$0] } + [days[300].addingTimeInterval(3600)]
        let s = try #require(EventStudy.run(asset: bars(ra), market: bars(rm), events: dates))
        #expect(s.events.count == 3)                                       // 300, 420, 540
        // 617 is the newest release: its window is still open, so it's pending, not averaged.
        let p = try #require(s.pending.first)
        #expect(s.pending.count == 1 && s.lastDay(p) < 5 && s.lastDay(p) >= 0)
        #expect(abs(s.car(p, from: 0, to: 0) - 0.05) < 0.003)
        #expect(s.events.allSatisfy { abs($0.beta - 1.2) < 0.02 })
        let day0 = s.summary(from: 0, to: 0), around = s.summary(from: -1, to: 1), before = s.summary(from: -5, to: -2)
        #expect(abs(day0.mean - 0.05) < 0.002 && abs(around.mean - 0.04) < 0.003)
        #expect(abs(before.mean) < 0.002 && day0.positive == 1)
        #expect(s.caar.count == 11 && abs(s.caar[5] - s.aar[0...5].reduce(0, +)) < 1e-12)
        #expect(EventStudy.run(asset: bars(ra), market: bars(rm), events: [days[10]]) == nil)
    }

    @Test func extractsEarningsReleases() throws {
        let json = #"{"cik":"320193","filings":{"recent":{"accessionNumber":["a","b","c","d","e"],"filingDate":["2026-10-30","2026-10-31","2026-07-31","2026-05-01","2026-04-15"],"form":["8-K","8-K","8-K","10-Q","8-K"],"items":["2.02,9.01","2.02","2.02","","5.02"],"primaryDocument":["x","x","x","x","x"]}}}"#
        let d = try SECFilings.earningsReleases(Data(json.utf8))
        #expect(d.count == 2)                                              // Oct 31 collapses into Oct 30
        #expect(d.first.map { SECFacts.day.string(from: $0) } == "2026-07-31")
    }
}

struct GuideTests {
    @Test func everyFunctionIsDocumented() {
        let covered = Set(KestrelGuide.topics.map(\.function))
        #expect(TerminalFunction.allCases.allSatisfy { covered.contains($0) })
        for t in KestrelGuide.topics { #expect((try? CommandParser.parse(t.example, current: nil))?.function == t.function, "\(t.example)") }
    }

    @Test func answersPlainQuestions() {
        func top(_ q: String) -> String? { KestrelGuide.answer(q).commands.first }
        #expect(top("how do I see Apple's dividends?") == "AAPL DVD")
        #expect(top("show me a chart of bitcoin") == "BTC GP")
        #expect(top("I want to buy some NVDA") == "NVDA BUY")
        #expect(top("compare my watchlist performance") == "COMP")
        #expect(top("compare my watchlist") == "COMP")
        #expect(top("add a stock to my watchlist") == "W")
        #expect(top("find the ticker for toyota") == "SECF TOYOTA")
        #expect(top("what's inflation doing in the us") == "ECO")
        #expect(top("gdp of japan") == "ECST JAPAN")
        #expect(top("how did aapl react to earnings") == "AAPL EVST")
        #expect(top("advanced chart please") == "NVDA GP")                // "advanced" isn't AMD
        #expect(KestrelGuide.answer("hello").commands.contains("HELP"))
        #expect(KestrelGuide.answer("what is beta?").text.hasPrefix("Beta measures"))
        #expect(KestrelGuide.answer("qwerty zxcv").commands.contains("SECF"))
        #expect(KestrelGuide.securityMentioned(in: "is the bank open") == nil)
        #expect(KestrelGuide.securityMentioned(in: "price of 7203.T")?.symbol == "7203.T")
    }
}

struct GuideConversationTests {
    @Test func everyFunctionHasSteps() {
        #expect(KestrelGuide.topics.allSatisfy { !$0.steps.isEmpty })
        for h in KestrelGuide.howTos { for c in h.commands { #expect((try? CommandParser.parse(c, current: nil)) != nil, "\(h.title): \(c)") } }
        for (_, c) in KestrelGuide.glossary.keys.compactMap({ k in KestrelGuide.answer("what is \(k)").commands.first.map { (k, $0) } }) {
            #expect((try? CommandParser.parse(c, current: nil)) != nil, "\(c)")
        }
    }

    @Test func explainsTrading() {
        let r = KestrelGuide.answer("how do I trade?")
        #expect(r.text.contains("CONFIRM") && r.text.contains("1. ") && r.commands.first == "AAPL BUY")
        #expect(KestrelGuide.answer("how do I buy apple stock").commands.first == "AAPL BUY")
        #expect(KestrelGuide.answer("what's the difference between limit and stop?").text.contains("STOP LMT"))
        let short = KestrelGuide.answer("can I short tesla?")
        #expect(short.text.contains("150%") && short.commands.first == "TSLA SELL")
        #expect(KestrelGuide.answer("how do I cancel an order").commands == ["BLOT"])
        #expect(KestrelGuide.answer("how do panels work?").text.contains("focused panel"))
        #expect(KestrelGuide.answer("is the data live?").text.contains("15 minutes"))
        #expect(KestrelGuide.answer("what can kestrel do").text.contains("EQS"))
    }

    @Test func remembersTheConversation() {
        var c = KestrelGuide.Context()
        let first = KestrelGuide.answer("show me Apple's dividends", context: &c)
        #expect(first.commands.first == "AAPL DVD" && first.text.hasPrefix("DVD for AAPL"))     // "show" isn't "how"
        let more = KestrelGuide.answer("how do I use it?", context: &c)
        #expect(more.text.hasPrefix("How to use DVD") && more.commands.first == "AAPL DVD")
        #expect(KestrelGuide.answer("and for Microsoft?", context: &c).commands.first == "MSFT DVD")
        #expect(KestrelGuide.answer("what about NVDA", context: &c).commands.first == "NVDA DVD")
        #expect(KestrelGuide.answer("thanks!", context: &c).text.hasPrefix("You're welcome"))
    }
}

struct GuideSafetyTests {
    @Test func neverRecommendsTrades() {
        for q in ["is apple a good buy?", "should I invest in nvidia", "will bitcoin go up", "what stock should I buy", "give me a tip"] {
            let r = KestrelGuide.answer(q)
            #expect(r.text.contains("can't tell you what to buy"), "\(q)")
            #expect(!r.commands.contains { $0.hasSuffix(" BUY") || $0.hasSuffix(" SELL") }, "\(q)")
        }
    }

    @Test func routesEverydayQuestions() {
        func top(_ q: String) -> String? { KestrelGuide.answer(q).commands.first }
        #expect(top("what's my profit") == "PORT")
        #expect(top("how much cash do I have") == "PORT")
        #expect(top("tesla news") == "TSLA CN")
        #expect(top("japan economy") == "ECST JAPAN")
        #expect(top("which countries have the highest inflation") != nil && KestrelGuide.answer("which countries have the highest inflation").commands.contains { $0.hasPrefix("ECST") })
        #expect(top("compare apple and microsoft") == "AAPL GP")
        #expect(KestrelGuide.answer("how do I make the chart bigger").text.contains("full screen"))
        #expect(KestrelGuide.answer("how do I go back").text.contains("MENU"))
        #expect(KestrelGuide.answer("does it work offline").text.contains("internet"))
        #expect(top("how do I change colours") == "PREF")
        #expect(KestrelGuide.answer("the app is confusing").text.contains("GO"))
        #expect(top("bitcoin options") == "BTC OMON")
        #expect(top("germany gdp") == "ECST GERMANY")
        #expect(top("what is the market doing today") == "WEI")
        #expect(KestrelGuide.answer("how does the guide work").text.contains("on your device"))
    }
}

@Suite struct RelativeValuationTests {
    func row(_ cik: Int, _ revenue: Double?, netIncome: Double? = nil, equity: Double? = nil, assets: Double? = nil, liabilities: Double? = nil) -> ScreenRow {
        ScreenRow(cik: cik, ticker: "T\(cik)", name: "Co \(cik)", sizeRank: cik, revenue: revenue, netIncome: netIncome, assets: assets, liabilities: liabilities, equity: equity)
    }

    @Test func readsEdgarCompanyListsIncludingFormerNames() {
        let xml = """
        <feed><entry><company-info><cik>0000320193</cik>
        <name>Apple Inc.</name><sic>3571</sic></company-info></entry>
        <entry><company-info><cik>0001571996</cik>
        <formerly-names>&lt;name&gt;Dell Technologies Inc&lt;/name&gt;</formerly-names>
        <name>Dell Technologies Inc.</name></company-info></entry></feed>
        """
        #expect(RelativeValuation.decodeIndustry(Data(xml.utf8)) == [.init(cik: 320193, name: "Apple Inc."), .init(cik: 1571996, name: "Dell Technologies Inc.")])
        #expect(RelativeValuation.industry(fromSubmissions: Data(#"{"sic":"3571","sicDescription":"Electronic Computers"}"#.utf8))?.sic == "3571")
    }

    @Test func picksSameIndustryPeersClosestInSize() {
        let target = row(1, 100)
        let peers = RelativeValuation.pickPeers(target: target, rows: [target, row(2, 110), row(3, 1000), row(4, 95), row(5, 10), row(6, 100)], members: [1, 2, 3, 4, 5], n: 3)
        #expect(peers.map(\.cik) == [4, 2, 3])
    }

    @Test func computesRatiosLikeTheWeb() {
        let r = RelativeValuation.row(row(1, 200, netIncome: 20, equity: 100, assets: 400, liabilities: 300), isTarget: true, price: 10, shares: 50, priorRevenue: 160)
        #expect(r.marketCap == 500 && r.pe == 25 && r.ps == 2.5 && r.pb == 5 && r.margin == 0.1 && r.roe == 0.2 && r.leverage == 0.75)
        #expect(abs(r.growth! - 0.25) < 1e-12)
        #expect(RelativeValuation.row(row(2, 100, netIncome: -5), isTarget: false, price: 10, shares: 10, priorRevenue: nil).pe == nil)
        #expect(RelativeValuation.median([3, nil, 1, 2]) == 2 && RelativeValuation.median([4, 1, 3, 2]) == 2.5)
        #expect(abs(RelativeValuation.premium(30, 20)! - 0.5) < 1e-12)
        #expect(RelativeValuation.recentQuarters(now: Date(timeIntervalSince1970: 1_795_000_000)) == ["CY2026Q3I", "CY2026Q2I", "CY2026Q1I"])
    }
}

@Suite struct ClipboardTableTests {
    @Test func csvBecomesTabSeparatedForExcelAndPandas() {
        let text = CSV.make(header: ["Ticker", "Name", "Note"], rows: [["AAPL", "Apple, Inc.", "said \"hi\"\nthen left"], ["MSFT", "Microsoft", "=SUM(A1)"]])
        #expect(CSV.parse(text) == [["Ticker", "Name", "Note"], ["AAPL", "Apple, Inc.", "said \"hi\"\nthen left"], ["MSFT", "Microsoft", "'=SUM(A1)"]])
        #expect(CSV.tsv(fromCSV: text) == "Ticker\tName\tNote\nAAPL\tApple, Inc.\tsaid \"hi\" then left\nMSFT\tMicrosoft\t'=SUM(A1)\n")
    }
}

@Suite struct SeasonalityTests {
    @Test func monthlyReturnsByCalendarMonthLikeTheWeb() {
        func bar(_ y: Int, _ m: Int, _ d: Int, _ close: Double) -> Candle {
            var c = DateComponents(); c.year = y; c.month = m + 1; c.day = d; c.timeZone = TimeZone(identifier: "UTC")
            let t = Calendar(identifier: .gregorian).date(from: c)!
            return Candle(time: t, open: close, high: close, low: close, close: close, volume: 0)
        }
        let bars = [bar(2024, 0, 31, 100), bar(2024, 1, 10, 105), bar(2024, 1, 29, 110), bar(2024, 2, 29, 99), bar(2025, 0, 31, 120), bar(2025, 1, 28, 114), bar(2025, 2, 31, 114), bar(2025, 3, 15, 200)]
        let r = Seasonality.monthlyReturns(bars, now: bar(2025, 3, 20, 1).time)
        #expect(r.map { [$0.year, $0.month] } == [[2024, 1], [2024, 2], [2025, 1], [2025, 2]])
        #expect(r.map { ($0.ret * 10_000).rounded() / 10_000 } == [0.1, -0.1, -0.05, 0])
        let s = Seasonality.stats(r)
        #expect(s[1].n == 2 && s[1].positive == 0.5 && abs(s[1].mean! - 0.025) < 1e-12 && s[0].n == 0)
    }
}


@Suite struct BondTests {
    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d))!
    }
    static let csv = """
    Date,"1 Mo","1.5 Month","2 Mo","3 Mo","4 Mo","6 Mo","1 Yr","2 Yr","3 Yr","5 Yr","7 Yr","10 Yr","20 Yr","30 Yr"
    11/19/2026,4.20,4.27,4.29,4.34,4.35,4.42,4.62,4.76,4.81,4.86,4.94,5.04,5.43,5.40
    11/18/2026,4.10,4.24,4.27,4.34,,4.43,4.62,4.80,4.84,4.89,4.96,5.07,5.44,5.41
    """

    @Test func readsTreasuryCSVLikeTheWeb() {
        let days = Treasury.parse(Self.csv)
        #expect(days.map(\.date) == [Self.day(2026, 11, 18), Self.day(2026, 11, 19)])
        #expect(days[1].yields["10Y"] == 5.04 && days[1].yields["30Y"] == 5.4 && days[0].yields["4M"] == nil)
        #expect(Treasury.curve(on: Self.day(2026, 11, 18).addingTimeInterval(3600), in: days) == days[0])
        #expect(Treasury.curve(on: Self.day(2026, 11, 1), in: days) == nil)
        #expect(abs(Treasury.interpolate(days[1], years: 8.5)! - 4.99) < 1e-12)
        #expect(Treasury.parse("Date\n").isEmpty)
    }

    @Test func pricesAndRisk() {
        let par = Bond.risk(coupon: 0.05, Bond.Schedule(n: 20, w: 1), yield: 0.05)
        #expect(abs(par.clean - 100) < 1e-8 && abs(par.accrued) < 1e-10)
        #expect(abs(par.modified - 7.7946) < 1e-3 && abs(par.dv01 - 0.077946) < 1e-5)
        #expect(abs(Bond.risk(coupon: 0.04, Bond.Schedule(n: 20, w: 1), yield: 0.05).clean - 92.2054) < 1e-3)
        let zero = Bond.risk(coupon: 0, Bond.Schedule(n: 20, w: 1), yield: 0.05)
        #expect(abs(zero.macaulay - 10) < 1e-10 && abs(zero.convexity - 10 * 10.5 / pow(1.025, 2)) < 1e-8)
        let b = Bond.risk(coupon: 0.06, Bond.Schedule(n: 20, w: 0.5), yield: 0.05)
        #expect(abs(b.accrued - 1.5) < 1e-8)
        #expect(abs(Bond.yield(coupon: 0.06, Bond.Schedule(n: 20, w: 0.5), clean: b.clean)! - 0.05) < 1e-9)
        #expect(Bond.yield(coupon: 0.05, Bond.Schedule(n: 20, w: 1), clean: -1) == nil)
    }

    @Test func couponScheduleActualActual() {
        #expect(Bond.schedule(settle: Self.day(2026, 11, 20), maturity: Self.day(2036, 11, 20)).map { [$0.n, Int($0.w * 1000)] } == [20, 1000])
        let s = Bond.schedule(settle: Self.day(2026, 11, 15), maturity: Self.day(2036, 2, 15))!
        #expect(s.n == 19 && abs(s.w - 92.0 / 184) < 1e-12)
        let eom = Bond.schedule(settle: Self.day(2027, 3, 1), maturity: Self.day(2027, 8, 31))!
        #expect(eom.n == 1 && abs(eom.w - 183.0 / 184) < 1e-12)
        #expect(Bond.schedule(settle: Self.day(2027, 1, 1), maturity: Self.day(2026, 1, 1)) == nil)
    }
}

@Suite struct LearnTests {
    @Test func curriculumLoadsAndCommandsParse() throws {
        #expect(Learn.modules.count == 4)
        let drills = Learn.modules.flatMap(\.drills)
        #expect(drills.count == 16 && Set(drills.map(\.id)).count == 16)
        for d in drills {
            #expect(d.choices.indices.contains(d.answer))
            #expect((try? CommandParser.parse(d.command, current: nil)) != nil, "\(d.command)")
        }
    }

    @Test func shufflesLikeTheWeb() {
        #expect(Learn.order(Learn.modules[0].drills[0]) == [2, 3, 0, 1])
        let slots = Learn.modules.flatMap { $0.drills.map { Learn.order($0).firstIndex(of: $0.answer)! } }
        #expect(slots == [2, 1, 0, 2, 3, 3, 0, 0, 2, 2, 1, 3, 2, 1, 2, 0])
    }

    @Test func progressAndBadges() {
        let m = Learn.modules[1]
        let some = Learn.sanitize([m.drills[0].id, "bogus"])
        #expect(some == [m.drills[0].id] && Learn.done(m, some) == 1 && Learn.next(m, some) == 1)
        let all = Set(m.drills.map(\.id))
        #expect(Learn.earned(m, all) && Learn.next(m, all) == 0)
    }
}
