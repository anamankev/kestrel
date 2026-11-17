import Foundation
import Testing
import KestrelCore
@testable import Kestrel

/// App-layer tests: workspace routing, persistence and formatting. Each test uses its own
/// storage so the real app data on this machine is never touched.
@MainActor
@Suite struct WorkspaceTests {
    @Test func runsCommandsInFocusedPanel() {
        let ws = Workspace(saved: "W|TOP|WEI|ECO|PORT|BLOT", layout: "4")
        ws.focused = 1
        #expect(ws.run("AAPL GP"))
        #expect(ws.panels[1].command.function == .gp && ws.panels[1].command.instrument?.ticker == "AAPL")
        #expect(ws.panels[1].history.last?.function == .top)
        ws.back(1)
        #expect(ws.panels[1].command.function == .top)
        #expect(!ws.run("$$$ GP") && ws.error != nil)
    }

    @Test func numberedHotspotsDrillIn() {
        let ws = Workspace(saved: "W|BTC CRYPTO GP|TOP|WEI|ECO|PORT", layout: "2")
        let eth = Universe.resolve("ETH")!
        ws.hotspots[0] = [.link(Universe.resolve("BTC")!), .link(eth)]
        ws.focused = 0
        #expect(ws.run("2 <GO>"))
        #expect(ws.panels[1].command.instrument == eth)      // linked into the chart panel
        #expect(!ws.run("9") && ws.error == "No item 9 on this screen")
    }

    @Test func persistsThroughCallbackAndRestores() {
        var stored = ("", "")
        let ws = Workspace(saved: "W|TOP|WEI|ECO|PORT|BLOT", layout: "4")
        ws.persist = { stored = ($0, $1) }
        ws.focused = 2
        ws.run("NVDA DES")
        #expect(stored.0.components(separatedBy: "|")[2] == "NVDA EQUITY DES")
        let restored = Workspace(saved: stored.0, layout: stored.1)
        #expect(restored.panels[2].command.instrument?.ticker == "NVDA" && restored.layout == .four)
    }

    @Test func pagesSaveAndOpen() {
        let name = "TEST-\(UUID().uuidString.prefix(6))"
        defer { Workspace.deletePage(name.uppercased()) }
        let ws = Workspace(saved: "BTC CRYPTO GP|W|TOP|WEI|ECO|PORT", layout: "6")
        ws.savePage(name)
        let other = Workspace(saved: "W|W|W|W|W|W", layout: "1")
        let page = Workspace.pages.first { $0.name == name.uppercased() }!
        other.open(page)
        #expect(other.layout == .six && other.panels[0].command.function == .gp)
    }
}

@MainActor
@Suite struct UserDataTests {
    func tempURL() -> URL { FileManager.default.temporaryDirectory.appending(path: "kestrel-test-\(UUID().uuidString).json") }

    /// Regression: an @Observable didSet once fired inside init and saved a half-loaded state,
    /// wiping every alert on launch.
    @Test func loadingNeverRewritesOrLosesAlerts() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = UserData(url: url)
        try first.addAlert(Universe.resolve("BTC")!, .above(1_000_000), last: 65_000)
        let before = try Data(contentsOf: url)
        let second = UserData(url: url)
        #expect(second.alerts.active.count == 1)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func watchlistEditing() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let u = UserData(url: url)
        u.newList("Semis")
        #expect(u.active.name == "SEMIS")
        #expect(u.add("nvda") == nil && u.add("NVDA") != nil)   // duplicate rejected
        #expect(u.add("$$$")?.hasPrefix("Unknown") == true)
        #expect(UserData(url: url).active.symbols == ["NVDA"])   // persisted
    }
}

@Suite struct FormatTests {
    @Test func priceAndPercentFormatting() {
        #expect(Fmt.price(1234.5) == "1,234.50")
        #expect(Fmt.price(0.0123) == "0.0123")
        #expect(Fmt.price(1.08766, .fx) == "1.0877")   // 1.08765 is 1.087649999… in binary
        #expect(Fmt.pct(1.234) == "+1.23%" && Fmt.pct(-0.5) == "-0.50%")
        #expect(Fmt.compact(1_250_000) == "1.25M" && Fmt.compact(nil) == "—")
    }
}

@MainActor @Suite struct AuthServiceTests {
    func fresh() -> (URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appending(path: "kestrel-auth-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "kestrel-tests-\(UUID().uuidString)"
        return (root, UserDefaults(suiteName: suite)!)
    }

    @Test func firstAccountAdoptsExistingPaperBookAndSessionPersists() async throws {
        let (root, defaults) = fresh()
        try Data("legacy".utf8).write(to: root.appending(path: "paper-account.json"))
        let auth = AuthService(root: root, defaults: defaults)
        try await auth.register(name: "Ada Lovelace", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine")
        let me = try #require(auth.current)
        #expect(FileManager.default.fileExists(atPath: auth.folder(for: me.id).appending(path: "paper-account.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "paper-account.json").path))
        // Relaunch: still signed in.
        #expect(AuthService(root: root, defaults: defaults).current?.id == me.id)
    }

    @Test func signOutSignInAndDeleteNeedsPassword() async throws {
        let (root, defaults) = fresh()
        let auth = AuthService(root: root, defaults: defaults)
        try await auth.register(name: "Grace Hopper", email: "grace@example.com", password: "nanoseconds wire", confirm: "nanoseconds wire")
        auth.signOut()
        #expect(auth.current == nil && auth.space == nil)
        #expect(AuthService(root: root, defaults: defaults).current == nil)
        try await auth.signIn(email: "GRACE@example.com", password: "nanoseconds wire")
        #expect(auth.space != nil)
        await #expect(throws: AuthError.invalidCredentials) { try await auth.deleteAccount(password: "wrong") }
        #expect(auth.current != nil)
        try await auth.deleteAccount(password: "nanoseconds wire")
        #expect(auth.current == nil && auth.directory.accounts.isEmpty)
    }
}
