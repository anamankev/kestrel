import Foundation

/// The in-app guide's knowledge: what every function does in plain words, the words people use
/// for it, and a glossary. `Guide.answer` matches a question offline; the on-device model (when
/// the device has Apple Intelligence) gets `Guide.directory` as its reference.
public enum KestrelGuide {
    public struct Topic: Sendable {
        public var function: TerminalFunction
        public var summary: String
        public var example: String
        public var keywords: [String]
    }

    public struct Reply: Sendable, Equatable {
        public var text: String
        /// Commands the user can tap to run, best first.
        public var commands: [String]
    }

    public static let topics: [Topic] = [
        .init(function: .des, summary: "a security's overview: price, day range, 52-week range, and links to every other function", example: "AAPL DES", keywords: ["overview", "quote", "price", "describe", "description", "about", "summary", "info", "market cap", "how much"]),
        .init(function: .gp, summary: "a price chart with indicators and trendlines", example: "NVDA GP", keywords: ["chart", "graph", "candles", "candlestick", "plot", "trend", "indicator", "moving average", "rsi", "macd", "technical"]),
        .init(function: .hp, summary: "daily price history with returns and volatility, exportable to CSV", example: "SPY HP", keywords: ["history", "historical", "past prices", "csv", "download", "export", "daily prices", "data"]),
        .init(function: .fa, summary: "financial statements from SEC 10-K filings: revenue, earnings, margins, balance sheet", example: "MSFT FA", keywords: ["financials", "income statement", "balance sheet", "revenue", "earnings per share", "eps", "profit", "fundamentals", "10-k", "margins", "cash flow"]),
        .init(function: .evts, summary: "SEC filings and corporate events: earnings releases, insider trades, 8-Ks", example: "AAPL EVTS", keywords: ["filings", "sec", "8-k", "insider", "events", "announcements", "corporate"]),
        .init(function: .cn, summary: "news for one company", example: "TSLA CN", keywords: ["company news", "headlines about"]),
        .init(function: .top, summary: "market news with search (\"exact phrases\", -exclude) and source filters", example: "TOP", keywords: ["news", "headlines", "what happened", "today"]),
        .init(function: .dvd, summary: "ten years of dividends: yield, payment frequency, 5-year growth and every payment", example: "KO DVD", keywords: ["dividend", "dividends", "yield", "payout", "income"]),
        .init(function: .secf, summary: "finds any security by name or ticker on any exchange (stocks, ETFs, funds, indices, FX, futures, crypto)", example: "SECF TOYOTA", keywords: ["find", "search", "look up", "lookup", "ticker for", "symbol", "what is the ticker", "foreign", "exchange", "international"]),
        .init(function: .w, summary: "your watchlists, with live and delayed prices; add tickers in the ADD box", example: "W", keywords: ["watchlist", "watch list", "monitor", "track", "follow", "favorites", "add a stock"]),
        .init(function: .wei, summary: "world stock market indices by region", example: "WEI", keywords: ["indices", "indexes", "world markets", "global markets", "s&p", "dow", "nasdaq", "ftse", "nikkei", "markets today"]),
        .init(function: .most, summary: "today's biggest movers", example: "MOST", keywords: ["movers", "gainers", "losers", "most active", "biggest moves", "top stocks"]),
        .init(function: .hmap, summary: "a heat map of the market", example: "HMAP", keywords: ["heat map", "heatmap", "sectors", "map"]),
        .init(function: .fx, summary: "currency rates: G10, crosses, emerging markets and the dollar index", example: "FX", keywords: ["currency", "currencies", "forex", "fx", "exchange rate", "dollar", "euro", "yen", "pound"]),
        .init(function: .comd, summary: "commodity and futures prices: oil, gas, gold, crops, livestock, index and Treasury futures", example: "COMD", keywords: ["commodities", "commodity", "oil", "gold", "silver", "futures", "gas", "wheat", "corn", "copper"]),
        .init(function: .rates, summary: "US Treasury yields", example: "RATES", keywords: ["treasury", "yields", "bonds", "interest rates", "10-year", "yield curve"]),
        .init(function: .eco, summary: "the US economy: inflation, jobs, and Fed policy rates", example: "ECO", keywords: ["us economy", "inflation", "cpi", "jobs", "unemployment", "fed", "federal reserve", "macro", "sofr"]),
        .init(function: .ecst, summary: "World Bank statistics for 217 countries: GDP, inflation, unemployment, debt; compare or rank countries", example: "ECST JAPAN", keywords: ["country", "countries", "gdp", "world bank", "global economy", "compare countries", "emerging markets", "population"]),
        .init(function: .beta, summary: "regresses a security on a benchmark: beta, alpha, R² and t-stats with a scatter plot", example: "NVDA BETA", keywords: ["beta", "regression", "alpha", "systematic risk", "market sensitivity", "capm"]),
        .init(function: .fact, summary: "Fama-French factor models (CAPM, FF3, Carhart 4, FF5): size, value, profitability and momentum exposures", example: "MSFT FACT", keywords: ["factor", "factors", "fama", "french", "ff3", "ff5", "carhart", "momentum", "value", "size factor", "smb", "hml"]),
        .init(function: .evst, summary: "an earnings event study: how the stock moved beyond the market around each earnings release", example: "NVDA EVST", keywords: ["event study", "earnings reaction", "abnormal return", "earnings move", "post-earnings", "drift", "react", "reaction", "after earnings", "around earnings", "earnings day", "earnings jump"]),
        .init(function: .bt, summary: "backtests trading strategies (moving-average cross, RSI, Bollinger) against buy-and-hold", example: "SPY BT", keywords: ["backtest", "strategy", "test a strategy", "simulate", "trading rule", "sma", "bollinger"]),
        .init(function: .comp, summary: "compares total returns of your watchlist on one chart, with Sharpe and drawdown", example: "COMP", keywords: ["compare", "comparison", "performance", "returns", "which did better", "relative", "compare my watchlist", "compare stocks", "side by side"]),
        .init(function: .mvo, summary: "a portfolio optimizer: efficient frontier, lowest-risk and best-Sharpe weights for your watchlist", example: "MVO", keywords: ["optimize", "optimizer", "portfolio weights", "efficient frontier", "markowitz", "allocation", "diversify", "diversification"]),
        .init(function: .corr, summary: "a correlation matrix across assets or your watchlist", example: "CORR", keywords: ["correlation", "correlated", "move together", "diversification matrix"]),
        .init(function: .eqs, summary: "screens about 5,700 US companies on annual-report data: revenue, margins, ROE, ROA, leverage", example: "EQS", keywords: ["screen", "screener", "filter stocks", "find stocks", "profitable companies", "high roe", "ideas"]),
        .init(function: .ern, summary: "projected earnings dates for your watchlist", example: "ERN", keywords: ["earnings date", "earnings calendar", "when does", "report earnings", "next earnings"]),
        .init(function: .omon, summary: "the options chain with greeks, volatility smile and term structure (BTC and ETH)", example: "BTC OMON", keywords: ["options", "option chain", "greeks", "implied volatility", "iv", "calls", "puts", "smile"]),
        .init(function: .osa, summary: "an option strategy builder: payoff at expiry and today, breakevens, greeks (BTC and ETH)", example: "ETH OSA", keywords: ["option strategy", "straddle", "strangle", "spread", "iron condor", "butterfly", "payoff"]),
        .init(function: .depth, summary: "the live order book (crypto)", example: "BTC DEPTH", keywords: ["order book", "depth", "bids", "asks", "level 2", "l2", "liquidity"]),
        .init(function: .tas, summary: "time and sales: every trade as it prints (crypto)", example: "ETH TAS", keywords: ["trades", "time and sales", "tape", "prints"]),
        .init(function: .trade, summary: "a paper-trading order ticket: market, limit, stop, stop-limit; no real money moves", example: "SOL BUY", keywords: ["buy", "sell", "trade", "order", "purchase", "short", "paper trade", "place an order", "invest"]),
        .init(function: .port, summary: "your paper portfolio: P&L, positions and risk (beta, VaR, expected shortfall)", example: "PORT", keywords: ["portfolio", "positions", "holdings", "p&l", "pnl", "profit and loss", "my account", "balance", "var", "risk"]),
        .init(function: .blot, summary: "your paper orders and fills", example: "BLOT", keywords: ["orders", "fills", "blotter", "executions", "open orders"]),
        .init(function: .alrt, summary: "price alerts that fire even when the app is closed", example: "NVDA ALRT", keywords: ["alert", "alerts", "notify", "notification", "tell me when", "price target"]),
        .init(function: .pref, summary: "settings: theme, SEC contact email, encrypted iPad ↔ Mac transfer, account", example: "PREF", keywords: ["settings", "preferences", "sec email", "contact email", "transfer", "sign out", "account settings", "colour blind", "color blind"]),
        .init(function: .pro, summary: "your Kestrel Pro subscription", example: "PRO", keywords: ["subscription", "subscribe", "pro", "plan", "billing", "price of kestrel", "cancel subscription", "restore"]),
        .init(function: .help, summary: "the directory of every function", example: "HELP", keywords: ["all functions", "list of functions", "directory", "commands", "what can i do"]),
    ]

    public static let glossary: [String: String] = [
        "beta": "Beta measures how much a security moves with the market: 1 moves in line, above 1 amplifies market moves, below 1 dampens them. Try NVDA BETA.",
        "alpha": "Alpha is the return left over after accounting for market (or factor) exposure, annualized. Positive alpha means it beat what its risk would predict. See BETA or FACT.",
        "sharpe": "The Sharpe ratio is return above the risk-free rate divided by volatility: reward per unit of risk. Above 1 is good. See COMP or MVO.",
        "volatility": "Volatility is how much returns swing, usually the annualized standard deviation of daily returns. Higher means riskier.",
        "drawdown": "Maximum drawdown is the worst peak-to-trough fall over a period. See COMP or BT.",
        "var": "Value at Risk (VaR) is the loss you'd not expect to exceed on 95% of days, from history. Expected shortfall is the average loss on the worst 5%. See PORT.",
        "p/e": "The price-to-earnings ratio is the share price divided by earnings per share: what investors pay for each dollar of profit. See DES or FA.",
        "pe": "The price-to-earnings ratio is the share price divided by earnings per share: what investors pay for each dollar of profit. See DES or FA.",
        "dividend yield": "Dividend yield is the last 12 months of dividends divided by the share price. See DVD.",
        "yield": "For a stock, dividend yield is a year's dividends over the price (DVD). For a bond, it's the annual return if held to maturity (RATES).",
        "r²": "R² is the share of a security's return variance its benchmark or factors explain, from 0 to 1. See BETA or FACT.",
        "r2": "R² is the share of a security's return variance its benchmark or factors explain, from 0 to 1. See BETA or FACT.",
        "t-stat": "A t-statistic measures how far an estimate is from zero relative to its uncertainty. |t| above about 2 means it's significant at roughly 95%.",
        "abnormal return": "An abnormal return is the part of a move the market doesn't explain: actual return minus what the market model predicted. See EVST.",
        "efficient frontier": "The efficient frontier is the set of portfolios with the highest expected return for each level of risk. See MVO.",
        "correlation": "Correlation runs from −1 to +1: how closely two assets move together. Low correlation helps diversification. See CORR.",
        "roe": "Return on equity is net income divided by shareholders' equity: how much profit a company makes on owners' capital. See EQS or FA.",
        "roa": "Return on assets is net income divided by total assets. See EQS.",
        "greeks": "Greeks measure an option's sensitivity: delta (price), gamma (delta's change), vega (volatility), theta (time decay). See OMON.",
        "implied volatility": "Implied volatility is the volatility an option's price implies; higher means options are pricier. See OMON.",
        "paper trading": "Paper trading is practice trading with $1,000,000 of play money: real prices, no real money. Try SOL BUY, then PORT.",
        "smb": "SMB (small minus big) is the size factor: small companies' returns minus large ones'. A positive loading means the stock behaves like a small cap. See FACT.",
        "hml": "HML (high minus low) is the value factor: cheap (high book-to-market) stocks minus expensive ones. Negative means growth-like. See FACT.",
    ]

    /// The reference handed to the on-device model.
    public static var directory: String {
        topics.map { "\($0.function.rawValue) (\($0.function.title)): \($0.summary). Example: \($0.example)" }.joined(separator: "\n")
    }

    static let syntax = "Type a security and a function, then press GO: for example AAPL DES or NVDA GP. Functions that don't need a security work alone, like WEI or TOP. Tap a command below to run it."

    /// Answers a question offline: glossary first, then the best-matching functions, with any
    /// security named in the question filled into the commands.
    public static func answer(_ question: String) -> Reply {
        let q = " " + question.lowercased().replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: ",", with: " ") + " "
        let security = securityMentioned(in: question)

        let greetings = ["hi", "hello", "hey", "help", "what can you do", "how does this work", "how do i use", "where do i start", "i'm lost", "im lost", "confused", "getting started"]
        let isGreeting = q.trimmingCharacters(in: .whitespaces).isEmpty || greetings.contains { q.contains(" \($0) ") || q.contains(" \($0)") && $0.contains(" ") }
        if isGreeting, security == nil, (bestTopics(q).first?.1 ?? 0) < 2 {
            return Reply(text: "I'm the Kestrel guide. Ask me what you want to do in your own words: \"show Apple's dividends\", \"compare my watchlist\", \"what is beta?\". " + syntax,
                         commands: ["HELP", "AAPL DES", "W", "TOP"])
        }

        // "What is X" style questions go to the glossary.
        for term in glossary.keys.sorted(by: { $0.count > $1.count }) where q.contains(" \(term) ") || q.contains(" \(term)?") {
            if q.contains("what") || q.contains("mean") || q.contains("explain") || q.contains("define") || bestTopics(q).first.map({ $0.1 < 2 }) ?? true {
                let related = bestTopics(q).prefix(2).map { command(for: $0.0, security: security, question: q) }
                return Reply(text: glossary[term]!, commands: Array(related))
            }
        }

        let ranked = bestTopics(q)
        guard let top = ranked.first else {
            if let s = security {
                return Reply(text: "\(s.name) (\(s.ticker)): here are the main views. DES is the overview; GP is the chart.",
                             commands: ["\(s.ticker) DES", "\(s.ticker) GP", s.assetClass == .equity ? "\(s.ticker) FA" : "\(s.ticker) HP"])
            }
            return Reply(text: "I'm not sure which function you mean. " + syntax + " If you're looking for a company or ticker, SECF searches every exchange.",
                         commands: ["HELP", "SECF"])
        }
        let picks = ranked.prefix(3).filter { $0.1 >= max(1, top.1 / 2) }.map(\.0)
        let main = picks[0]
        var text = "\(main.function.rawValue) shows \(main.summary)."
        if main.function.requiresSecurity, security == nil {
            text += " It works on one security: type its ticker first, e.g. \(main.example). Don't know the ticker? Use SECF."
        } else if let s = security, main.function.requiresSecurity {
            text = "\(main.function.rawValue) for \(s.ticker) shows \(main.summary)."
        }
        if picks.count > 1 {
            text += " Related: " + picks.dropFirst().map { "\($0.function.rawValue) (\($0.function.title.lowercased()))" }.joined(separator: ", ") + "."
        }
        return Reply(text: text, commands: picks.map { command(for: $0, security: security, question: q) })
    }

    static func bestTopics(_ q: String) -> [(Topic, Int)] {
        topics.compactMap { t -> (Topic, Int)? in
            var score = 0
            for k in t.keywords where q.contains(" \(k)") { score += k.contains(" ") ? 3 : 2 }
            let code = t.function.rawValue.lowercased()
            if q.contains(" \(code) ") { score += 4 }
            return score > 0 ? (t, score) : nil
        }
        .sorted { $0.1 > $1.1 }
    }

    static func command(for t: Topic, security: Instrument?, question: String = "") -> String {
        guard let s = security else { return t.example }
        let token = Universe.token(for: s)
        if t.function == .trade { return "\(token) \(question.contains(" sell") || question.contains(" short") ? "SELL" : "BUY")" }
        if t.function.requiresSecurity || t.function == .alrt { return "\(token) \(t.function.rawValue)" }
        return t.example
    }

    /// A security named in the question: a ticker typed in capitals (AAPL, BTC, 7203.T), or a
    /// company in the built-in list named in words ("apple", "bitcoin").
    public static func securityMentioned(in question: String) -> Instrument? {
        let words = question.split(whereSeparator: { $0.isWhitespace || ",?!;:()\"'".contains($0) }).map(String.init)
        let skip: Set<String> = ["I", "A", "OK", "US", "USA", "CEO", "ETF", "SEC", "GDP", "CPI", "FX", "P/E", "PE", "IV", "VAR", "ROE", "ROA", "EPS", "AI", "IPO", "UK", "EU", "MY", "ME", "IS", "IT", "OR", "AND", "THE", "FOR", "HOW", "WHAT", "CSV", "PNL"]
        for w in words where w.count <= 12 && w == w.uppercased() && w.contains(where: \.isLetter) && !skip.contains(w) {
            if TerminalFunction.from(w) != nil { continue }
            if let i = Universe.instrument(symbol: w) ?? Universe.all.first(where: { $0.ticker == w }) { return i }
            if w.contains("."), let i = Universe.resolve(w) { return i }
        }
        // Lower-case tickers ("aapl"), except ones that are everyday words.
        let english: Set<String> = ["link", "sol", "ada", "cost", "meta", "spy", "all", "ma", "ms", "gs", "v"]
        for w in words.map({ $0.lowercased() }) where w.count >= 3 && !english.contains(w) {
            if let i = (Universe.equities + Universe.crypto).first(where: { $0.ticker.lowercased() == w }) { return i }
        }
        // Companies and coins named in words ("apple", "bitcoin"), by the first word of the name.
        let lower = question.lowercased()
        let common: Set<String> = ["advanced", "bank", "spdr", "invesco", "the", "new"]
        for i in Universe.equities + Universe.crypto {
            let first = i.name.lowercased().split(separator: " ").first.map(String.init) ?? ""
            let name = first.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            guard name.count >= 4, !common.contains(name) else { continue }
            if lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b", options: .regularExpression) != nil { return i }
        }
        return nil
    }
}
