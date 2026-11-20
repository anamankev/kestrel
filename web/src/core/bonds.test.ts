import { describe, expect, it } from "vitest";
import { bondRisk, curveOn, interpolate, parseTreasuryCSV, schedule, yieldFromPrice } from "./bonds";

// Real header and rows from Treasury's 2026 file (a 1.5-month column the app doesn't chart) plus a blank cell.
const CSV = `Date,"1 Mo","1.5 Month","2 Mo","3 Mo","4 Mo","6 Mo","1 Yr","2 Yr","3 Yr","5 Yr","7 Yr","10 Yr","20 Yr","30 Yr"
11/19/2026,4.20,4.27,4.29,4.34,4.35,4.42,4.62,4.76,4.81,4.86,4.94,5.04,5.43,5.40
11/18/2026,4.10,4.24,4.27,4.34,,4.43,4.62,4.80,4.84,4.89,4.96,5.07,5.44,5.41`;

describe("Treasury curve", () => {
  const days = parseTreasuryCSV(CSV);
  it("reads Treasury's CSV oldest first, by tenor label", () => {
    expect(days.map((d) => new Date(d.date).toISOString().slice(0, 10))).toEqual(["2026-11-18", "2026-11-19"]);
    expect(days[1].yields).toMatchObject({ "1M": 4.2, "2Y": 4.76, "10Y": 5.04, "30Y": 5.4 });
    expect(days[0].yields["4M"]).toBeUndefined();
    expect(parseTreasuryCSV("Date\n")).toEqual([]);
  });
  it("finds the curve on or before a date and interpolates", () => {
    expect(curveOn(days, Date.UTC(2026, 10, 18, 12))).toBe(days[0]);
    expect(curveOn(days, Date.UTC(2026, 10, 1))).toBeUndefined();
    expect(interpolate(days[1], 8.5)).toBeCloseTo((4.94 + 5.04) / 2);
    expect(interpolate(days[1], 40)).toBe(5.4);
  });
});

describe("bond math", () => {
  it("prices at par, at a discount, and a zero", () => {
    const par = bondRisk(0.05, { n: 20, w: 1 }, 0.05);
    expect(par.clean).toBeCloseTo(100, 8);
    expect(par.accrued).toBeCloseTo(0, 10);
    expect(par.modified).toBeCloseTo(7.7946, 3);
    expect(par.dv01).toBeCloseTo(0.077946, 5);
    expect(bondRisk(0.04, { n: 20, w: 1 }, 0.05).clean).toBeCloseTo(92.2054, 3);
    const zero = bondRisk(0, { n: 20, w: 1 }, 0.05);
    expect(zero.macaulay).toBeCloseTo(10, 10);
    expect(zero.convexity).toBeCloseTo((10 * 10.5) / 1.025 ** 2, 8);
  });
  it("accrues between coupons and inverts price to yield", () => {
    const b = bondRisk(0.06, { n: 20, w: 0.5 }, 0.05);
    expect(b.accrued).toBeCloseTo(1.5, 8);          // half a 3.00 coupon elapsed
    expect(b.dirty - b.accrued).toBeCloseTo(b.clean, 10);
    expect(yieldFromPrice(0.06, { n: 20, w: 0.5 }, b.clean)).toBeCloseTo(0.05, 9);
    expect(yieldFromPrice(0.04, { n: 20, w: 1 }, 92.2054)).toBeCloseTo(0.05, 5);
    expect(yieldFromPrice(0.05, { n: 20, w: 1 }, -1)).toBeUndefined();
  });
});

describe("coupon schedule", () => {
  it("counts coupons back from maturity, actual/actual", () => {
    // Exactly 10 years out: on a coupon date, nothing accrued.
    expect(schedule(Date.UTC(2026, 10, 20), Date.UTC(2036, 10, 20))).toMatchObject({ n: 20, w: 1 });
    // Feb 15 / Aug 15 bond settling Nov 15: 92 of 184 days to go.
    const s = schedule(Date.UTC(2026, 10, 15), Date.UTC(2036, 1, 15))!;
    expect(s.n).toBe(19);
    expect(s.w).toBeCloseTo(92 / 184, 12);
    // Month-end maturity clamps to shorter months (Aug 31 → Feb 28).
    expect(schedule(Date.UTC(2027, 2, 1), Date.UTC(2027, 7, 31))).toMatchObject({ n: 1, w: 183 / 184 });
    expect(schedule(Date.UTC(2027, 0, 1), Date.UTC(2026, 0, 1))).toBeUndefined();
  });
});

