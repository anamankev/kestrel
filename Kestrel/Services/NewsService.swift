import Foundation
import KestrelCore

/// Headlines from free RSS wires. Cached per feed for two minutes.
@Observable final class NewsService {
    private(set) var top: [NewsItem] = []
    private(set) var company: [String: [NewsItem]] = [:]
    private(set) var loading = false

    @ObservationIgnored private var fetchedAt: [String: Date] = [:]

    static let wires: [(String, URL)] = [
        ("CNBC", URL(string: "https://www.cnbc.com/id/100003114/device/rss/rss.html")!),
        ("CNBC FIN", URL(string: "https://www.cnbc.com/id/10000664/device/rss/rss.html")!),
        ("MKTWATCH", URL(string: "https://feeds.content.dowjones.io/public/rss/mw_topstories")!),
        ("COINDESK", URL(string: "https://www.coindesk.com/arc/outboundfeeds/rss/")!),
    ]

    private func fresh(_ key: String) -> Bool {
        fetchedAt[key].map { Date().timeIntervalSince($0) < 120 } ?? false
    }

    private static func fetch(_ url: URL, source: String) async -> [NewsItem] {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Mozilla/5.0 (Kestrel Terminal)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        return RSS.parse(data, source: source)
    }

    func loadTop(force: Bool = false) async {
        guard force || !fresh("TOP") else { return }
        loading = true
        defer { loading = false }
        var all: [NewsItem] = []
        await withTaskGroup(of: [NewsItem].self) { g in
            for (name, url) in Self.wires { g.addTask { await Self.fetch(url, source: name) } }
            for await items in g { all += items }
        }
        var seen = Set<String>()
        top = all.filter { seen.insert($0.title.lowercased()).inserted }
            .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        fetchedAt["TOP"] = .now
    }

    func loadCompany(_ i: Instrument, force: Bool = false) async {
        guard force || !fresh(i.symbol) else { return }
        var c = URLComponents(string: "https://feeds.finance.yahoo.com/rss/2.0/headline")!
        c.queryItems = [.init(name: "s", value: i.symbol), .init(name: "region", value: "US"), .init(name: "lang", value: "en-US")]
        let items = await Self.fetch(c.url!, source: "YAHOO")
        company[i.symbol] = items.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        fetchedAt[i.symbol] = .now
    }
}
