/** DCF: a two-stage discounted free-cash-flow valuation from SEC annual data. Mirrors KestrelCore/DCF.swift.
 *  Stage 1 (years 1–5) grows at `growth`; stage 2 (years 6–10) fades linearly to `terminalGrowth`;
 *  the terminal value is a Gordon growth perpetuity on year 10. */
import type { FiscalYear } from "./sec";

export interface DCFInputs { baseFCF: number; growth: number; terminalGrowth: number; discount: number }
export interface DCFYear { year: number; growth: number; fcf: number; factor: number; pv: number }
export interface DCFResult {
  flows: DCFYear[]; pvFlows: number; terminalValue: number; pvTerminal: number;
  enterprise: number; equity: number; perShare?: number; terminalShare: number;
}

export const YEARS = 10, HIGH = 5;
export const ERP = 0.055, BETA = 1, TERMINAL = 0.025;

/** Growth for each projected year: `growth` for years 1–5, then a straight line to `terminalGrowth` by year 10. */
export function growthPath(growth: number, terminalGrowth: number): number[] {
  return Array.from({ length: YEARS }, (_, k) => (k < HIGH ? growth : growth + ((terminalGrowth - growth) * (k + 1 - HIGH)) / (YEARS - HIGH)));
}

/** The valuation, or an explanation when the inputs can't produce one. `netCash` = cash − long-term debt. */
export function dcf(inp: DCFInputs, netCash: number, shares?: number): DCFResult | string {
  const { baseFCF, growth, terminalGrowth, discount } = inp;
  if (![baseFCF, growth, terminalGrowth, discount, netCash].every(Number.isFinite)) return "Enter numbers in every field.";
  if (baseFCF <= 0) return "A DCF needs positive free cash flow to start from. Enter the base you expect.";
  if (discount <= terminalGrowth + 0.005) return "The discount rate must exceed terminal growth by at least 0.5 points, or the terminal value is infinite.";
  if (discount > 0.5 || growth < -0.5 || growth > 1 || terminalGrowth < -0.05 || terminalGrowth > 0.06) return "Inputs are outside sensible ranges.";
  let fcf = baseFCF, pvFlows = 0;
  const flows = growthPath(growth, terminalGrowth).map((g, k) => {
    fcf *= 1 + g;
    const factor = 1 / (1 + discount) ** (k + 1), pv = fcf * factor;
    pvFlows += pv;
    return { year: k + 1, growth: g, fcf, factor, pv };
  });
  const terminalValue = (fcf * (1 + terminalGrowth)) / (discount - terminalGrowth);
  const pvTerminal = terminalValue * flows[YEARS - 1].factor;
  const enterprise = pvFlows + pvTerminal, equity = enterprise + netCash;
  return { flows, pvFlows, terminalValue, pvTerminal, enterprise, equity, perShare: shares && shares > 0 ? equity / shares : undefined, terminalShare: pvTerminal / enterprise };
}

export const freeCashFlow = (y: FiscalYear) => (y.operatingCashFlow == null ? undefined : y.operatingCashFlow - (y.capex ?? 0));

/** Compound annual revenue growth across the years given (oldest first), or undefined without two positive years. */
export function revenueCAGR(years: FiscalYear[]): number | undefined {
  const r = years.filter((y) => y.revenue != null && y.revenue > 0);
  if (r.length < 2) return undefined;
  const span = r[r.length - 1].year - r[0].year;
  return span > 0 ? (r[r.length - 1].revenue! / r[0].revenue!) ** (1 / span) - 1 : undefined;
}

const round = (v: number, step: number) => Math.round(v / step) * step;

/** Starting inputs: last year's free cash flow; growth = revenue CAGR clamped to −5%…20% (0.5-point steps);
 *  discount = CAPM with the 10-year Treasury, beta 1 and a 5.5% equity risk premium; terminal growth 2.5%. */
export function defaultInputs(years: FiscalYear[], tenYear?: number): DCFInputs & { baseKnown: boolean } {
  const last = years[years.length - 1], base = last ? freeCashFlow(last) : undefined;
  const g = revenueCAGR(years.slice(-5));
  const rf = tenYear != null && Number.isFinite(tenYear) && tenYear > 0 && tenYear < 0.2 ? tenYear : 0.045;
  return {
    baseFCF: base != null && base > 0 ? base : 0, baseKnown: base != null && base > 0,
    growth: round(Math.min(0.2, Math.max(-0.05, g ?? 0.05)), 0.005),
    terminalGrowth: TERMINAL, discount: round(rf + BETA * ERP, 0.0025),
  };
}

/** Value per share across discount rates (rows) and terminal growth rates (columns). */
export function sensitivity(inp: DCFInputs, netCash: number, shares: number, discounts: number[], terminals: number[]): (number | undefined)[][] {
  return discounts.map((d) => terminals.map((t) => { const r = dcf({ ...inp, discount: d, terminalGrowth: t }, netCash, shares); return typeof r === "string" ? undefined : r.perShare; }));
}
