import Foundation

/// Yellow-key style asset classes. Raw values are what a user types on the command line.
public enum AssetClass: String, Codable, Sendable, CaseIterable {
    case equity = "EQUITY"
    case crypto = "CRYPTO"
    case index = "INDEX"
    case fx = "CURNCY"
    case commodity = "CMDTY"
    case rate = "GOVT"
    case option = "OPTION"
}

public enum Region: String, Codable, Sendable, CaseIterable {
    case americas = "AMERICAS"
    case emea = "EMEA"
    case apac = "ASIA/PACIFIC"
}

public struct Instrument: Hashable, Codable, Sendable, Identifiable {
    /// Data-source symbol: a Yahoo symbol (`^GSPC`, `EURUSD=X`) or a Coinbase product (`BTC-USD`).
    public let symbol: String
    /// What the user types and sees (`SPX`, `EURUSD`, `BTC`).
    public let ticker: String
    public let name: String
    public let assetClass: AssetClass
    public let region: Region?

    public var id: String { symbol }
    /// Crypto streams tick-by-tick over WebSocket; everything else is polled.
    public var isStreaming: Bool { assetClass == .crypto }

    public init(symbol: String, ticker: String, name: String, assetClass: AssetClass, region: Region? = nil) {
        self.symbol = symbol
        self.ticker = ticker
        self.name = name
        self.assetClass = assetClass
        self.region = region
    }
}

/// The built-in security master. Unknown equity tickers resolve ad hoc.
public enum Universe {
    private static func eq(_ s: String, _ n: String) -> Instrument {
        Instrument(symbol: s, ticker: s, name: n, assetClass: .equity, region: .americas)
    }
    private static func cx(_ base: String, _ n: String) -> Instrument {
        Instrument(symbol: "\(base)-USD", ticker: base, name: n, assetClass: .crypto)
    }
    private static func ix(_ s: String, _ t: String, _ n: String, _ r: Region) -> Instrument {
        Instrument(symbol: s, ticker: t, name: n, assetClass: .index, region: r)
    }
    private static func fx(_ pair: String, _ n: String) -> Instrument {
        Instrument(symbol: "\(pair)=X", ticker: pair, name: n, assetClass: .fx)
    }
    private static func cm(_ s: String, _ t: String, _ n: String) -> Instrument {
        Instrument(symbol: s, ticker: t, name: n, assetClass: .commodity)
    }
    private static func rt(_ s: String, _ t: String, _ n: String) -> Instrument {
        Instrument(symbol: s, ticker: t, name: n, assetClass: .rate, region: .americas)
    }

    public static let equities: [Instrument] = [
        eq("AAPL", "Apple Inc."), eq("MSFT", "Microsoft Corp."), eq("NVDA", "NVIDIA Corp."),
        eq("AMZN", "Amazon.com Inc."), eq("GOOGL", "Alphabet Inc. Cl A"), eq("META", "Meta Platforms Inc."),
        eq("TSLA", "Tesla Inc."), eq("AVGO", "Broadcom Inc."), eq("AMD", "Advanced Micro Devices"),
        eq("NFLX", "Netflix Inc."), eq("JPM", "JPMorgan Chase & Co."), eq("GS", "Goldman Sachs Group"),
        eq("MS", "Morgan Stanley"), eq("BAC", "Bank of America Corp."), eq("BRK-B", "Berkshire Hathaway Cl B"),
        eq("V", "Visa Inc."), eq("MA", "Mastercard Inc."), eq("XOM", "Exxon Mobil Corp."),
        eq("COST", "Costco Wholesale"), eq("WMT", "Walmart Inc."), eq("SPY", "SPDR S&P 500 ETF"),
        eq("QQQ", "Invesco QQQ Trust"),
    ]

    public static let crypto: [Instrument] = [
        cx("BTC", "Bitcoin"), cx("ETH", "Ethereum"), cx("SOL", "Solana"), cx("XRP", "XRP"),
        cx("DOGE", "Dogecoin"), cx("ADA", "Cardano"), cx("AVAX", "Avalanche"), cx("LINK", "Chainlink"),
    ]

    public static let indices: [Instrument] = [
        ix("^GSPC", "SPX", "S&P 500", .americas), ix("^DJI", "INDU", "Dow Jones Industrial Avg", .americas),
        ix("^IXIC", "CCMP", "Nasdaq Composite", .americas), ix("^RUT", "RTY", "Russell 2000", .americas),
        ix("^VIX", "VIX", "CBOE Volatility Index", .americas), ix("^GSPTSE", "SPTSX", "S&P/TSX Composite", .americas),
        ix("^BVSP", "IBOV", "Bovespa", .americas), ix("^MXX", "MEXBOL", "S&P/BMV IPC", .americas),
        ix("^FTSE", "UKX", "FTSE 100", .emea), ix("^GDAXI", "DAX", "DAX", .emea),
        ix("^FCHI", "CAC", "CAC 40", .emea), ix("^STOXX50E", "SX5E", "Euro Stoxx 50", .emea),
        ix("^IBEX", "IBEX", "IBEX 35", .emea), ix("^SSMI", "SMI", "Swiss Market Index", .emea),
        ix("^N225", "NKY", "Nikkei 225", .apac), ix("^HSI", "HSI", "Hang Seng", .apac),
        ix("000001.SS", "SHCOMP", "Shanghai Composite", .apac), ix("^AXJO", "AS51", "S&P/ASX 200", .apac),
        ix("^KS11", "KOSPI", "KOSPI", .apac), ix("^BSESN", "SENSEX", "BSE Sensex", .apac),
        ix("^TWII", "TWSE", "Taiwan Weighted", .apac),
    ]

    public static let currencies: [Instrument] = [
        fx("EURUSD", "Euro / US Dollar"), fx("GBPUSD", "British Pound / US Dollar"),
        fx("USDJPY", "US Dollar / Japanese Yen"), fx("USDCHF", "US Dollar / Swiss Franc"),
        fx("AUDUSD", "Australian Dollar / US Dollar"), fx("USDCAD", "US Dollar / Canadian Dollar"),
        fx("USDCNY", "US Dollar / Chinese Yuan"), fx("USDMXN", "US Dollar / Mexican Peso"),
    ]

    public static let commodities: [Instrument] = [
        cm("CL=F", "CL1", "WTI Crude Oil"), cm("BZ=F", "CO1", "Brent Crude Oil"),
        cm("NG=F", "NG1", "Natural Gas"), cm("GC=F", "GC1", "Gold"), cm("SI=F", "SI1", "Silver"),
        cm("HG=F", "HG1", "Copper"), cm("ZC=F", "C1", "Corn"), cm("ZW=F", "W1", "Wheat"),
    ]

    public static let rates: [Instrument] = [
        rt("^IRX", "US3M", "US Treasury 13-Week Bill"), rt("^FVX", "US5Y", "US Treasury 5-Year"),
        rt("^TNX", "US10Y", "US Treasury 10-Year"), rt("^TYX", "US30Y", "US Treasury 30-Year"),
    ]

    public static let all: [Instrument] = equities + crypto + indices + currencies + commodities + rates

    private static let byTicker: [String: [Instrument]] = Dictionary(grouping: all, by: \.ticker)
    private static let bySymbol: [String: Instrument] = Dictionary(all.map { ($0.symbol, $0) }, uniquingKeysWith: { a, _ in a })

    public static func instrument(symbol: String) -> Instrument? { bySymbol[symbol] }

    /// Resolves a typed token (`AAPL`, `BTC`, `SPX`, `BRK/B`) into an instrument.
    /// Unknown but well-formed tickers resolve to an ad-hoc equity.
    /// A listed Deribit option (`BTC-27NOV26-70000-C`) as a tradable instrument.
    public static func option(_ symbol: String) -> Instrument? {
        let s = symbol.uppercased()
        guard let p = Deribit.parse(s) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dMMMyy"
        let strike = p.strike.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        return Instrument(symbol: s, ticker: s, name: "\(p.underlying) \(f.string(from: p.expiry).uppercased()) \(strike) \(p.call ? "Call" : "Put")",
                          assetClass: .option)
    }

    public static func resolve(_ raw: String, hint: AssetClass? = nil) -> Instrument? {
        if let o = option(raw) { return o }
        let token = raw.uppercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        if hint == .crypto, let c = bySymbol[token.hasSuffix("-USD") ? token : "\(token)-USD"] { return c }
        if let matches = byTicker[token] {
            return matches.first { $0.assetClass == hint } ?? matches[0]
        }
        if let s = bySymbol[token] ?? bySymbol[raw.uppercased()] { return s }
        if hint == .fx, let f = bySymbol["\(token)=X"] { return f }
        guard hint == nil || hint == .equity,
              token.range(of: #"^[A-Z][A-Z0-9\-]{0,7}$"#, options: .regularExpression) != nil
        else { return nil }
        return Instrument(symbol: token, ticker: token, name: token, assetClass: .equity, region: .americas)
    }

    /// Prefix search on ticker, then substring search on name.
    public static func search(_ query: String, limit: Int = 6) -> [Instrument] {
        let q = query.uppercased()
        guard !q.isEmpty else { return [] }
        let byPrefix = all.filter { $0.ticker.hasPrefix(q) }
        let byName = all.filter { !$0.ticker.hasPrefix(q) && $0.name.uppercased().contains(q) }
        return Array((byPrefix + byName).prefix(limit))
    }
}
