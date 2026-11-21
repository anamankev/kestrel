import Foundation

/// DATA: every source the app reads directly, what it powers, and a cheap request that shows whether it answers.
/// Mirrors web/src/core/health.ts (the web reaches most of these through its relay).
public enum DataSources {
    public enum Probe: Sendable, Equatable { case feed, get(URL), needsSECContact(URL) }
    public struct Source: Sendable, Identifiable, Equatable { public let id, name, powers: String; public let probe: Probe }
    public enum Status: String, Sendable { case ok = "OK", slow = "SLOW", down = "DOWN" }

    public static func all(year: Int = Calendar(identifier: .gregorian).component(.year, from: .now)) -> [Source] {
        [
            .init(id: "coinbase-ws", name: "Coinbase live feed", powers: "Live crypto prices, DEPTH, TAS, GP (crypto)", probe: .feed),
            .init(id: "coinbase", name: "Coinbase market data", powers: "Crypto charts and history", probe: .get(URL(string: "https://api.exchange.coinbase.com/products/BTC-USD/ticker")!)),
            .init(id: "yahoo", name: "Yahoo Finance (delayed)", powers: "Stocks, indices, FX, futures, rates: W, GP, HP, BETA, SEAS, MOST",
                  probe: .get(YahooChart.url(symbol: "SPY", range: "1d", interval: "1d"))),
            .init(id: "sec", name: "SEC EDGAR", powers: "FA, DCF, RV, EQS, EVTS, ERN, AI", probe: .needsSECContact(URL(string: "https://data.sec.gov/submissions/CIK0000320193.json")!)),
            .init(id: "treasury", name: "U.S. Treasury", powers: "GC, YAS", probe: .get(Treasury.url(year: year))),
            .init(id: "bls", name: "Bureau of Labor Statistics", powers: "ECO inflation and jobs", probe: .get(URL(string: "https://www.bls.gov/bls/news-release/home.htm")!)),
            .init(id: "nyfed", name: "New York Fed", powers: "ECO policy rates (EFFR, SOFR)", probe: .get(URL(string: "https://markets.newyorkfed.org/api/rates/unsecured/effr/last/1.json")!)),
            .init(id: "news", name: "News feeds (CNBC, MarketWatch, CoinDesk, Yahoo)", powers: "TOP, CN, AI headlines", probe: .get(URL(string: "https://www.cnbc.com/id/100003114/device/rss/rss.html")!)),
            .init(id: "deribit", name: "Deribit", powers: "OMON, OSA crypto options", probe: .get(URL(string: "https://www.deribit.com/api/v2/public/get_index_price?index_name=btc_usd")!)),
            .init(id: "worldbank", name: "World Bank", powers: "ECST country data", probe: .get(URL(string: "https://api.worldbank.org/v2/country/USA?format=json")!)),
            .init(id: "french", name: "Ken French data library", powers: "FACT factor models", probe: .get(URL(string: "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html")!)),
        ]
    }

    /// Over 3 seconds counts as slow; any failure is down.
    public static func classify(ok: Bool, seconds: Double) -> Status { !ok ? .down : seconds > 3 ? .slow : .ok }
}
