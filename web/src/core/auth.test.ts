import { describe, expect, test } from "vitest";
import { AccountDirectory, AuthError, importDataKey, open, passwordProblem, seal, isValidEmail, b64, unb64 } from "./auth";

const FAST = 1000; // iterations for tests; production uses 600,000

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
