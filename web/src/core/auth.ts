/**
 * Browser accounts, mirroring the app's Accounts.swift: Argon2id password hashes (older accounts used
 * PBKDF2 and upgrade at their next sign-in), lockout after five failures, and a per-account AES-256-GCM data
 * key wrapped with a password-derived key. Passwords are never stored.
 */
import { derive, parseKDF, STANDARD, type KDF } from "./kdf";

const subtle = globalThis.crypto.subtle;
/** Byte arrays over plain (not shared) memory, as WebCrypto requires. */
export type Bytes = Uint8Array<ArrayBuffer>;
const enc = new TextEncoder();

/** PBKDF2 rounds used by accounts created before Argon2id. */
export const ITERATIONS = 600_000;
export const MIN_PASSWORD = 10, MAX_PASSWORD = 128, MAX_ATTEMPTS = 5;
export const SESSION_LIFETIME = 30 * 86_400_000;

export const normalize = (email: string) => email.trim().toLowerCase();
export const isValidEmail = (email: string) => {
  const e = normalize(email);
  return e.length <= 254 && /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/.test(e);
};

const COMMON = ["password", "123456", "qwerty", "letmein", "welcome", "abc123", "iloveyou", "kestrel", "trading", "bloomberg", "admin"];
/** NIST 800-63B style: length and a blocklist, no composition rules. Returns the problem, if any. */
export function passwordProblem(password: string, email: string): string | null {
  const len = [...password].length;
  if (len < MIN_PASSWORD) return `Use at least ${MIN_PASSWORD} characters`;
  if (len > MAX_PASSWORD) return `Use at most ${MAX_PASSWORD} characters`;
  const lower = password.toLowerCase();
  if (new Set(lower).size < 4) return "Too repetitive: use a mix of characters";
  const local = normalize(email).split("@")[0] ?? "";
  if (local.length >= 3 && lower.includes(local)) return "Don't include your email in the password";
  if (COMMON.some((c) => lower.includes(c))) return 'Too common: avoid words like "password" or "123456"';
  return null;
}

export const randomBytes = (n: number): Bytes => globalThis.crypto.getRandomValues(new Uint8Array(n));
/** Base64 in 32 KB chunks (spreading a large array into one call overflows the stack). */
export function b64(u: Uint8Array): string {
  let s = "";
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000));
  return btoa(s);
}
export const unb64 = (s: string): Bytes => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export const pbkdf2 = (password: string, salt: Bytes, iterations: number): Promise<Bytes> => derive({ kind: "pbkdf2", iterations }, password, salt);

/** Compares every byte so timing doesn't reveal how much of a hash matched. */
export function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

// MARK: Vault: "KSV1" | 12-byte IV | AES-256-GCM ciphertext+tag

const MAGIC = enc.encode("KSV1");
export const importDataKey = (raw: Bytes, extractable = false) => subtle.importKey("raw", raw, "AES-GCM", extractable, ["encrypt", "decrypt"]);

export async function seal(plain: Bytes, key: CryptoKey): Promise<Bytes> {
  const iv = randomBytes(12);
  const ct = new Uint8Array(await subtle.encrypt({ name: "AES-GCM", iv }, key, plain));
  const out = new Uint8Array(4 + 12 + ct.length);
  out.set(MAGIC); out.set(iv, 4); out.set(ct, 16);
  return out;
}

export async function open(box: Bytes, key: CryptoKey): Promise<Bytes> {
  if (box.length < 16 + 16 || !MAGIC.every((b, i) => box[i] === b)) throw new Error("not a Kestrel vault");
  return new Uint8Array(await subtle.decrypt({ name: "AES-GCM", iv: box.slice(4, 16) }, key, box.slice(16)));
}

// MARK: Accounts

export interface AccountRecord {
  id: string; email: string; displayName: string; created: number;
  salt: string; hash: string;
  /** PBKDF2 rounds for accounts created before Argon2id (0 once upgraded). */
  iterations: number;
  /** Absent on accounts created before Argon2id, which use PBKDF2 with `iterations`. */
  kdf?: KDF;
  failedAttempts: number; lockedUntil?: number;
  keySalt?: string; wrappedKey?: string;
}

/** The KDF behind an account's login hash and the key that wraps its data key. */
export const passwordKDF = (r: AccountRecord): KDF => parseKDF(r.kdf) ?? { kind: "pbkdf2", iterations: r.iterations };

export class AuthError extends Error {
  constructor(message: string, readonly lockedUntil?: number) { super(message); }
}

export const initials = (a: AccountRecord) => a.displayName.split(" ").slice(0, 2).map((p) => p[0] ?? "").join("").toUpperCase();

export class AccountDirectory {
  accounts: AccountRecord[] = [];
  /** `kdf` is what new and upgraded accounts use (tests pass cheap settings). */
  constructor(accounts: AccountRecord[] = [], readonly kdf: KDF = STANDARD) { this.accounts = accounts; }

  async register(name: string, email: string, password: string, confirm: string, now = Date.now()): Promise<AccountRecord> {
    const n = name.trim();
    if (!n || n.length > 60) throw new AuthError("Enter your name");
    if (!isValidEmail(email)) throw new AuthError("Enter a valid email address");
    const e = normalize(email);
    if (this.accounts.some((a) => a.email === e)) throw new AuthError("An account with this email already exists on this browser");
    const why = passwordProblem(password, e);
    if (why) throw new AuthError(why);
    if (password !== confirm) throw new AuthError("Passwords don't match");
    const salt = randomBytes(16);
    const r: AccountRecord = { id: globalThis.crypto.randomUUID(), email: e, displayName: n, created: now, salt: b64(salt),
      hash: b64(await derive(this.kdf, password, salt)), iterations: this.kdf.kind === "pbkdf2" ? this.kdf.iterations : 0,
      ...(this.kdf.kind === "argon2id" ? { kdf: this.kdf } : {}), failedAttempts: 0 };
    this.accounts.push(r);
    return r;
  }

  /** After five failures the account locks for 30 s, doubling per failure up to an hour. Unknown emails cost the same work. */
  async signIn(email: string, password: string, now = Date.now()): Promise<AccountRecord> {
    const r = this.accounts.find((a) => a.email === normalize(email));
    if (!r) { await derive(this.accounts[0] ? passwordKDF(this.accounts[0]) : this.kdf, password, new Uint8Array(16)); throw new AuthError("Email or password is incorrect"); }
    if (r.lockedUntil && r.lockedUntil > now) throw new AuthError(lockMessage(r.lockedUntil, now), r.lockedUntil);
    if (!constantTimeEqual(await derive(passwordKDF(r), password, unb64(r.salt)), unb64(r.hash))) {
      r.failedAttempts += 1;
      const over = r.failedAttempts - MAX_ATTEMPTS;
      if (over >= 0) { r.lockedUntil = now + Math.min(30_000 * 2 ** over, 3_600_000); throw new AuthError(lockMessage(r.lockedUntil, now), r.lockedUntil); }
      throw new AuthError("Email or password is incorrect");
    }
    r.failedAttempts = 0; r.lockedUntil = undefined;
    return r;
  }

  /** The account's data key (raw bytes) for a verified password; creates and wraps one the first time.
   *  A PBKDF2 account is upgraded here to Argon2id: new salts, and the login hash and wrapped key re-derived. */
  async unlockDataKey(id: string, password: string): Promise<Bytes> {
    const r = this.accounts.find((a) => a.id === id);
    if (!r) throw new AuthError("Email or password is incorrect");
    const current = passwordKDF(r), upgrade = current.kind === "pbkdf2" && this.kdf.kind === "argon2id";
    const kdf = upgrade ? this.kdf : current;
    let key: Bytes;
    if (r.wrappedKey && r.keySalt) {
      const kek = await importDataKey(await derive(current, password, unb64(r.keySalt)) as Bytes);
      try { key = await open(unb64(r.wrappedKey), kek); } catch { throw new AuthError("Email or password is incorrect"); }
      if (!upgrade) return key;
    } else key = randomBytes(32);
    // (Re)wrap under `kdf`. Unwrapping above (or signIn/register) proved the password, so re-hashing is safe.
    const keySalt = randomBytes(16);
    const wrapped = await seal(key, await importDataKey(await derive(kdf, password, keySalt) as Bytes));
    if (upgrade) {
      const loginSalt = randomBytes(16);
      r.salt = b64(loginSalt); r.hash = b64(await derive(kdf, password, loginSalt)); r.iterations = 0; r.kdf = kdf;
    }
    r.keySalt = b64(keySalt); r.wrappedKey = b64(wrapped);
    return key;
  }

  remove(id: string) { this.accounts = this.accounts.filter((a) => a.id !== id); }
}

function lockMessage(until: number, now: number) {
  const s = Math.ceil((until - now) / 1000);
  return `Too many attempts. Try again in ${s < 60 ? `${s} seconds` : `${Math.ceil(s / 60)} minutes`}`;
}
