import Foundation

/// Moving an account between iPad and Mac without a server: watchlists, alerts and the paper
/// book in one file, sealed with AES-256-GCM under a key derived from a passphrase the user
/// chooses (Argon2id, random salt; older files used PBKDF2). The file is treated as untrusted input on import.
public struct TransferBundle: Codable, Sendable, Equatable {
    public static let format = 1
    public var format = TransferBundle.format
    public var exported: Date
    public var watchlists: [Watchlist]
    public var activeID: UUID
    public var alerts: AlertBook
    public var account: PaperAccount

    public init(exported: Date = .now, watchlists: [Watchlist], activeID: UUID, alerts: AlertBook, account: PaperAccount) {
        self.exported = exported; self.watchlists = watchlists; self.activeID = activeID; self.alerts = alerts; self.account = account
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case weakPassphrase, notATransferFile, wrongPassphrase, unsupportedVersion, invalidContents(String)
        public var errorDescription: String? {
            switch self {
            case .weakPassphrase: "Use a passphrase of at least 10 characters"
            case .notATransferFile: "That isn't a Kestrel transfer file"
            case .wrongPassphrase: "Wrong passphrase, or the file was changed"
            case .unsupportedVersion: "This file comes from a newer version of Kestrel"
            case .invalidContents(let why): "The file's contents were rejected: \(why)"
            }
        }
    }

    static let magic = Data("KXF1".utf8)
    static let magic2 = Data("KXF2".utf8)
    public static let iterations = 600_000
    public static let maxFileSize = 8 * 1024 * 1024

    /// Layouts (integers big-endian):
    /// - "KXF2" · salt (16) · Argon2id memory KiB, passes, lanes (UInt32 each) · Vault-sealed JSON. Written by default.
    /// - "KXF1" · salt (16) · PBKDF2 iterations (UInt32) · Vault-sealed JSON. Older files; still opened.
    public func seal(passphrase: String, kdf: KDF = .standard) throws(Failure) -> Data {
        guard passphrase.count >= 10 else { throw .weakPassphrase }
        let salt = Credentials.salt()
        let key = kdf.derive(passphrase, salt: salt)
        guard let json = try? JSONEncoder().encode(self), let sealed = try? Vault.seal(json, key: key) else { throw .invalidContents("encode") }
        func be(_ v: Int) -> Data { var n = UInt32(v).bigEndian; return Data(bytes: &n, count: 4) }
        switch kdf {
        case .pbkdf2(let n): return Self.magic + salt + be(n) + sealed
        case .argon2id(let m, let t, let p): return Self.magic2 + salt + be(m) + be(t) + be(p) + sealed
        }
    }

    /// The older PBKDF2 format (tests and compatibility checks).
    public func seal(passphrase: String, iterations: Int) throws(Failure) -> Data { try seal(passphrase: passphrase, kdf: .pbkdf2(iterations: iterations)) }

    public static func open(_ data: Data, passphrase: String) throws(Failure) -> TransferBundle {
        guard data.count <= maxFileSize, data.count > 24 else { throw .notATransferFile }
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> Int { Int(bytes[at..<at + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
        let kdf: KDF, body: Int
        if data.starts(with: magic2), data.count > 32 {
            kdf = .argon2id(memoryKiB: u32(20), passes: u32(24), lanes: u32(28)); body = 32
        } else if data.starts(with: magic) {
            kdf = .pbkdf2(iterations: u32(20)); body = 24
        } else { throw .notATransferFile }
        // Bound the work an attacker-supplied file can demand.
        guard kdf.isWithinImportLimits else { throw .notATransferFile }
        let key = kdf.derive(passphrase, salt: data.subdata(in: 4..<20))
        let json: Data
        do { json = try Vault.open(data.subdata(in: body..<data.count), key: key) } catch { throw .wrongPassphrase }
        guard let b = try? JSONDecoder().decode(TransferBundle.self, from: json) else { throw .invalidContents("unreadable") }
        guard b.format <= format else { throw .unsupportedVersion }
        try b.validate()
        return b
    }

    /// The same limits typed input gets, so a crafted file can't smuggle in more.
    public func validate() throws(Failure) {
        guard !watchlists.isEmpty, watchlists.count <= 20 else { throw .invalidContents("watchlist count") }
        let symbolRule = /^[A-Z0-9^=\-\.]{1,32}$/
        for w in watchlists {
            guard w.symbols.count <= Watchlist.maxSymbols, !w.name.isEmpty, w.name.count <= Watchlist.maxNameLength else { throw .invalidContents("watchlist \(w.name.prefix(24))") }
            guard w.symbols.allSatisfy({ $0.wholeMatch(of: symbolRule) != nil }) else { throw .invalidContents("symbol in \(w.name.prefix(24))") }
        }
        guard watchlists.contains(where: { $0.id == activeID }) else { throw .invalidContents("active list") }
        guard alerts.active.count <= AlertBook.maxActive, alerts.alerts.count <= AlertBook.maxActive + AlertBook.maxHistory else { throw .invalidContents("alerts") }
        guard alerts.alerts.allSatisfy({ $0.symbol.wholeMatch(of: symbolRule) != nil || Deribit.parse($0.symbol) != nil }) else { throw .invalidContents("alert symbol") }
        guard account.cash.isFinite, account.openPositions.count <= 500, account.orders.count <= 10_000 else { throw .invalidContents("paper account") }
    }
}

private extension Decimal { var isFinite: Bool { !isNaN && !isInfinite } }
