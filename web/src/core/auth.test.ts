import { describe, expect, test } from "vitest";
import { AccountDirectory, AuthError, importDataKey, open, passwordProblem, seal, isValidEmail, b64, unb64, passwordKDF } from "./auth";
import { derive, STANDARD, TESTING, withinImportLimits } from "./kdf";

const FAST = TESTING; // cheap Argon2id for tests; production uses 64 MiB, 3 passes

describe("credentials", () => {
  test("password policy matches the app", () => {
    expect(passwordProblem("short", "a@b.co")).toMatch(/at least 10/);
    expect(passwordProblem("aaaaaaaaaaaa", "a@b.co")).toMatch(/repetitive/);
    expect(passwordProblem("kelvin is great 1", "kelvin@x.com")).toMatch(/email/);
    expect(passwordProblem("my password here", "a@b.co")).toMatch(/common/);
    expect(passwordProblem("graphite ledger kite", "tour@kestrel.test")).toBeNull();
    expect(isValidEmail(" Ada@Example.COM ")).toBe(true);
    expect(isValidEmail("nope@x")).toBe(false);
  });
});

describe("accounts", () => {
  test("register, sign in, wrong password, lockout", async () => {
    const d = new AccountDirectory([], FAST);
    const r = await d.register("Ada Lovelace", "ada@example.com", "graphite ledger kite", "graphite ledger kite");
    expect(r.hash).not.toContain("graphite");
    await expect(d.register("Ada", "ADA@example.com", "graphite ledger kite", "graphite ledger kite")).rejects.toThrow(/already exists/);
    expect((await d.signIn("ada@example.com", "graphite ledger kite")).id).toBe(r.id);
    await expect(d.signIn("nobody@example.com", "x")).rejects.toThrow(/incorrect/);
    const t0 = 1_000_000;
    for (let i = 0; i < 4; i++) await expect(d.signIn("ada@example.com", "wrong password!!", t0)).rejects.toThrow(/incorrect/);
    const locked = await d.signIn("ada@example.com", "wrong password!!", t0).catch((e) => e);
    expect(locked).toBeInstanceOf(AuthError);
    expect((locked as AuthError).lockedUntil).toBe(t0 + 30_000);
    await expect(d.signIn("ada@example.com", "graphite ledger kite", t0 + 1000)).rejects.toThrow(/Too many/);
    expect((await d.signIn("ada@example.com", "graphite ledger kite", t0 + 31_000)).failedAttempts).toBe(0);
  });

  test("data key is stable and wrapped by the password", async () => {
    const d = new AccountDirectory([], FAST);
    const r = await d.register("Ada", "ada@example.com", "graphite ledger kite", "graphite ledger kite");
    const k1 = await d.unlockDataKey(r.id, "graphite ledger kite");
    const k2 = await d.unlockDataKey(r.id, "graphite ledger kite");
    expect(k1).toEqual(k2);
    await expect(d.unlockDataKey(r.id, "something else entirely")).rejects.toThrow();
  });

  test("vault round-trips and rejects tampering", async () => {
    const key = await importDataKey(crypto.getRandomValues(new Uint8Array(32)));
    const box = await seal(new TextEncoder().encode("watchlists"), key);
    expect(new TextDecoder().decode(await open(box, key))).toBe("watchlists");
    box[box.length - 1] ^= 1;
    await expect(open(box, key)).rejects.toThrow();
  });
});

test("base64 handles large vaults", () => {
  const big = Uint8Array.from({ length: 65536 * 4 }, (_, i) => (i * 31 + 7) % 256);
  expect(unb64(b64(big))).toEqual(big);
});

const hex = (u: Uint8Array) => [...u].map((b) => b.toString(16).padStart(2, "0")).join("");
describe("Argon2id", () => {
  test("matches the reference implementation's vectors (the same ones KestrelCore checks)", async () => {
    const salt = new TextEncoder().encode("somesalt"), a = (m: number, t: number, p: number, pw = "password", s = salt) => derive({ kind: "argon2id", memoryKiB: m, passes: t, lanes: p }, pw, s).then(hex);
    expect(await a(1 << 16, 2, 1)).toBe("09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7");
    expect(await a(1 << 8, 2, 1)).toBe("9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe");
    expect(await a(1 << 8, 2, 2)).toBe("6d093c501fd5999645e0ea3bf620d7b8be7fd2db59c20d9fff9539da2bf57037");
    expect(await a(1 << 16, 1, 1)).toBe("f6a5adc1ba723dddef9b5ac1d464e180fcd9dffc9d1cbf76cca2fed795d9ca98");
    expect(await a(1 << 16, 2, 1, "differentpassword")).toBe("0b84d652cf6b0c4beaef0dfe278ba6a80df6696281d7e0d2891b817d8c458fde");
    expect(await a(1 << 16, 2, 1, "password", new TextEncoder().encode("diffsalt"))).toBe("bdf32b05ccc42eb15d58fd19b1f856b113da1e9a5874fdcc544308565aa8141c");
  });
  test("new accounts use the standard settings; hostile settings are refused", async () => {
    const r = await new AccountDirectory().register("Ada", "ada@example.com", "analytical engine", "analytical engine");
    expect(passwordKDF(r)).toEqual(STANDARD);
    expect(withinImportLimits({ kind: "argon2id", memoryKiB: 2 ** 31, passes: 3, lanes: 1 })).toBe(false);
    expect(withinImportLimits({ kind: "argon2id", memoryKiB: 64, passes: 500, lanes: 1 })).toBe(false);
  });
  test("upgrades a PBKDF2 account at sign-in, keeping its data key", async () => {
    const pw = "analytical engine";
    const legacy = new AccountDirectory([], { kind: "pbkdf2", iterations: 1_000 });
    const r = await legacy.register("Ada", "ada@example.com", pw, pw);
    const k0 = await legacy.unlockDataKey(r.id, pw);
    expect(r.kdf).toBeUndefined(); expect(r.iterations).toBe(1_000);
    const before = { salt: r.salt, keySalt: r.keySalt };
    // The same stored records, opened by the current build.
    const d = new AccountDirectory(JSON.parse(JSON.stringify(legacy.accounts)), TESTING);
    const s = await d.signIn("ada@example.com", pw);
    const k1 = await d.unlockDataKey(s.id, pw);
    expect(hex(k1)).toBe(hex(k0));
    expect(passwordKDF(s)).toEqual(TESTING); expect(s.iterations).toBe(0);
    expect(s.salt).not.toBe(before.salt); expect(s.keySalt).not.toBe(before.keySalt);
    expect((await d.signIn("ada@example.com", pw)).id).toBe(r.id);
    await expect(d.signIn("ada@example.com", pw + "x")).rejects.toThrow(/incorrect/);
    expect(hex(await d.unlockDataKey(s.id, pw))).toBe(hex(k0));
  });
});
