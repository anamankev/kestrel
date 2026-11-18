/**
 * Password-to-key derivation, matching KestrelCore's `KDF`. New accounts and files use Argon2id (memory-hard:
 * each guess needs 64 MiB, so GPUs can't run thousands in parallel). PBKDF2 remains only to open older
 * accounts and transfer files. Argon2id comes from hash-wasm, checked against the reference vectors in kdf.test.ts.
 */
import { argon2id } from "hash-wasm";

export type KDF = { kind: "pbkdf2"; iterations: number } | { kind: "argon2id"; memoryKiB: number; passes: number; lanes: number };

/** RFC 9106's second recommended option (64 MiB, 3 passes), one lane: the same as the app. */
export const STANDARD: KDF = { kind: "argon2id", memoryKiB: 65_536, passes: 3, lanes: 1 };
/** Cheap settings for tests only. */
export const TESTING: KDF = { kind: "argon2id", memoryKiB: 64, passes: 1, lanes: 1 };

export const sameKDF = (a: KDF, b: KDF) => JSON.stringify(a) === JSON.stringify(b);

/** Bounds for settings read from a file, so a crafted one can't demand unbounded memory or time. */
export function withinImportLimits(k: KDF): boolean {
  if (k.kind === "pbkdf2") return k.iterations >= 1_000 && k.iterations <= 5_000_000;
  return k.lanes >= 1 && k.lanes <= 4 && k.memoryKiB >= 8 * k.lanes && k.memoryKiB <= 262_144 && k.passes >= 1 && k.passes <= 10;
}

/** A KDF from untrusted JSON (a stored account record), or undefined. */
export function parseKDF(v: any): KDF | undefined {
  if (v?.kind === "argon2id" && [v.memoryKiB, v.passes, v.lanes].every(Number.isInteger)) {
    const k: KDF = { kind: "argon2id", memoryKiB: v.memoryKiB, passes: v.passes, lanes: v.lanes };
    return withinImportLimits(k) ? k : undefined;
  }
  return undefined;
}

const enc = new TextEncoder();

/** A 32-byte key from `password` and `salt`. */
export async function derive(kdf: KDF, password: string, salt: Uint8Array): Promise<Uint8Array<ArrayBuffer>> {
  if (kdf.kind === "pbkdf2") {
    const subtle = globalThis.crypto.subtle;
    const base = await subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
    return new Uint8Array(await subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: salt as Uint8Array<ArrayBuffer>, iterations: kdf.iterations }, base, 256));
  }
  const out = await argon2id({ password: enc.encode(password), salt, parallelism: kdf.lanes, iterations: kdf.passes, memorySize: kdf.memoryKiB, hashLength: 32, outputType: "binary" });
  return new Uint8Array(out);
}
