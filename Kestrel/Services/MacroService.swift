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
}
