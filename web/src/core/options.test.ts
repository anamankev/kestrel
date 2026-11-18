import { describe, expect, it } from "vitest";
import { decodeDeribit, greeks, impliedVol, isITM, OptionChain, optionInstrument, parseOption, StrategyAnalysis, templateLegs, type OptionContract } from "./options";
import { resolve } from "./universe";

describe("Black-76 (ported from KestrelCore)", () => {
  it("matches reference values", () => {
    const c = greeks(100, 100, 1, 0.2, true);
    expect(Math.abs(c.price - 7.9656)).toBeLessThan(1e-4);
    expect(Math.abs(c.delta - 0.5398)).toBeLessThan(1e-4);
    expect(Math.abs(c.vega - 0.397)).toBeLessThan(1e-4);
  });
  it("satisfies put-call parity", () => {
    for (const k of [60, 90, 100, 130]) {
      const c = greeks(100, k, 0.3, 0.7, true), p = greeks(100, k, 0.3, 0.7, false);
      expect(Math.abs(c.price - p.price - (100 - k))).toBeLessThan(1e-9);
      expect(Math.abs(c.delta - p.delta - 1)).toBeLessThan(1e-12);
      expect(Math.abs(c.gamma - p.gamma)).toBeLessThan(1e-12);
    }
  });
  it("round-trips implied vol", () => {
    for (const [k, s, call] of [[80, 0.35, true], [100, 0.9, false], [150, 1.5, true], [50, 0.6, false]] as const) {
      const iv = impliedVol(greeks(100, k, 0.25, s, call).price, 100, k, 0.25, call);
      expect(iv).toBeDefined(); expect(Math.abs(iv! - s)).toBeLessThan(1e-6);
    }
    expect(impliedVol(0.5, 100, 80, 0.25, true)).toBeUndefined();
    expect(greeks(110, 100, 0, 0.5, true).price).toBe(10);
    expect(greeks(110, 100, 0, 0.5, false).price).toBe(0);
  });
});

describe("Deribit chains", () => {
  it("parses names and resolves options as instruments", () => {
    const p = parseOption("BTC-4DEC26-70000-C")!;
    expect(p).toMatchObject({ underlying: "BTC", strike: 70_000, call: true });
    expect(p.expiry).toBe(Date.parse("2026-12-04T08:00:00Z"));
    expect(parseOption("BTC-PERPETUAL")).toBeUndefined();
    expect(optionInstrument("ETH-27MAR26-3000-P")?.name).toBe("ETH 27 MAR 26 3,000 PUT");
    expect(resolve("btc-4dec26-70000-c")?.assetClass).toBe("OPTION");
  });
  it("computes chain analytics", () => {
    const r = (n: string, bid: number, ask: number, mark: number, iv: number, oi: number) => ({ instrument_name: n, bid_price: bid, ask_price: ask, mark_price: mark, mark_iv: iv, open_interest: oi, volume: 1, underlying_price: 65000 });
    const chain = decodeDeribit({ result: [r("BTC-25DEC26-60000-C", 0.08, 0.081, 0.0805, 50, 10), r("BTC-25DEC26-60000-P", 0.01, 0.011, 0.0105, 54, 40),
      r("BTC-25DEC26-65000-C", 0.04, 0.041, 0.0405, 48, 30), r("BTC-25DEC26-65000-P", 0.04, 0.041, 0.0405, 50, 20), r("BTC-25DEC26-70000-C", 0, 0.02, 0.019, 47, 50)] });
    const e = chain.expiries[0];
    expect(chain.rows(e).map((x) => x.strike)).toEqual([60_000, 65_000, 70_000]);
    expect(chain.atmStrike(e)).toBe(65_000);
    expect(Math.abs(chain.atmIV(e)! - 0.49)).toBeLessThan(1e-12);
    expect(chain.putCallOI()).toBe(60 / 90);
    expect(chain.maxPain(e)).toBe(65_000);
    const c = chain.rows(e)[0].call!;
    expect(c.bid).toBe(0.08 * 65_000); expect(isITM(c)).toBe(true);
    expect(chain.rows(e)[2].call?.bid).toBeUndefined();
  });
});

describe("strategies", () => {
  const exp = 1_900_000_000_000;
  const c = (k: number, call: boolean, mark: number): OptionContract => ({ name: `BTC-X-${k}-${call ? "C" : "P"}`, underlying: "BTC", expiry: exp, strike: k, isCall: call, mark, iv: 0.5, openInterest: 0, volume: 0, forward: 100 });
  it("bounds payoffs", () => {
    const long = new StrategyAnalysis([{ contract: c(100, true, 5), quantity: 1 }]);
    expect(long.netPremium).toBe(5); expect(long.maxProfit).toBeUndefined(); expect(long.maxLoss).toBe(-5); expect(long.breakevens).toEqual([105]); expect(long.payoffAtExpiry(120)).toBe(15);
    const spread = new StrategyAnalysis([{ contract: c(100, true, 6), quantity: 1 }, { contract: c(110, true, 2), quantity: -1 }]);
    expect(spread.maxProfit).toBe(6); expect(spread.maxLoss).toBe(-4); expect(spread.breakevens).toEqual([104]);
    const short = new StrategyAnalysis([{ contract: c(100, true, 5), quantity: -1 }, { contract: c(100, false, 5), quantity: -1 }]);
    expect(short.maxLoss).toBeUndefined(); expect(short.maxProfit).toBe(10); expect(short.breakevens).toEqual([90, 110]);
  });
  it("converges to expiry and picks listed strikes", () => {
    const a = new StrategyAnalysis([{ contract: c(100, true, 5), quantity: 1 }]);
    expect(Math.abs(a.valueToday(120, exp) - a.payoffAtExpiry(120))).toBeLessThan(1e-9);
    expect(a.valueToday(100, exp - 30 * 86_400_000)).toBeGreaterThan(a.payoffAtExpiry(100));
    const all: OptionContract[] = [];
    for (let k = 80; k <= 120; k += 2) all.push(c(k, true, 3), c(k, false, 3));
    const chain = new OptionChain(all);
    const condor = templateLegs("IRON CONDOR", chain, exp)!;
    expect(condor.map((l) => l.contract.strike)).toEqual([88, 94, 106, 112]); expect(condor.map((l) => l.quantity)).toEqual([1, -1, -1, 1]);
    expect(new StrategyAnalysis(templateLegs("CALL BUTTERFLY", chain, exp)!).netPremium).toBe(0);
  });
});
