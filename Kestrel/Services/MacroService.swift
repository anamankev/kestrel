import Foundation
import KestrelCore

/// US macro data: BLS (one batched request for every series) and New York Fed policy rates.
/// Cached for six hours; these series move monthly or daily.
@Observable final class MacroService {
    private(set) var series: [String: [DataPoint]] = [:]
    private(set) var effr: NYFed.Rates?
    private(set) var sofr: NYFed.Rates?
    private(set) var updated: Date?
    private(set) var error: String?
    private(set) var loading = false

    func load(force: Bool = false) async {
        if !force, let updated, Date().timeIntervalSince(updated) < 6 * 3600 { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        async let bls: [String: [DataPoint]]? = {
            guard let (d, _) = try? await URLSession.shared.data(for: BLS.request(series: MacroIndicator.all.map(\.id))) else { return nil }
            return try? BLS.decode(d)
        }()
        async let e: NYFed.Rates? = Self.rates("effr")
        async let s: NYFed.Rates? = Self.rates("sofr")
        let (b, ef, so) = await (bls, e, s)
        if let b { series = b }
        effr = ef ?? effr
        sofr = so ?? sofr
        error = (b == nil && ef == nil) ? "Couldn't reach BLS or the New York Fed." : nil
        if b != nil || ef != nil { updated = .now }
    }

    private static func rates(_ r: String) async -> NYFed.Rates? {
        guard let (d, _) = try? await URLSession.shared.data(from: NYFed.url(r)) else { return nil }
        return try? NYFed.decode(d)
    }

    // MARK: Treasury curve (GC, YAS)

    private(set) var curves: [Treasury.CurveDay] = []
    private(set) var curveYears = 0
    private(set) var curveError: String?
    @ObservationIgnored private var curvesUpdated: Date?

    /// Daily par curves for the last `years` calendar years plus this one (one small CSV per year, refreshed hourly).
    func loadCurves(years: Int) async {
        if curveYears >= years, let curvesUpdated, Date().timeIntervalSince(curvesUpdated) < 3600 { return }
        let now = Calendar(identifier: .gregorian).component(.year, from: .now)
        let files = await withTaskGroup(of: [Treasury.CurveDay].self) { g in
            for y in (now - years)...now {
                g.addTask {
                    guard let (d, r) = try? await URLSession.shared.data(for: URLRequest(url: Treasury.url(year: y), timeoutInterval: 25)),
                          (r as? HTTPURLResponse)?.statusCode == 200 else { return [] }
                    return Treasury.parse(String(decoding: d, as: UTF8.self))
                }
            }
            var all: [Treasury.CurveDay] = []
            for await rows in g { all += rows }
            return all
        }
        guard !files.isEmpty else { curveError = "Couldn't reach Treasury.gov."; return }
        curves = files.sorted { $0.date < $1.date }
        curveYears = years
        curvesUpdated = .now
        curveError = nil
    }

    // MARK: World Bank (ECST)

    private(set) var countries: [WorldBank.Country] = []
    /// Indicator id → ISO3 → yearly points. Each indicator is one bulk download for every country.
    private(set) var panels: [String: [String: [WorldBank.Point]]] = [:]
    private(set) var failedIndicators: Set<String> = []
    private(set) var worldError: String?
    @ObservationIgnored private var loadingWorld = false

    private static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "worldbank", directoryHint: .isDirectory)

    /// Disk cache for 24 hours: the World Bank's origin is slow at times; its data changes rarely.
    private static func fetch(_ url: URL, cacheKey: String) async throws -> Data {
        let file = cacheDir.appending(path: cacheKey)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 86_400,
           let d = try? Data(contentsOf: file) { return d }
        var lastError: Error = URLError(.unknown)
        for _ in 0..<2 {
            do {
                let (d, r) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 25))
                guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try? d.write(to: file, options: .atomic)
                return d
            } catch { lastError = error; if Task.isCancelled { break } }
        }
        // Stale beats nothing.
        if let d = try? Data(contentsOf: file) { return d }
        throw lastError
    }

    func loadCountries() async {
        guard countries.isEmpty else { return }
        do { countries = try WorldBank.decodeCountries(await Self.fetch(WorldBank.countriesURL, cacheKey: "countries.json")); worldError = nil }
        catch { worldError = "Couldn't reach the World Bank: \(error.localizedDescription)" }
    }

    /// Every headline indicator, three downloads at a time, the requested one first.
    func loadWorld(first: String? = nil) async {
        guard !loadingWorld else { return }
        loadingWorld = true
        defer { loadingWorld = false }
        let to = Calendar(identifier: .gregorian).component(.year, from: .now), from = to - 15
        var queue = WorldBank.indicators.map(\.id).filter { panels[$0] == nil }
        if let first, let i = queue.firstIndex(of: first) { queue.swapAt(0, i) }
        failedIndicators = []
        await withTaskGroup(of: (String, [String: [WorldBank.Point]]?).self) { g in
            var it = queue.makeIterator()
            func next() -> Bool {
                guard let id = it.next() else { return false }
                g.addTask {
                    // Bulk ZIP first (static, full history); the query API as a fallback.
                    if let z = try? await Self.fetch(WorldBank.bulkURL(indicator: id), cacheKey: "\(id).zip"),
                       let p = try? WorldBank.decodeBulk(z), !p.isEmpty { return (id, p) }
                    let d = try? await Self.fetch(WorldBank.panelURL(indicator: id, from: from, to: to), cacheKey: "\(id)-\(from).json")
                    return (id, d.flatMap { try? WorldBank.decodePanel($0) })
                }
                return true
            }
            for _ in 0..<3 { _ = next() }
            for await (id, panel) in g {
                if let panel { panels[id] = panel } else { failedIndicators.insert(id) }
                _ = next()
            }
        }
        worldError = panels.isEmpty ? "The World Bank isn't responding. Try again in a minute." : nil
    }

    func profile(_ iso: String) -> [String: [WorldBank.Point]] { panels.compactMapValues { $0[iso] } }
    func ranking(_ indicator: String) -> [String: WorldBank.Point]? { panels[indicator].map(WorldBank.latest) }
}
