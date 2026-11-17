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

    func fundamentals(_ symbol: String) -> CompanyFundamentals? {
        if case .ready(let f) = states[symbol] { f } else { nil }
    }
}
