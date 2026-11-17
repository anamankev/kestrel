import Foundation

/// Moving an account between iPad and Mac without a server: watchlists, alerts and the paper
/// book in one file, sealed with AES-256-GCM under a key derived from a passphrase the user
/// chooses (PBKDF2, random salt). The file is treated as untrusted input on import.
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
    public static let iterations = 600_000
    public static let maxFileSize = 8 * 1024 * 1024

    /// Layout: "KXF1" · salt (16) · iterations (UInt32, big-endian) · Vault-sealed JSON.
    public func seal(passphrase: String, iterations: Int = TransferBundle.iterations) throws(Failure) -> Data {
        guard passphrase.count >= 10 else { throw .weakPassphrase }
        let salt = Credentials.salt()
        let key = Vault.passwordKey(passphrase, salt: salt, iterations: iterations)
        guard let json = try? JSONEncoder().encode(self), let sealed = try? Vault.seal(json, key: key) else { throw .invalidContents("encode") }
        var n = UInt32(iterations).bigEndian
        return Self.magic + salt + Data(bytes: &n, count: 4) + sealed
    }

    public static func open(_ data: Data, passphrase: String) throws(Failure) -> TransferBundle {
        guard data.count <= maxFileSize, data.count > 24, data.starts(with: magic) else { throw .notATransferFile }
        let salt = data.subdata(in: 4..<20)
        let iterations = Int(data.subdata(in: 20..<24).reduce(0) { $0 << 8 | UInt32($1) })
        // Bound the work an attacker-supplied file can demand.
        guard (1_000...5_000_000).contains(iterations) else { throw .notATransferFile }
        let key = Vault.passwordKey(passphrase, salt: salt, iterations: iterations)
        let json: Data
        do { json = try Vault.open(data.subdata(in: 24..<data.count), key: key) } catch { throw .wrongPassphrase }
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
