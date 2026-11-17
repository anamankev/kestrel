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

@Suite struct LaunchScreenTests {
    @Test func subscriptionComesFirstAndNeedsNoAccount() {
        #expect(LaunchScreen.decide(checked: false, subscribed: true, signedIn: true) == .checking)    // never flash the paywall
        #expect(LaunchScreen.decide(checked: true, subscribed: false, signedIn: false) == .subscribe)  // buy without registering
        #expect(LaunchScreen.decide(checked: true, subscribed: false, signedIn: true) == .subscribe)   // lapsed: data kept, gate shown
        #expect(LaunchScreen.decide(checked: true, subscribed: true, signedIn: false) == .signIn)
        #expect(LaunchScreen.decide(checked: true, subscribed: true, signedIn: true) == .terminal)
    }
}

@MainActor @Suite struct AuthServiceTests {
    func fresh() -> (URL, MemorySessionStore) {
        let root = FileManager.default.temporaryDirectory.appending(path: "kestrel-auth-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, MemorySessionStore())
    }

    @Test func firstAccountAdoptsExistingPaperBookAndSessionPersists() async throws {
        let (root, defaults) = fresh()
        try Data("legacy".utf8).write(to: root.appending(path: "paper-account.json"))
        let auth = AuthService(root: root, sessions: defaults)
        try await auth.register(name: "Ada Lovelace", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine")
        let me = try #require(auth.current)
        #expect(FileManager.default.fileExists(atPath: auth.folder(for: me.id).appending(path: "paper-account.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "paper-account.json").path))
        // Relaunch: still signed in.
        #expect(AuthService(root: root, sessions: defaults).current?.id == me.id)
    }

    @Test func signOutSignInAndDeleteNeedsPassword() async throws {
        let (root, defaults) = fresh()
        let auth = AuthService(root: root, sessions: defaults)
        try await auth.register(name: "Grace Hopper", email: "grace@example.com", password: "nanoseconds wire", confirm: "nanoseconds wire")
        auth.signOut()
        #expect(auth.current == nil && auth.space == nil)
        #expect(AuthService(root: root, sessions: defaults).current == nil)
        try await auth.signIn(email: "GRACE@example.com", password: "nanoseconds wire")
        #expect(auth.space != nil)
        await #expect(throws: AuthError.invalidCredentials) { try await auth.deleteAccount(password: "wrong") }
        #expect(auth.current != nil)
        try await auth.deleteAccount(password: "nanoseconds wire")
        #expect(auth.current == nil && auth.directory.accounts.isEmpty)
    }
}


@MainActor @Suite struct SessionHardeningTests {
    @Test func signOutRevokesACopiedToken() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kestrel-auth-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MemorySessionStore()
        let auth = AuthService(root: root, sessions: store)
        try await auth.register(name: "Ada Lovelace", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine")
        let stolen = try #require(store.load())
        auth.signOut()
        // Replaying the old token (e.g. restored from a backup) must not sign anyone in.
        let replay = MemorySessionStore(); replay.plant(id: stolen.id, token: stolen.token, key: stolen.key)
        #expect(AuthService(root: root, sessions: replay).current == nil)
        #expect(replay.load() == nil)   // and the rejected token is wiped
    }

    @Test func editingTheAccountIdDoesNotSwitchAccounts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "kestrel-auth-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = MemorySessionStore()
        let auth = AuthService(root: root, sessions: store)
        try await auth.register(name: "Ada Lovelace", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine")
        auth.signOut()
        try await auth.register(name: "Grace Hopper", email: "grace@example.com", password: "nanoseconds wire", confirm: "nanoseconds wire")
        let mine = try #require(store.load())
        let ada = try #require(auth.directory.accounts.first { $0.email == "ada@example.com" })
        let forged = MemorySessionStore(); forged.plant(id: ada.id, token: mine.token, key: mine.key)   // Grace's token, Ada's id
        #expect(AuthService(root: root, sessions: forged).current == nil)
    }

    @Test func keychainRoundTrip() {
        let kc = KeychainSessionStore(service: "dev.kestrel.terminal.tests.\(UUID().uuidString)")
        let id = UUID(), token = AccountDirectory.newSessionToken(), key = Vault.newKey()
        kc.save(id: id, token: token, key: key)
        defer { kc.clear() }
        // The session must really round-trip through the Keychain (verified on iPad and Mac).
        let got = kc.load()
        #expect(got?.id == id && got?.token == token && got?.key == key)
        kc.clear()
        #expect(kc.load() == nil)
    }
}


@MainActor @Suite struct EncryptionAtRestTests {
    func root() -> URL { FileManager.default.temporaryDirectory.appending(path: "kestrel-enc-\(UUID().uuidString)", directoryHint: .isDirectory) }

    @Test func accountFilesAreSealedAndReopenAfterRelaunch() async throws {
        let r = root(), store = MemorySessionStore()
        let auth = AuthService(root: r, sessions: store)
        try await auth.register(name: "Ada Lovelace", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine")
        let me = try #require(auth.current)
        _ = auth.space?.data.add("NVDA")
        let file = auth.folder(for: me.id).appending(path: "user-data.json")
        let onDisk = try Data(contentsOf: file)
        #expect(Vault.isSealed(onDisk))
        #expect(onDisk.range(of: Data("NVDA".utf8)) == nil)                 // no plaintext on disk
        // Relaunch: the Keychain-held key opens it again.
        let again = AuthService(root: r, sessions: store)
        #expect(again.space?.data.active.symbols.contains("NVDA") == true)
    }

    @Test func legacyPlaintextIsEncryptedAtNextSignIn() async throws {
        let r = root(), store = MemorySessionStore()
        let auth = AuthService(root: r, sessions: store)
        try await auth.register(name: "Ada Lovelace", email: "ada@example.com", password: "analytical engine", confirm: "analytical engine")
        let me = try #require(auth.current)
        let file = auth.folder(for: me.id).appending(path: "paper-account.json")
        auth.signOut()
        // Simulate a pre-encryption file left on disk.
        try JSONEncoder().encode(PaperAccount(cash: 4_242)).write(to: file)
        try await auth.signIn(email: "ada@example.com", password: "analytical engine")
        #expect(auth.space?.broker.account.cash == 4_242)                     // data kept
        #expect(Vault.isSealed(try Data(contentsOf: file)))                    // and now sealed
    }

    @Test func wrongKeyNeverOverwritesData() throws {
        let dir = root(); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "user-data.json")
        let good = SecureStore(key: Vault.newKey())
        good.write(Data("{}".utf8), to: url)
        let before = try Data(contentsOf: url)
        let bad = SecureStore(key: Vault.newKey())
        #expect(bad.read(url) == nil)
        bad.write(Data("{\"wiped\":true}".utf8), to: url)
        #expect(try Data(contentsOf: url) == before)
    }
}

import StoreKitTest

/// Real StoreKit purchases against Config/Kestrel.storekit (Apple's local test store).
@MainActor @Suite(.serialized) struct SubscriptionStoreTests {
    func session() throws -> SKTestSession {
        let config = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Config/Kestrel.storekit")
        let s = try SKTestSession(contentsOf: config)
        s.resetToDefaultState()
        s.clearTransactions()
        s.disableDialogs = true
        return s
    }

    @Test func productsLoadWithThePrices() async throws {
        let s = try session(); defer { s.clearTransactions() }
        let store = SubscriptionStore()
        await store.loadProducts()
        #expect(store.products.map(\.id) == ProPlan.allCases.map(\.productID), "loaded \(store.products.count), error: \(store.loadError ?? "none")")
        #expect(store.products.map(\.price) == [Decimal(string: "9.99")!, Decimal(string: "49.99")!, Decimal(string: "99.99")!])
        #expect(store.products.allSatisfy { $0.type == .autoRenewable })
    }

    // Purchases need a window to present against; the macOS test host has none, so these
    // run on the iPad simulator (the shipped Mac app presents the sheet on its own window).
    #if os(iOS)
    @Test func eachPlanUnlocksPro() async throws {
        for plan in ProPlan.allCases {
            let s = try session(); defer { s.clearTransactions() }
            let store = SubscriptionStore()
            await store.loadProducts()
            #expect(!store.isPro)
            await store.purchase(plan, account: UUID())
            #expect(store.isPro, "\(store.message ?? "no message")")
            if case .pro(let got, let expires, _) = store.entitlement {
                #expect(got == plan && (expires ?? .distantPast) > .now)
            } else { Issue.record("expected Pro after buying \(plan)") }
        }
    }

    @Test func renewalKeepsProAndRefundRevokesIt() async throws {
        let s = try session(); defer { s.clearTransactions() }
        let store = SubscriptionStore()
        await store.loadProducts()
        await store.purchase(.monthly, account: nil)
        #expect(store.isPro)
        // Period ends with auto-renew on: StoreKit renews, so Pro must stay.
        try s.expireSubscription(productIdentifier: ProPlan.monthly.productID)
        try? await Task.sleep(for: .milliseconds(500))
        await store.refresh()
        #expect(store.isPro)
        // A lapse without renewal is covered by EntitlementTests (expired transactions are free).

        await store.purchase(.annual, account: nil)
        #expect(store.isPro)
        let tx = try #require(s.allTransactions().last { $0.productIdentifier == ProPlan.annual.productID })
        try s.refundTransaction(identifier: UInt(tx.identifier))
        #expect(await becomesFree(store))
    }

    /// StoreKit applies expiry and refunds asynchronously; the app picks them up from
    /// `Transaction.updates`. Wait the same way, up to 5 s.
    func becomesFree(_ store: SubscriptionStore) async -> Bool {
        for _ in 0..<50 {
            await store.refresh()
            if !store.isPro { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    @Test func restoreFindsAnExistingSubscription() async throws {
        let s = try session(); defer { s.clearTransactions() }
        _ = try await s.buyProduct(identifier: ProPlan.halfYear.productID)   // bought elsewhere
        let store = SubscriptionStore()
        await store.loadProducts()
        await store.refresh()
        #expect(store.entitlement.isPro)
    }
    #endif
}

#if os(macOS)
import AppKit
import SwiftUI

/// The Mac window once grew to 6,006 points wide because a panel's content demanded it.
@MainActor @Suite struct WindowSizingTests {
    func minimumWidth<V: View>(_ v: V) -> CGFloat {
        // Offered no space at all, a view reports the least it insists on: its minimum.
        NSHostingController(rootView: v).sizeThatFits(in: .zero).width
    }

    @Test func contentCannotStretchTheWindow() {
        let runaway = Text(String(repeating: "W", count: 2_000)).fixedSize()   // one unbreakable line
        #expect(minimumWidth(runaway) > 10_000)                                 // what used to stretch it
        #expect(minimumWidth(SizeIsolated { runaway }) < 10)                    // isolated: no demand
        let window = SizeIsolated { runaway }.frame(minWidth: 1100, minHeight: 700)
        #expect(abs(minimumWidth(window) - 1100) < 1)                           // only the explicit floor
    }

    @Test func oversizedSavedFramesAreFittedToTheScreen() throws {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 923)          // MacBook Air visible frame
        // The frame an old build saved: 6,006 points wide.
        let fixed = try #require(WindowFit.fitted(CGRect(x: 0, y: 45, width: 6006, height: 878), in: screen))
        #expect(fixed.width == 1470 && fixed.height == 878 && screen.contains(fixed))
        // Partly off the right edge: moved back on.
        let moved = try #require(WindowFit.fitted(CGRect(x: 900, y: 45, width: 1200, height: 800), in: screen))
        #expect(screen.contains(moved) && moved.width == 1200)
        // Already fine: untouched.
        #expect(WindowFit.fitted(CGRect(x: 0, y: 45, width: 1470, height: 878), in: screen) == nil)
    }
}
#endif
