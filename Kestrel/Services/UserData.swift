import Foundation
import KestrelCore
import UserNotifications

/// Watchlists and price alerts, persisted as JSON in the app container.
/// Alert hits raise an in-app toast and a local notification (so they reach you in the background).
@Observable final class UserData {
    private(set) var watchlists: [Watchlist]
    /// Change with `select(_:)`, which persists. (No `didSet`: under @Observable it also fires
    /// during `init`, which once saved a half-loaded state and wiped alerts on launch.)
    private(set) var activeID: UUID
    private(set) var alerts: AlertBook
    var lastAlert: PriceAlert?

    private struct Snapshot: Codable {
        var watchlists: [Watchlist]
        var activeID: UUID
        var alerts: AlertBook
    }

    @ObservationIgnored private let url: URL

    static let defaultURL: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Kestrel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "user-data.json")
    }()
    @ObservationIgnored private var askedForNotifications = false

    @ObservationIgnored private let store: SecureStore

    /// - Parameters: `url` is the storage location (tests pass a temporary file); `store` seals it.
    init(url: URL = UserData.defaultURL, store: SecureStore = SecureStore(key: nil)) {
        self.url = url
        self.store = store
        // Build the complete state in locals, then assign once: init must never write to disk.
        var lists = [Watchlist.core]
        var active = lists[0].id
        var book = AlertBook()
        if let data = store.read(url), let s = try? JSONDecoder().decode(Snapshot.self, from: data), !s.watchlists.isEmpty {
            lists = s.watchlists
            active = s.watchlists.contains { $0.id == s.activeID } ? s.activeID : s.watchlists[0].id
            book = s.alerts
        }
        watchlists = lists
        activeID = active
        alerts = book
    }

    func select(_ id: UUID) {
        guard watchlists.contains(where: { $0.id == id }) else { return }
        activeID = id
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(Snapshot(watchlists: watchlists, activeID: activeID, alerts: alerts)) else { return }
        store.write(data, to: url)
    }

    // MARK: Watchlists

    var active: Watchlist { watchlists.first { $0.id == activeID } ?? watchlists[0] }

    private func mutateActive(_ f: (inout Watchlist) -> Void) {
        guard let i = watchlists.firstIndex(where: { $0.id == activeID }) else { return }
        f(&watchlists[i])
        save()
    }

    /// Resolves a typed ticker and adds it to the active list. Returns an error message on failure.
    func add(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        guard t.count <= 12, let i = Universe.resolve(t) else { return "Unknown security: \(t.uppercased())" }
        var ok = false
        mutateActive { ok = $0.add(i.symbol) }
        return ok ? nil : (active.symbols.contains(i.symbol) ? "\(i.ticker) is already on \(active.name)" : "List is full (\(Watchlist.maxSymbols))")
    }

    func remove(_ symbol: String) { mutateActive { $0.remove(symbol) } }
    func move(_ symbol: String, by offset: Int) { mutateActive { $0.move(symbol, by: offset) } }
    func renameActive(_ name: String) { mutateActive { $0.rename(name) } }

    func newList(_ name: String) {
        guard watchlists.count < 20 else { return }
        let w = Watchlist(name: name)
        watchlists.append(w)
        activeID = w.id
        save()
    }

    func deleteActive() {
        guard watchlists.count > 1 else { return }
        watchlists.removeAll { $0.id == activeID }
        activeID = watchlists[0].id
        save()
    }

    /// Every symbol any list or alert needs quotes for.
    var watchedSymbols: Set<String> { Set(watchlists.flatMap(\.symbols)).union(alerts.watchedSymbols) }

    // MARK: Alerts

    func addAlert(_ i: Instrument, _ condition: AlertCondition, last: Double?) throws(AlertError) {
        try alerts.add(symbol: i.symbol, condition: condition, last: last)
        save()
        requestNotificationPermission()
    }

    func resetAlerts() { alerts = AlertBook(); save() }

    func resetWatchlists() {
        let core = Watchlist.core
        watchlists = [core]
        activeID = core.id
        save()
    }

    func cancelAlert(_ id: UUID) { alerts.cancel(id); save() }
    func clearAlertHistory() { alerts.clearHistory(); save() }

    /// Called with every fresh quote.
    /// Replaces watchlists and alerts with an imported (already validated) transfer.
    func replace(with b: TransferBundle) {
        watchlists = b.watchlists
        activeID = b.activeID
        alerts = b.alerts
        save()
    }

    func check(_ symbol: String, _ q: Quote) {
        guard alerts.watchedSymbols.contains(symbol) else { return }
        let fired = alerts.evaluate(symbol: symbol, last: q.last, changePercent: q.changePercent)
        guard !fired.isEmpty else { return }
        save()
        for a in fired { notify(a) }
        lastAlert = fired.last
    }

    private func requestNotificationPermission() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ a: PriceAlert) {
        let ticker = Universe.instrument(symbol: a.symbol)?.ticker ?? a.symbol
        let content = UNMutableNotificationContent()
        content.title = "\(ticker) alert"
        content.body = "\(a.condition.label) · last \(Fmt.price(a.triggerPrice))"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: a.id.uuidString, content: content, trigger: nil))
    }
}
