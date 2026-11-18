import Foundation
import CommonCrypto
import CryptoKit
import CArgon2

/// How a password becomes a key. New accounts and files use Argon2id, which is memory-hard: each guess needs
/// 64 MiB, so GPUs can't run thousands of guesses in parallel. PBKDF2 remains only to open older accounts
/// and transfer files; accounts upgrade at their next sign-in.
public enum KDF: Codable, Sendable, Equatable {
    case pbkdf2(iterations: Int)
    /// RFC 9106's second recommended option (64 MiB, 3 passes), with one lane so no threads are needed.
    case argon2id(memoryKiB: Int, passes: Int, lanes: Int)

    public static let standard = KDF.argon2id(memoryKiB: 65_536, passes: 3, lanes: 1)
    /// Cheap settings for tests only.
    public static let testing = KDF.argon2id(memoryKiB: 64, passes: 1, lanes: 1)

    /// Bounds for parameters read from a file, so a crafted one can't demand unbounded memory or time.
    public var isWithinImportLimits: Bool {
        switch self {
        case .pbkdf2(let n): (1_000...5_000_000).contains(n)
        case .argon2id(let m, let t, let p): (1...4).contains(p) && (8 * p...262_144).contains(m) && (1...10).contains(t)
        }
    }

    /// A 32-byte key from `password` and `salt`.
    public func derive(_ password: String, salt: Data) -> Data {
        switch self {
        case .pbkdf2(let n): return Credentials.derive(password, salt: salt, iterations: n)
        case .argon2id(let m, let t, let p): return Credentials.argon2id(password, salt: salt, memoryKiB: m, passes: t, lanes: p)
        }
    }
}

/// On-device accounts: each person on a shared iPad or Mac gets their own paper account,
/// watchlists and alerts. Passwords are never stored; only a salted PBKDF2-SHA256 hash is.
public struct AccountRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public private(set) var email: String
    public private(set) var displayName: String
    var salt: Data
    var hash: Data
    /// PBKDF2 rounds for accounts created before Argon2id (0 once upgraded).
    var iterations: Int
    /// nil for accounts created before Argon2id, which use PBKDF2 with `iterations`.
    var kdf: KDF?
    /// The KDF behind both `hash` and the key that wraps the data key.
    public var passwordKDF: KDF { kdf ?? .pbkdf2(iterations: iterations) }
    public let created: Date
    public internal(set) var failedAttempts = 0
    public internal(set) var lockedUntil: Date?
    /// SHA-256 of the current session token (the token itself lives only in the Keychain).
    var sessionHash: Data?
    public internal(set) var sessionExpires: Date?
    /// Salt for the password-derived key that wraps `wrappedKey`.
    var keySalt: Data?
    /// The account's data key, sealed with the password-derived key. nil for accounts created
    /// before encryption; their files are encrypted at their next sign-in.
    var wrappedKey: Data?
    public var hasDataKey: Bool { wrappedKey != nil }

    public var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }
}

public enum AuthError: Error, Equatable, LocalizedError {
    case nameRequired, invalidEmail, weakPassword(String), passwordsDiffer, emailTaken, invalidCredentials
    case locked(until: Date)

    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Enter your name"
        case .invalidEmail: "Enter a valid email address"
        case .weakPassword(let why): why
        case .passwordsDiffer: "Passwords don't match"
        case .emailTaken: "An account with this email already exists on this device"
        case .invalidCredentials: "Email or password is incorrect"
        case .locked(let until): "Too many attempts. Try again \(until.formatted(.relative(presentation: .named)))"
        }
    }
}

public enum Credentials {
    /// OWASP's 2023 floor for PBKDF2-HMAC-SHA256.
    public static let iterations = 600_000
    public static let minPasswordLength = 10
    public static let maxPasswordLength = 128

    public static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isValidEmail(_ email: String) -> Bool {
        let e = normalize(email)
        guard e.count <= 254 else { return false }
        return e.wholeMatch(of: /[a-z0-9._%+\-]+@[a-z0-9\-]+(\.[a-z0-9\-]+)*\.[a-z]{2,}/) != nil
    }

    /// NIST 800-63B style: length and a blocklist, no composition rules. Returns the problem, if any.
    public static func passwordProblem(_ password: String, email: String) -> String? {
        if password.count < minPasswordLength { return "Use at least \(minPasswordLength) characters" }
        if password.count > maxPasswordLength { return "Use at most \(maxPasswordLength) characters" }
        let lower = password.lowercased()
        if Set(lower).count < 4 { return "Too repetitive: use a mix of characters" }
        let local = normalize(email).split(separator: "@").first.map(String.init) ?? ""
        if local.count >= 3, lower.contains(local) { return "Don't include your email in the password" }
        if common.contains(where: { lower.contains($0) }) { return "Too common: avoid words like \"password\" or \"123456\"" }
        return nil
    }

    private static let common = ["password", "123456", "qwerty", "letmein", "welcome", "abc123", "iloveyou", "kestrel", "trading", "bloomberg", "admin"]

    public static func salt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return Data(bytes)
    }

    public static func derive(_ password: String, salt: Data, iterations: Int) -> Data {
        let pw = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { s in
            pw.withUnsafeBufferPointer { p in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) }, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
            }
        }
        precondition(status == kCCSuccess)
        return Data(out)
    }

    /// Argon2id (RFC 9106) through the vendored reference implementation; 32-byte output.
    public static func argon2id(_ password: String, salt: Data, memoryKiB: Int, passes: Int, lanes: Int) -> Data {
        let pw = Array(password.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let rc = salt.withUnsafeBytes { s in
            pw.withUnsafeBytes { p in
                argon2id_hash_raw(UInt32(passes), UInt32(memoryKiB), UInt32(lanes), p.baseAddress, pw.count, s.baseAddress, salt.count, &out, out.count)
            }
        }
        precondition(rc == ARGON2_OK.rawValue, "argon2id failed: \(rc)")
        return Data(out)
    }

    /// Compares every byte so timing doesn't reveal how much of a hash matched.
    public static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// Every account on this device. A pure value type: the app persists it and runs the slow
/// key derivation off the main thread.
public struct AccountDirectory: Codable, Sendable, Equatable {
    public private(set) var accounts: [AccountRecord] = []
    public static let maxAttempts = 5

    public init() {}

    public func account(id: UUID) -> AccountRecord? { accounts.first { $0.id == id } }

    @discardableResult
    public mutating func register(name: String, email: String, password: String, confirm: String,
                                  kdf: KDF = .standard, now: Date = .now) throws(AuthError) -> AccountRecord {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { throw .nameRequired }
        guard Credentials.isValidEmail(email) else { throw .invalidEmail }
        let e = Credentials.normalize(email)
        guard !accounts.contains(where: { $0.email == e }) else { throw .emailTaken }
        if let why = Credentials.passwordProblem(password, email: e) { throw .weakPassword(why) }
        guard password == confirm else { throw .passwordsDiffer }
        let salt = Credentials.salt()
        var iterations = 0
        if case .pbkdf2(let n) = kdf { iterations = n }
        let r = AccountRecord(id: UUID(), email: e, displayName: name, salt: salt,
                              hash: kdf.derive(password, salt: salt),
                              iterations: iterations, kdf: iterations > 0 ? nil : kdf, created: now)
        accounts.append(r)
        return r
    }

    /// Verifies a password. After `maxAttempts` failures the account locks for 30 s, doubling
    /// with each further failure up to an hour. Unknown emails cost the same work as known ones.
    public mutating func signIn(email: String, password: String, now: Date = .now) throws(AuthError) -> AccountRecord {
        let e = Credentials.normalize(email)
        guard let i = accounts.firstIndex(where: { $0.email == e }) else {
            _ = (accounts.first?.passwordKDF ?? .standard).derive(password, salt: Data(count: 16))
            throw .invalidCredentials
        }
        if let until = accounts[i].lockedUntil, until > now { throw .locked(until: until) }
        let r = accounts[i]
        guard Credentials.constantTimeEqual(r.passwordKDF.derive(password, salt: r.salt), r.hash) else {
            accounts[i].failedAttempts += 1
            let over = accounts[i].failedAttempts - Self.maxAttempts
            if over >= 0 {
                let until = now.addingTimeInterval(min(30 * pow(2, Double(over)), 3600))
                accounts[i].lockedUntil = until
                throw .locked(until: until)
            }
            throw .invalidCredentials
        }
        accounts[i].failedAttempts = 0
        accounts[i].lockedUntil = nil
        return accounts[i]
    }

    public mutating func remove(id: UUID) { accounts.removeAll { $0.id == id } }

    // MARK: Data key

    /// The account's data key for `password` (already verified by `signIn` or `register`).
    /// Creates and wraps one the first time, which also migrates pre-encryption accounts. A PBKDF2 account is
    /// upgraded here to `upgradeTo` (Argon2id): new salts, and the login hash and wrapped key re-derived.
    public mutating func unlockDataKey(id: UUID, password: String, upgradeTo target: KDF = .standard) throws(AuthError) -> Data {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { throw .invalidCredentials }
        let r = accounts[i]
        var upgrade = false
        if case .pbkdf2 = r.passwordKDF, case .argon2id = target { upgrade = true }
        let kdf = upgrade ? target : r.passwordKDF
        let key: Data
        if let wrapped = r.wrappedKey, let salt = r.keySalt {
            do { key = try Vault.open(wrapped, key: r.passwordKDF.derive(password, salt: salt)) } catch { throw .invalidCredentials }
            if !upgrade { return key }
        } else {
            key = Vault.newKey()
        }
        // (Re)wrap under `kdf`. Unwrapping above (or signIn/register) proved the password, so re-hashing is safe.
        let keySalt = Credentials.salt()
        guard let wrapped = try? Vault.seal(key, key: kdf.derive(password, salt: keySalt)) else { throw .invalidCredentials }
        if upgrade {
            let loginSalt = Credentials.salt()
            accounts[i].salt = loginSalt
            accounts[i].hash = kdf.derive(password, salt: loginSalt)
            accounts[i].iterations = 0
            accounts[i].kdf = kdf
        }
        accounts[i].keySalt = keySalt
        accounts[i].wrappedKey = wrapped
        return key
    }

    // MARK: Sessions

    /// Idle sessions expire after 30 days; each successful restore extends them.
    public static let sessionLifetime: TimeInterval = 30 * 86_400

    public static func newSessionToken() -> Data { Credentials.salt() + Credentials.salt() }   // 256 random bits

    static func tokenHash(_ token: Data) -> Data { Data(SHA256.hash(data: token)) }

    public mutating func beginSession(id: UUID, token: Data, now: Date = .now) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].sessionHash = Self.tokenHash(token)
        accounts[i].sessionExpires = now.addingTimeInterval(Self.sessionLifetime)
    }

    /// The account a stored token belongs to, if it matches and hasn't expired. Slides the expiry.
    public mutating func resumeSession(id: UUID, token: Data, now: Date = .now) -> AccountRecord? {
        guard let i = accounts.firstIndex(where: { $0.id == id }),
              let hash = accounts[i].sessionHash, let exp = accounts[i].sessionExpires, exp > now,
              Credentials.constantTimeEqual(Self.tokenHash(token), hash) else { return nil }
        accounts[i].sessionExpires = now.addingTimeInterval(Self.sessionLifetime)
        return accounts[i]
    }

    /// Revokes the session server-side style: the old token stops working even if a copy survives.
    public mutating func endSession(id: UUID) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].sessionHash = nil
        accounts[i].sessionExpires = nil
    }
}
