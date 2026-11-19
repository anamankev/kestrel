import Foundation
import KestrelCore

/// SEC EDGAR fundamentals. SEC requires a declared contact in the User-Agent, which the user
/// enters once in PREF; nothing is requested until then.
@Observable final class FundamentalsService {
    enum State: Equatable { case needsContact, loading, ready(CompanyFundamentals), notFound, failed(String) }

    private(set) var states: [String: State] = [:]

    var contact: String = UserDefaults.standard.string(forKey: "secContact") ?? "" {
        didSet {
            UserDefaults.standard.set(contact, forKey: "secContact")
            states = states.filter { if case .ready = $0.value { true } else { false } } // retry the rest
        }
    }
    var hasValidContact: Bool { SECFacts.isValidContact(contact) }

    @ObservationIgnored private var tickers: [String: Int]?
    @ObservationIgnored private var inFlight: Set<String> = []

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(SECFacts.userAgent(contact: contact), forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw URLError(code == 404 ? .fileDoesNotExist : .badServerResponse) }
        return data
    }

    func state(for i: Instrument) -> State {
        guard i.assetClass == .equity else { return .notFound }
        guard hasValidContact else { return .needsContact }
        return states[i.symbol] ?? .loading
    }

    func load(_ i: Instrument) async {
        guard i.assetClass == .equity, hasValidContact, !inFlight.contains(i.symbol) else { return }
        if case .ready = states[i.symbol] { return }
        inFlight.insert(i.symbol)
        defer { inFlight.remove(i.symbol) }
        states[i.symbol] = .loading
        do {
            if tickers == nil { tickers = try SECFacts.decodeTickers(await get(SECFacts.tickersURL)) }
            guard let cik = tickers?[i.ticker] else { states[i.symbol] = .notFound; return }
            let raw = try await get(SECFacts.factsURL(cik: cik))
            // Company-facts JSON is 3–8 MB (70–110 ms to decode): keep it off the main thread.
            let facts = try await Task.detached(priority: .userInitiated) { try SECFacts.decode(raw) }.value
            states[i.symbol] = facts.years.isEmpty ? .notFound : .ready(facts)
        } catch {
            states[i.symbol] = .failed(error.localizedDescription)
        }
    }

    // MARK: Filings (EVTS)

    private(set) var filings: [String: Result<[Filing], FilingError>] = [:]
    enum FilingError: Error, Equatable { case notFound, failed(String) }
    /// Every earnings release (8-K item 2.02) in SEC's recent filings, oldest first (for EVST).
    private(set) var releases: [String: [Date]] = [:]

    func loadFilings(_ i: Instrument) async {
        guard i.assetClass == .equity, hasValidContact, filings[i.symbol] == nil else { return }
        do {
            if tickers == nil { tickers = try SECFacts.decodeTickers(await get(SECFacts.tickersURL)) }
            guard let cik = tickers?[i.ticker] else { filings[i.symbol] = .failure(.notFound); return }
            let raw = try await get(SECFilings.url(cik: cik))
            filings[i.symbol] = .success(try SECFilings.decode(raw))
            releases[i.symbol] = (try? SECFilings.earningsReleases(raw)) ?? []
        } catch {
            filings[i.symbol] = .failure(.failed(error.localizedDescription))
        }
    }

    // MARK: Screener (EQS)

    enum ScreenState: Equatable { case idle, loading, ready(rows: [ScreenRow], year: Int), failed(String) }
    private(set) var screen: ScreenState = .idle

    /// Last fiscal-calendar year of revenue, earnings and balance sheets for every SEC filer:
    /// seven XBRL frame files (~4 MB), joined onto SEC's ticker list.
    func loadScreen() async {
        guard hasValidContact else { return }
        switch screen { case .loading, .ready: return; default: break }
        screen = .loading
        let thisYear = Calendar(identifier: .gregorian).component(.year, from: .now)
        for year in [thisYear - 1, thisYear - 2] {
            do {
                async let t = get(SECFacts.tickersURL)
                async let rev = get(SECFrames.url(concept: "Revenues", period: .year(year)))
                async let asc = get(SECFrames.url(concept: "RevenueFromContractWithCustomerExcludingAssessedTax", period: .year(year)))
                async let ni = get(SECFrames.url(concept: "NetIncomeLoss", period: .year(year)))
                async let at = get(SECFrames.url(concept: "Assets", period: .yearEnd(year)))
                async let lt = get(SECFrames.url(concept: "Liabilities", period: .yearEnd(year)))
                async let eq = get(SECFrames.url(concept: "StockholdersEquity", period: .yearEnd(year)))
                let raw = try await (t, rev, asc, ni, at, lt, eq)
                // Fallbacks, fetched after the first batch to stay well under SEC's 10 requests/second.
                async let pl = get(SECFrames.url(concept: "ProfitLoss", period: .year(year)))
                async let nci = get(SECFrames.url(concept: "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest", period: .yearEnd(year)))
                async let lse = get(SECFrames.url(concept: "LiabilitiesAndStockholdersEquity", period: .yearEnd(year)))
                let extra = try await (pl, nci, lse)
                let rows = try await Task.detached(priority: .userInitiated) {
                    try SECFrames.rows(listings: SECFrames.listings(raw.0), revenues: SECFrames.decode(raw.1),
                                       contractRevenues: SECFrames.decode(raw.2), netIncome: SECFrames.decode(raw.3),
                                       assets: SECFrames.decode(raw.4), liabilities: SECFrames.decode(raw.5), equity: SECFrames.decode(raw.6),
                                       profitLoss: SECFrames.decode(extra.0), equityWithNCI: SECFrames.decode(extra.1),
                                       liabilitiesAndEquity: SECFrames.decode(extra.2))
                }.value
                if rows.count >= 500 { screen = .ready(rows: rows, year: year); return }
            } catch let e as URLError where e.code == .fileDoesNotExist {
                continue   // that year's frames aren't published yet
            } catch {
                screen = .failed(error.localizedDescription); return
            }
        }
        screen = .failed("SEC has no complete annual frames yet")
    }

    // MARK: Relative valuation (RV)

    struct RVData: Equatable {
        var sic: String, industry: String, widened: Bool, filers: Int, year: Int
        var target: ScreenRow, peers: [ScreenRow]
        var shares: [Int: Double], priorRevenue: [Int: Double]
    }
    enum RVState: Equatable { case loading, ready(RVData), notFound, noData(Int?), failed(String) }
    private(set) var rv: [String: RVState] = [:]
    @ObservationIgnored private var industryMembers: [String: [RelativeValuation.Member]] = [:]
    @ObservationIgnored private var sharesOutstanding: [Int: Double]?
    @ObservationIgnored private var revenueByYear: [Int: [Int: Double]] = [:]

    /// Every 10-K filer under one SIC code (EDGAR pages 100 at a time).
    private func members(sic: String) async throws -> [RelativeValuation.Member] {
        if let m = industryMembers[sic] { return m }
        var out: [RelativeValuation.Member] = []
        for start in stride(from: 0, through: 2000, by: 100) {
            let page = RelativeValuation.decodeIndustry(try await get(RelativeValuation.industryURL(sic: sic, start: start)))
            out += page
            if page.count < 100 { break }
        }
        industryMembers[sic] = out
        return out
    }

    func loadRV(_ i: Instrument) async {
        guard i.assetClass == .equity, hasValidContact, rv[i.symbol] == nil else { return }
        rv[i.symbol] = .loading
        do {
            if tickers == nil { tickers = try SECFacts.decodeTickers(await get(SECFacts.tickersURL)) }
            guard let cik = tickers?[i.ticker] else { rv[i.symbol] = .notFound; return }
            await loadScreen()
            while case .loading = screen { try await Task.sleep(for: .milliseconds(300)) }   // another panel is loading it
            guard case .ready(let rows, let year) = screen else { rv[i.symbol] = .failed("SEC annual data is unavailable"); return }
            guard let target = rows.first(where: { $0.cik == cik }) else { rv[i.symbol] = .noData(year); return }
            guard let ind = RelativeValuation.industry(fromSubmissions: try await get(SECFilings.url(cik: cik))) else { rv[i.symbol] = .noData(year); return }
            var list = try await members(sic: ind.sic)
            var peers = RelativeValuation.pickPeers(target: target, rows: rows, members: Set(list.map(\.cik)))
            var widened = false
            // Exact codes can be narrow (HP files under 3570, Apple and Dell under 3571): widen to the 3-digit group.
            if peers.count < 5, ind.sic.count == 4 {
                for k in 0..<10 { list += (try? await members(sic: "\(ind.sic.prefix(3))\(k)")) ?? [] }
                peers = RelativeValuation.pickPeers(target: target, rows: rows, members: Set(list.map(\.cik)))
                widened = true
            }
            if sharesOutstanding == nil {
                var m: [Int: Double] = [:]
                for q in RelativeValuation.recentQuarters().reversed() {   // oldest first, so the newest wins
                    if let d = try? await get(RelativeValuation.sharesURL(quarter: q)), let f = try? SECFrames.decode(d) { m.merge(f) { _, new in new } }
                }
                sharesOutstanding = m
            }
            if revenueByYear[year - 1] == nil {
                var m = (try? SECFrames.decode(await get(SECFrames.url(concept: "Revenues", period: .year(year - 1))))) ?? [:]
                let asc = (try? SECFrames.decode(await get(SECFrames.url(concept: "RevenueFromContractWithCustomerExcludingAssessedTax", period: .year(year - 1))))) ?? [:]
                m.merge(asc) { have, _ in have }
                revenueByYear[year - 1] = m
            }
            rv[i.symbol] = .ready(RVData(sic: ind.sic, industry: ind.name, widened: widened, filers: Set(list.map(\.cik)).count, year: year,
                                         target: target, peers: peers, shares: sharesOutstanding ?? [:], priorRevenue: revenueByYear[year - 1] ?? [:]))
        } catch {
            rv[i.symbol] = .failed(error.localizedDescription)
        }
    }

    func fundamentals(_ symbol: String) -> CompanyFundamentals? {
        if case .ready(let f) = states[symbol] { f } else { nil }
    }
}
