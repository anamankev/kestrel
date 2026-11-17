import Foundation
import KestrelCore

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
    @ObservationIgnored private let defaults: UserDefaults
    private static let sessionKey = "auth.session"
    /// Files from before accounts existed; the first account on the device adopts them.
    private static let legacyFiles = ["paper-account.json", "equity-curve.json", "user-data.json"]

    init(root: URL = AuthService.root, defaults: UserDefaults = .standard) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appending(path: "accounts.json")
        self.defaults = defaults
        let dir = (try? JSONDecoder().decode(AccountDirectory.self, from: Data(contentsOf: fileURL))) ?? AccountDirectory()
        directory = dir
        self.root = root
        if let id = defaults.string(forKey: Self.sessionKey).flatMap(UUID.init), let r = dir.account(id: id) {
            current = r
        }
        if let r = current { space = UserSpace(id: r.id, folder: folder(for: r.id)) }
    }
    @ObservationIgnored private let root: URL

    func folder(for id: UUID) -> URL { root.appending(path: "users/\(id.uuidString)", directoryHint: .isDirectory) }

    func signIn(email: String, password: String) async throws(AuthError) {
        let r = try await run { d throws(AuthError) in try d.signIn(email: email, password: password) }
        begin(r)
    }

    func register(name: String, email: String, password: String, confirm: String) async throws(AuthError) {
        let first = directory.accounts.isEmpty
        let r = try await run { d throws(AuthError) in try d.register(name: name, email: email, password: password, confirm: confirm) }
        if first { adoptLegacyData(into: folder(for: r.id)) }
        begin(r)
    }

    func signOut() {
        current = nil
        space = nil
        defaults.removeObject(forKey: Self.sessionKey)
    }

    /// Deleting needs the password again, so a borrowed, unlocked device can't wipe an account.
    func deleteAccount(password: String) async throws(AuthError) {
        guard let me = current else { return }
        _ = try await run { d throws(AuthError) in try d.signIn(email: me.email, password: password) }
        directory.remove(id: me.id)
        save()
        try? FileManager.default.removeItem(at: folder(for: me.id))
        signOut()
    }

    // MARK: -

    /// Runs a directory operation off the main actor and commits its result (including failed-attempt counts).
    private func run(_ op: @escaping @Sendable (inout AccountDirectory) throws(AuthError) -> AccountRecord) async throws(AuthError) -> AccountRecord {
        guard !busy else { throw .invalidCredentials }
        busy = true
        defer { busy = false }
        let snapshot = directory
        let (updated, result) = await Task.detached(priority: .userInitiated) { () -> (AccountDirectory, Result<AccountRecord, AuthError>) in
            var d = snapshot
            do throws(AuthError) { let r = try op(&d); return (d, .success(r)) } catch { return (d, .failure(error)) }
        }.value
        directory = updated
        save()
        return try result.get()
    }

    private func begin(_ r: AccountRecord) {
        current = r
        space = UserSpace(id: r.id, folder: folder(for: r.id))
        defaults.set(r.id.uuidString, forKey: Self.sessionKey)
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

    init(id: UUID, folder: URL) {
        self.id = id
        broker = PaperBroker(dir: folder)
        data = UserData(url: folder.appending(path: "user-data.json"))
    }
}
