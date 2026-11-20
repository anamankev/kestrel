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
    /// Coinbase-listed crypto streams tick-by-tick over WebSocket; everything else is polled.
    public var isStreaming: Bool { assetClass == .crypto && Universe.streamed.contains(symbol) }

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
        ix("^VXN", "VXN", "CBOE Nasdaq-100 Volatility", .americas), ix("^MERV", "MERVAL", "S&P Merval", .americas),
        ix("^SPCOSLCP", "COLCAP", "S&P Colombia Select", .americas),
        ix("FTSEMIB.MI", "FTSEMIB", "FTSE MIB", .emea), ix("^AEX", "AEX", "AEX", .emea),
        ix("^N100", "N100", "Euronext 100", .emea), ix("^BFX", "BEL20", "BEL 20", .emea),
        ix("^ATX", "ATX", "Austrian Traded Index", .emea), ix("^OMXS30", "OMX", "OMX Stockholm 30", .emea),
        ix("^OMXC25", "OMXC25", "OMX Copenhagen 25", .emea), ix("^TA125.TA", "TA125", "Tel Aviv 125", .emea),
        ix("^TASI.SR", "SASEIDX", "Tadawul All Share", .emea), ix("^CASE30", "EGX30", "EGX 30", .emea),
        ix("^J203.JO", "JALSH", "JSE All Share", .emea),
        ix("^NSEI", "NIFTY", "Nifty 50", .apac), ix("^STI", "FSSTI", "Straits Times Index", .apac),
        ix("^JKSE", "JCI", "Jakarta Composite", .apac), ix("^KLSE", "FBMKLCI", "FTSE Bursa Malaysia KLCI", .apac),
        ix("^SET.BK", "SET", "SET Index", .apac), ix("^NZ50", "NZSE50", "S&P/NZX 50", .apac),
    ]

    public static let currencies: [Instrument] = [
        fx("EURUSD", "Euro / US Dollar"), fx("GBPUSD", "British Pound / US Dollar"),
        fx("USDJPY", "US Dollar / Japanese Yen"), fx("USDCHF", "US Dollar / Swiss Franc"),
        fx("AUDUSD", "Australian Dollar / US Dollar"), fx("USDCAD", "US Dollar / Canadian Dollar"),
        fx("USDCNY", "US Dollar / Chinese Yuan"), fx("USDMXN", "US Dollar / Mexican Peso"),
        fx("NZDUSD", "New Zealand Dollar / US Dollar"), fx("EURGBP", "Euro / British Pound"),
        fx("EURJPY", "Euro / Japanese Yen"), fx("GBPJPY", "British Pound / Japanese Yen"),
        fx("USDINR", "US Dollar / Indian Rupee"), fx("USDBRL", "US Dollar / Brazilian Real"),
        fx("USDZAR", "US Dollar / South African Rand"), fx("USDKRW", "US Dollar / Korean Won"),
        fx("USDSGD", "US Dollar / Singapore Dollar"), fx("USDHKD", "US Dollar / Hong Kong Dollar"),
        fx("USDTRY", "US Dollar / Turkish Lira"),
        Instrument(symbol: "DX-Y.NYB", ticker: "DXY", name: "US Dollar Index", assetClass: .fx),
    ]

    /// FX board sections.
    public static var currencyGroups: [(String, [Instrument])] {
        let g10: Set = ["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD", "DXY"]
        let crosses: Set = ["EURGBP", "EURJPY", "GBPJPY"]
        return [("G10 & DOLLAR INDEX", currencies.filter { g10.contains($0.ticker) }),
                ("CROSSES", currencies.filter { crosses.contains($0.ticker) }),
                ("EMERGING MARKETS", currencies.filter { !g10.contains($0.ticker) && !crosses.contains($0.ticker) })]
    }

    public static let commodities: [Instrument] = [
        cm("CL=F", "CL1", "WTI Crude Oil"), cm("BZ=F", "CO1", "Brent Crude Oil"),
        cm("NG=F", "NG1", "Natural Gas"), cm("GC=F", "GC1", "Gold"), cm("SI=F", "SI1", "Silver"),
        cm("HG=F", "HG1", "Copper"), cm("ZC=F", "C1", "Corn"), cm("ZW=F", "W1", "Wheat"),
        cm("HO=F", "HO1", "Heating Oil"), cm("RB=F", "XB1", "RBOB Gasoline"),
        cm("PL=F", "PL1", "Platinum"), cm("PA=F", "PA1", "Palladium"),
        cm("ZS=F", "S1", "Soybeans"), cm("KC=F", "KC1", "Coffee"), cm("SB=F", "SB1", "Sugar No. 11"),
        cm("CT=F", "CT1", "Cotton"), cm("CC=F", "CC1", "Cocoa"), cm("LE=F", "LC1", "Live Cattle"), cm("HE=F", "LH1", "Lean Hogs"),
        cm("ES=F", "ES1", "E-mini S&P 500"), cm("NQ=F", "NQ1", "E-mini Nasdaq-100"), cm("YM=F", "DM1", "E-mini Dow"),
        cm("RTY=F", "RTY1", "E-mini Russell 2000"), cm("ZN=F", "TY1", "10-Year T-Note"), cm("ZB=F", "US1", "US Treasury Bond"),
    ]

    /// COMD board sections, by front-month future.
    public static var commodityGroups: [(String, [Instrument])] {
        let sections: [(String, [String])] = [
            ("ENERGY", ["CL1", "CO1", "NG1", "HO1", "XB1"]), ("METALS", ["GC1", "SI1", "HG1", "PL1", "PA1"]),
            ("AGRICULTURE & LIVESTOCK", ["C1", "W1", "S1", "KC1", "SB1", "CT1", "CC1", "LC1", "LH1"]),
            ("EQUITY INDEX & RATE FUTURES", ["ES1", "NQ1", "DM1", "RTY1", "TY1", "US1"]),
        ]
        return sections.map { name, tickers in (name, tickers.compactMap { t in commodities.first { $0.ticker == t } }) }
    }

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

    /// Coinbase products on the live WebSocket feed.
    public static let streamed: Set<String> = Set(crypto.map(\.symbol))

    /// Yahoo exchange suffixes for listings outside the US (`7203.T`, `VOD.L`, `SAP.DE`).
    /// Single letters that are US share classes (`BRK.B`, `BF.A`) are deliberately absent.
    public static let exchangeSuffixes: [String: Region] = [
        "TO": .americas, "V": .americas, "NE": .americas, "CN": .americas, "SA": .americas, "MX": .americas,
        "BA": .americas, "SN": .americas, "L": .emea, "IL": .emea, "DE": .emea, "F": .emea, "PA": .emea,
        "AS": .emea, "BR": .emea, "LS": .emea, "MI": .emea, "MC": .emea, "SW": .emea, "VI": .emea, "ST": .emea,
        "OL": .emea, "CO": .emea, "HE": .emea, "IR": .emea, "WA": .emea, "AT": .emea, "IS": .emea, "JO": .emea,
        "TA": .emea, "SR": .emea, "QA": .emea, "PR": .emea, "BD": .emea, "T": .apac, "HK": .apac, "SS": .apac,
        "SZ": .apac, "KS": .apac, "KQ": .apac, "TW": .apac, "TWO": .apac, "AX": .apac, "NZ": .apac, "SI": .apac,
        "NS": .apac, "BO": .apac, "JK": .apac, "BK": .apac, "KL": .apac,
    ]

    private static let isoCurrencies = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    /// A six-letter token made of two ISO currency codes (`GBPJPY`): an FX cross.
    static func isCurrencyPair(_ t: String) -> Bool {
        t.count == 6 && t.allSatisfy(\.isLetter) && isoCurrencies.contains(String(t.prefix(3))) && isoCurrencies.contains(String(t.suffix(3)))
    }

    /// What to type so `resolve` returns this instrument again.
    public static func token(for i: Instrument) -> String {
        switch i.assetClass {
        case .fx: i.ticker
        case .crypto: streamed.contains(i.symbol) ? i.ticker : i.symbol
        case .index, .commodity, .rate: byTicker[i.ticker] != nil ? i.ticker : i.symbol
        default: i.symbol
        }
    }

    public static func resolve(_ raw: String, hint: AssetClass? = nil) -> Instrument? {
        if let o = option(raw) { return o }
        let upper = raw.uppercased()
        let token = raw.uppercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        if hint == .crypto, let c = bySymbol[token.hasSuffix("-USD") ? token : "\(token)-USD"] { return c }
        if let matches = byTicker[token] {
            return matches.first { $0.assetClass == hint } ?? matches[0]
        }
        if let s = bySymbol[token] ?? bySymbol[raw.uppercased()] { return s }
        if hint == .fx, let f = bySymbol["\(token)=X"] { return f }
        // Any FX cross: GBPJPY, or Yahoo's GBPJPY=X.
        let pair = upper.hasSuffix("=X") ? String(upper.dropLast(2)) : upper
        if (hint == nil || hint == .fx), isCurrencyPair(pair) {
            return Instrument(symbol: "\(pair)=X", ticker: pair, name: "\(pair.prefix(3)) / \(pair.suffix(3))", assetClass: .fx)
        }
        // Futures (CL=F, ES=F) and Yahoo index symbols (^N100, ^STI).
        // ASCII only: the symbol becomes part of a request path.
        if upper.range(of: #"^[A-Z0-9.\-]{1,8}=F$"#, options: .regularExpression) != nil {
            return Instrument(symbol: upper, ticker: upper, name: upper, assetClass: .commodity)
        }
        if upper.range(of: #"^\^[A-Z0-9.]{1,11}$"#, options: .regularExpression) != nil {
            return Instrument(symbol: upper, ticker: upper, name: upper, assetClass: .index)
        }
        // Any coin: Coinbase streams the majors; the rest poll Yahoo's XXX-USD.
        if hint == .crypto || upper.hasSuffix("-USD"), token.range(of: #"^[A-Z0-9]{2,12}(-USD)?$"#, options: .regularExpression) != nil {
            let base = token.hasSuffix("-USD") ? String(token.dropLast(4)) : token
            return Instrument(symbol: "\(base)-USD", ticker: hint == .crypto ? base : "\(base)-USD", name: base, assetClass: .crypto)
        }
        // Listed outside the US: keep Yahoo's exchange suffix.
        if hint == nil || hint == .equity,
           let dot = upper.lastIndex(of: "."), let region = exchangeSuffixes[String(upper[upper.index(after: dot)...])],
           upper.range(of: #"^[A-Z0-9][A-Z0-9\-&]{0,11}\.[A-Z]{1,3}$"#, options: .regularExpression) != nil {
            return Instrument(symbol: upper, ticker: upper, name: upper, assetClass: .equity, region: region)
        }
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
