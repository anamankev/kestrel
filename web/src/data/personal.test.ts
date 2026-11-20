import { describe, expect, it } from "vitest";
import { clearPersonalUI } from "./personal";
import { validInputs } from "../ui/functions/Bonds";

class Mem implements Storage {
  m = new Map<string, string>();
  get length() { return this.m.size; }
  key(i: number) { return [...this.m.keys()][i] ?? null; }
  getItem(k: string) { return this.m.get(k) ?? null; }
  setItem(k: string, v: string) { this.m.set(k, v); }
  removeItem(k: string) { this.m.delete(k); }
  clear() { this.m.clear(); }
}

describe("personal data on shared computers", () => {
  it("clears trendlines and bond inputs at sign-out, keeps display settings", () => {
    const s = new Mem();
    for (const k of ["gp.lines.AAPL", "gp.lines.BTC-USD", "yas.inputs", "gp.range", "kestrel.cvd", "seas.span"]) s.setItem(k, "x");
    clearPersonalUI(s);
    expect([...s.m.keys()].sort()).toEqual(["gp.range", "kestrel.cvd", "seas.span"]);
  });
  it("rejects tampered bond inputs", () => {
    const good = { coupon: "5", maturity: "2036-11-19", mode: "YIELD→PRICE", price: "100", yld: "5", face: "1000000" };
    expect(validInputs(good)).toEqual(good);
    expect(validInputs({ ...good, mode: "x" })).toBeNull();
    expect(validInputs({ ...good, coupon: 5 })).toBeNull();
    expect(validInputs({ ...good, face: "9".repeat(500) })).toBeNull();
    expect(validInputs({ ...good, maturity: "<img src=x>" })).toBeNull();
    expect(validInputs(null)).toBeNull();
    expect(validInputs("str")).toBeNull();
  });
});
