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
            let facts = try SECFacts.decode(await get(SECFacts.factsURL(cik: cik)))
            states[i.symbol] = facts.years.isEmpty ? .notFound : .ready(facts)
        } catch {
            states[i.symbol] = .failed(error.localizedDescription)
        }
    }

    func fundamentals(_ symbol: String) -> CompanyFundamentals? {
        if case .ready(let f) = states[symbol] { f } else { nil }
    }
}
