/** Kestrel Pro plans (same products and prices as the App Store). */
export interface Plan { id: "monthly" | "halfyear" | "annual"; title: string; months: number; price: number; period: string }
export const PLANS: Plan[] = [
  { id: "annual", title: "Yearly", months: 12, price: 99.99, period: "year" },
  { id: "halfyear", title: "6 Months", months: 6, price: 49.99, period: "6 months" },
  { id: "monthly", title: "Monthly", months: 1, price: 9.99, period: "month" },
];
const monthly = PLANS.find((p) => p.id === "monthly")!.price;
/** What the same period costs on the monthly plan (the crossed-out price); never an invented "was" price. */
export const reference = (p: Plan) => (p.months === 1 ? null : Math.round(monthly * p.months * 100) / 100);
export const saving = (p: Plan) => { const r = reference(p); return r ? 1 - p.price / r : null; };
export const perMonth = (p: Plan) => p.price / p.months;
export const INCLUDED = [
  "Live crypto order book, trades and charts, with indicators",
  "Stocks, indices, FX, commodities and Treasury rates on every exchange; heat map and movers",
  "News search, SEC filings, financials and an earnings calendar",
  "Research: screener, beta, factor models, event studies, backtests, portfolio optimizer",
  "Paper trading with stops, risk and VaR; up to 6 panels; price alerts",
];
