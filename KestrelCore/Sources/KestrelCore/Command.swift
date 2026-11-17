import Foundation

/// Terminal functions, addressed by mnemonic like a professional terminal.
public enum TerminalFunction: String, CaseIterable, Codable, Sendable {
    case des = "DES", fa = "FA", evts = "EVTS", gp = "GP", depth = "DEPTH", tas = "TAS", cn = "CN", omon = "OMON"
    case w = "W", hmap = "HMAP", wei = "WEI", most = "MOST", fx = "FX", comd = "COMD", rates = "RATES"
    case top = "TOP", eco = "ECO", alrt = "ALRT", pref = "PREF", trade = "TRADE", port = "PORT", blot = "BLOT", help = "HELP"

    public var title: String {
        switch self {
        case .des: "Security Description"
        case .fa: "Financial Analysis"
        case .evts: "Corporate Events & Filings"
        case .eco: "US Economy"
        case .gp: "Price Chart"
        case .depth: "Market Depth"
        case .tas: "Time & Sales"
        case .cn: "Company News"
        case .omon: "Option Monitor"
        case .w: "Monitor"
        case .hmap: "Heat Map"
        case .wei: "World Equity Indices"
        case .most: "Most Active / Movers"
        case .fx: "Currency Monitor"
        case .comd: "Commodities"
        case .rates: "US Treasury Yields"
        case .top: "Top News"
        case .alrt: "Price Alerts"
        case .pref: "Settings"
        case .trade: "Order Ticket"
        case .port: "Portfolio & P&L"
        case .blot: "Order Blotter"
        case .help: "Function Directory"
        }
    }

    /// Functions that operate on a loaded security.
    public var requiresSecurity: Bool {
        switch self {
        case .des, .fa, .evts, .gp, .depth, .tas, .cn, .omon, .trade: true
        default: false
        }
    }

    /// Alternate mnemonics accepted on the command line.
    static let aliases: [String: TerminalFunction] = [
        "G": .gp, "GIP": .gp, "GPO": .gp, "CHART": .gp, "Q": .des, "BOOK": .depth, "L2": .depth,
        "T&S": .tas, "TS": .tas, "N": .top, "NEWS": .top, "MON": .w, "WATCH": .w, "IMAP": .hmap,
        "MOV": .most, "FXC": .fx, "GLCO": .comd, "GOV": .rates, "BUY": .trade, "SELL": .trade,
        "OMS": .trade, "ALERT": .alrt, "SETTINGS": .pref, "PDF": .pref, "FIN": .fa, "EVT": .evts, "EARN": .evts, "FILINGS": .evts, "ECON": .eco, "MACRO": .eco, "FINANCIALS": .fa, "ALERTS": .alrt, "OPT": .omon, "OPTIONS": .omon, "OV": .omon, "SMILE": .omon, "TKT": .trade, "PNL": .port, "PRT": .port, "ORD": .blot, "?": .help,
    ]

    public static func from(_ token: String) -> TerminalFunction? {
        TerminalFunction(rawValue: token) ?? aliases[token]
    }
}

public struct Command: Equatable, Sendable {
    public var function: TerminalFunction
    public var instrument: Instrument?
    /// BUY or SELL, when typed (e.g. `BTC BUY`), to prefill the ticket.
    public var side: TradeSide?

    public init(function: TerminalFunction, instrument: Instrument? = nil, side: TradeSide? = nil) {
        self.function = function; self.instrument = instrument; self.side = side
    }
}

public enum CommandError: Error, Equatable, LocalizedError {
    case empty
    case unknownSecurity(String)
    case needsSecurity(TerminalFunction)

    public var errorDescription: String? {
        switch self {
        case .empty: "Enter a security, a function, or HELP <GO>"
        case .unknownSecurity(let t): "Unknown security: \(t)"
        case .needsSecurity(let f): "\(f.rawValue) needs a security, e.g. AAPL \(f.rawValue) <GO>"
        }
    }
}

/// Parses `TICKER [EXCH] [YELLOW KEY] [FUNCTION] [<GO>]` in any order.
public enum CommandParser {
    static let yellowKeys: [String: AssetClass] = [
        "EQUITY": .equity, "EQUITIES": .equity, "CRYPTO": .crypto, "INDEX": .index, "CURNCY": .fx,
        "CMDTY": .commodity, "COMDTY": .commodity, "GOVT": .rate,
    ]

    /// Longest command accepted; anything longer is rejected before parsing.
    public static let maxLength = 64

    public static func tokens(_ input: String) -> [String] {
        guard input.count <= maxLength else { return [] }
        return input.uppercased()
            .replacingOccurrences(of: "<", with: " ")
            .replacingOccurrences(of: ">", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0 != "GO" }
    }

    public static func parse(_ input: String, current: Instrument?) throws(CommandError) -> Command {
        var function: TerminalFunction?
        var side: TradeSide?
        var hint: AssetClass?
        var ticker: String?

        for token in tokens(input) {
            if function == nil, let f = TerminalFunction.from(token) {
                function = f
                if token == "BUY" { side = .buy } else if token == "SELL" { side = .sell }
            } else if let k = yellowKeys[token] {
                hint = k
            } else if ticker == nil {
                ticker = token
            } // Extra tokens (exchange codes such as US, LN) are accepted and ignored.
        }

        var instrument: Instrument?
        if let ticker {
            guard let resolved = Universe.resolve(ticker, hint: hint) else { throw .unknownSecurity(ticker) }
            instrument = resolved
        }

        guard let fn = function ?? (instrument != nil ? .des : nil) else { throw .empty }
        if instrument == nil {
            if fn.requiresSecurity {
                guard let current else { throw .needsSecurity(fn) }
                instrument = current
            } else if fn == .alrt {
                instrument = current // optional: alerts default to the loaded security
            }
        }
        return Command(function: fn, instrument: instrument, side: side)
    }

    public struct Suggestion: Sendable, Equatable, Identifiable {
        public var completion: String
        public var label: String
        public var detail: String
        public var id: String { completion }
    }

    /// Autocomplete for the token being typed: securities first, then functions.
    public static func suggestions(for input: String, limit: Int = 8) -> [Suggestion] {
        let trimmed = input.uppercased()
        guard let last = trimmed.split(separator: " ").last.map(String.init), !trimmed.hasSuffix(" ") else { return [] }
        let head = String(trimmed.dropLast(last.count))
        let fns = TerminalFunction.allCases
            .filter { $0.rawValue.hasPrefix(last) }
            .map { Suggestion(completion: head + $0.rawValue, label: $0.rawValue, detail: $0.title) }
        let secs = head.isEmpty
            ? Universe.search(last, limit: limit).map {
                Suggestion(completion: $0.ticker, label: "\($0.ticker) \($0.assetClass.rawValue)", detail: $0.name)
            }
            : []
        return Array((secs + fns).prefix(limit))
    }
}
