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
        let r = try d.register(name: "Ada Lovelace", email: " Ada@Example.com ", password: pw, confirm: pw, iterations: 1_000, now: t0)
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
        #expect(throws: AuthError.emailTaken) { try d.register(name: "A", email: "ada@example.com", password: pw, confirm: pw, iterations: 1_000) }
        #expect(throws: AuthError.invalidEmail) { try d.register(name: "A", email: "ada@", password: pw, confirm: pw, iterations: 1_000) }
        #expect(throws: AuthError.nameRequired) { try d.register(name: "  ", email: "b@example.com", password: pw, confirm: pw, iterations: 1_000) }
        #expect(throws: AuthError.passwordsDiffer) { try d.register(name: "B", email: "b@example.com", password: pw, confirm: pw + "!", iterations: 1_000) }
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
        let r = try d.register(name: "Ada", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine", iterations: 1_000, now: t0)
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
        let r = try d.register(name: "Ada", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine", iterations: 1_000)
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

    @Test func rejectsHostileIterationCounts() throws {
        var file = try bundle().seal(passphrase: "move my desk please", iterations: 1_000)
        file.replaceSubrange(20..<24, with: [0xFF, 0xFF, 0xFF, 0xFF])               // 4 billion rounds: a DoS
        #expect(throws: TransferBundle.Failure.notATransferFile) { try TransferBundle.open(file, passphrase: "move my desk please") }
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
