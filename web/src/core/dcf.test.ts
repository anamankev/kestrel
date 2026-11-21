import { describe, expect, it } from "vitest";
import { dcf, defaultInputs, growthPath, revenueCAGR, sensitivity, type DCFResult } from "./dcf";
import type { FiscalYear } from "./sec";

const ok = (r: DCFResult | string) => { if (typeof r === "string") throw new Error(r); return r; };
const fy = (year: number, revenue: number, ocf?: number, capex?: number): FiscalYear => ({ year, periodEnd: Date.UTC(year, 11, 31), revenue, operatingCashFlow: ocf, capex }) as FiscalYear;

describe("DCF", () => {
  it("matches a perpetuity when growth is flat", () => {
    // No growth anywhere: value = FCF / r.
    expect(ok(dcf({ baseFCF: 100, growth: 0, terminalGrowth: 0, discount: 0.08 }, 0)).enterprise).toBeCloseTo(1250, 6);
    // Constant 3% growth throughout: value = FCF·(1+g)/(r−g), whatever the horizon.
    expect(ok(dcf({ baseFCF: 100, growth: 0.03, terminalGrowth: 0.03, discount: 0.08 }, 0)).enterprise).toBeCloseTo(2060, 6);
  });
  it("fades growth from stage 1 to terminal over years 6–10", () => {
    const g = growthPath(0.1, 0);
    expect(g.slice(0, 5)).toEqual([0.1, 0.1, 0.1, 0.1, 0.1]);
    expect(g[5]).toBeCloseTo(0.08); expect(g[9]).toBeCloseTo(0);
    const r = ok(dcf({ baseFCF: 100, growth: 0.1, terminalGrowth: 0, discount: 0.09 }, 0));
    expect(r.flows[5].fcf).toBeCloseTo(r.flows[4].fcf * 1.08);
    expect(r.pvFlows + r.pvTerminal).toBeCloseTo(r.enterprise);
  });
  it("bridges to equity and per-share value", () => {
    const r = ok(dcf({ baseFCF: 100, growth: 0, terminalGrowth: 0, discount: 0.1 }, -200, 10));
    expect(r.equity).toBeCloseTo(800); expect(r.perShare).toBeCloseTo(80);
    expect(r.terminalShare).toBeCloseTo(1 / 1.1 ** 10);
  });
  it("refuses inputs that can't be valued", () => {
    expect(dcf({ baseFCF: -5, growth: 0.05, terminalGrowth: 0.02, discount: 0.09 }, 0)).toMatch(/positive free cash flow/);
    expect(dcf({ baseFCF: 100, growth: 0.05, terminalGrowth: 0.03, discount: 0.033 }, 0)).toMatch(/exceed terminal growth/);
    expect(dcf({ baseFCF: NaN, growth: 0.05, terminalGrowth: 0.02, discount: 0.09 }, 0)).toMatch(/numbers/);
  });
  it("starts from filings and the 10-year yield", () => {
    const years = [fy(2021, 100, 30, 10), fy(2022, 110), fy(2023, 121), fy(2024, 133.1, 40, 15)];
    expect(revenueCAGR(years)).toBeCloseTo(0.1);
    expect(defaultInputs(years, 0.045)).toMatchObject({ baseFCF: 25, baseKnown: true, growth: 0.1, terminalGrowth: 0.025, discount: 0.1 });
    expect(defaultInputs([fy(2024, 100, 5, 20)], 0.05)).toMatchObject({ baseKnown: false, growth: 0.05, discount: 0.105 });
    expect(defaultInputs([fy(2020, 100), fy(2024, 1000, 50, 0)]).growth).toBe(0.2);   // clamped
  });
  it("builds a sensitivity grid", () => {
    const grid = sensitivity({ baseFCF: 100, growth: 0, terminalGrowth: 0, discount: 0.1 }, 0, 10, [0.08, 0.1], [0, 0.02]);
    expect(grid[0][0]).toBeCloseTo(125); expect(grid[1][0]).toBeCloseTo(100);
    expect(grid[1][1]! > grid[1][0]!).toBe(true);
  });
});
