import Foundation
import KestrelCore

/// Reads and writes one account's files, sealed with its data key.
/// - Legacy plaintext files still load, and are rewritten sealed (`needsMigration`).
/// - A sealed file that won't open (wrong key, corruption, tampering) is reported and
///   never overwritten, so a bad key can't silently replace real data with defaults.
final class SecureStore: @unchecked Sendable {
    let key: Data?
    private var unreadable = Set<URL>()
    private(set) var needsMigration = false

    init(key: Data?) { self.key = key }

    func read(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard Vault.isSealed(data) else {
            if key != nil { needsMigration = true }
            return data
        }
        guard let key, let plain = try? Vault.open(data, key: key) else {
            unreadable.insert(url)
            securityLog.error("sealed file could not be opened: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return plain
    }

    func write(_ data: Data, to url: URL) {
        guard !unreadable.contains(url) else { return }
        let out: Data
        if let key {
            guard let sealed = try? Vault.seal(data, key: key) else { return }
            out = sealed
        } else {
            out = data
        }
        try? out.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
