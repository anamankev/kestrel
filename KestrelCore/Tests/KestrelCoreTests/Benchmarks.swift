import Foundation
import Testing
@testable import KestrelCore

/// Opt-in micro-benchmarks for the hot paths. Run in release:
///   KESTREL_BENCH=1 swift test -c release --filter Benchmarks
/// Optional: KESTREL_FACTS_DIR=<dir with facts-*.json> adds SEC decode timing.
@Suite struct Benchmarks {
    static var enabled: Bool { ProcessInfo.processInfo.environment["KESTREL_BENCH"] != nil }

    /// Median of `runs` timings of `body`, in seconds.
    func time(runs: Int = 7, _ body: () -> Void) -> Double {
        var t: [Double] = []
        for _ in 0..<runs {
            let s = ContinuousClock.now
            body()
            let d = ContinuousClock.now - s
            t.append(Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
        }
        return t.sorted()[runs / 2]
    }

    func report(_ name: String, _ perOp: Double, _ unit: String = "op") {
        let ns = perOp * 1e9
        print("BENCH \(name): \(ns >= 1000 ? String(format: "%.2f µs", ns / 1000) : String(format: "%.0f ns", ns))/\(unit)  (\(String(format: "%.2fM", 1 / perOp / 1e6))/s)")
    }

    @Test func hotPaths() throws {
        guard Self.enabled else { return }

        // 1. Coinbase L2 update message (10 levels), decode only.
        let levels = (0..<10).map { #"{"side":"\#($0 % 2 == 0 ? "bid" : "offer")","event_time":"2026-11-16T21:48:17.933557Z","price_level":"\#(65000 + $0).12","new_quantity":"0.\#($0)1234"}"# }
        let msg = Data(#"{"channel":"l2_data","timestamp":"2026-11-16T21:48:18.177502777Z","sequence_num":4,"events":[{"type":"update","product_id":"BTC-USD","updates":[\#(levels.joined(separator: ","))]}]}"#.utf8)
        let n1 = 20_000
        struct Header: Decodable { let sequence_num: Int?; let timestamp: String? }
        let twoPass = time { for _ in 0..<n1 {
            _ = try? JSONDecoder().decode(Header.self, from: msg)
            _ = try? CoinbaseFeed.decode(msg)
            _ = CoinbaseFeed.date("2026-11-16T21:48:18.177502777Z")
        } } / Double(n1)
        let onePass = time { for _ in 0..<n1 { _ = try? CoinbaseFeed.decodeMessage(msg) } } / Double(n1)
        report("coinbase l2 message, old two-pass (header + body)", twoPass, "msg")
        report("coinbase l2 message, single pass", onePass, "msg")

        // 2. Order book: apply 1M level updates on a ~20k-level book, then build a 20-deep ladder.
        var book = OrderBook()
        for i in 0..<10_000 { book.apply(.bid, price: 60_000 - Double(i) * 0.01, size: 1); book.apply(.ask, price: 60_001 + Double(i) * 0.01, size: 1) }
        let n2 = 1_000_000
        report("order book level update", time(runs: 5) {
            var b = book
            for i in 0..<n2 { b.apply(i % 2 == 0 ? .bid : .ask, price: 60_000 + Double(i % 500) * 0.01 - 2.5, size: Double(i % 3)) }
        } / Double(n2), "update")
        report("ladder(depth: 20) on 20k levels", time { _ = book.ladder(depth: 20) }, "build")

        // 3. Options math.
        let n3 = 1_000_000
        var sink = 0.0
        report("Black-76 price + greeks", time {
            for i in 0..<n3 { sink += Black76.greeks(f: 64_000, k: 50_000 + Double(i % 300) * 100, t: 0.03, sigma: 0.45, call: i % 2 == 0).delta }
        } / Double(n3), "contract")
        let px = Black76.greeks(f: 64_000, k: 66_000, t: 0.03, sigma: 0.42, call: true).price
        let n4 = 100_000
        report("implied vol solve", time { for _ in 0..<n4 { sink += Black76.impliedVol(price: px, f: 64_000, k: 66_000, t: 0.03, call: true) ?? 0 } } / Double(n4), "solve")

        // 4. Full Deribit chain decode (1,000 contracts) + analytics.
        let rows = (0..<1000).map { i in
            #"{"instrument_name":"BTC-\#(["27NOV26","25DEC26","26MAR27"][i % 3])-\#(40_000 + (i / 6) * 500)-\#(i % 2 == 0 ? "C" : "P")","bid_price":0.01,"ask_price":0.011,"mark_price":0.0105,"mark_iv":45.5,"open_interest":12,"volume":3,"underlying_price":64000}"#
        }
        let chainData = Data(#"{"result":[\#(rows.joined(separator: ","))]}"#.utf8)
        report("deribit chain decode (1,000 contracts)", time { _ = try? Deribit.decode(chainData) }, "chain")
        let chain = try Deribit.decode(chainData)
        report("chain analytics (ATM IV, max pain, P/C)", time {
            for e in chain.expiries { _ = chain.atmIV(expiry: e); _ = chain.maxPain(expiry: e); _ = chain.putCallOIRatio(expiry: e) }
        }, "chain")

        // 5. Risk: 1 year × 10 positions VaR.
        let r = (0..<250).map { sin(Double($0)) * 0.02 }
        let returns = Dictionary(uniqueKeysWithValues: (0..<10).map { ("S\($0)", r) })
        let exposure = Dictionary(uniqueKeysWithValues: (0..<10).map { ("S\($0)", 10_000.0) })
        report("historical VaR (10 positions × 250 days)", time {
            sink += Risk.historicalVaR(pnl: Risk.pnlSeries(exposure: exposure, returns: returns)) ?? 0
        }, "portfolio")

        // 6. SEC company facts (real filings, optional).
        if let dir = ProcessInfo.processInfo.environment["KESTREL_FACTS_DIR"] {
            for f in try FileManager.default.contentsOfDirectory(atPath: dir).filter({ $0.hasPrefix("facts-") }).sorted() {
                let d = try Data(contentsOf: URL(fileURLWithPath: dir).appending(path: f))
                report("SEC facts decode \(f) (\(d.count / 1_000_000) MB)", time(runs: 3) { _ = try? SECFacts.decode(d) }, "file")
            }
        }
        #expect(sink.isFinite)
    }
}
