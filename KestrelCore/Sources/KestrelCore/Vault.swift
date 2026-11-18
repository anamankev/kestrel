import Foundation
import CryptoKit

/// Encryption at rest for each account's files (AES-256-GCM, authenticated: tampering is
/// detected, not just hidden). Each account has a random data key; it is stored only wrapped
/// by a key derived from the account password, so the files are unreadable without it.
public enum Vault {
    public enum Failure: Error, Equatable { case notSealed, wrongKey }

    /// File header, so sealed data is never mistaken for legacy plaintext JSON.
    static let magic = Data("KSV1".utf8)

    public static func newKey() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }

    public static func isSealed(_ data: Data) -> Bool { data.starts(with: magic) }

    public static func seal(_ plain: Data, key: Data) throws -> Data {
        guard let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key)).combined else { throw Failure.wrongKey }
        return magic + box
    }

    public static func open(_ sealed: Data, key: Data) throws(Failure) -> Data {
        guard isSealed(sealed) else { throw .notSealed }
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed.dropFirst(magic.count)), using: SymmetricKey(data: key))
        } catch { throw .wrongKey }
    }

    /// Key-encryption key from the password (separate salt from the login hash).
    public static func passwordKey(_ password: String, salt: Data, iterations: Int) -> Data {
        Credentials.derive(password, salt: salt, iterations: iterations)
    }

    public static func passwordKey(_ password: String, salt: Data, kdf: KDF) -> Data { kdf.derive(password, salt: salt) }
}
