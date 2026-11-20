import Foundation
import KestrelCore
import Security
import os

let securityLog = Logger(subsystem: "dev.kestrel.terminal", category: "security")

/// Where the session token lives between launches.
protocol SessionStore {
    func load() -> (id: UUID, token: Data, key: Data?)?
    func save(id: UUID, token: Data, key: Data)
    func clear()
}

/// The system Keychain: device-only, readable after first unlock, never synced or backed up.
struct KeychainSessionStore: SessionStore {
    var service = "dev.kestrel.terminal.session"
    private var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current"]
        #if os(macOS)
        // The data-protection keychain (what iOS always uses): items belong to the app, not to one build's code
        // signature, so a rebuilt or updated app never asks for the login-keychain password, and the read can't
        // block the main thread on a prompt. Sessions saved by older builds in the login keychain aren't read:
        // those people sign in once.
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    /// The store to use. A Mac build without a signing team (a local development build) has no access to the
    /// data-protection keychain (errSecMissingEntitlement), so its session lives in memory: sign in at each
    /// launch, with no password prompt and nothing written to the login keychain.
    #if os(macOS)
    /// Reads of a missing item report "not found" either way; only a write reveals errSecMissingEntitlement.
    private static let dataProtectionAvailable: Bool = {
        let probe = KeychainSessionStore(service: "dev.kestrel.terminal.probe")
        probe.clear()
        var q = probe.query
        q[kSecValueData as String] = Data([0])
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        probe.clear()
        return status != errSecMissingEntitlement
    }()
    #endif

    static func preferred() -> SessionStore {
        #if os(macOS)
        if !dataProtectionAvailable {
            securityLog.notice("unsigned build: sessions kept in memory")
            return MemorySessionStore()
        }
        return KeychainSessionStore()
        #else
        return KeychainSessionStore()
        #endif
    }

    func load() -> (id: UUID, token: Data, key: Data?)? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        // Layout: account id (16) · session token (32) · data key (32). Older items lack the key.
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data, data.count == 48 || data.count == 80 else { return nil }
        let id = UUID(uuid: data.prefix(16).withUnsafeBytes { $0.loadUnaligned(as: uuid_t.self) })
        let token = Data(data.dropFirst(16).prefix(32))
        return (id, token, data.count == 80 ? Data(data.suffix(32)) : nil)
    }

    func save(id: UUID, token: Data, key: Data) {
        clear()
        var raw = id.uuid
        var q = query
        q[kSecValueData as String] = Data(bytes: &raw, count: 16) + token + key
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess { securityLog.error("keychain save failed: \(status, privacy: .public)") }
    }

    func clear() { SecItemDelete(query as CFDictionary) }
}

/// Tests and the snapshot tour: never touches the real Keychain.
final class MemorySessionStore: SessionStore {
    private var value: (UUID, Data, Data?)?
    func load() -> (id: UUID, token: Data, key: Data?)? { value.map { ($0.0, $0.1, $0.2) } }
    func save(id: UUID, token: Data, key: Data) { value = (id, token, key) }
    /// Tests: plant an arbitrary (possibly forged) session.
    func plant(id: UUID, token: Data, key: Data?) { value = (id, token, key) }
    func clear() { value = nil }
}

/// Accounts on this device. Hashing runs off the main thread (600k PBKDF2 rounds take a few
/// hundred milliseconds by design), and each account's data lives in its own folder.
@MainActor @Observable final class AuthService {
    private(set) var directory: AccountDirectory
    private(set) var current: AccountRecord?
    private(set) var busy = false
    /// The signed-in person's stores, shared by every window.
    private(set) var space: UserSpace?

    static let root = URL.applicationSupportDirectory.appending(path: "Kestrel", directoryHint: .isDirectory)
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let sessions: SessionStore
    /// Files from before accounts existed; the first account on the device adopts them.
    private static let legacyFiles = ["paper-account.json", "equity-curve.json", "user-data.json"]

    init(root: URL = AuthService.root, sessions: SessionStore = KeychainSessionStore.preferred()) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appending(path: "accounts.json")
        self.sessions = sessions
        var dir = (try? JSONDecoder().decode(AccountDirectory.self, from: Data(contentsOf: fileURL))) ?? AccountDirectory()
        self.root = root
        // Older builds kept a bare account ID in UserDefaults; it proves nothing, so drop it.
        UserDefaults.standard.removeObject(forKey: "auth.session")
        var resumedKey: Data?
        if let stored = sessions.load() {
            // A session without the data key predates encryption: sign in once to migrate.
            if let key = stored.key, dir.account(id: stored.id)?.hasDataKey == true,
               let r = dir.resumeSession(id: stored.id, token: stored.token) {
                current = r
                resumedKey = key
            } else {
                securityLog.notice("stored session rejected (expired, revoked or tampered)")
                sessions.clear()
            }
        }
        directory = dir
        if current != nil { save() }   // persist the slid expiry
        if let r = current, let key = resumedKey { space = UserSpace(id: r.id, folder: folder(for: r.id), key: key) }
    }
    @ObservationIgnored private let root: URL

    func folder(for id: UUID) -> URL { root.appending(path: "users/\(id.uuidString)", directoryHint: .isDirectory) }

    func signIn(email: String, password: String) async throws(AuthError) {
        do {
            let (r, key) = try await run { d throws(AuthError) in
                let r = try d.signIn(email: email, password: password)
                return (r, try d.unlockDataKey(id: r.id, password: password))
            }
            begin(r, key: key)
        } catch {
            switch error {
            case .locked: securityLog.warning("account locked after repeated failures: \(Credentials.normalize(email), privacy: .private(mask: .hash))")
            default: securityLog.notice("failed sign-in: \(Credentials.normalize(email), privacy: .private(mask: .hash))")
            }
            throw error
        }
    }

    func register(name: String, email: String, password: String, confirm: String) async throws(AuthError) {
        let first = directory.accounts.isEmpty
        let (r, key) = try await run { d throws(AuthError) in
            let r = try d.register(name: name, email: email, password: password, confirm: confirm)
            return (r, try d.unlockDataKey(id: r.id, password: password))
        }
        if first { adoptLegacyData(into: folder(for: r.id)) }
        begin(r, key: key)
    }

    func signOut() {
        if let me = current {
            directory.endSession(id: me.id)   // the token stops working even if a copy survives
            save()
            securityLog.info("signed out")
        }
        current = nil
        space = nil
        sessions.clear()
    }

    /// Deleting needs the password again, so a borrowed, unlocked device can't wipe an account.
    func deleteAccount(password: String) async throws(AuthError) {
        guard let me = current else { return }
        _ = try await run { d throws(AuthError) in try d.signIn(email: me.email, password: password) }
        directory.remove(id: me.id)
        save()
        securityLog.info("account deleted")
        try? FileManager.default.removeItem(at: folder(for: me.id))
        signOut()
    }

    // MARK: -

    /// Runs a directory operation off the main actor and commits its result (including failed-attempt counts).
    private func run<T: Sendable>(_ op: @escaping @Sendable (inout AccountDirectory) throws(AuthError) -> T) async throws(AuthError) -> T {
        guard !busy else { throw .invalidCredentials }
        busy = true
        defer { busy = false }
        let snapshot = directory
        let (updated, result) = await Task.detached(priority: .userInitiated) { () -> (AccountDirectory, Result<T, AuthError>) in
            var d = snapshot
            do throws(AuthError) { let r = try op(&d); return (d, .success(r)) } catch { return (d, .failure(error)) }
        }.value
        directory = updated
        save()
        return try result.get()
    }

    private func begin(_ r: AccountRecord, key: Data) {
        let token = AccountDirectory.newSessionToken()
        directory.beginSession(id: r.id, token: token)
        save()
        sessions.save(id: r.id, token: token, key: key)
        current = directory.account(id: r.id) ?? r
        space = UserSpace(id: r.id, folder: folder(for: r.id), key: key)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(directory) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func adoptLegacyData(into dir: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in Self.legacyFiles where fm.fileExists(atPath: root.appending(path: name).path) {
            try? fm.moveItem(at: root.appending(path: name), to: dir.appending(path: name))
        }
    }
}

/// One signed-in person's stores.
@MainActor final class UserSpace {
    let id: UUID
    let broker: PaperBroker
    let data: UserData

    init(id: UUID, folder: URL, key: Data?) {
        self.id = id
        let store = SecureStore(key: key)
        broker = PaperBroker(dir: folder, store: store)
        data = UserData(url: folder.appending(path: "user-data.json"), store: store)
        // Files written before encryption are re-saved sealed, once, after a clean load.
        if store.needsMigration {
            broker.persistAll()
            data.save()
            securityLog.info("encrypted legacy account files")
        }
    }
}
