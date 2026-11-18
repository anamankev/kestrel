import Foundation

/// The in-app guide's knowledge, answered fully offline: what every function does and how to
/// use it step by step, task guides (placing a paper trade, panels, watchlists, alerts…), and a
/// glossary. `answer(_:context:)` remembers the conversation's security and function, so
/// follow-ups like "how do I use it?" or "and for Microsoft?" work.
public enum KestrelGuide {
    public struct Topic: Sendable {
        public var function: TerminalFunction
        public var summary: String
        public var example: String
        public var keywords: [String]
        /// Step-by-step use, from the real controls on screen.
        public var steps: [String]
    }

    /// A task that spans functions (e.g. placing a trade).
    public struct HowTo: Sendable {
        public var title: String
        public var keywords: [String]
        public var intro: String
        public var steps: [String]
        public var commands: [String]
        public var followUps: [String]
    }

    public struct Reply: Sendable, Equatable {
        public var text: String
        /// Commands the user can tap to run, best first.
        public var commands: [String]
        /// Suggested next questions.
        public var followUps: [String] = []
    }

    /// What the conversation is about, for follow-up questions.
    public struct Context: Sendable {
        public var security: Instrument?
        public var function: TerminalFunction?
        public init() {}
    }

    // MARK: - Functions

    public static let topics: [Topic] = [
        .init(function: .des, summary: "a security's overview: price, change, day and 52-week range, and numbered shortcuts to every other function", example: "AAPL DES",
              keywords: ["overview", "quote", "price", "describe", "description", "summary", "info", "market cap", "how much", "worth"],
              steps: ["Type a ticker then DES, e.g. AAPL DES, and press GO (or just type the ticker: DES is the default).", "Read price, change, day range, volume and the 52-week range bar.", "Tap a numbered button, or type its number and GO, to open that function for the same security."]),
        .init(function: .gp, summary: "a price chart with ranges from 1 day to 5 years, indicators (SMA 20/50, Bollinger, VWAP, RSI), trendlines and comparison", example: "NVDA GP",
              keywords: ["chart", "graph", "candles", "candlestick", "plot", "trend", "indicator", "moving average", "rsi", "vwap", "bollinger band", "technical", "trendline"],
              steps: ["Type a ticker then GP, e.g. NVDA GP.", "Pick a range: 1D, 5D, 1M, 6M, 1Y or 5Y.", "Toggle indicators: SMA 20/50, BOLL, VWAP, RSI. OHLC switches the candle style.", "LINE lets you draw trendlines on the chart; CLR removes them.", "VS… overlays another security to compare performance."]),
        .init(function: .hp, summary: "daily (or weekly) price history with return, volatility and drawdown stats, exportable to CSV", example: "SPY HP",
              keywords: ["history", "historical", "past prices", "csv", "download", "export prices", "daily prices", "price data"],
              steps: ["Type a ticker then HP, e.g. SPY HP.", "Choose the span and switch between daily and weekly bars.", "Tap EXPORT CSV to save or share the table (Files, Mail, AirDrop)."]),
        .init(function: .fa, summary: "financial statements from SEC 10-K filings: revenue, earnings, margins, balance sheet and cash flow", example: "MSFT FA",
              keywords: ["financials", "income statement", "balance sheet", "revenue", "earnings per share", "eps", "profit", "fundamentals", "10-k", "margins", "cash flow", "statements"],
              steps: ["Add a contact email once in PREF: the SEC requires every app to identify itself.", "Type a US ticker then FA, e.g. MSFT FA.", "Read annual figures side by side; ETFs, indices, FX and crypto don't file 10-Ks."]),
        .init(function: .evts, summary: "SEC filings and corporate events: earnings releases, 10-Ks and 10-Qs, insider trades, material 8-Ks", example: "AAPL EVTS",
              keywords: ["filings", "sec filing", "8-k", "insider", "events", "announcements", "corporate", "10-q"],
              steps: ["Needs the SEC contact email in PREF.", "Type a ticker then EVTS, e.g. AAPL EVTS.", "Tap a filing to open the original document on sec.gov."]),
        .init(function: .cn, summary: "news for one company", example: "TSLA CN",
              keywords: ["company news", "headlines about", "news about", "news on"],
              steps: ["Type a ticker then CN, e.g. TSLA CN.", "Tap a headline to read it."]),
        .init(function: .top, summary: "market news from several sources, with search (\"exact phrases\", -exclude), source and time filters, and tappable tickers", example: "TOP",
              keywords: ["news", "headlines", "what happened", "market news", "articles"],
              steps: ["Type TOP and press GO.", "Search in the box: put phrases in quotes, start a word with - to exclude it.", "Filter by source or time; tap a ticker in a headline to load it."]),
        .init(function: .dvd, summary: "ten years of cash dividends: trailing yield, how often it pays, 5-year growth, yearly totals and every payment", example: "KO DVD",
              keywords: ["dividend", "dividends", "yield", "payout", "income stock", "pays"],
              steps: ["Type a ticker then DVD, e.g. KO DVD.", "Read trailing-12-month dividend, yield, frequency and 5-year growth at the top.", "The chart shows yearly totals; the table lists every payment with its change. EXPORT CSV saves it."]),
        .init(function: .secf, summary: "a search across every exchange for stocks, ETFs, funds, indices, currency pairs, futures and crypto", example: "SECF TOYOTA",
              keywords: ["find", "search", "look up", "lookup", "ticker for", "symbol", "what is the ticker", "foreign", "international", "japanese", "german", "british", "london", "tokyo", "hong kong"],
              steps: ["Type SECF and a name, e.g. SECF TOYOTA (or TOYOTA SECF).", "Narrow results with the tabs: stocks & funds, indices, FX, futures, crypto.", "Tap a row to open it; tap + to add it to your watchlist.", "Foreign listings keep their exchange suffix: 7203.T is Tokyo, VOD.L is London."]),
        .init(function: .w, summary: "your watchlists, with live crypto and delayed stock prices", example: "W",
              keywords: ["watchlist", "watch list", "monitor", "track", "follow", "favorites", "favourites", "add a stock", "my list"],
              steps: ["Type W and press GO.", "Type a ticker in the ADD box and press return to add it.", "Use the list menu (e.g. CORE ▾) to switch, create, rename or delete lists.", "Tap a row to load it into the other panels; long-press for more functions or Set alert…"]),
        .init(function: .wei, summary: "world stock indices by region: Americas, Europe/Middle East/Africa, Asia-Pacific", example: "WEI",
              keywords: ["indices", "indexes", "world markets", "global markets", "s&p", "dow", "nasdaq", "ftse", "nikkei", "dax", "markets today", "stock market", "the market", "market doing", "how is the market", "market today", "markets"],
              steps: ["Type WEI and press GO.", "Tap an index to load it into the linked panels."]),
        .init(function: .most, summary: "the day's biggest movers", example: "MOST",
              keywords: ["movers", "gainers", "losers", "most active", "biggest moves", "top stocks", "what's moving"],
              steps: ["Type MOST and press GO.", "Tap a row to load it."]),
        .init(function: .hmap, summary: "a heat map of stocks and crypto coloured by today's move", example: "HMAP",
              keywords: ["heat map", "heatmap", "sectors", "map"],
              steps: ["Type HMAP and press GO.", "Green is up, red is down (blue/orange with colour-vision-safe mode); tap a tile to load it."]),
        .init(function: .fx, summary: "currency rates: G10, crosses, emerging markets and the dollar index", example: "FX",
              keywords: ["currency", "currencies", "forex", "exchange rate", "dollar", "euro", "yen", "pound", "rupee"],
              steps: ["Type FX and press GO.", "Any pair also works on its own, e.g. GBPJPY GP for a chart."]),
        .init(function: .comd, summary: "commodity and futures prices: energy, metals, crops, livestock, index and Treasury futures", example: "COMD",
              keywords: ["commodities", "commodity", "oil", "gold", "silver", "futures", "natural gas", "wheat", "corn", "copper", "coffee"],
              steps: ["Type COMD and press GO.", "Front-month futures are grouped by sector; tap one to chart it."]),
        .init(function: .rates, summary: "US Treasury yields from 3 months to 30 years", example: "RATES",
              keywords: ["treasury", "yields", "bonds", "interest rates", "10-year", "yield curve"],
              steps: ["Type RATES and press GO."]),
        .init(function: .eco, summary: "the US economy: inflation, jobs and Fed policy rates (BLS and New York Fed)", example: "ECO",
              keywords: ["us economy", "inflation", "cpi", "jobs", "unemployment", "fed", "federal reserve", "macro", "sofr", "payrolls"],
              steps: ["Type ECO and press GO.", "Read the latest prints, their change and trend; policy rates are at the top."]),
        .init(function: .ecst, summary: "World Bank statistics for 217 countries: GDP, growth, inflation, unemployment, debt, trade, population", example: "ECST JAPAN",
              keywords: ["country", "countries", "gdp", "world bank", "global economy", "compare countries", "emerging markets", "population", "richest", "economy of", "economy"],
              steps: ["Type ECST and a country, e.g. ECST JAPAN.", "COUNTRY PROFILE shows recent years and a 15-year trend for each indicator.", "Tap an indicator (or RANK COUNTRIES) to rank every country on it; filter by region.", "EXPORT CSV includes the full history back to 1960."]),
        .init(function: .beta, summary: "a regression of the security on a benchmark: beta, adjusted beta, alpha, R² and t-stats, with a scatter plot", example: "NVDA BETA",
              keywords: ["beta", "regression", "systematic risk", "market sensitivity", "capm"],
              steps: ["Type a ticker then BETA, e.g. NVDA BETA.", "Pick the benchmark (SPX by default), the window and daily or weekly returns.", "Read beta and its t-stat; |t| above 2 is significant. EXPORT CSV saves the return pairs."]),
        .init(function: .fact, summary: "Fama-French factor models (CAPM, FF3, Carhart 4, FF5): market, size, value, profitability, investment and momentum exposures", example: "MSFT FACT",
              keywords: ["factor", "factors", "fama", "french", "ff3", "ff5", "carhart", "momentum", "value stock", "growth stock", "smb", "hml", "style"],
              steps: ["Type a US ticker then FACT, e.g. MSFT FACT.", "Pick the model and window.", "Positive SMB means small-cap-like, negative HML means growth-like; ** marks significant loadings."]),
        .init(function: .evst, summary: "an earnings event study: how the stock moved beyond the market around each earnings release, including today's", example: "NVDA EVST",
              keywords: ["event study", "earnings reaction", "abnormal return", "earnings move", "post-earnings", "drift", "react", "reaction", "after earnings", "around earnings", "earnings day", "earnings jump"],
              steps: ["Needs the SEC contact email in PREF (earnings dates come from SEC filings).", "Type a ticker then EVST, e.g. NVDA EVST.", "CAR [−1, +1] is the three-day earnings move beyond the market; the table lists every release.", "A release still in its window shows IN PROGRESS."]),
        .init(function: .bt, summary: "a strategy backtester (moving-average cross, RSI, Bollinger) against buy-and-hold, with Sharpe, Sortino, drawdown and trades", example: "SPY BT",
              keywords: ["backtest", "strategy", "test a strategy", "simulate", "trading rule", "sma cross", "would have"],
              steps: ["Type a ticker then BT, e.g. SPY BT.", "Choose a strategy and its settings, and the period.", "Compare the strategy's equity curve and stats with buy-and-hold. Signals act at the next open, with no look-ahead."]),
        .init(function: .comp, summary: "total-return comparison of your active watchlist on one chart, with Sharpe and drawdown", example: "COMP",
              keywords: ["compare", "comparison", "performance", "returns", "which did better", "relative", "compare my watchlist", "compare stocks", "side by side"],
              steps: ["Put the securities you want in your active watchlist (W).", "Type COMP and press GO; pick 3M to 5Y.", "Each line starts at 100; the table shows return, volatility, Sharpe and worst drop."]),
        .init(function: .mvo, summary: "a portfolio optimizer: the efficient frontier and the lowest-risk and best-Sharpe weights for your watchlist", example: "MVO",
              keywords: ["optimize", "optimizer", "portfolio weights", "efficient frontier", "markowitz", "allocation", "diversify", "diversification", "how much of each"],
              steps: ["Put 2 to 12 securities in your active watchlist.", "Type MVO and press GO; pick 1Y, 2Y or 5Y of history.", "The table shows minimum-variance and maximum-Sharpe weights. Historical inputs are noisy: treat it as a study, not advice."]),
        .init(function: .corr, summary: "a correlation matrix, cross-asset or for your watchlist", example: "CORR",
              keywords: ["correlation", "correlated", "move together", "relationship between"],
              steps: ["Type CORR and press GO.", "Switch between CROSS-ASSET and WATCHLIST, and pick the window.", "Tap a cell for the pair's value; +1 moves together, −1 opposite."]),
        .init(function: .eqs, summary: "a screener over about 5,700 US companies' annual reports: revenue, earnings, margins, ROE, ROA and leverage", example: "EQS",
              keywords: ["screen", "screener", "filter stocks", "find stocks", "profitable companies", "high roe", "stock ideas", "biggest companies"],
              steps: ["Needs the SEC contact email in PREF.", "Type EQS and press GO.", "Set the REVENUE, NET MARGIN, ROE and LIAB/ASSETS filters, or type a name.", "Tap a column header to sort; tap a company to open its financials. EXPORT CSV saves the results."]),
        .init(function: .ern, summary: "projected earnings dates for the companies on your watchlist", example: "ERN",
              keywords: ["earnings date", "earnings calendar", "when does", "report earnings", "next earnings", "upcoming earnings"],
              steps: ["Needs the SEC contact email in PREF.", "Type ERN and press GO.", "Dates are estimated from each company's own reporting rhythm, with a ± range."]),
        .init(function: .omon, summary: "the option chain for BTC and ETH with greeks, the volatility smile and term structure", example: "BTC OMON",
              keywords: ["options", "option chain", "greeks", "implied volatility", "calls", "puts", "smile", "strike"],
              steps: ["Type BTC OMON or ETH OMON.", "Pick an expiry; read bids, asks, implied volatility and greeks by strike.", "Tap a contract to open its trade ticket (long premium only)."]),
        .init(function: .osa, summary: "an option strategy builder for BTC and ETH: payoff at expiry and today, breakevens, greeks", example: "ETH OSA",
              keywords: ["option strategy", "straddle", "strangle", "spread", "iron condor", "butterfly", "payoff", "breakeven"],
              steps: ["Type BTC OSA or ETH OSA.", "Choose a template (straddle, spread, condor, butterfly) or add legs.", "Read the payoff chart, breakevens and net greeks."]),
        .init(function: .depth, summary: "the live order book for streaming crypto", example: "BTC DEPTH",
              keywords: ["order book", "depth", "bids and asks", "level 2", "l2", "liquidity"],
              steps: ["Type BTC DEPTH (or another Coinbase coin)."]),
        .init(function: .tas, summary: "time and sales: every crypto trade as it prints", example: "ETH TAS",
              keywords: ["trades", "time and sales", "tape", "prints"],
              steps: ["Type ETH TAS (or another Coinbase coin)."]),
        .init(function: .trade, summary: "the paper-trading order ticket: buy or sell with market, limit, stop or stop-limit orders, using play money", example: "SOL BUY",
              keywords: ["buy", "sell", "trade", "order", "purchase", "short", "paper trade", "place an order", "invest", "ticket"],
              steps: ["Type a ticker then BUY or SELL, e.g. AAPL BUY.", "Enter a quantity (or tap a preset) and pick MARKET, LIMIT, STOP or STOP LMT.", "Press the order button, then press CONFIRM to send it.", "Check fills in PORT and working orders in BLOT."]),
        .init(function: .port, summary: "your paper portfolio: net liquidation, P&L, positions and risk (beta, VaR, expected shortfall)", example: "PORT",
              keywords: ["portfolio", "positions", "holdings", "p&l", "pnl", "profit and loss", "my account", "balance", "how am i doing", "my money", "my profit", "my profits", "my cash", "how much cash", "cash do i have", "my trades", "my returns", "made money", "lost money", "my risk"],
              steps: ["Type PORT and press GO.", "Read cash, buying power, P&L and each position's unrealized gain.", "Reset paper account (bottom right) starts over with $1,000,000."]),
        .init(function: .blot, summary: "your paper orders and fills; cancel working orders here", example: "BLOT",
              keywords: ["orders", "fills", "blotter", "executions", "open orders", "pending orders", "working orders"],
              steps: ["Type BLOT and press GO.", "Tap CXL on a working order to cancel it."]),
        .init(function: .alrt, summary: "price alerts that fire once when a price goes above or below a level or moves by a percentage, even with the app closed", example: "NVDA ALRT",
              keywords: ["alert", "alerts", "notify", "notification", "tell me when", "price target", "remind"],
              steps: ["Type a ticker then ALRT, e.g. NVDA ALRT (or long-press any row and choose Set alert…).", "Choose ABOVE, BELOW or MOVE %, enter the level, tap SET.", "Alerts fire once; on iPad they're checked in the background, on Mac from the menu bar."]),
        .init(function: .pref, summary: "settings: SEC contact email, colour-vision-safe colours, refresh speed, subscription, iPad ↔ Mac transfer, account", example: "PREF",
              keywords: ["settings", "preferences", "sec email", "contact email", "transfer", "sign out", "log out", "account settings", "colour blind", "color blind", "refresh", "colours", "colors", "change colours", "change colors", "theme"],
              steps: ["Type PREF and press GO.", "Sections: SEC EDGAR contact, display, data refresh, subscription, transfer between iPad and Mac, reset, account (sign out)."]),
        .init(function: .pro, summary: "your Kestrel Pro subscription: plans, renewal, restore and manage", example: "PRO",
              keywords: ["subscription", "subscribe", "plan", "billing", "price of kestrel", "cancel subscription", "restore", "renew"],
              steps: ["Type PRO and press GO.", "See your plan and renewal date; Manage subscription opens Apple's subscription settings.", "Restore purchases brings back a subscription bought on this Apple ID."]),
        .init(function: .help, summary: "the directory of every function with an example for each", example: "HELP",
              keywords: ["all functions", "list of functions", "directory", "commands", "function list"],
              steps: ["Type HELP and press GO, or tap HELP in the bottom bar.", "Tap any example to run it."]),
    ]

    // MARK: - Task guides

    public static let howTos: [HowTo] = [
        HowTo(title: "Placing a paper trade",
              keywords: ["how do i trade", "how to trade", "place a trade", "make a trade", "buy a stock", "buy stock", "buy shares", "how do i buy", "how to buy", "how do i sell", "how to sell", "start trading", "place an order", "trading work", "paper trading work"],
              intro: "Trading in Kestrel is paper trading: $1,000,000 of play money, real prices, no real money and no brokerage.",
              steps: ["Open a ticket: type a ticker then BUY or SELL, e.g. AAPL BUY, and press GO.",
                      "Enter a quantity, or tap a preset (1, 10, 50, 100 shares; fractions for crypto).",
                      "Choose the order type: MARKET fills now; LIMIT sets your price; STOP triggers at a price; STOP LMT triggers, then limits.",
                      "Check estimated cost and buying power, press the order button, then CONFIRM to send.",
                      "See it in PORT (positions, P&L) and BLOT (orders; tap CXL to cancel a working one)."],
              commands: ["AAPL BUY", "PORT", "BLOT"],
              followUps: ["What's the difference between limit and stop?", "Can I short sell?", "How do I cancel an order?"]),
        HowTo(title: "Order types",
              keywords: ["order type", "order types", "limit order", "market order", "stop order", "stop limit", "stop-limit", "difference between limit and stop", "limit and stop", "stop loss", "take profit"],
              intro: "The ticket offers four order types:",
              steps: ["MARKET: fills immediately at the best price (crypto at the live bid/ask; delayed stocks at the last price).",
                      "LIMIT: fills only at your price or better. Buy limits sit below the market, sell limits above.",
                      "STOP: becomes a market order once the price touches your stop. A sell stop below the market is a stop-loss.",
                      "STOP LMT: once the stop triggers, it becomes a limit order at your limit price, so you control the worst fill."],
              commands: ["AAPL BUY", "AAPL SELL", "BLOT"],
              followUps: ["How do I place a trade?", "Can I short sell?"]),
        HowTo(title: "Short selling",
              keywords: ["short sell", "short selling", "go short", "shorting", "sell short", "bet against", "can i short", "how do i short", "how to short", "how can i short"],
              intro: "Yes. Selling more than you own opens a short position in your paper account.",
              steps: ["Open a SELL ticket, e.g. TSLA SELL, and enter a quantity above what you hold.",
                      "The ticket warns that it opens a short; 150% of its value is held as margin from your buying power.",
                      "Buy the shares back later (e.g. TSLA BUY) to cover; covering releases the margin.",
                      "Shorts show as negative quantities in PORT."],
              commands: ["TSLA SELL", "PORT"],
              followUps: ["What's the difference between limit and stop?", "How do I reset my paper account?"]),
        HowTo(title: "Cancelling an order",
              keywords: ["cancel an order", "cancel order", "cancel my order", "remove an order", "undo an order"],
              intro: "Working (unfilled) orders can be cancelled:",
              steps: ["Open BLOT.", "Tap CXL next to the working order. Filled orders can't be cancelled; place an opposite trade instead."],
              commands: ["BLOT"], followUps: ["How do I place a trade?"]),
        HowTo(title: "Resetting the paper account",
              keywords: ["reset my paper", "reset paper", "reset account", "start over", "start again", "lost all my money", "more money"],
              intro: "You can start fresh at any time:",
              steps: ["Open PORT.", "Tap Reset paper account (bottom right) and confirm. Cash returns to $1,000,000 and positions and orders are cleared."],
              commands: ["PORT"], followUps: ["How do I place a trade?"]),
        HowTo(title: "Getting started",
              keywords: ["getting started", "where do i start", "how does this work", "how do i use kestrel", "how to use kestrel", "i'm new", "im new", "first time", "beginner", "tutorial", "basics", "how do i use this"],
              intro: "Kestrel works like a professional terminal: you type a security and a function, then press GO.",
              steps: ["Click the command line at the top and type, e.g., AAPL DES (Apple's overview), then press GO or return.",
                      "Functions that don't need a security work alone: WEI (world markets), TOP (news), W (watchlist).",
                      "Don't know a ticker? Type SECF and a company name, e.g. SECF TOYOTA.",
                      "Use the bottom bar for common functions, and the layout buttons for 2, 4 or 6 panels.",
                      "HELP lists everything; or just ask me."],
              commands: ["AAPL DES", "WEI", "HELP"],
              followUps: ["What can Kestrel do?", "How do panels work?", "How do I place a trade?"]),
        HowTo(title: "Panels and layouts",
              keywords: ["panels", "panel", "layout", "layouts", "split screen", "multiple screens", "two screens", "6 panels", "four panels", "how do panels work", "full screen", "maximize", "maximise", "link", "linked", "bigger", "enlarge", "make it bigger", "make the chart bigger", "chart bigger", "bigger chart", "bigger panel", "two charts", "at once", "go back", "previous screen", "back button"],
              intro: "You can work in 1, 2, 4 or 6 panels at once:",
              steps: ["Pick a layout with the panel buttons at the bottom right.",
                      "Tap a panel's number (top left of the panel) to focus it; commands run in the focused panel.",
                      "Tap a security in a list to load it into the other panels that show a single security (they're linked).",
                      "The ⤢ icon at a panel's top right makes it full screen; tap it again, or CANCEL, to return.",
                      "< or MENU goes back to the panel's previous screen."],
              commands: ["W", "BTC GP"],
              followUps: ["How do I save a layout?", "What are the keyboard shortcuts?"]),
        HowTo(title: "Saving pages",
              keywords: ["save a layout", "save layout", "save my layout", "pages", "save page", "workspace", "save my screen"],
              intro: "A page saves the current layout and every panel's function:",
              steps: ["Set up the panels you want.", "Tap PAGES at the bottom, then Save current as…, and name it.", "Open it later from PAGES; delete pages from the same menu."],
              commands: [], followUps: ["How do panels work?"]),
        HowTo(title: "Managing watchlists",
              keywords: ["add to watchlist", "add a stock to my watchlist", "new watchlist", "create a watchlist", "rename watchlist", "delete watchlist", "remove from watchlist", "manage watchlist", "multiple watchlists"],
              intro: "Watchlists hold up to 100 securities each, and you can have several:",
              steps: ["Open W.", "Type a ticker in the ADD box and press return (or tap + in SECF results).",
                      "Use the list menu (e.g. CORE ▾) to switch lists, create a new list, rename or delete it.",
                      "COMP, MVO, CORR and ERN work on your active list."],
              commands: ["W", "SECF"], followUps: ["Compare my watchlist", "How do alerts work?"]),
        HowTo(title: "Price alerts",
              keywords: ["how do alerts work", "set an alert", "set a price alert", "create an alert", "alert me", "notify me", "tell me when"],
              intro: "Alerts fire once when their condition is met:",
              steps: ["Type a ticker then ALRT, e.g. NVDA ALRT, or long-press a watchlist row and choose Set alert….",
                      "Choose ABOVE, BELOW or MOVE %, enter the level and tap SET.",
                      "They keep working with the app closed: background refresh on iPad, the menu bar on Mac.",
                      "Open ALRT to see active alerts and cancel them (CXL)."],
              commands: ["NVDA ALRT", "ALRT"], followUps: ["How do I manage watchlists?"]),
        HowTo(title: "Keyboard shortcuts",
              keywords: ["shortcut", "shortcuts", "keyboard", "hotkey", "hotkeys", "keys", "tab complete", "autocomplete"],
              intro: "The command line is built for the keyboard:",
              steps: ["Start typing: suggestions appear; ↑/↓ choose, Tab completes, return runs.", "Esc clears the command line.",
                      "Type a number and GO to press that numbered button on screen (e.g. 3 in DES).",
                      "⌘/ opens or closes this guide."],
              commands: ["HELP"], followUps: ["How do panels work?"]),
        HowTo(title: "Exporting data",
              keywords: ["export", "csv", "excel", "spreadsheet", "download data", "save data", "get the data"],
              intro: "Most data screens export CSV for Excel, Numbers or Python:",
              steps: ["Open the function, e.g. SPY HP or EQS.", "Tap EXPORT CSV (top right) and choose where to save or share it.",
                      "Available in HP, BETA, FACT, EVST, DVD, COMP, MVO, EQS and ECST."],
              commands: ["SPY HP", "EQS"], followUps: ["How do I screen stocks?"]),
        HowTo(title: "SEC contact email",
              keywords: ["contact email", "sec email", "needs a contact", "sec contact", "why email", "fundamentals need", "fa not working", "eqs not working"],
              intro: "The SEC asks every app that reads its free data to identify itself with a contact email:",
              steps: ["Open PREF.", "Enter your email under SEC EDGAR CONTACT. It's stored on this device and sent only to sec.gov.",
                      "FA, EVTS, EQS, ERN and EVST then load."],
              commands: ["PREF"], followUps: ["What does EQS do?"]),
        HowTo(title: "Data and delays",
              keywords: ["delayed", "real time", "real-time", "live data", "how current", "how fresh", "is the data live", "where does the data come from", "data source", "data sources"],
              intro: "Where Kestrel's data comes from:",
              steps: ["Coinbase crypto (BTC, ETH, SOL…) streams live: marked LIVE or STREAMING.",
                      "Stocks, ETFs, indices, FX and futures are delayed about 15 minutes (Yahoo Finance): marked DELAYED.",
                      "Financials, filings and earnings dates come from the SEC; US macro from BLS and the New York Fed; countries from the World Bank; factors from the Kenneth R. French Data Library.",
                      "PREF sets how often delayed quotes refresh."],
              commands: ["W", "PREF"], followUps: ["How do I place a trade?"]),
        HowTo(title: "Subscription",
              keywords: ["how much does kestrel cost", "price of kestrel", "subscription cost", "cancel my subscription", "restore purchase", "restore my subscription", "manage subscription", "plans"],
              intro: "Kestrel Pro is $9.99 a month, $49.99 for 6 months or $99.99 a year, through your Apple ID:",
              steps: ["Open PRO to see your plan and renewal date.", "Manage subscription opens Apple's settings to change or cancel.",
                      "Restore purchases brings back a subscription bought on this Apple ID."],
              commands: ["PRO"], followUps: ["What can Kestrel do?"]),
        HowTo(title: "Moving data between iPad and Mac",
              keywords: ["transfer", "move to mac", "move to ipad", "sync", "between ipad and mac", "other device", "backup", "export my account"],
              intro: "Accounts live on each device; you can move your data with an encrypted file:",
              steps: ["Open PREF → TRANSFER BETWEEN IPAD AND MAC.", "Export with a passphrase, then open the file on the other device and enter the same passphrase."],
              commands: ["PREF"], followUps: ["Is my data private?"]),
        HowTo(title: "Privacy and security",
              keywords: ["private", "privacy", "secure", "security", "is my data safe", "encrypted", "password safe"],
              intro: "Your data stays on your device:",
              steps: ["Passwords are never stored, only a salted hash; each account's data is encrypted on the device.",
                      "Kestrel has no API keys and no servers; it reads public market data directly.",
                      "This guide runs entirely on the device too."],
              commands: ["PREF"], followUps: ["How do I move data between iPad and Mac?"]),
        HowTo(title: "Reading a quote",
              keywords: ["bid", "ask", "spread", "what is bid", "bid and ask", "read a quote", "what do the colours mean", "what do the colors mean", "green and red"],
              intro: "On a quote:",
              steps: ["Last is the latest trade price; Net and % are the change from the previous close.",
                      "Bid is the best price buyers offer, Ask the best sellers want; the gap is the spread.",
                      "Green is up and red down (blue/orange in colour-vision-safe mode, the eye icon at the bottom right)."],
              commands: ["BTC DES", "AAPL DES"], followUps: ["Is the data live?"]),
        HowTo(title: "Offline use",
              keywords: ["offline", "without internet", "no internet", "work offline", "internet connection", "wifi"],
              intro: "Kestrel needs an internet connection for market data:",
              steps: ["Prices, news, filings and statistics load from public sources online.",
                      "Your account, watchlists, paper trades, alerts and this guide live on the device, so nothing is lost while you're offline.",
                      "Live crypto shows a LIVE dot that turns off when the feed drops; it reconnects by itself."],
              commands: ["W"], followUps: ["Is the data live?"]),
        HowTo(title: "Investment advice",
              keywords: ["should i buy", "should i sell", "should i invest", "good buy", "good investment", "worth buying", "is it a buy", "will it go up", "will it go down", "go up", "price prediction", "predict", "recommend", "best stock", "best stocks", "what should i buy", "what to buy", "tip", "tips", "make money fast"],
              intro: "I can't tell you what to buy or sell: that's personal financial advice, and I'm not a licensed adviser. I can show you how to research it yourself:",
              steps: ["DES and FA: the company's price, valuation and financial statements.",
                      "GP and HP: price trend and history; BETA and FACT: how risky it is relative to the market.",
                      "EVST: how it has reacted to earnings; DVD: its dividends; CN: its news.",
                      "Try ideas risk-free with paper trading."],
              commands: ["AAPL DES", "AAPL FA", "AAPL BETA"], followUps: ["How do I place a trade?", "What is beta?"]),
        HowTo(title: "About this guide",
              keywords: ["this guide", "the guide", "guide work", "who are you", "what are you", "are you ai", "are you a bot", "chatbot", "assistant"],
              intro: "I'm Kestrel's built-in guide. I run entirely on your device, with no internet or AI service:",
              steps: ["Ask in your own words: what you want to see, how a feature works, or what a term means.",
                      "Tap a command button to open that screen; tap a suggested question to keep going.",
                      "I remember the conversation: after \"Apple's dividends\", try \"how do I use it?\" or \"and for Microsoft?\".",
                      "⌘/ opens or closes me; ↺ starts over. I never give investment advice."],
              commands: ["HELP"], followUps: ["What can Kestrel do?", "How do I place a trade?"]),
        HowTo(title: "What Kestrel can do",
              keywords: ["what can kestrel do", "what can you do", "features", "what does this app do", "capabilities", "everything", "all features", "what can i do here", "what can i do"],
              intro: "Kestrel is a market terminal for research and paper trading:",
              steps: ["Markets: any stock, ETF, index, currency, future or coin (SECF), world indices (WEI), FX, COMD, RATES, movers (MOST), heat map (HMAP), news (TOP).",
                      "Companies: overview (DES), charts (GP), history (HP), financials (FA), filings (EVTS), dividends (DVD), news (CN).",
                      "Research: screener (EQS), BETA, factor models (FACT), earnings event study (EVST), backtests (BT), COMP, portfolio optimizer (MVO), CORR, earnings calendar (ERN).",
                      "Economy: US (ECO) and 217 countries (ECST). Crypto options: OMON, OSA.",
                      "Paper trading: tickets (BUY/SELL), PORT, BLOT and price alerts (ALRT)."],
              commands: ["HELP", "SECF", "EQS"],
              followUps: ["How do I place a trade?", "How do panels work?", "What is beta?"]),
    ]

    // MARK: - Glossary

    public static let glossary: [String: String] = [
        "straddle": "A straddle buys a call and a put at the same strike: it profits from a big move either way. Build one in OSA.",
        "stop loss": "A stop-loss is a sell stop below the market that limits a loss: it turns into a market order if the price falls to it.",
        "beta": "Beta measures how much a security moves with the market: 1 moves in line, above 1 amplifies market moves, below 1 dampens them.",
        "alpha": "Alpha is the return left after accounting for market (or factor) exposure, annualized. Positive alpha beat what its risk would predict.",
        "sharpe": "The Sharpe ratio is return above the risk-free rate divided by volatility: reward per unit of risk. Above 1 is good.",
        "sortino": "The Sortino ratio is like Sharpe but only counts downside volatility.",
        "volatility": "Volatility is how much returns swing, usually the annualized standard deviation of daily returns. Higher is riskier.",
        "drawdown": "Maximum drawdown is the worst peak-to-trough fall over a period.",
        "var": "Value at Risk (VaR) is the daily loss not exceeded on 95% of days, from history. Expected shortfall is the average loss on the worst 5%.",
        "expected shortfall": "Expected shortfall is the average loss on the worst 5% of days, a deeper look at tail risk than VaR.",
        "p/e": "The price-to-earnings ratio is the share price divided by earnings per share: what investors pay for each dollar of profit.",
        "pe ratio": "The price-to-earnings ratio is the share price divided by earnings per share: what investors pay for each dollar of profit.",
        "eps": "Earnings per share is net income divided by shares outstanding.",
        "market cap": "Market capitalization is share price times shares outstanding: what the market values the whole company at.",
        "dividend yield": "Dividend yield is the last 12 months of dividends divided by the share price.",
        "yield": "For a stock, dividend yield is a year's dividends over the price. For a bond, it's the annual return if held to maturity.",
        "r²": "R² is the share of a security's return variance its benchmark or factors explain, from 0 to 1.",
        "r2": "R² is the share of a security's return variance its benchmark or factors explain, from 0 to 1.",
        "r squared": "R² is the share of a security's return variance its benchmark or factors explain, from 0 to 1.",
        "t-stat": "A t-statistic measures how far an estimate is from zero relative to its uncertainty. |t| above about 2 is significant at roughly 95%.",
        "abnormal return": "An abnormal return is the part of a move the market doesn't explain: actual return minus the market model's prediction.",
        "efficient frontier": "The efficient frontier is the set of portfolios with the highest expected return for each level of risk.",
        "correlation": "Correlation runs from −1 to +1: how closely two assets move together. Low correlation helps diversification.",
        "roe": "Return on equity is net income divided by shareholders' equity: profit made on the owners' capital.",
        "roa": "Return on assets is net income divided by total assets.",
        "net margin": "Net margin is net income divided by revenue: how much of each dollar of sales becomes profit.",
        "leverage": "Leverage here is total liabilities divided by total assets: how much of the company is funded by debt and other obligations.",
        "greeks": "Greeks measure an option's sensitivity: delta (price), gamma (delta's change), vega (volatility), theta (time decay).",
        "delta": "Delta is how much an option's price changes for a $1 move in the underlying; also roughly the chance it ends in the money.",
        "implied volatility": "Implied volatility is the volatility an option's price implies; higher means options are pricier.",
        "option": "An option is the right, not the obligation, to buy (call) or sell (put) at a set strike price before expiry.",
        "call": "A call option is the right to buy at the strike price; it gains when the price rises.",
        "put": "A put option is the right to sell at the strike price; it gains when the price falls.",
        "paper trading": "Paper trading is practice trading with $1,000,000 of play money: real prices, no real money.",
        "short": "Short selling is selling shares you don't own to buy them back later, profiting if the price falls.",
        "margin": "Margin is collateral held against a position. Shorts in Kestrel hold 150% of their value as margin.",
        "buying power": "Buying power is the cash available for new orders after margin and working orders are set aside.",
        "smb": "SMB (small minus big) is the size factor: small companies minus large ones. Positive means the stock behaves like a small cap.",
        "hml": "HML (high minus low) is the value factor: cheap (high book-to-market) stocks minus expensive ones. Negative means growth-like.",
        "momentum": "Momentum is the tendency of recent winners to keep winning; the factor is winners minus losers over the past year.",
        "etf": "An ETF (exchange-traded fund) is a fund that trades like a stock, usually tracking an index, e.g. SPY tracks the S&P 500.",
        "index": "An index tracks a basket of securities, like the S&P 500 (SPX) or Nikkei 225 (NKY). WEI lists them by region.",
        "futures": "A futures contract is an agreement to buy or sell at a set price on a future date. COMD shows front-month futures.",
        "bid": "The bid is the best price buyers are currently offering.",
        "ask": "The ask is the best price sellers are currently asking.",
        "spread": "The spread is the gap between bid and ask; smaller spreads mean cheaper trading.",
        "limit order": "A limit order fills only at your price or better.",
        "stop order": "A stop order becomes a market order once the price touches the stop; a sell stop below the market is a stop-loss.",
        "gdp": "GDP (gross domestic product) is the value of everything a country produces in a year. ECST has it for 217 countries.",
        "inflation": "Inflation is how fast prices rise, usually the yearly change in the consumer price index (CPI).",
    ]

    // MARK: - Answering

    /// Answers with a fresh conversation (no memory).
    public static func answer(_ question: String) -> Reply {
        var c = Context()
        return answer(question, context: &c)
    }

    public static func answer(_ question: String, context: inout Context) -> Reply {
        let q = normalize(question)
        let named = securityMentioned(in: question)
        let security = named ?? context.security
        defer { if let named { context.security = named } }

        let functionScores = rank(q, original: question)
        let howToScores = rankHowTos(q)
        let bestFunction = functionScores.first?.1 ?? 0
        let bestHowTo = howToScores.first?.1 ?? 0

        // 1. Follow-ups about the current function: "how do I use it?", "tell me more".
        let followUpWords = [" it ", " that ", " this ", " more", "how does it", "how do i use it", "how do i read", "explain that", "what does it show", "steps"]
        if bestFunction < 2, bestHowTo < 3, let f = context.function, let t = topics.first(where: { $0.function == f }),
           followUpWords.contains(where: { q.contains($0) }) {
            return howToUse(t, security: security)
        }

        // 2. A new security alone: "and for Microsoft?", "what about TSLA" keeps the function.
        let switching = [" what about ", " and for ", " how about ", " and ", " now ", " same for ", " for "].contains { q.hasPrefix($0) }
        if let n = named, bestFunction < (switching ? 4 : 2), bestHowTo < 3, glossaryTerm(in: q) == nil,
           let f = context.function, f.requiresSecurity || f == .alrt || f == .trade,
           let t = topics.first(where: { $0.function == f }) {
            context.function = f
            let cmd = command(for: t, security: n, question: q)
            return Reply(text: "\(f.rawValue) for \(n.ticker) (\(n.name)): \(t.summary).", commands: [cmd, "\(Universe.token(for: n)) DES"],
                         followUps: ["How do I use \(f.rawValue)?"])
        }

        // 3. Task guides (trading, panels, watchlists…) when they fit at least as well as a function.
        // Advice requests always get the no-advice answer, even from a single word ("tip").
        if let (h, s) = howToScores.first, h.title == "Investment advice" ? s >= 2 : s >= 3,
           s >= bestFunction || q.contains(" how ") || h.title == "Investment advice" {
            if h.title == "Investment advice" {
                let t = security.map { Universe.token(for: $0) } ?? "AAPL"
                var r = render(h)
                r.commands = ["\(t) DES", security?.assetClass == .crypto ? "\(t) GP" : "\(t) FA", "\(t) BETA"]
                return r
            }
            if h.title == "Placing a paper trade" || h.title == "Short selling", let sec = security {
                context.function = .trade
                let side = h.title == "Short selling" || q.contains(" sell") ? "SELL" : "BUY"
                var r = render(h)
                r.commands = ["\(Universe.token(for: sec)) \(side)"] + r.commands.filter { !$0.hasSuffix(" BUY") && !$0.hasSuffix(" SELL") }
                return r
            }
            return render(h)
        }

        // 4. Glossary: "what is beta?", "what does ROE mean".
        let definitional = [" what is ", " what are ", " what does ", " what do ", " whats ", " what ", " mean", " explain", " define", " definition", " meaning"].contains { q.contains($0) }
        if let term = glossaryTerm(in: q), definitional || q.trimmingCharacters(in: .whitespaces) == term {
            let related = functionScores.prefix(2).map { command(for: $0.0, security: security, question: q) }
            let more = glossaryHome[term].map { " See \($0)." } ?? ""
            return Reply(text: glossary[term]! + more, commands: related.isEmpty ? (glossaryHome[term].map { [$0] } ?? []) : Array(related),
                         followUps: ["What can Kestrel do?"])
        }

        // 5. Greetings and "I'm lost".
        let greetings = [" hi ", " hello ", " hey ", " help ", " lost ", " confused ", " confusing ", " stuck ", " don't understand ", " dont understand ", " overwhelmed ", " thanks ", " thank you "]
        if functionScores.isEmpty, named == nil, q.trimmingCharacters(in: .whitespaces).isEmpty || greetings.contains(where: { q.contains($0) }) {
            if q.contains(" thank") { return Reply(text: "You're welcome! Ask me anything else, any time.", commands: [], followUps: ["What can Kestrel do?"]) }
            return render(howTos.first { $0.title == "Getting started" }!)
        }

        // 6. Functions.
        guard let top = functionScores.first else {
            if let s = named {
                return Reply(text: "\(s.name) (\(s.ticker)). DES is its overview and GP its chart.",
                             commands: ["\(Universe.token(for: s)) DES", "\(Universe.token(for: s)) GP", s.assetClass == .equity ? "\(Universe.token(for: s)) FA" : "\(Universe.token(for: s)) HP"],
                             followUps: ["How do I place a trade?", "What can Kestrel do?"])
            }
            return Reply(text: "I'm not sure what you mean. Try describing what you want to see or do, like \"Apple's dividends\", \"compare my watchlist\" or \"how do I buy\". To find a company or ticker, SECF searches every exchange.",
                         commands: ["HELP", "SECF"], followUps: ["What can Kestrel do?", "How do I place a trade?"])
        }
        let picks = functionScores.prefix(3).filter { $0.1 >= max(1, top.1 / 2) }.map(\.0)
        let main = picks[0]
        context.function = main.function
        if main.function == .comp {
            let several = securitiesMentioned(in: question)
            if several.count >= 2 {
                let a = several[0].ticker, b = several[1].ticker
                return Reply(text: "To compare \(a) and \(b): open \(a) GP and tap VS… to overlay \(b) on the same chart. For returns, Sharpe and drawdown side by side, add both to your watchlist (W) and run COMP.",
                             commands: ["\(Universe.token(for: several[0])) GP", "W", "COMP"], followUps: ["How do I manage watchlists?"])
            }
        }
        if main.function == .top, let s = security, s.assetClass == .equity {
            context.function = .cn
            return Reply(text: "CN shows news for \(s.ticker); TOP has all market news with search.", commands: ["\(Universe.token(for: s)) CN", "TOP"], followUps: ["What about another stock?"])
        }
        if [" how ", " use ", " using ", " steps ", " work ", " works "].contains(where: { q.contains($0) }) { return howToUse(main, security: security) }
        var text = "\(main.function.rawValue) shows \(main.summary)."
        if let s = security, main.function.requiresSecurity {
            text = "\(main.function.rawValue) for \(s.ticker) shows \(main.summary)."
        } else if main.function.requiresSecurity {
            text += " Type a ticker first, e.g. \(main.example). Don't know the ticker? Use SECF."
        }
        if picks.count > 1 {
            text += "\nRelated: " + picks.dropFirst().map { "\($0.function.rawValue) (\($0.function.title.lowercased()))" }.joined(separator: ", ") + "."
        }
        return Reply(text: text, commands: picks.map { command(for: $0, security: security, question: q) },
                     followUps: ["How do I use \(main.function.rawValue)?"] + (main.function.requiresSecurity ? ["What about another stock?"] : []))
    }

    /// Where each glossary term is used in the app.
    static let glossaryHome: [String: String] = [
        "beta": "NVDA BETA", "alpha": "MSFT FACT", "sharpe": "COMP", "sortino": "SPY BT", "volatility": "COMP", "drawdown": "COMP",
        "var": "PORT", "expected shortfall": "PORT", "p/e": "AAPL DES", "pe ratio": "AAPL DES", "eps": "AAPL FA", "market cap": "AAPL DES",
        "dividend yield": "KO DVD", "r²": "NVDA BETA", "r2": "NVDA BETA", "r squared": "NVDA BETA", "abnormal return": "NVDA EVST",
        "efficient frontier": "MVO", "correlation": "CORR", "roe": "EQS", "roa": "EQS", "net margin": "EQS", "leverage": "EQS",
        "greeks": "BTC OMON", "delta": "BTC OMON", "implied volatility": "BTC OMON", "option": "BTC OMON", "call": "BTC OMON", "put": "BTC OMON",
        "paper trading": "PORT", "short": "PORT", "margin": "PORT", "buying power": "PORT", "smb": "MSFT FACT", "hml": "MSFT FACT", "momentum": "MSFT FACT",
        "etf": "SPY DES", "index": "WEI", "futures": "COMD", "bid": "BTC DES", "ask": "BTC DES", "spread": "BTC DES", "limit order": "AAPL BUY",
        "stop order": "AAPL BUY", "gdp": "ECST JAPAN", "inflation": "ECO", "straddle": "ETH OSA", "stop loss": "AAPL SELL",
    ]

    static func normalize(_ s: String) -> String {
        var t = " " + s.lowercased() + " "
        for (a, b) in [("’", "'"), ("?", " "), ("!", " "), (",", " "), (".", " "), (";", " "), (":", " "), ("\n", " ")] { t = t.replacingOccurrences(of: a, with: b) }
        // Possessives: "apple's" → "apple".
        t = t.replacingOccurrences(of: "'s ", with: " ")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t
    }

    static func glossaryTerm(in q: String) -> String? {
        glossary.keys.sorted { $0.count > $1.count }.first { q.contains(" \($0) ") || q.contains(" \($0)s ") }
    }

    static func matches(_ q: String, _ k: String) -> Bool {
        q.contains(" \(k) ") || q.contains(" \(k)s ") || (k.count >= 6 && q.contains(" \(k)"))
    }

    static func rank(_ q: String, original: String = "") -> [(Topic, Int)] {
        // A function code counts as such only when typed in capitals ("DVD"), so everyday words
        // like "trade", "top" or "most" don't masquerade as commands.
        let typed = Set(original.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0 == $0.uppercased() })
        return topics.compactMap { t -> (Topic, Int)? in
            var score = 0
            for k in t.keywords where matches(q, k) { score += k.contains(" ") ? 3 : 2 }
            if typed.contains(t.function.rawValue) { score += 4 }
            if t.function == .ecst, country(in: original.isEmpty ? q : original) != nil { score += 3 }
            return score > 0 ? (t, score) : nil
        }
        .sorted { $0.1 > $1.1 }
    }

    static func rankHowTos(_ q: String) -> [(HowTo, Int)] {
        howTos.compactMap { h -> (HowTo, Int)? in
            let score = h.keywords.filter { matches(q, $0) }.map { $0.contains(" ") ? 3 : 2 }.reduce(0, +)
            return score > 0 ? (h, score) : nil
        }
        .sorted { $0.1 > $1.1 }
    }

    static func numbered(_ steps: [String]) -> String {
        steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    static func render(_ h: HowTo) -> Reply {
        Reply(text: h.intro + "\n" + numbered(h.steps), commands: h.commands, followUps: h.followUps)
    }

    static func howToUse(_ t: Topic, security: Instrument?) -> Reply {
        let head = "How to use \(t.function.rawValue) (\(t.function.title)): it shows \(t.summary)."
        let cmd = command(for: t, security: security, question: "")
        return Reply(text: head + "\n" + numbered(t.steps), commands: cmd == t.example ? [cmd] : [cmd, t.example],
                     followUps: t.function.requiresSecurity ? ["What about another stock?", "What can Kestrel do?"] : ["What can Kestrel do?"])
    }

    static func command(for t: Topic, security: Instrument?, question: String) -> String {
        if t.function == .ecst, let c = country(in: question) { return "ECST \(c.uppercased())" }
        guard let s = security else { return t.example }
        if t.function == .top, s.assetClass == .equity { return "\(Universe.token(for: s)) CN" }
        let token = Universe.token(for: s)
        if t.function == .trade { return "\(token) \(question.contains(" sell") || question.contains(" short") ? "SELL" : "BUY")" }
        if t.function.requiresSecurity || t.function == .alrt { return "\(token) \(t.function.rawValue)" }
        return t.example
    }

    static let countries = ["united states", "united kingdom", "south africa", "south korea", "new zealand", "saudi arabia", "japan", "china", "india", "germany",
                            "france", "italy", "spain", "canada", "brazil", "mexico", "russia", "australia", "indonesia", "turkey", "argentina", "nigeria",
                            "egypt", "kenya", "ghana", "pakistan", "bangladesh", "vietnam", "thailand", "malaysia", "singapore", "philippines", "israel",
                            "switzerland", "sweden", "norway", "denmark", "finland", "netherlands", "belgium", "austria", "poland", "ireland", "portugal",
                            "greece", "chile", "colombia", "peru", "ukraine", "korea", "uk"]

    /// A country named in the question, for ECST ("japan economy" → ECST JAPAN).
    static func country(in question: String) -> String? {
        let q = normalize(question)
        return countries.first { q.contains(" \($0) ") }.map { $0 == "uk" ? "united kingdom" : $0 == "korea" ? "korea" : $0 }
    }

    /// Up to three distinct securities named in the question, in order of mention.
    static func securitiesMentioned(in question: String) -> [Instrument] {
        var out: [Instrument] = []
        for part in question.components(separatedBy: CharacterSet(charactersIn: ",;")).flatMap({ $0.components(separatedBy: " and ") }).flatMap({ $0.components(separatedBy: " vs ") }) {
            if let i = securityMentioned(in: part), !out.contains(i) { out.append(i) }
            if out.count == 3 { break }
        }
        return out
    }

    /// A security named in the question: a ticker typed in capitals (AAPL, BTC, 7203.T), a
    /// lower-case ticker that isn't an everyday word, or a company or coin named in words.
    public static func securityMentioned(in question: String) -> Instrument? {
        let words = question.split(whereSeparator: { $0.isWhitespace || ",?!;:()\"".contains($0) })
            .map { String($0).replacingOccurrences(of: "'s", with: "").replacingOccurrences(of: "’s", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "'’")) }
        let skip: Set<String> = ["I", "A", "OK", "US", "USA", "CEO", "ETF", "SEC", "GDP", "CPI", "FX", "P/E", "PE", "IV", "VAR", "ROE", "ROA", "EPS", "AI", "IPO", "UK", "EU", "MY", "ME", "IS", "IT", "OR", "AND", "THE", "FOR", "HOW", "WHAT", "CSV", "PNL", "SMB", "HML", "GO", "DO", "TO"]
        for w in words where w.count <= 12 && w == w.uppercased() && w.contains(where: \.isLetter) && !skip.contains(w) {
            if TerminalFunction.from(w) != nil { continue }
            if let i = Universe.instrument(symbol: w) ?? Universe.all.first(where: { $0.ticker == w }) { return i }
            if w.contains("."), let i = Universe.resolve(w) { return i }
        }
        // Lower-case tickers ("aapl"), except ones that are everyday words.
        let english: Set<String> = ["link", "sol", "ada", "cost", "meta", "spy", "all", "ma", "ms", "gs", "v", "amd", "ko"]
        for w in words.map({ $0.lowercased() }) where w.count >= 3 && !english.contains(w) {
            if let i = (Universe.equities + Universe.crypto).first(where: { $0.ticker.lowercased() == w }) { return i }
        }
        // Companies and coins named in words ("apple", "bitcoin", "coca-cola").
        let lower = question.lowercased()
        let aliases: [String: String] = ["coca-cola": "KO", "coca cola": "KO", "coke": "KO", "google": "GOOGL", "facebook": "META", "berkshire": "BRK-B",
                                         "jp morgan": "JPM", "goldman": "GS", "home depot": "HD", "s&p 500": "SPX", "s&p": "SPX", "dow jones": "INDU",
                                         "nasdaq": "CCMP", "ether": "ETH", "gold": "GC1", "oil": "CL1", "crude": "CL1", "euro": "EURUSD"]
        for (name, t) in aliases.sorted(by: { $0.key.count > $1.key.count })
        where lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b", options: .regularExpression) != nil {
            if let i = Universe.resolve(t) { return i }
        }
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
