import Foundation

/// One result from the security finder: a resolvable instrument plus where it trades.
public struct SearchHit: Hashable, Sendable, Identifiable {
    public var instrument: Instrument
    public var exchange: String
    public var kind: String
    public var id: String { instrument.symbol }
    /// What to type on the command line to load it.
    public var token: String { Universe.token(for: instrument) }
}

/// Yahoo Finance symbol search (no key): every exchange, plus ETFs, funds, indices, futures, FX and crypto.
public enum YahooSearch {
    public static func url(_ query: String, limit: Int = 20) -> URL? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...64).contains(q.count) else { return nil }
        var c = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        c.queryItems = [.init(name: "q", value: q), .init(name: "quotesCount", value: String(limit)),
                        .init(name: "newsCount", value: "0"), .init(name: "listsCount", value: "0")]
        return c.url
    }

    private struct Root: Decodable { let quotes: [Q]? }
    private struct Q: Decodable {
        let symbol: String?
        let shortname: String?
        let longname: String?
        let quoteType: String?
        let exchDisp: String?
        let typeDisp: String?
    }

    public static func decode(_ data: Data) throws -> [SearchHit] {
        let quotes = try JSONDecoder().decode(Root.self, from: data).quotes ?? []
        var seen = Set<String>()
        return quotes.compactMap { q -> SearchHit? in
            guard let raw = q.symbol?.uppercased(), !raw.isEmpty, raw.count <= 24 else { return nil }
            let name = (q.longname ?? q.shortname ?? raw).trimmingCharacters(in: .whitespaces)
            guard let i = instrument(symbol: raw, name: name, type: q.quoteType ?? ""), seen.insert(i.symbol).inserted else { return nil }
            return SearchHit(instrument: i, exchange: q.exchDisp ?? "", kind: q.typeDisp ?? q.quoteType?.capitalized ?? "")
        }
    }

    /// Maps a Yahoo quote type onto Kestrel's asset classes (options and unknown types are skipped).
    static func instrument(symbol s: String, name: String, type: String) -> Instrument? {
        switch type {
        case "EQUITY", "ETF", "MUTUALFUND":
            let suffix = s.split(separator: ".").last.map(String.init)
            let region = s.contains(".") ? suffix.flatMap { Universe.exchangeSuffixes[$0] } ?? .americas : .americas
            return Instrument(symbol: s, ticker: s, name: name, assetClass: .equity, region: region)
        case "INDEX":
            if let known = Universe.instrument(symbol: s) { return known }
            return Instrument(symbol: s, ticker: s, name: name, assetClass: .index)
        case "CURRENCY":
            let pair = s.hasSuffix("=X") ? String(s.dropLast(2)) : s
            guard pair.count == 6 else { return nil }
            return Universe.instrument(symbol: "\(pair)=X") ?? Instrument(symbol: "\(pair)=X", ticker: pair, name: name, assetClass: .fx)
        case "FUTURE":
            return Universe.instrument(symbol: s) ?? Instrument(symbol: s, ticker: s, name: name, assetClass: .commodity)
        case "CRYPTOCURRENCY":
            if let known = Universe.instrument(symbol: s) { return known }
            guard s.hasSuffix("-USD") else { return nil }   // USD pairs only, like the rest of the book
            return Instrument(symbol: s, ticker: s, name: name, assetClass: .crypto)
        default:
            return nil
        }
    }
}
