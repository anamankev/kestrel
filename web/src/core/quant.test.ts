import { describe, expect, test } from "vitest";
import { ols, adjustedBeta, performance, rebased, projectToSimplex, frontier, optimize, linearFit, dividendSummary, eventStudy, carSummary, car, lastDay, backtest, csvField, csv, correlation, alignedCloses, returnStats } from "./quant";
import type { Candle } from "./market";

describe("regression and performance", () => {
  test("OLS recovers a known line", () => {
    const x = Array.from({ length: 200 }, (_, i) => Math.sin(i * 0.37) * 0.02);
    const y = x.map((v, i) => 0.0005 + 1.3 * v + Math.cos(i * 1.91) * 0.001);
    const r = ols(y, x)!;
    expect(Math.abs(r.beta - 1.3)).toBeLessThan(0.02);
    expect(Math.abs(r.alpha - 0.0005)).toBeLessThan(0.0002);
    expect(r.r2).toBeGreaterThan(0.98);
    expect(adjustedBeta(1)).toBeCloseTo(1);
    expect(ols([1, 2, 3], [1, 1, 1])).toBeNull();
  });
  test("performance summary", () => {
    const p = performance([100, 110, 99, 121], 252)!;
    expect(p.totalReturn).toBeCloseTo(0.21, 12);
    expect(p.maxDrawdown).toBeCloseTo(99 / 110 - 1, 12);
    expect(rebased([100, 110])[0]).toBe(100);
  });
  test("correlation needs 20 points and variance", () => {
    const a = Array.from({ length: 30 }, (_, i) => Math.sin(i));
    expect(correlation(a, a)).toBeCloseTo(1);
    expect(correlation(a.slice(0, 10), a.slice(0, 10))).toBeNull();
    expect(correlation(a, a.map(() => 1))).toBeNull();
  });
});

describe("efficient frontier", () => {
  test("simplex projection", () => {
    const w = projectToSimplex([0.9, 0.8, -2]);
    expect(w.reduce((a, b) => a + b)).toBeCloseTo(1, 12);
    expect(w[2]).toBe(0);
  });
  test("matches the two-asset closed form", () => {
    const mu = [0.08, 0.12], cov = [[0.04, 0], [0, 0.09]];
    const f = frontier(mu, cov, 0.02)!;
    expect(f.minVariance.weights[0]).toBeCloseTo(0.09 / 0.13, 3);
    expect(Math.abs(f.maxSharpe.weights[0] - 1.5 / (1.5 + 0.1 / 0.09))).toBeLessThan(0.03);
    expect(f.frontier.length).toBeGreaterThanOrEqual(5);
    expect(optimize(mu, cov, 100).weights[0]).toBeGreaterThanOrEqual(0);
  });
});

describe("multiple regression and dividends", () => {
  test("recovers loadings and agrees with simple OLS", () => {
    const n = 300, a = Array.from({ length: n }, (_, i) => Math.sin(i * 0.3) * 0.01), b = Array.from({ length: n }, (_, i) => Math.cos(i * 0.71) * 0.01), c = Array.from({ length: n }, (_, i) => Math.sin(i * 1.37 + 1) * 0.01);
    const y = a.map((_, i) => 0.0002 + 1.1 * a[i] + 0.4 * b[i] - 0.3 * c[i] + Math.sin(i * 5.1) * 0.0005);
    const f = linearFit(y, [a, b, c], ["A", "B", "C"])!;
    expect(f.terms.map((t) => t.name)).toEqual(["Alpha", "A", "B", "C"]);
    expect(f.terms[1].coefficient).toBeCloseTo(1.1, 1);
    expect(f.terms[3].coefficient).toBeCloseTo(-0.3, 1);
    const one = linearFit(y, [a], ["A"])!, s = ols(y, a)!;
    expect(one.terms[1].coefficient).toBeCloseTo(s.beta, 9);
    expect(one.terms[1].standardError).toBeCloseTo(s.betaSE, 9);
    expect(linearFit(y, [a, a], ["A", "B"])).toBeNull();
  });
  test("dividend summary", () => {
    const d = (s: string) => Date.parse(s + "T12:00:00Z");
    const divs = [[2019, 0.4], [2020, 0.41], [2021, 0.42], [2022, 0.44], [2023, 0.46], [2024, 0.485], [2025, 0.51]].flatMap(([y, a]) => ["03", "06", "09", "11"].map((m) => ({ date: d(`${y}-${m}-14`), amount: a })));
    const s = dividendSummary(divs, 68, d("2026-01-10"))!;
    expect(s.paymentsPerYear).toBe(4);
    expect(s.trailing12M).toBeCloseTo(2.04, 9);
    expect(s.growth5Y).toBeCloseTo((0.51 / 0.41) ** 0.2 - 1, 9);
    expect(dividendSummary([], 10)).toBeNull();
  });
});

describe("event study", () => {
  test("recovers known event returns and keeps the open window pending", () => {
    const days: number[] = [];
    for (let t = Date.UTC(2024, 0, 2, 14, 30); days.length < 620; t += 86_400_000) { const w = new Date(t).getUTCDay(); if (w !== 0 && w !== 6) days.push(t); }
    const rm = days.map((_, i) => Math.sin(i * 0.41) * 0.01 + Math.cos(i * 1.3) * 0.004);
    const ra = days.map((_, i) => 0.0001 + 1.2 * rm[i] + Math.sin(i * 7.7) * 0.0003);
    for (const k of [100, 300, 420, 540, 617]) { ra[k] += 0.05; if (k + 1 < ra.length) ra[k + 1] -= 0.01; }
    const bars = (r: number[]): Candle[] => { let p = 100; return days.map((t, i) => { if (i > 0) p *= 1 + r[i]; return { time: t, open: p, high: p, low: p, close: p, volume: 1 }; }); };
    const s = eventStudy(bars(ra), bars(rm), [100, 300, 420, 540, 617].map((k) => days[k]))!;
    expect(s.events.length).toBe(3);
    expect(s.events.every((e) => Math.abs(e.beta - 1.2) < 0.02)).toBe(true);
    expect(carSummary(s, 0, 0).mean).toBeCloseTo(0.05, 2);
    expect(carSummary(s, -1, 1).mean).toBeCloseTo(0.04, 2);
    expect(s.pending.length).toBe(1);
    expect(lastDay(s, s.pending[0])).toBeLessThan(5);
    expect(car(s, s.pending[0], 0, 0)).toBeCloseTo(0.05, 2);
  });
});

describe("backtest, history, csv", () => {
  const bars = (closes: number[]): Candle[] => closes.map((c, i) => ({ time: Date.UTC(2025, 0, 1) + i * 86_400_000, open: c, high: c, low: c, close: c, volume: 1 }));
  test("buy and hold matches the asset, with entry cost", () => {
    const r = backtest(bars([100, 100, 110, 121]), { kind: "hold" }, 0)!;
    expect(r.equity[r.equity.length - 1]).toBeCloseTo(1.21, 9);
    expect(r.benchmarkReturn).toBeCloseTo(0.21, 9);
    expect(r.exposure).toBe(1);
  });
  test("signals act at the next open (no look-ahead)", () => {
    // A strategy can't capture a jump on the bar its signal is computed from.
    const closes = [...Array(60).fill(100), 100, 200, 200];
    const r = backtest(bars(closes), { kind: "sma", fast: 2, slow: 50 }, 0)!;
    expect(r.equity[r.equity.length - 1]).toBeLessThan(1.5);
  });
  test("return stats and csv", () => {
    expect(returnStats([100, 110, 99], 252)!.worst).toBeCloseTo(-0.1, 9);
    expect(csvField('=HYPERLINK("x")').startsWith("\"'=")).toBe(true);
    expect(csvField("-0.25")).toBe("-0.25");
    expect(csv(["a", "b"], [["1", "x,y"]])).toBe('a,b\r\n1,"x,y"\r\n');
    expect(alignedCloses({ a: bars([1, 2]), b: bars([3]) }).dates.length).toBe(1);
  });
});
